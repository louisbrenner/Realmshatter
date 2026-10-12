class_name TurnController
extends RefCounted
## Command interface for the rules. All mutating calls validate first; on failure they return
## false / null and set last_error. Turn flow:
## start_game (deal hands) -> [start_turn: tile ticks (Lava/Healing), score VP, check win, set AP] -> Main phase
## (play_unit_card / play_spell_card / play_spell_on_tile / act / convert_vp_to_ap / draw -> Draft phase ->
## choose_draft_card -> Main) -> end_turn (expire spells/statuses/tile effects, swap player, turn_number++, start_turn).
## act resolves a piece's move + attack IMMEDIATELY (there is no end-of-turn resolution); every piece acts at
## most once per turn. AP costs: cards (get_card_cost), Draw (GameConfig.draw_ap_cost), an action
## (GameConfig.order_ap_cost). Pieces are summoning sick on the turn they were summoned.
## Up to GameConfig.max_vp_to_ap_per_turn VP can be converted into AP per turn (1:1). Player 1 gets
## GameConfig.second_player_first_turn_bonus_ap extra AP on its first turn.
## Nullable C# GridPos? parameters are Variant (Vector2i or null).

var state: GameState
var last_error: String = ""

## Raised after a turn has started (after ticks/scoring/AP). Arg: player index.
signal turn_started(player_index: int)
## Raised when a player scores at turn start. Args: player index, points gained.
signal victory_points_scored(player_index: int, points: int)
## Raised when a draft offer is ready (after a successful draw). Arg: player index.
signal draft_offered(player_index: int)
## Raised after a piece action (act) resolved, with its events.
signal action_resolved(events: Array)
## Raised in end_turn after spells / statuses / tile effects expired (before the next turn starts).
signal turn_ended(events: Array)
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
var _last_action_events: Array[ResolutionEvent] = []

## Tile-tick events of the most recent turn start (Lava/Healing). Animate them after end_turn's events.
var last_turn_start_events: Array[ResolutionEvent]:
	get:
		return _last_turn_start_events
## Immediate events of the most recently cast spell (SpellCast, Damaged, Healed, TileEffectApplied...).
var last_spell_events: Array[ResolutionEvent]:
	get:
		return _last_spell_events
## Events of the most recent piece action (Moved, Attacked, Damaged, Died...).
var last_action_events: Array[ResolutionEvent]:
	get:
		return _last_action_events


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
## last_turn_start_events), VP per own piece in the scoring zone (1, crown field hot_zone_points), win check,
## AP = base_ap + sum of own ap_bonus (+ second-player bonus on player 1's first turn), then Main phase.
func start_turn() -> void:
	var idx: int = state.current_player_index
	var player: PlayerState = state.current_player
	player.turns_started += 1
	player.vp_converted_this_turn = 0

	_last_turn_start_events = _to_events(OrderResolver.resolve_turn_start(state, idx))
	_last_turn_start_events.append_array(_to_events(OrderResolver.resolve_buildings_turn_start(state, idx)))
	_last_turn_start_events.append_array(_to_events(OrderResolver.resolve_auras(state, idx)))
	_last_turn_start_events.append_array(_to_events(OrderResolver.resolve_legends(state, idx)))
	if _last_turn_start_events.size() > 0:
		turn_start_resolved.emit(_last_turn_start_events)

	var scored: int = 0
	var ap_bonus: int = 0
	for p: Piece in state.get_pieces_of(idx):
		if p.is_building:
			if p.building == BuildingType.MANA_WELL and not p.under_construction:
				ap_bonus += state.config.mana_well_ap
			continue
		if p.can_score:
			scored += state.board.score_value(p.position)
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

	player.action_points = state.config.base_ap + ap_bonus + player.pending_ap + player.bonus_ap_per_turn
	player.pending_ap = 0
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
	if card.has_keyword(Keyword.PLANTED):
		if not _is_valid_plant_tile(pos):
			return _fail("Planted units go within %d tiles of one of your units (not on the crown)." % state.config.plant_radius)
	elif not state.board.is_in_deploy_zone(state.current_player_index, pos):
		return _fail("Not in own deploy rows.")
	if state.board.is_wall(pos):
		return _fail("A wall blocks this tile.")
	if state.board.is_occupied(pos):
		return _fail("Tile occupied.")
	return true


## Planted units: the own deploy rows, or any tile within GameConfig.plant_radius of one of the current player's
## units (buildings do not count). Never the crown field.
func _is_valid_plant_tile(pos: Vector2i) -> bool:
	if not state.board.is_inside(pos) or state.board.is_in_hot_zone(pos):
		return false
	if state.board.is_in_deploy_zone(state.current_player_index, pos):
		return true
	for p: Piece in state.get_pieces_of(state.current_player_index):
		if not p.is_building and GridPos.manhattan_distance(p.position, pos) <= state.config.plant_radius:
			return true
	return false


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
	if not is_in_spell_range(target.position):
		return _fail("Too far from your units (spells reach %d tiles)." % state.config.spell_cast_radius)
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

	var power: int = spell_power(target.position)
	var events: Array[ResolutionEvent] = []
	var cast := ResolutionEvent.new()
	cast.type = ResolutionEventType.SPELL_CAST
	cast.piece_id = target.id
	cast.player_index = state.current_player_index
	cast.from = target.position
	cast.to = target.position
	cast.card_name = card.name
	cast.amount = power
	events.append(cast)
	var effect: SpellEffect = SpellEffect.from_card(card, power)
	var has_modifiers: bool = effect.attack_delta != 0 or effect.hp_delta != 0 or effect.shield_delta != 0 \
		or effect.movement_delta != 0 or effect.range_delta != 0
	if has_modifiers or (card.grant_status == StatusEffectType.NONE and card.ap_gain <= 0):
		target.active_spells.append(ActiveSpell.new(card, effect, state.current_player_index, state.turn_number, state.turn_number + 2))
		target.current_hp = clampi(target.current_hp + effect.hp_delta, 1, target.max_hp)
	if card.grant_status != StatusEffectType.NONE:
		OrderResolver.apply_status(state, target, card.grant_status, state.config.spell_status_duration + power, card.name, -1, events)
	OrderResolver.grant_ap(state, state.current_player_index, card.ap_gain, -1, card.name, target.position, events)
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
	if not is_in_spell_range(tile):
		return _fail("Too far from your units (spells reach %d tiles)." % state.config.spell_cast_radius)
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

	# Obelisk: +1 damage, healing and duration.
	var power: int = spell_power(tile)
	var damage: int = SpellEffect.boost(card.spell_damage, power)
	var heal: int = SpellEffect.boost(card.spell_heal, power)
	var duration: int = card.tile_effect_duration + power
	var events: Array[ResolutionEvent] = []
	var cast := ResolutionEvent.new()
	cast.type = ResolutionEventType.SPELL_CAST
	cast.player_index = caster
	cast.from = tile
	cast.to = tile
	cast.card_name = card.name
	cast.amount = power
	events.append(cast)
	var area: Array[Vector2i] = get_spell_area_preview(card, tile)
	for p: Vector2i in area:
		var piece: Piece = state.board.get_piece_at(p)
		if piece == null:
			if damage > 0 and state.board.get_terrain(p) == TerrainType.ROCK:
				OrderResolver.damage_rock(state, p, damage, events)
			continue
		if piece.owner_index != caster and damage > 0:
			OrderResolver.apply_damage(state, piece, damage, -1, events)
		elif piece.owner_index == caster and heal > 0:
			OrderResolver.apply_heal(state, piece, heal, -1, events)
	if card.spell_push:
		# Farthest pieces first so the inner ones are not blocked by their own neighbours.
		var pushed: Array[Piece] = []
		for p: Vector2i in area:
			var piece: Piece = state.board.get_piece_at(p)
			if piece != null:
				pushed.append(piece)
		pushed.sort_custom(func(a: Piece, b: Piece) -> bool:
			return GridPos.manhattan_distance(a.position, tile) > GridPos.manhattan_distance(b.position, tile))
		for piece: Piece in pushed:
			var dir: Vector2i = Vector2i(0, BoardState.forward_direction(caster)) if piece.position == tile \
				else OrderResolver.attack_direction(tile, piece.position)
			OrderResolver.push_piece(state, piece, dir, -1, events)
	if card.tile_effect != TileEffectType.NONE:
		for p: Vector2i in area:
			OrderResolver.apply_tile_effect(state, card.tile_effect, p, duration, caster, card.name, -1, events)
	OrderResolver.grant_ap(state, caster, card.ap_gain, -1, card.name, tile, events)
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
	var result: Array[Vector2i] = []
	if card == null or not state.board.is_inside(tile):
		return result
	var shape: int = card.area_shape if card.spell_target == SpellTargetType.AREA else AreaShape.SINGLE
	result.assign(state.board.get_area_tiles(tile, shape))
	return result


## All tiles where can_cast_spell_at(card, tile) is true (for highlights).
func get_valid_spell_tiles(card: CardData) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y: int in range(state.board.height):
		for x: int in range(state.board.width):
			var pos := Vector2i(x, y)
			if can_cast_spell_at(card, pos):
				result.append(pos)
	return result


# ------------------------------------------------------------------ piece actions

## Valid move destinations for a piece (excluding its own tile). Friendly pieces do not block and may be a
## destination (they get pushed); enemies and walls block. Frozen pieces cannot move.
func get_valid_move_targets(piece: Piece) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if piece.constructing_id >= 0 or piece.is_building or piece.has_keyword(Keyword.PLANTED):
		return result
	result.assign(state.board.get_reachable_tiles(piece.position, piece.effective_movement, piece.owner_index))
	return result


## True if the current player may cast a spell centred on 'tile': within GameConfig.spell_cast_radius
## (Manhattan) of one of its units.
func is_in_spell_range(tile: Vector2i) -> bool:
	for p: Piece in state.get_pieces_of(state.current_player_index):
		var d: int = GridPos.manhattan_distance(p.position, tile)
		if not p.is_building and d <= state.config.spell_cast_radius:
			return true
	return false


## All tiles where the current player may centre a spell (is_in_spell_range), for the cast range overlay.
func get_spell_range_tiles() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y: int in range(state.board.height):
		for x: int in range(state.board.width):
			var pos := Vector2i(x, y)
			if is_in_spell_range(pos):
				result.append(pos)
	return result


## Tiles a building standing on 'at' covers: Turret = its shooting range, Shrine = the 8 surrounding tiles,
## Obelisk = its spell cast radius. Empty for buildings without a range.
func get_building_range_tiles(type: int, at: Vector2i, turret_range: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y: int in range(state.board.height):
		for x: int in range(state.board.width):
			var pos := Vector2i(x, y)
			var in_range: bool = false
			match type:
				BuildingType.TURRET:
					in_range = state.board.is_in_attack_range(at, pos, turret_range)
				BuildingType.SHRINE:
					in_range = pos != at and absi(pos.x - at.x) <= 1 and absi(pos.y - at.y) <= 1
				BuildingType.OBELISK:
					in_range = GridPos.manhattan_distance(at, pos) <= state.config.obelisk_empower_radius
			if in_range:
				result.append(pos)
	return result


## Trap a Trapper sets (by its clan, a TrapType int), or null if the piece is no Trapper.
func get_trap_type(piece: Piece) -> Variant:
	if piece != null and not piece.is_building and piece.has_keyword(Keyword.TRAPPER) and piece.source != null:
		return TrapInfo.for_clan(piece.source.clan)
	return null


## Free tiles next to 'from_tile' (default null: the piece's tile; 8 directions) where it could hide a trap.
func get_valid_trap_tiles(piece: Piece, from_tile: Variant = null) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if piece == null:
		return result
	var at: Vector2i = from_tile if from_tile != null else piece.position
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var tile := Vector2i(at.x + dx, at.y + dy)
			var occupant: Piece = state.board.get_piece_at(tile)
			if (dx != 0 or dy != 0) and state.board.is_passable(tile) and (occupant == null or occupant == piece) \
					and state.board.get_trap(tile) == null and not state.board.is_in_hot_zone(tile):
				result.append(tile)
	return result


## Checks a trap command: commandable Trapper, AP, an optional reachable move first, a valid tile next to the destination.
func can_set_trap(piece: Piece, tile: Vector2i, move: Variant) -> bool:
	if not can_command(piece):
		return false
	if get_trap_type(piece) == null:
		return _fail("This unit cannot set traps.")
	if piece.constructing_id >= 0:
		return _fail("Busy building.")
	if state.config.trap_ap_cost > state.current_player.action_points:
		return _fail("Not enough AP.")
	var moves: bool = move != null and move != piece.position
	if moves and _is_unreachable(state.board.find_path(piece.position, move, piece.effective_movement, piece.owner_index)):
		return _fail("Frozen - cannot move this turn." if piece.is_frozen else "Move target not reachable.")
	if not get_valid_trap_tiles(piece, move if moves else null).has(tile) or (moves and tile == move):
		return _fail("Hide the trap on a free tile next to the unit.")
	return true


## Trap command: pays GameConfig.trap_ap_cost and uses the piece's action. The piece first makes its move (if any,
## enemy traps may stop it), then hides its clan's trap on 'tile'. A Trapper keeps at most
## GameConfig.max_traps_per_trapper traps; its oldest one disappears. Returns the events or null.
func set_trap(piece: Piece, tile: Vector2i, move: Variant) -> Variant:
	if not can_set_trap(piece, tile, move):
		return null
	var type: int = get_trap_type(piece)
	state.current_player.action_points -= maxi(0, state.config.trap_ap_cost)
	piece.acted_turn = state.turn_number
	var events: Array[ResolutionEvent] = []
	if move != null and move != piece.position:
		events.append_array(_to_events(OrderResolver.resolve_action(state, piece, move, null)))
	var adjacent: bool = absi(tile.x - piece.position.x) <= 1 and absi(tile.y - piece.position.y) <= 1
	if piece.is_alive and state.get_piece(piece.id) != null and adjacent and state.board.is_passable(tile) \
			and not state.board.is_occupied(tile) and state.board.get_trap(tile) == null:
		var own: Array[Trap] = []
		for t: Trap in state.board.traps.values():
			if t.source_piece_id == piece.id:
				own.append(t)
		own.sort_custom(func(a: Trap, b: Trap) -> bool: return a.serial < b.serial)
		var i: int = 0
		while i <= own.size() - maxi(1, state.config.max_traps_per_trapper):
			state.board.remove_trap(own[i].position)
			i += 1
		state.board.add_trap(tile, piece.owner_index, type, piece.id)
		var ev := ResolutionEvent.new()
		ev.type = ResolutionEventType.TRAP_SET
		ev.piece_id = piece.id
		ev.player_index = piece.owner_index
		ev.from = piece.position
		ev.to = tile
		ev.card_name = TrapInfo.display_name(type)
		ev.spell_name = TrapType.name_of(type)
		events.append(ev)
	_last_action_events = events
	action_resolved.emit(_last_action_events)
	state_changed.emit()
	return _last_action_events


## Spell power bonus for a spell of the current player aimed at 'target': 1 if one of its finished Obelisks
## stands within GameConfig.obelisk_empower_radius, else 0 (several Obelisks do not stack).
func spell_power(target: Vector2i) -> int:
	for p: Piece in state.get_pieces_of(state.current_player_index):
		if p.building == BuildingType.OBELISK and not p.under_construction \
				and GridPos.manhattan_distance(p.position, target) <= state.config.obelisk_empower_radius:
			return 1
	return 0


## The building this piece could construct (None if it is no Builder or its class builds nothing).
func get_build_type(piece: Piece) -> int:
	if piece != null and not piece.is_building and piece.has_keyword(Keyword.BUILDER) and piece.source != null:
		return BuildingInfo.for_class(piece.source.class_)
	return BuildingType.NONE


## Free tiles next to 'from_tile' (default null: the piece's tile; 8 directions) where the piece could build after
## moving there. The piece's own current tile counts as free when it builds from somewhere else.
func get_valid_build_tiles(piece: Piece, from_tile: Variant = null) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if piece == null:
		return result
	var at: Vector2i = from_tile if from_tile != null else piece.position
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var tile := Vector2i(at.x + dx, at.y + dy)
			var occupant: Piece = state.board.get_piece_at(tile)
			if (dx != 0 or dy != 0) and state.board.is_passable(tile) and (occupant == null or occupant == piece) \
					and not state.board.is_in_deploy_zone(1 - piece.owner_index, tile) and not state.board.is_in_hot_zone(tile):
				result.append(tile)
	return result


## Checks a build command: commandable Builder, not already building, enough AP, an optional reachable move
## first (the build replaces the attack), and 1..BuildingInfo.get_build_count distinct free tiles next to the
## destination. Merges both C# overloads: 'tiles' is a single Vector2i (CanBuild(piece, tile)) or an
## Array of Vector2i; 'move' is a Vector2i or null.
func can_build(piece: Piece, tiles: Variant, move: Variant = null) -> bool:
	var tile_list: Array[Vector2i] = _to_tile_list(tiles)
	if not can_command(piece):
		return false
	var type: int = get_build_type(piece)
	if type == BuildingType.NONE:
		return _fail("This unit cannot build.")
	if piece.constructing_id >= 0:
		return _fail("Already building something.")
	if BuildingInfo.get_cost(type) > state.current_player.action_points:
		return _fail("Not enough AP.")
	var moves: bool = move != null and move != piece.position
	if moves and _is_unreachable(state.board.find_path(piece.position, move, piece.effective_movement, piece.owner_index)):
		return _fail("Frozen - cannot move this turn." if piece.is_frozen else "Move target not reachable.")
	if tiles == null or tile_list.size() == 0 or tile_list.size() > BuildingInfo.get_build_count(type):
		return _fail("Choose where to build.")
	var valid: Array[Vector2i] = get_valid_build_tiles(piece, move if moves else null)
	var seen: Dictionary = {}
	for tile: Vector2i in tile_list:
		if seen.has(tile) or not valid.has(tile) or (moves and tile == move):
			return _fail("Build on free tiles next to the unit.")
		seen[tile] = true
	return true


## Build command: pays the building's AP cost and uses the piece's action. The piece first makes its move (if
## any; it resolves like a normal move, Turrets may shoot), then places its building(s) on the given tiles next
## to it (Barricades: up to two) and stays pinned until they are finished (BuildingInfo.get_build_turns own turns
## later). Returns the events or null. Merges both C# overloads ('tiles' = Vector2i or Array, 'move' = Vector2i or null).
func build(piece: Piece, tiles: Variant, move: Variant = null) -> Variant:
	if not can_build(piece, tiles, move):
		return null
	var tile_list: Array[Vector2i] = _to_tile_list(tiles)
	var type: int = get_build_type(piece)
	state.current_player.action_points -= BuildingInfo.get_cost(type)
	piece.acted_turn = state.turn_number
	var events: Array[ResolutionEvent] = []
	if move != null and move != piece.position:
		events.append_array(_to_events(OrderResolver.resolve_action(state, piece, move, null)))
	if piece.is_alive and state.get_piece(piece.id) != null:
		for tile: Vector2i in tile_list:
			# A push chain or a Turret shot during the move may have changed the board: skip blocked tiles.
			if not state.board.is_passable(tile) or state.board.is_occupied(tile) \
					or absi(tile.x - piece.position.x) > 1 or absi(tile.y - piece.position.y) > 1:
				continue
			var building: Piece = state.spawn_building(type, piece.owner_index, tile, state.turn_number + 2 * BuildingInfo.get_build_turns(type), piece.id)
			if piece.constructing_id < 0:
				piece.constructing_id = building.id
			var ev := ResolutionEvent.new()
			ev.type = ResolutionEventType.BUILDING_STARTED
			ev.piece_id = piece.id
			ev.other_piece_id = building.id
			ev.player_index = piece.owner_index
			ev.from = piece.position
			ev.to = tile
			ev.spell_name = BuildingInfo.display_name(type)
			ev.expiry_turn = building.complete_turn
			events.append(ev)
	_last_action_events = events
	action_resolved.emit(_last_action_events)
	state_changed.emit()
	return _last_action_events


## Shortest path for a move (same rules as get_valid_move_targets): the tiles after the piece's position,
## ending with target. Empty if target is the current tile or unreachable.
func get_planned_path(piece: Piece, target: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if piece == null:
		return result
	var path: Variant = state.board.find_path(piece.position, target, piece.effective_movement, piece.owner_index)
	if path != null:
		result.assign(path)
	return result


## Valid attack tiles for a piece standing at from_pos (default null: its current position).
func get_valid_attack_targets(piece: Piece, from_pos: Variant = null) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var center: Vector2i = from_pos if from_pos != null else piece.position
	result.assign(state.board.get_tiles_in_range(center, piece.effective_range))
	return result


## True if the current player may command this piece now: Main phase, own living piece, not summoning sick,
## not acted yet this turn. Does not check AP.
func can_command(piece: Piece) -> bool:
	if state.phase != GamePhase.MAIN:
		return _fail("Not in main phase.")
	if piece == null or state.get_piece(piece.id) == null:
		return _fail("Invalid piece.")
	if piece.owner_index != state.current_player_index:
		return _fail("Not your piece.")
	if piece.is_summoning_sick(state.turn_number):
		return _fail("Summoning sick - can act next turn.")
	if piece.is_building:
		return _fail("Buildings cannot be commanded.")
	if piece.has_acted(state.turn_number):
		return _fail("Already acted this turn.")
	return true


## Checks an action without applying it: can_command, GameConfig.order_ap_cost AP, the move must be reachable
## (get_valid_move_targets) and the attack tile in range from the destination. At least a move or an attack.
## move / attack: Vector2i or null.
func can_act(piece: Piece, move: Variant, attack: Variant) -> bool:
	if not can_command(piece):
		return false
	var moves: bool = move != null and move != piece.position
	if not moves and attack == null:
		return _fail("Nothing to do.")
	if state.config.order_ap_cost > state.current_player.action_points:
		return _fail("Not enough AP.")
	if moves and piece.constructing_id >= 0:
		return _fail("Busy building - it cannot move until the building is finished.")
	if moves and _is_unreachable(state.board.find_path(piece.position, move, piece.effective_movement, piece.owner_index)):
		return _fail("Frozen - cannot move this turn." if piece.is_frozen else "Move target not reachable.")
	var attack_from: Vector2i = move if move != null else piece.position
	if attack != null and (attack == attack_from or not state.board.is_in_attack_range(attack_from, attack, piece.effective_range)):
		return _fail("Attack target out of range.")
	return true


## Commands a piece: pays GameConfig.order_ap_cost, then its move and attack resolve IMMEDIATELY (friendly fire
## included). The piece cannot act again this turn. Returns the events (also last_action_events and
## action_resolved), or null if the action is invalid (see last_error).
func act(piece: Piece, move: Variant, attack: Variant) -> Variant:
	if not can_act(piece, move, attack):
		return null
	state.current_player.action_points -= maxi(0, state.config.order_ap_cost)
	piece.acted_turn = state.turn_number
	var real_move: Variant = move if (move != null and move != piece.position) else null
	_last_action_events = _to_events(OrderResolver.resolve_action(state, piece, real_move, attack))
	action_resolved.emit(_last_action_events)
	state_changed.emit()
	return _last_action_events


## Predicts what ONE attack of 'attacker' standing at 'from_pos' on tile 'target' would cause, on a clone of
## the CURRENT board: damage (friendly fire included), kills, keyword effects. If from_pos holds a friendly,
## the planned move is simulated (push).
## Does not check AP / summoning sickness; is_valid is false if the attack is impossible (range etc.).
## Merges both C# overloads: predict_attack(attacker, target) uses the attacker's current position.
func predict_attack(attacker: Piece, from_or_target: Vector2i, target: Variant = null) -> ChainPreview:
	var from_pos: Vector2i = from_or_target
	var target_pos: Vector2i = from_or_target
	if target == null:
		from_pos = attacker.position if attacker != null else from_or_target
	else:
		target_pos = target
	var invalid := ChainPreview.new()
	invalid.attacker_id = attacker.id if attacker != null else -1
	invalid.from = from_pos
	invalid.target = target_pos
	invalid.is_valid = false
	if attacker == null or state.get_piece(attacker.id) == null:
		return invalid
	if not state.board.is_in_attack_range(from_pos, target_pos, attacker.effective_range):
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
	var events: Array[ResolutionEvent] = _to_events(OrderResolver.simulate_attack(clone, a, target_pos))
	return ChainPreview.from_events(attacker.id, from_pos, target_pos, attacker.owner_index, owners, events)


# ------------------------------------------------------------------ end of turn

## Ends the current turn: expires spells, statuses and tile effects with expiry_turn <= turn_number, swaps
## player, increments turn_number and starts the next turn (its tile ticks are in last_turn_start_events).
## Returns the expiry events (empty list if the call was invalid). Piece actions were already resolved by act.
func end_turn() -> Array[ResolutionEvent]:
	if state.phase != GamePhase.MAIN:
		_fail("Can only end the turn in main phase.")
		return [] as Array[ResolutionEvent]
	state.phase = GamePhase.RESOLVING
	var events: Array[ResolutionEvent] = []
	_expire_spells(events)
	_expire_statuses(events)
	_expire_tile_effects(events)
	turn_ended.emit(events)

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
	expired.sort_custom(func(a: TileEffect, b: TileEffect) -> bool:
		if a.position.y != b.position.y:
			return a.position.y < b.position.y
		return a.position.x < b.position.x)
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


## True if a find_path result means "unreachable" (null; an empty path only occurs for from == to, which callers exclude).
func _is_unreachable(path: Variant) -> bool:
	return path == null or (path is Array and (path as Array).is_empty())


## Copies any event array (typed or untyped, null = empty) into a typed Array[ResolutionEvent].
func _to_events(src: Variant) -> Array[ResolutionEvent]:
	var result: Array[ResolutionEvent] = []
	if src != null:
		result.assign(src)
	return result


## Single Vector2i or array of Vector2i -> typed tile list (for the merged build overloads).
func _to_tile_list(tiles: Variant) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if tiles is Vector2i:
		result.append(tiles)
	elif tiles is Array:
		result.assign(tiles)
	return result
