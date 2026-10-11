class_name TurnController
extends RefCounted
## Command interface for the rules. All mutating calls validate first; on failure they return
## false / null and set last_error. Turn flow:
## start_game (deal hands) -> [start_turn: tile ticks (Lava/Healing), score VP, check win, set AP] -> Main phase
## (play_unit_card / play_spell_card / play_spell_on_tile / set_order / convert_vp_to_ap / draw -> Draft phase ->
## choose_draft_card -> Main) -> end_turn (resolve orders, expire spells/statuses/tile effects, swap player,
## turn_number++, start_turn).
## AP costs: cards (get_card_cost), Draw (GameConfig.draw_ap_cost), a NEW order (GameConfig.order_ap_cost;
## replacing is free, clearing refunds). Pieces are summoning sick on the turn they were summoned.
## Up to GameConfig.max_vp_to_ap_per_turn VP can be converted into AP per turn (1:1). Player 1 gets
## GameConfig.second_player_first_turn_bonus_ap extra AP on its first turn.

var state: GameState
var last_error: String = ""

## Raised after a turn has started (after ticks/scoring/AP). Arg: player index.
signal turn_started(player_index: int)
## Raised when a player scores at turn start. Args: player index, points gained.
signal victory_points_scored(player_index: int, points: int)
## Raised when a draft offer is ready (after a successful draw). Arg: player index.
signal draft_offered(player_index: int)
## Raised after orders were resolved in end_turn (before the next turn starts).
signal orders_resolved(events: Array)
## Raised at turn start (before scoring) when tile ticks produced events (Lava damage, healing).
signal turn_start_resolved(events: Array)
## Raised after a spell was cast (piece or tile spell) with its immediate events.
signal spell_resolved(events: Array)
## Raised when a winner is determined. Arg: winner index.
signal game_over(winner_index: int)
## Raised after any successful state change.
signal state_changed()

var _last_turn_start_events: Array[ResolutionEvent] = []
var _last_spell_events: Array[ResolutionEvent] = []

## Tile-tick events of the most recent turn start (Lava/Healing). Animate them after end_turn's events.
var last_turn_start_events: Array[ResolutionEvent]:
	get:
		return _last_turn_start_events
## Immediate events of the most recently cast spell (SpellCast, Damaged, Healed, TileEffectApplied...).
var last_spell_events: Array[ResolutionEvent]:
	get:
		return _last_spell_events


func _init(p_state: GameState) -> void:
	assert(p_state != null, "state must not be null")
	state = p_state


## Deals starting hands and starts turn 1 for player 0.
func start_game() -> void:
	state.current_player_index = 0
	state.turn_number = 1
	state.winner = -1
	for player: PlayerState in state.players:
		var i: int = 0
		while i < state.config.starting_hand_size and player.deck.size() > 0:
			player.hand.append(_draw_random(player.deck))
			i += 1
	start_turn()


## Starts the current player's turn: tile ticks for its pieces (Lava damage / Healing, see
## last_turn_start_events), +1 VP per own piece in the scoring zone, win check,
## AP = base_ap + sum of own ap_bonus (+ second-player bonus on player 1's first turn), then Main phase.
func start_turn() -> void:
	var idx: int = state.current_player_index
	var player: PlayerState = state.current_player
	state.reset_order_index()
	player.turns_started += 1
	player.vp_converted_this_turn = 0

	_last_turn_start_events = OrderResolver.resolve_turn_start(state, idx)
	if _last_turn_start_events.size() > 0:
		turn_start_resolved.emit(_last_turn_start_events)

	var scored: int = 0
	var ap_bonus: int = 0
	for p: Piece in state.get_pieces_of(idx):
		if state.board.is_in_scoring_zone(p.position):
			scored += 1
		ap_bonus += p.ap_bonus
	if scored > 0:
		player.victory_points += scored
		victory_points_scored.emit(idx, scored)
	if player.victory_points >= state.config.points_target:
		state.winner = idx
		state.phase = GamePhase.GAME_OVER
		game_over.emit(idx)
		state_changed.emit()
		return

	player.action_points = state.config.base_ap + ap_bonus
	if idx == 1 and player.turns_started == 1:
		player.action_points += maxi(0, state.config.second_player_first_turn_bonus_ap)

	_return_draft_offer(player)
	state.phase = GamePhase.MAIN

	turn_started.emit(idx)
	state_changed.emit()


# ------------------------------------------------------------------ VP -> AP

## VP the current player converted into AP this turn.
var vp_converted_this_turn: int:
	get:
		return state.current_player.vp_converted_this_turn

## Conversions the current player has left this turn (ignores whether it has VP).
var remaining_vp_conversions: int:
	get:
		return maxi(0, state.config.max_vp_to_ap_per_turn - state.current_player.vp_converted_this_turn)


## True if the current player may convert 1 VP into 1 AP now (Main phase, VP >= 1, per-turn limit).
func can_convert_vp_to_ap() -> bool:
	if state.phase != GamePhase.MAIN:
		return _fail("Not in main phase.")
	var player: PlayerState = state.current_player
	if player.victory_points < 1:
		return _fail("No victory points to convert.")
	if remaining_vp_conversions <= 0:
		return _fail("Already converted %d VP this turn." % state.config.max_vp_to_ap_per_turn)
	return true


## Converts 1 VP into 1 AP for the current player (max GameConfig.max_vp_to_ap_per_turn per turn).
func convert_vp_to_ap() -> bool:
	if not can_convert_vp_to_ap():
		return false
	var player: PlayerState = state.current_player
	player.victory_points -= 1
	player.action_points += 1
	player.vp_converted_this_turn += 1
	state_changed.emit()
	return true


# ------------------------------------------------------------------ draw / draft

## Checks whether the current player may use the Draw action (Main phase, non-empty deck, enough AP).
func can_draw() -> bool:
	if state.phase != GamePhase.MAIN:
		return _fail("Not in main phase.")
	var player: PlayerState = state.current_player
	if player.deck.size() == 0:
		return _fail("Deck is empty.")
	if state.config.draw_ap_cost > player.action_points:
		return _fail("Not enough AP.")
	return true


## Pays GameConfig.draw_ap_cost and creates a draft offer of up to draft_offer_size cards (Draft phase).
## Must be completed with choose_draft_card; it cannot be cancelled. Can be used several times per turn.
func draw() -> bool:
	if not can_draw():
		return false
	var player: PlayerState = state.current_player
	player.action_points -= state.config.draw_ap_cost
	_return_draft_offer(player)
	var i: int = 0
	while i < state.config.draft_offer_size and player.deck.size() > 0:
		player.draft_offer.append(_draw_random(player.deck))
		i += 1
	state.phase = GamePhase.DRAFT
	draft_offered.emit(state.current_player_index)
	state_changed.emit()
	return true


## Takes the offered card at offer_index into the hand; the rest return to the deck. Returns to Main phase.
func choose_draft_card(offer_index: int) -> bool:
	var player: PlayerState = state.current_player
	if state.phase != GamePhase.DRAFT:
		return _fail("Not in draft phase.")
	if offer_index < 0 or offer_index >= player.draft_offer.size():
		return _fail("Invalid draft index.")
	var chosen: CardData = player.draft_offer[offer_index]
	player.draft_offer.remove_at(offer_index)
	player.hand.append(chosen)
	_return_draft_offer(player)
	state.phase = GamePhase.MAIN
	state_changed.emit()
	return true


# ------------------------------------------------------------------ cards

## AP cost of a card: its ap_cost if > 0, else GameConfig.unit_ap_cost / spell_ap_cost.
func get_card_cost(card: CardData) -> int:
	if card.ap_cost > 0:
		return card.ap_cost
	return state.config.spell_ap_cost if card.card_type == CardType.SPELL else state.config.unit_ap_cost


## Checks whether the current player may deploy this unit card on pos (no side effects).
func can_play_unit_card(card: CardData, pos: Vector2i) -> bool:
	if state.phase != GamePhase.MAIN:
		return _fail("Not in main phase.")
	if card == null or card.card_type != CardType.UNIT:
		return _fail("Not a unit card.")
	var player: PlayerState = state.current_player
	if not player.hand.has(card):
		return _fail("Card not in hand.")
	if get_card_cost(card) > player.action_points:
		return _fail("Not enough AP.")
	if not state.board.is_in_deploy_zone(state.current_player_index, pos):
		return _fail("Not in own deploy rows.")
	if state.board.is_wall(pos):
		return _fail("A wall blocks this tile.")
	if state.board.is_occupied(pos):
		return _fail("Tile occupied.")
	return true


## Deploys a unit card from the hand on pos. Returns the new piece, or null on failure.
func play_unit_card(card: CardData, pos: Vector2i) -> Piece:
	if not can_play_unit_card(card, pos):
		return null
	var player: PlayerState = state.current_player
	player.action_points -= get_card_cost(card)
	player.hand.erase(card)
	var piece: Piece = state.spawn_piece(card, state.current_player_index, pos)
	state_changed.emit()
	return piece


## Checks whether the current player may cast this spell on target (any living piece). For tile/area
## spells (CardData.targets_tile) this checks can_play_spell_on_tile(card, target.position) instead.
func can_play_spell_card(card: CardData, target: Piece) -> bool:
	if card != null and card.targets_tile:
		if target == null or state.get_piece(target.id) == null:
			return _fail("Invalid target.")
		return can_play_spell_on_tile(card, target.position)
	if not _check_spell_basics(card):
		return false
	if target == null or not target.is_alive or state.get_piece(target.id) == null:
		return _fail("Invalid target.")
	return true


## Casts a spell on a piece. Lasts until the end of the caster's next turn (expiry_turn = turn_number + 2).
## hp_delta changes max and current HP immediately (a spell never reduces HP below 1);
## shield_delta grants a temporary shield that absorbs damage first; grant_status adds a status
## (GameConfig.spell_status_duration). Tile/area spells are redirected to play_spell_on_tile(card, target.position).
## Immediate events: last_spell_events.
func play_spell_card(card: CardData, target: Piece) -> bool:
	if card != null and card.targets_tile:
		return can_play_spell_card(card, target) and play_spell_on_tile(card, target.position)
	if not can_play_spell_card(card, target):
		return false
	var player: PlayerState = state.current_player
	player.action_points -= get_card_cost(card)
	player.hand.erase(card)

	var cast := ResolutionEvent.new()
	cast.type = ResolutionEventType.SPELL_CAST
	cast.piece_id = target.id
	cast.player_index = state.current_player_index
	cast.from = target.position
	cast.to = target.position
	cast.card_name = card.name
	var events: Array[ResolutionEvent] = [cast]

	var effect: SpellEffect = SpellEffect.from_card(card)
	var has_modifiers: bool = effect.attack_delta != 0 or effect.hp_delta != 0 or effect.shield_delta != 0 \
		or effect.movement_delta != 0 or effect.range_delta != 0
	if has_modifiers or card.grant_status == StatusEffectType.NONE:
		target.active_spells.append(ActiveSpell.new(card, effect, state.current_player_index, state.turn_number, state.turn_number + 2))
		target.current_hp = clampi(target.current_hp + effect.hp_delta, 1, target.max_hp)
	if card.grant_status != StatusEffectType.NONE:
		OrderResolver.apply_status(state, target, card.grant_status, state.config.spell_status_duration, card.name, -1, events)
	_finish_spell(events)
	return true


## Checks whether the current player may cast a tile/area spell anchored at 'tile': Main phase, card in hand,
## enough AP, tile on the board, and (for Wall spells) at least one free tile in the area.
func can_play_spell_on_tile(card: CardData, tile: Vector2i) -> bool:
	if not _check_spell_basics(card):
		return false
	if not card.targets_tile:
		return _fail("This spell targets a piece.")
	if not state.board.is_inside(tile):
		return _fail("Invalid tile.")
	if card.tile_effect == TileEffectType.WALL and card.spell_damage <= 0 and card.spell_heal <= 0:
		var any: bool = false
		for p: Vector2i in get_spell_area_preview(card, tile):
			any = any or not state.board.is_occupied(p)
		if not any:
			return _fail("No free tile for the wall.")
	return true


## Casts a tile/area spell: SpellCast event, spell_damage to every enemy piece in the area, spell_heal to every
## friendly piece in it, then tile_effect on every area tile for tile_effect_duration turns (walls skip occupied
## tiles). Immediate events: last_spell_events (also raised via spell_resolved).
func play_spell_on_tile(card: CardData, tile: Vector2i) -> bool:
	if not can_play_spell_on_tile(card, tile):
		return false
	var caster: int = state.current_player_index
	var player: PlayerState = state.current_player
	player.action_points -= get_card_cost(card)
	player.hand.erase(card)

	var cast := ResolutionEvent.new()
	cast.type = ResolutionEventType.SPELL_CAST
	cast.player_index = caster
	cast.from = tile
	cast.to = tile
	cast.card_name = card.name
	var events: Array[ResolutionEvent] = [cast]

	var area: Array[Vector2i] = get_spell_area_preview(card, tile)
	for p: Vector2i in area:
		var piece: Piece = state.board.get_piece_at(p)
		if piece == null:
			continue
		if piece.owner_index != caster and card.spell_damage > 0:
			OrderResolver.apply_damage(state, piece, card.spell_damage, -1, events)
		elif piece.owner_index == caster and card.spell_heal > 0:
			OrderResolver.apply_heal(state, piece, card.spell_heal, -1, events)
	if card.tile_effect != TileEffectType.NONE:
		for p: Vector2i in area:
			OrderResolver.apply_tile_effect(state, card.tile_effect, p, card.tile_effect_duration, caster, card.name, -1, events)
	_finish_spell(events)
	return true


## Unified check: piece spells need a piece on 'tile', tile/area spells use can_play_spell_on_tile.
func can_cast_spell_at(card: CardData, tile: Vector2i) -> bool:
	if card != null and card.targets_tile:
		return can_play_spell_on_tile(card, tile)
	return can_play_spell_card(card, state.board.get_piece_at(tile))


## Unified cast: piece spells on the piece standing on 'tile', tile/area spells on the tile.
func cast_spell_at(card: CardData, tile: Vector2i) -> bool:
	if card != null and card.targets_tile:
		return play_spell_on_tile(card, tile)
	return play_spell_card(card, state.board.get_piece_at(tile))


## Tiles a spell would affect when anchored at 'tile' (piece spells: just that tile). For highlights.
func get_spell_area_preview(card: CardData, tile: Vector2i) -> Array[Vector2i]:
	if card == null or not state.board.is_inside(tile):
		return [] as Array[Vector2i]
	var shape: int = card.area_shape if card.spell_target == SpellTargetType.AREA else AreaShape.SINGLE
	return state.board.get_area_tiles(tile, shape)


## All tiles where can_cast_spell_at(card, tile) is true (for highlights).
func get_valid_spell_tiles(card: CardData) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y: int in range(state.board.height):
		for x: int in range(state.board.width):
			var pos := Vector2i(x, y)
			if can_cast_spell_at(card, pos):
				result.append(pos)
	return result


# ------------------------------------------------------------------ orders

## Valid move destinations for a piece (excluding its own tile). Friendly pieces do not block and may be a
## destination (they get pushed at resolution); enemies and walls block. Frozen pieces cannot move.
func get_valid_move_targets(piece: Piece) -> Array[Vector2i]:
	return state.board.get_reachable_tiles(piece.position, piece.effective_movement, piece.owner_index)


## Planned shortest path for a move (same rules as get_valid_move_targets): the tiles after the piece's position,
## ending with target. Empty if target is the current tile or unreachable. Other orders are not simulated.
func get_planned_path(piece: Piece, target: Vector2i) -> Array[Vector2i]:
	if piece == null:
		return [] as Array[Vector2i]
	var path: Variant = state.board.find_path(piece.position, target, piece.effective_movement, piece.owner_index)
	if path == null:
		return [] as Array[Vector2i]
	var result: Array[Vector2i] = []
	result.assign(path)
	return result


## Valid attack tiles for a piece standing at from_pos (default: its current position). from_pos: Vector2i or null.
func get_valid_attack_targets(piece: Piece, from_pos: Variant = null) -> Array[Vector2i]:
	var origin: Vector2i = from_pos if from_pos != null else piece.position
	return state.board.get_tiles_in_range(origin, piece.effective_range)


## True if the current player may give this piece orders now: Main phase, own living piece,
## not summoning sick. Does not check AP.
func can_command(piece: Piece) -> bool:
	if state.phase != GamePhase.MAIN:
		return _fail("Not in main phase.")
	if piece == null or state.get_piece(piece.id) == null:
		return _fail("Invalid piece.")
	if piece.owner_index != state.current_player_index:
		return _fail("Not your piece.")
	if piece.is_summoning_sick(state.turn_number):
		return _fail("Summoning sick - can act next turn.")
	return true


## Checks an order without applying it. A new order needs GameConfig.order_ap_cost AP; replacing an
## existing order or clearing it (null/null) needs none. Moves follow get_valid_move_targets.
## move / attack: Vector2i or null.
func can_set_order(piece: Piece, move: Variant, attack: Variant) -> bool:
	if not can_command(piece):
		return false
	var is_new: bool = piece.order == null and (move != null or attack != null)
	if is_new and state.config.order_ap_cost > state.current_player.action_points:
		return _fail("Not enough AP.")
	if move != null and move != piece.position \
			and state.board.find_path(piece.position, move, piece.effective_movement, piece.owner_index) == null:
		return _fail("Frozen - cannot move this turn." if piece.is_frozen else "Move target not reachable.")
	var attack_from: Vector2i = move if move != null else piece.position
	if attack != null and not state.board.is_in_attack_range(attack_from, attack, piece.effective_range):
		return _fail("Attack target out of range.")
	return true


## Queues (or replaces) the order of a piece. A new order costs GameConfig.order_ap_cost and gets the next
## order index; replacing an existing order is free and keeps its index. Passing null for both clears
## the order and refunds its AP. move / attack: Vector2i or null.
func set_order(piece: Piece, move: Variant, attack: Variant) -> bool:
	if not can_set_order(piece, move, attack):
		return false
	if move == null and attack == null:
		_remove_order_with_refund(piece)
	elif piece.order != null:
		piece.order.move_target = move
		piece.order.attack_target = attack
	else:
		var cost: int = maxi(0, state.config.order_ap_cost)
		state.current_player.action_points -= cost
		var order := PieceOrder.new(move, attack, state.take_order_index())
		order.ap_paid = cost
		piece.order = order
	state_changed.emit()
	return true


## Removes the queued order of a piece and refunds the AP paid for it (current player's turn only).
func clear_order(piece: Piece) -> void:
	if piece != null and piece.order != null:
		_remove_order_with_refund(piece)
		state_changed.emit()


## Predicts what ONE attack of 'attacker' standing at 'from_pos' on tile 'target' would cause, on a clone of
## the CURRENT board: chains, damage, kills, keyword effects. Other queued orders are NOT simulated (it is a
## preview of that single attack). If from_pos holds a friendly, the planned move is simulated (push).
## Does not check AP / summoning sickness; is_valid is false if the attack is impossible (range etc.).
## Merged C# overload: predict_attack(attacker, target) (2 args) predicts from the attacker's current position.
func predict_attack(attacker: Piece, from_pos: Vector2i, target: Variant = null) -> ChainPreview:
	if target == null:
		# C# overload PredictAttack(attacker, target).
		var t: Vector2i = from_pos
		return _predict_attack_impl(attacker, attacker.position if attacker != null else t, t)
	return _predict_attack_impl(attacker, from_pos, target)


func _predict_attack_impl(attacker: Piece, from_pos: Vector2i, target: Vector2i) -> ChainPreview:
	var invalid := ChainPreview.new()
	invalid.attacker_id = attacker.id if attacker != null else -1
	invalid.from = from_pos
	invalid.target = target
	invalid.is_valid = false
	if attacker == null or state.get_piece(attacker.id) == null:
		return invalid
	if not state.board.is_in_attack_range(from_pos, target, attacker.effective_range):
		return invalid
	var owners: Dictionary[int, int] = {}
	for p: Piece in state.pieces:
		owners[p.id] = p.owner_index

	var clone: GameState = state.clone()
	var a: Piece = clone.get_piece(attacker.id)
	if from_pos != a.position:
		var occupant: Piece = clone.board.get_piece_at(from_pos)
		if occupant == null and clone.board.is_passable(from_pos):
			clone.board.move_piece(a, from_pos)
		elif occupant != null and occupant.owner_index == a.owner_index:
			OrderResolver.simulate_move(clone, a, from_pos)
		if a.position != from_pos:
			return invalid
	var events: Array[ResolutionEvent] = OrderResolver.simulate_attack(clone, a, target)
	return ChainPreview.from_events(attacker.id, from_pos, target, attacker.owner_index, owners, events)


func _remove_order_with_refund(piece: Piece) -> void:
	if piece.order == null:
		return
	if piece.owner_index == state.current_player_index and state.phase == GamePhase.MAIN:
		state.current_player.action_points += piece.order.ap_paid
	piece.order = null


# ------------------------------------------------------------------ end of turn

## Ends the current turn: resolves the current player's orders, clears orders (no refund), expires spells,
## statuses and tile effects with expiry_turn <= turn_number, swaps player, increments turn_number and starts
## the next turn (its tile ticks are in last_turn_start_events). Returns the resolution events (empty list if
## the call was invalid).
func end_turn() -> Array[ResolutionEvent]:
	if state.phase != GamePhase.MAIN:
		_fail("Can only end the turn in main phase.")
		return [] as Array[ResolutionEvent]
	state.phase = GamePhase.RESOLVING
	var events: Array[ResolutionEvent] = OrderResolver.resolve(state, state.current_player_index)

	for p: Piece in state.pieces:
		p.order = null
	_expire_spells(events)
	_expire_statuses(events)
	_expire_tile_effects(events)
	orders_resolved.emit(events)

	state.current_player_index = 1 - state.current_player_index
	state.turn_number += 1
	start_turn()
	return events


func _expire_spells(events: Array[ResolutionEvent]) -> void:
	var turn: int = state.turn_number
	for p: Piece in state.pieces:
		for i: int in range(p.active_spells.size() - 1, -1, -1):
			var spell: ActiveSpell = p.active_spells[i]
			if spell.expiry_turn > turn:
				continue
			p.active_spells.remove_at(i)
			var ev := ResolutionEvent.new()
			ev.type = ResolutionEventType.SPELL_EXPIRED
			ev.piece_id = p.id
			ev.from = p.position
			ev.to = p.position
			ev.spell_name = spell.source.name if spell.source != null else ""
			events.append(ev)
		p.current_hp = clampi(p.current_hp, 1, p.max_hp)


func _expire_statuses(events: Array[ResolutionEvent]) -> void:
	var turn: int = state.turn_number
	for p: Piece in state.pieces:
		for i: int in range(p.status_effects.size() - 1, -1, -1):
			var status: StatusEffect = p.status_effects[i]
			if status.expiry_turn > turn:
				continue
			p.status_effects.remove_at(i)
			var ev := ResolutionEvent.new()
			ev.type = ResolutionEventType.STATUS_EXPIRED
			ev.piece_id = p.id
			ev.from = p.position
			ev.to = p.position
			ev.status = status.type
			events.append(ev)


func _expire_tile_effects(events: Array[ResolutionEvent]) -> void:
	var turn: int = state.turn_number
	var expired: Array[TileEffect] = []
	for effect: TileEffect in state.board.tile_effects.values():
		if effect.expiry_turn <= turn:
			expired.append(effect)
	var by_row_then_column := func(a: TileEffect, b: TileEffect) -> bool:
		if a.position.y != b.position.y:
			return a.position.y < b.position.y
		return a.position.x < b.position.x
	expired.sort_custom(by_row_then_column)
	for effect: TileEffect in expired:
		state.board.remove_tile_effect(effect.position)
		var ev := ResolutionEvent.new()
		ev.type = ResolutionEventType.TILE_EFFECT_EXPIRED
		ev.from = effect.position
		ev.to = effect.position
		ev.tile_effect = effect.type
		ev.card_name = effect.source_name
		events.append(ev)


# ------------------------------------------------------------------ helpers

func _check_spell_basics(card: CardData) -> bool:
	if state.phase != GamePhase.MAIN:
		return _fail("Not in main phase.")
	if card == null or card.card_type != CardType.SPELL:
		return _fail("Not a spell card.")
	var player: PlayerState = state.current_player
	if not player.hand.has(card):
		return _fail("Card not in hand.")
	if get_card_cost(card) > player.action_points:
		return _fail("Not enough AP.")
	return true


func _finish_spell(events: Array[ResolutionEvent]) -> void:
	_last_spell_events = events
	spell_resolved.emit(events)
	state_changed.emit()


func _return_draft_offer(player: PlayerState) -> void:
	player.deck.append_array(player.draft_offer)
	player.draft_offer.clear()


func _draw_random(deck: Array[CardData]) -> CardData:
	var i: int = state.random.randi_range(0, deck.size() - 1)
	var card: CardData = deck[i]
	deck.remove_at(i)
	return card


func _fail(reason: String) -> bool:
	last_error = reason
	return false
