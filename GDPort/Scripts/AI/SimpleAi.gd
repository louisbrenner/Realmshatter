class_name SimpleAi
extends RefCounted
## Heuristic AI opponent. Uses only the public TurnController command API.
## AP is budgeted greedily in priority order, re-evaluated after every action:
## 1. finish a pending draft (free), 2. high-value orders (attacks, entering the scoring zone),
## 3. units while the own board is weak, 4. draw if the hand has nothing useful,
## 5. low-value orders (advance toward the zone), 6. remaining cards (spells incl. tile spells, units up to a cap),
## 7. draw with leftover AP, 8. convert VP into AP for a very valuable order (kills) when the VP lead is safe
## or the opponent is about to win.
## Orders: move toward a free scoring-zone tile (avoiding lava, friendlies may be passed), attack the target
## whose TurnController.predict_attack outcome is best (direct hits, chains through friendlies, keyword effects).
## It never calls end_turn; the caller does that after presenting the actions.

const MAX_STEPS := 64
const HIGH_ORDER_VALUE := 3
const MAX_DESIRED_PIECES := 6
const VP_ORDER_VALUE := 6
const LAVA_PENALTY := 25

const _INT_MAX := 2147483647
const _INT_MIN := -2147483648

var _controller: TurnController


## Simulated resolution-time knowledge for the orders already queued this turn.
class PlanContext:
	extends RefCounted
	## Set of Vector2i (Dictionary used as a set).
	var sim_occupied: Dictionary = {}
	## piece id -> planned damage.
	var planned_damage: Dictionary = {}
	## Set of piece ids.
	var planned: Dictionary = {}
	## Set of piece ids.
	var chain_fired: Dictionary = {}


class OrderCandidate:
	extends RefCounted
	var piece: Piece = null
	## Vector2i or null.
	var move: Variant = null
	## AttackPlan or null.
	var attack: Variant = null
	var value: int = 0

	func copy() -> OrderCandidate:
		var c := OrderCandidate.new()
		c.piece = piece
		c.move = move
		c.attack = attack
		c.value = value
		return c


class AttackPlan:
	extends RefCounted
	var tile: Vector2i = Vector2i.ZERO
	var chain_piece_id: int = 0
	var value: int = 0
	## Array of [piece_id: int, damage: int].
	var hits: Array = []
	var triggered: Array[int] = []

	func copy() -> AttackPlan:
		var c := AttackPlan.new()
		c.tile = tile
		c.chain_piece_id = chain_piece_id
		c.value = value
		c.hits = hits
		c.triggered = triggered
		return c


## The player this AI controls.
var player_index: int = 0

var _state: GameState:
	get:
		return _controller.state

var _board: BoardState:
	get:
		return _controller.state.board

## True if it is this AI's turn and the game is in Draft or Main phase.
var is_my_turn: bool:
	get:
		return (_state.winner < 0
			and _state.current_player_index == player_index
			and (_state.phase == GamePhase.DRAFT or _state.phase == GamePhase.MAIN))


## Creates an AI for the given player of the controller's game.
func _init(controller: TurnController, p_player_index: int) -> void:
	if controller == null:
		push_error("SimpleAi: controller is null")
	if p_player_index < 0 or p_player_index >= GameState.PLAYER_COUNT:
		push_error("SimpleAi: player_index out of range: %d" % p_player_index)
	_controller = controller
	player_index = p_player_index


## Executes the whole turn synchronously via the TurnController (draws, cards, orders, VP conversions) and
## returns the executed steps in order (Array of AiAction). Does NOT call end_turn. Returns an empty list if it
## is not this AI's turn. Always leaves the game in Main phase (a started draw is completed).
func take_turn() -> Array[AiAction]:
	var actions: Array[AiAction] = []
	if not is_my_turn:
		return actions

	if _state.phase == GamePhase.DRAFT:
		_do_draft(actions, false)

	var ctx := PlanContext.new()
	for pos in _board.occupancy.keys():
		ctx.sim_occupied[pos] = true
	for _step in range(MAX_STEPS):
		if _state.phase != GamePhase.MAIN or _state.current_player_index != player_index:
			break
		if _try_command(actions, ctx, HIGH_ORDER_VALUE, false):
			continue
		if _is_board_weak() and _try_play_best_card(actions, ctx, true):
			continue
		if _should_draw_early() and _try_draw(actions):
			continue
		if _try_command(actions, ctx, 1, false):
			continue
		if _try_play_best_card(actions, ctx, false):
			continue
		if _try_draw(actions):
			continue
		if _try_command(actions, ctx, VP_ORDER_VALUE, true):
			continue
		break

	# Safety net: never leave an unfinished draft behind.
	if _state.phase == GamePhase.DRAFT and _state.current_player_index == player_index:
		_do_draft(actions, false)
	return actions


## Picks the index of the best card in a draft offer, or -1 for an empty offer.
## Early on, Resource units are preferred while few own Resource pieces exist; otherwise the
## strongest unit (attack + hp + shield + keywords); spells only score well once own pieces are on the board.
func choose_draft_index(offer: Array) -> int:
	if offer == null or offer.size() == 0:
		return -1

	var me: PlayerState = _state.players[player_index]
	var my_pieces: Array = _state.get_pieces_of(player_index)
	var resource_count: int = 0
	var hand_units: int = 0
	var hand_spells: int = 0
	for p: Piece in my_pieces:
		if p.role == UnitRole.RESOURCE:
			resource_count += 1
	for c: CardData in me.hand:
		if c == null:
			continue
		if c.card_type == CardType.SPELL:
			hand_spells += 1
		else:
			hand_units += 1
			if c.role == UnitRole.RESOURCE:
				resource_count += 1
	var early: bool = _state.turn_number <= 8
	var have_units: bool = my_pieces.size() + hand_units > 0

	var best: int = -1
	var best_score: float = -INF
	for i in range(offer.size()):
		var card: CardData = offer[i]
		if card == null:
			continue
		var score: float
		if card.card_type == CardType.UNIT:
			score = float(_unit_strength(card))
			if card.role == UnitRole.RESOURCE and early and resource_count < 2:
				score += 10.0
		else:
			score = (_spell_draft_value(card) * 1.5 + 1.0 - hand_spells * 2.0) \
				if (my_pieces.size() > 0 or card.targets_tile) else -5.0
			if not have_units:
				score -= 10.0
		if score > best_score:
			best_score = score
			best = i
	return best


# ---------------------------------------------------------------- draft

## Pays for a Draw and picks the best offered card. False if drawing is not possible.
func _try_draw(actions: Array[AiAction]) -> bool:
	if not _controller.can_draw() or not _controller.draw():
		return false
	_do_draft(actions, true)
	return true


func _do_draft(actions: Array[AiAction], paid: bool) -> void:
	var me: PlayerState = _state.players[player_index]
	if me.draft_offer.size() == 0:
		return
	var index: int = choose_draft_index(me.draft_offer)
	if index < 0 or index >= me.draft_offer.size():
		index = 0
	var card: CardData = me.draft_offer[index]
	if not _controller.choose_draft_card(index) and not _controller.choose_draft_card(0):
		return
	var desc: String
	if paid:
		desc = "Drew (%d AP) and kept %s" % [_state.config.draw_ap_cost, _card_name(card)]
	else:
		desc = "Drafted %s" % _card_name(card)
	actions.append(_make_action(AiActionKind.DRAFT, card, -1, null, null, null, desc))


## Few own pieces, or fewer than the opponent.
func _is_board_weak() -> bool:
	var mine: int = _state.get_pieces_of(player_index).size()
	var theirs: int = _state.get_pieces_of(1 - player_index).size()
	return mine < 3 or mine < theirs


## Draw before spending AP elsewhere if the hand is empty, or the board is weak and no unit is in hand.
func _should_draw_early() -> bool:
	var hand: Array = _state.players[player_index].hand
	if hand.size() == 0:
		return true
	if not _is_board_weak():
		return false
	for c: CardData in hand:
		if c != null and c.card_type == CardType.UNIT:
			return false
	return true


# ---------------------------------------------------------------- VP -> AP

## Converting VP is worth it only if the lead is safe (>= 3 VP ahead and not about to win anyway)
## or the opponent is close to winning (spend to fight back).
func _should_spend_vp() -> bool:
	var me: PlayerState = _state.players[player_index]
	var opp: PlayerState = _state.players[1 - player_index]
	if me.victory_points < 1 or not _controller.can_convert_vp_to_ap():
		return false
	var target: int = _state.config.points_target
	var safe_lead: bool = me.victory_points - opp.victory_points >= 3 and me.victory_points < target - 3
	var desperate: bool = opp.victory_points >= target - 4
	return safe_lead or desperate


func _try_convert_vp(actions: Array[AiAction], reason: String) -> bool:
	if not _should_spend_vp() or not _controller.convert_vp_to_ap():
		return false
	actions.append(_make_action(AiActionKind.CONVERT_VP, null, -1, null, null, null,
		"Converted 1 VP into 1 AP (%s)" % reason))
	return true


# ---------------------------------------------------------------- cards

func _try_play_best_card(actions: Array[AiAction], ctx: PlanContext, units_only: bool) -> bool:
	var me: PlayerState = _state.players[player_index]
	var units_allowed: bool = units_only or _state.get_pieces_of(player_index).size() < MAX_DESIRED_PIECES
	var best_card: CardData = null
	var best_tile: Vector2i = Vector2i.ZERO
	var best_target: Piece = null
	var best_cost: int = _INT_MAX
	var best_value: float = -INF

	for card: CardData in me.hand.duplicate():
		if (card == null
				or (card.card_type == CardType.UNIT and not units_allowed)
				or (card.card_type == CardType.SPELL and units_only)):
			continue
		var cost: int = _controller.get_card_cost(card)
		if cost > me.action_points:
			continue

		var tile: Vector2i = Vector2i.ZERO
		var target: Piece = null
		var value: float
		if card.card_type == CardType.UNIT:
			var deploy: Variant = _find_deploy_tile(card)
			if deploy == null:
				continue
			tile = deploy
			value = float(_unit_strength(card))
		elif card.targets_tile:
			var res: Array = _find_tile_spell_target(card, ctx)
			var anchor: Variant = res[0]
			if anchor == null:
				continue
			tile = anchor
			value = float(res[1])
		else:
			target = _find_spell_target(card)
			if target == null:
				continue
			value = float(maxi(1, absi(_spell_net(card))))

		if cost < best_cost or (cost == best_cost and value > best_value):
			best_card = card
			best_tile = tile
			best_target = target
			best_cost = cost
			best_value = value

	if best_card == null:
		return false

	if best_card.card_type == CardType.UNIT:
		var piece: Piece = _controller.play_unit_card(best_card, best_tile)
		if piece == null:
			return false
		ctx.sim_occupied[best_tile] = true
		actions.append(_make_action(AiActionKind.PLAY_UNIT, best_card, piece.id, best_tile, null, null,
			"Deployed %s at %s" % [_card_name(best_card), str(best_tile)]))
	elif best_card.targets_tile:
		if not _controller.play_spell_on_tile(best_card, best_tile):
			return false
		# Kills from the spell free tiles; walls are respected by _simulated_reachable via the board.
		for p in ctx.sim_occupied.keys():
			if not _board.is_occupied(p) and not _is_planned_destination(ctx, p):
				ctx.sim_occupied.erase(p)
		actions.append(_make_action(AiActionKind.PLAY_SPELL, best_card, -1, best_tile, null, null,
			"Cast %s on %s" % [_card_name(best_card), str(best_tile)]))
	else:
		var target_pos: Vector2i = best_target.position
		if not _controller.play_spell_card(best_card, best_target):
			return false
		actions.append(_make_action(AiActionKind.PLAY_SPELL, best_card, best_target.id, target_pos, null, null,
			"Cast %s on #%d %s at %s" % [_card_name(best_card), best_target.id, _card_name(best_target.source), str(target_pos)]))
	return true


func _is_planned_destination(ctx: PlanContext, pos: Vector2i) -> bool:
	for p: Piece in _state.get_pieces_of(player_index):
		if ctx.planned.has(p.id) and p.order != null and p.order.move_target != null and p.order.move_target == pos:
			return true
	return false


## Free own deploy tile closest to the scoring zone (ties: free tile ahead, then center column). Avoids lava.
## Returns Vector2i or null.
func _find_deploy_tile(card: CardData) -> Variant:
	var best: Variant = null
	var best_score: int = _INT_MAX
	var forward: int = BoardState.forward_direction(player_index)
	for y in range(_board.height):
		for x in range(_board.width):
			var pos := Vector2i(x, y)
			if not _board.is_in_deploy_zone(player_index, pos) or _board.is_occupied(pos):
				continue
			if not _controller.can_play_unit_card(card, pos):
				continue
			var ahead := Vector2i(x, y + forward)
			var score: int = _distance_to_zone_rect(pos) * 20 \
				+ (10 if _board.is_inside(ahead) and (_board.is_occupied(ahead) or _board.is_wall(ahead)) else 0) \
				+ (50 if _board.get_tile_effect_type(pos) == TileEffectType.LAVA else 0) \
				+ absi(2 * x - (_board.width - 1))
			if score < best_score:
				best_score = score
				best = pos
	return best


## Buff (net positive deltas): own piece nearest the zone / most threatened. Debuff: strongest enemy.
## Overcharge-like status spells: own piece whose chain would hit the most enemies.
func _find_spell_target(card: CardData) -> Piece:
	if card.grant_status == StatusEffectType.OVERCHARGED:
		return _find_overcharge_target(card)
	var net: int = _spell_net(card)
	if net == 0:
		return null
	var buff: bool = net > 0
	var best: Piece = null
	var best_score: float = -INF
	for p: Piece in _state.pieces:
		if not p.is_alive:
			continue
		var mine: bool = p.owner_index == player_index
		if mine != buff:
			continue
		var score: float
		if buff:
			score = float((20 if _board.is_in_scoring_zone(p.position) else 0)
				- _distance_to_zone_rect(p.position) * 2
				+ _threat_count(p) * 5
				+ p.effective_attack)
		else:
			score = float(p.effective_attack * 2 + p.current_hp + p.total_shield
				+ (10 if _board.is_in_scoring_zone(p.position) else 0))
		if _has_spell(p, card):
			score -= 15.0
		if score > best_score and _controller.can_play_spell_card(card, p):
			best_score = score
			best = p
	return best


## Own piece (not yet Overcharged) whose chain directions hold enemies and that a friendly can trigger.
func _find_overcharge_target(card: CardData) -> Piece:
	var best: Piece = null
	var best_value: int = 1
	for p: Piece in _state.get_pieces_of(player_index):
		if p.has_status(StatusEffectType.OVERCHARGED) or p.effective_attack <= 0 or not _controller.can_play_spell_card(card, p):
			continue
		var enemies: int = _chain_hits(p).size()
		if enemies == 0 or not _can_be_triggered(p):
			continue
		var value: int = enemies * 2 + p.effective_attack
		if value > best_value:
			best_value = value
			best = p
	return best


## True if another own commandable piece has this piece within attack range (from its current tile).
func _can_be_triggered(target: Piece) -> bool:
	for p: Piece in _state.get_pieces_of(player_index):
		if (p != target and p.order == null and not p.is_summoning_sick(_state.turn_number)
				and _board.is_in_attack_range(p.position, target.position, p.effective_range)):
			return true
	return false


## Best anchor for a tile/area spell, scored by: enemy damage / kills, lava under enemies (minus own pieces
## on lava), walls in front of advancing enemies (minus walls in front of own pieces), healing of
## damaged own pieces. Returns [anchor: Vector2i or null, best_value: int]; anchor null if nothing reaches
## the minimum value.
func _find_tile_spell_target(card: CardData, ctx: PlanContext) -> Array:
	var best_value: int = 0
	var best: Variant = null
	var min_value: int = 3 if card.tile_effect == TileEffectType.WALL else (2 if card.tile_effect == TileEffectType.HEALING else 4)
	for y in range(_board.height):
		for x in range(_board.width):
			var anchor := Vector2i(x, y)
			if not _controller.can_play_spell_on_tile(card, anchor):
				continue
			var value: int = _score_tile_spell(card, anchor, ctx)
			if value >= min_value and value > best_value:
				best_value = value
				best = anchor
	return [best, best_value]


func _score_tile_spell(card: CardData, anchor: Vector2i, ctx: PlanContext) -> int:
	var value: int = 0
	for t: Vector2i in _controller.get_spell_area_preview(card, anchor):
		var p: Piece = _board.get_piece_at(t)
		var enemy: bool = p != null and p.owner_index != player_index
		var mine: bool = p != null and p.owner_index == player_index
		if enemy and card.spell_damage > 0:
			var kills: bool = p.current_hp + p.total_shield <= card.spell_damage
			if kills and ctx.planned_damage.has(p.id):
				# A queued attack targets this tile: killing it now would make that order hit an empty tile.
				return _INT_MIN
			value += 6 if kills else 2
		if mine and card.spell_heal > 0:
			value += mini(card.spell_heal, p.max_hp - p.current_hp)
		match card.tile_effect:
			TileEffectType.LAVA:
				value += 1 if enemy else 0
				value -= 3 if mine else 0
			TileEffectType.HEALING:
				if mine:
					value += mini(2, p.max_hp - p.current_hp) + (1 if _board.is_in_scoring_zone(t) else 0)
			TileEffectType.WALL:
				if p == null:
					value += _wall_value(t)
	return value


## +2 per enemy whose next 1-2 forward tiles include t, -2 per own piece likewise, +1 if t is a zone tile an enemy can reach.
func _wall_value(t: Vector2i) -> int:
	var value: int = 0
	for p: Piece in _state.pieces:
		var fwd: int = BoardState.forward_direction(p.owner_index)
		var in_front: bool = t == Vector2i(p.position.x, p.position.y + fwd) or t == Vector2i(p.position.x, p.position.y + 2 * fwd)
		if p.owner_index != player_index:
			value += 2 if in_front else 0
			if _board.is_in_scoring_zone(t) and GridPos.manhattan_distance(p.position, t) <= p.effective_movement:
				value += 1
		elif in_front:
			value -= 2
	return value


# ---------------------------------------------------------------- orders

## Evaluates every commandable own piece without an order and queues the best order whose value is at
## least min_value. If AP is missing and allow_vp is set, converts 1 VP into AP first (_should_spend_vp).
## False if none qualifies.
func _try_command(actions: Array[AiAction], ctx: PlanContext, min_value: int, allow_vp: bool) -> bool:
	var need_ap: bool = _state.config.order_ap_cost > _state.players[player_index].action_points
	if need_ap and not (allow_vp and _should_spend_vp()):
		return false
	if not need_ap and allow_vp:
		return false

	var best: OrderCandidate = null
	for piece: Piece in _state.get_pieces_of(player_index):
		if piece.order != null or ctx.planned.has(piece.id) or not _controller.can_command(piece):
			continue
		var c: OrderCandidate = _evaluate_order(piece, ctx)
		if c == null or c.value < min_value:
			continue
		if best == null or _is_better(c, best):
			best = c
	if best == null:
		return false

	var pick: OrderCandidate = best
	var p: Piece = pick.piece
	var attack_plan: AttackPlan = pick.attack
	var attack_tile: Variant = attack_plan.tile if attack_plan != null else null
	while _state.config.order_ap_cost > _state.players[player_index].action_points:
		if not _try_convert_vp(actions, "for %s's order" % _card_name(p.source)):
			return false
	if not _controller.set_order(p, pick.move, attack_tile):
		return false

	ctx.planned[p.id] = true
	if pick.move != null:
		ctx.sim_occupied.erase(p.position)
		ctx.sim_occupied[pick.move] = true
	if attack_plan != null:
		for hit: Array in attack_plan.hits:
			var id: int = hit[0]
			var dmg: int = hit[1]
			var prev: int = ctx.planned_damage.get(id, 0)
			ctx.planned_damage[id] = prev + dmg
		for id: int in attack_plan.triggered:
			ctx.chain_fired[id] = true

	actions.append(_make_action(AiActionKind.SET_ORDER, p.source, p.id,
		attack_tile if attack_tile != null else pick.move, pick.move, attack_tile,
		_describe_order(p, pick.move, attack_plan) + " (%d AP)" % _state.config.order_ap_cost))
	return true


func _is_better(a: OrderCandidate, b: OrderCandidate) -> bool:
	if a.value != b.value:
		return a.value > b.value
	var da: int = _distance_to_zone_rect(a.piece.position)
	var db: int = _distance_to_zone_rect(b.piece.position)
	return da < db if da != db else a.piece.id < b.piece.id


## Plans move + attack for a piece and scores it: attack = predicted value (3 per enemy hit, 6 per kill,
## +1 per keyword effect), entering the scoring zone = 4, advancing toward it = 1-2, leaving lava = 1.
## Null if the order would do nothing useful. Validity is checked without AP (_try_command handles AP).
func _evaluate_order(piece: Piece, ctx: PlanContext) -> OrderCandidate:
	var dest: Vector2i = _choose_move(piece, ctx.sim_occupied, ctx.planned_damage)
	var attack: AttackPlan = null if ctx.chain_fired.has(piece.id) else _choose_attack(piece, dest, ctx)
	var move: Variant = dest if dest != piece.position else null

	if move != null and not _controller.get_valid_move_targets(piece).has(move):
		move = null
		attack = null if ctx.chain_fired.has(piece.id) else _choose_attack(piece, piece.position, ctx)
	var attack_from: Vector2i = move if move != null else piece.position
	if attack != null and not _board.is_in_attack_range(attack_from, attack.tile, piece.effective_range):
		attack = null
	if move == null and attack == null:
		return null

	var value: int = attack.value if attack != null else 0
	if move != null:
		var was_in_zone: bool = _board.is_in_scoring_zone(piece.position)
		if not was_in_zone and _board.is_in_scoring_zone(move):
			value += 4
		else:
			var progress: int = _distance_to_zone_rect(piece.position) - _distance_to_zone_rect(move)
			if progress > 0:
				value += 2 if progress >= 2 else 1
		if (_board.get_tile_effect_type(piece.position) == TileEffectType.LAVA
				and _board.get_tile_effect_type(move) != TileEffectType.LAVA):
			value += 1
	if value <= 0:
		return null
	var cand := OrderCandidate.new()
	cand.piece = piece
	cand.move = move
	cand.attack = attack
	cand.value = value
	return cand


## Chooses a destination: nearest to a free scoring-zone tile, then best attack opportunity, then fewest steps.
## Lava tiles are penalized; friendlies may be passed but not used as destinations (no pushes planned).
func _choose_move(piece: Piece, sim_occupied: Dictionary, planned_damage: Dictionary) -> Vector2i:
	var start: Vector2i = piece.position
	var in_zone: bool = _board.is_in_scoring_zone(start)

	var candidates: Array[Vector2i] = [start]
	if piece.effective_movement > 0:
		var sim_reach: Dictionary = _simulated_reachable(start, piece.effective_movement, sim_occupied)
		for t: Vector2i in _controller.get_valid_move_targets(piece):
			if sim_reach.has(t) and (not in_zone or _board.is_in_scoring_zone(t)):
				candidates.append(t)

	var free_zone: Array[Vector2i] = []
	var zone: Rect2i = _board.scoring_zone
	for y in range(zone.position.y, zone.end.y):
		for x in range(zone.position.x, zone.end.x):
			var z := Vector2i(x, y)
			if _board.is_passable(z) and (z == start or not sim_occupied.has(z)):
				free_zone.append(z)

	var best: Vector2i = start
	var best_score: int = _INT_MAX
	for c: Vector2i in candidates:
		var dist: int
		if _board.is_in_scoring_zone(c):
			dist = 0
		elif free_zone.size() > 0:
			dist = _INT_MAX
			for z: Vector2i in free_zone:
				dist = mini(dist, GridPos.manhattan_distance(c, z))
		else:
			dist = _distance_to_zone_rect(c)
		var score: int = dist * 10 - _attack_opportunity(piece, c, planned_damage) * 2 + GridPos.manhattan_distance(start, c)
		if _board.get_tile_effect_type(c) == TileEffectType.LAVA:
			score += LAVA_PENALTY * 3 if piece.current_hp <= _state.config.lava_damage else LAVA_PENALTY
		elif _board.get_tile_effect_type(c) == TileEffectType.HEALING and piece.current_hp < piece.max_hp:
			score -= 5
		if score < best_score:
			best_score = score
			best = c
	return best


## 2 if a killable enemy is in range from 'from', 1 if any enemy is, else 0.
func _attack_opportunity(piece: Piece, from: Vector2i, planned_damage: Dictionary) -> int:
	var atk: int = piece.effective_attack
	if atk <= 0:
		return 0
	var result: int = 0
	for tile: Vector2i in _board.get_tiles_in_range(from, piece.effective_range):
		var target: Piece = _board.get_piece_at(tile)
		if target == null or target.owner_index == player_index:
			continue
		var ehp: int = _remaining_ehp(target, planned_damage)
		if ehp <= 0:
			continue
		if ehp <= atk:
			return 2
		result = 1
	return result


## Attack from 'from': every occupied tile in range is evaluated with TurnController.predict_attack (direct
## enemy hits as well as chains through unplanned friendlies) and scored by _score_preview. Ties prefer direct
## hits. Null if nothing has a positive value.
func _choose_attack(piece: Piece, from: Vector2i, ctx: PlanContext) -> AttackPlan:
	var best: AttackPlan = null
	var best_direct: bool = false
	for tile: Vector2i in _controller.get_valid_attack_targets(piece, from):
		var target: Piece = _board.get_piece_at(tile)
		if target == null or target == piece or not target.is_alive:
			continue
		var friendly: bool = target.owner_index == player_index
		if friendly and (ctx.planned.has(target.id) or ctx.chain_fired.has(target.id)):
			continue
		if not friendly and _remaining_ehp(target, ctx.planned_damage) <= 0:
			continue
		var preview: ChainPreview = _controller.predict_attack(piece, from, tile)
		if not preview.is_valid:
			continue
		var plan: AttackPlan = _score_preview(preview, ctx, tile, target.id if friendly else -1)
		if plan.value <= 0:
			continue
		var direct: bool = not friendly
		if best == null or plan.value > best.value or (plan.value == best.value and direct and not best_direct):
			best = plan
			best_direct = direct
	return best


## Scores a preview: per enemy hit 3 (6 if it kills given planned damage), +1 per keyword effect, + heals.
func _score_preview(preview: ChainPreview, ctx: PlanContext, tile: Vector2i, chain_piece_id: int) -> AttackPlan:
	var hits: Array = []
	var local: Dictionary = {}
	var value: int = 0
	for hit: PredictedHit in preview.hits:
		if hit.target_piece_id < 0 or hit.is_friendly:
			continue
		var enemy: Piece = _state.get_piece(hit.target_piece_id)
		if enemy == null:
			continue
		var already: int = local.get(enemy.id, 0)
		var ehp: int = _remaining_ehp(enemy, ctx.planned_damage) - already
		if ehp <= 0:
			continue
		if hit.damage > 0:
			value += 6 if ehp <= hit.damage else 3
			local[enemy.id] = already + hit.damage
			hits.append([enemy.id, hit.damage])
		if (hit.effects & HitEffect.FROZEN) != 0:
			value += 1
		if (hit.effects & HitEffect.LAVA) != 0:
			value += 1
		if (hit.effects & HitEffect.PUSHED) != 0:
			value += 3 if (_board.is_in_scoring_zone(enemy.position) and hit.pushed_to != null
				and not _board.is_in_scoring_zone(hit.pushed_to)) else 1
	value += preview.friendly_healed
	var plan := AttackPlan.new()
	plan.tile = tile
	plan.chain_piece_id = chain_piece_id
	plan.value = value
	plan.hits = hits
	var triggered: Array[int] = []
	for id: int in preview.triggered_piece_ids:
		triggered.append(id)
	plan.triggered = triggered
	return plan


## Enemies the friendly's chain fire would hit directly (nearest piece per chain direction, walls stop).
func _chain_hits(shooter: Piece) -> Array[int]:
	var hits: Array[int] = []
	var left: int = BoardState.left_direction(shooter.owner_index)
	var fwd: int = BoardState.forward_direction(shooter.owner_index)
	var dirs: Array[Vector2i] = [Vector2i(left, 0), Vector2i(-left, 0)]
	if shooter.has_keyword(Keyword.CONDUIT):
		dirs.append(Vector2i(0, fwd))
		dirs.append(Vector2i(0, -fwd))
	for dir: Vector2i in dirs:
		for d in range(1, shooter.effective_range + 1):
			var tile := Vector2i(shooter.position.x + dir.x * d, shooter.position.y + dir.y * d)
			if not _board.is_passable(tile):
				break
			var p: Piece = _board.get_piece_at(tile)
			if p == null:
				continue
			if p.owner_index != player_index:
				hits.append(p.id)
			break
	return hits


## Tiles reachable with the v3 move rules where the piece may END (not sim-occupied). Own pieces are passable.
## Returns a Dictionary used as a set of Vector2i.
func _simulated_reachable(from: Vector2i, movement: int, occupied: Dictionary) -> Dictionary:
	var dist: Dictionary = {from: 0}
	var queue: Array[Vector2i] = [from]
	var result: Dictionary = {}
	while queue.size() > 0:
		var cur: Vector2i = queue.pop_front()
		var d: int = dist[cur]
		if d >= movement:
			continue
		for next: Vector2i in GridPos.neighbors(cur):
			if not _board.is_passable(next) or dist.has(next):
				continue
			var occupant: Piece = _board.get_piece_at(next)
			if occupant != null and occupant.owner_index != player_index:
				continue
			dist[next] = d + 1
			if not occupied.has(next):
				result[next] = true
			queue.append(next)
	return result


# ---------------------------------------------------------------- helpers

func _distance_to_zone_rect(pos: Vector2i) -> int:
	var zone: Rect2i = _board.scoring_zone
	var dx: int = maxi(0, maxi(zone.position.x - pos.x, pos.x - (zone.end.x - 1)))
	var dy: int = maxi(0, maxi(zone.position.y - pos.y, pos.y - (zone.end.y - 1)))
	return dx + dy


func _threat_count(piece: Piece) -> int:
	var threats: int = 0
	for e: Piece in _state.pieces:
		if (e.owner_index != piece.owner_index and e.is_alive
				and GridPos.manhattan_distance(e.position, piece.position) <= e.effective_movement + e.effective_range):
			threats += 1
	return threats


static func _remaining_ehp(target: Piece, planned_damage: Dictionary) -> int:
	var dmg: int = planned_damage.get(target.id, 0)
	return target.current_hp + target.total_shield - dmg


static func _has_spell(piece: Piece, card: CardData) -> bool:
	for s: ActiveSpell in piece.active_spells:
		if s.source == card:
			return true
	return false


static func _unit_strength(card: CardData) -> int:
	return card.attack + card.hp + card.shield + KeywordInfo.split(card.keywords).size()


static func _spell_net(card: CardData) -> int:
	return card.attack_delta + card.hp_delta + card.shield_delta + card.movement_delta + card.range_delta


static func _spell_draft_value(card: CardData) -> int:
	return (absi(_spell_net(card)) + card.spell_damage * 2 + card.spell_heal
		+ (2 if card.tile_effect != TileEffectType.NONE else 0)
		+ (2 if card.grant_status != StatusEffectType.NONE else 0))


static func _card_name(card: CardData) -> String:
	return card.name if card != null else "?"


func _describe_order(piece: Piece, move: Variant, attack: AttackPlan) -> String:
	var text: String = "#%d %s" % [piece.id, _card_name(piece.source)]
	text += (" moves to %s" % str(move)) if move != null else " holds"
	if attack != null:
		var target: Piece = _board.get_piece_at(attack.tile)
		var target_name: String = ("#%d %s" % [target.id, _card_name(target.source)]) if target != null else "tile"
		if attack.chain_piece_id >= 0:
			text += ", triggers chain via %s at %s" % [target_name, str(attack.tile)]
		else:
			text += ", attacks %s at %s" % [target_name, str(attack.tile)]
	return text


## Replaces the C# object initializer `new AiAction { ... }`.
func _make_action(kind: int, card: CardData, piece_id: int, target: Variant, move_target: Variant,
		attack_target: Variant, description: String) -> AiAction:
	var a := AiAction.new()
	a.kind = kind
	a.player_index = player_index
	a.card = card
	a.piece_id = piece_id
	a.target = target
	a.move_target = move_target
	a.attack_target = attack_target
	a.description = description
	return a
