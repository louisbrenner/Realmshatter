class_name SimpleAi
extends RefCounted
## Heuristic AI opponent. Uses only the public TurnController command API.
## AP is budgeted greedily in priority order, re-evaluated after every action:
## 1. finish a pending draft (free), 2. high-value actions (attacks, entering the scoring zone),
## 3. one reinforcement per turn while the own army is critically small, 4. draw if the hand has nothing useful,
## 5. strong expensive cards (3+ AP, high value per AP) before low-value moves,
## 6. buildings (before the builders walk off), 7. advance toward the scoring zone (before any further deploys,
## so the army never camps in its base), 8. remaining cards (spells incl. tile spells, units up to a cap),
## 9. draw with leftover AP, 10. convert VP into AP for a very valuable action (kills) when the VP lead is safe
## or the opponent is about to win.
## AP-gaining spells (Mana Surge) are cast first. Cards are chosen by _card_value with a small knapsack over the hand
## (the most valuable set the AP budget allows), and VP may be converted to pay for a strong card of 4+ AP.
## Actions resolve immediately (TurnController.act), so every decision sees the real board. A piece moves toward
## a free scoring-zone tile (avoiding lava, friendlies may be passed) and attacks the target whose
## TurnController.predict_attack outcome is best: enemy damage and kills minus friendly fire (Pierce / Arc can
## hit own pieces), keyword effects and Mending heals.
## It never calls end_turn; the caller does that after presenting the actions.

const MAX_STEPS := 64
const HIGH_ORDER_VALUE := 3
const MAX_DESIRED_PIECES := 6
const VP_ORDER_VALUE := 6
const LAVA_PENALTY := 25
const MAX_HAND_TO_DRAW := 6
const MAX_BUILDINGS := 4

const _INT_MAX := 2147483647

var _controller: TurnController


## Board knowledge of the current turn (actions resolve immediately, so it mirrors the real board).
class PlanContext:
	extends RefCounted
	## Set of Vector2i (Dictionary used as a set).
	var sim_occupied: Dictionary = {}
	## Always empty now (no queued damage); kept so the scoring helpers stay uniform. piece id -> damage.
	var planned_damage: Dictionary = {}


class AttackPlan:
	extends RefCounted
	var tile: Vector2i = Vector2i.ZERO
	var value: int = 0

	func copy() -> AttackPlan:
		var c := AttackPlan.new()
		c.tile = tile
		c.value = value
		return c


class OrderCandidate:
	extends RefCounted
	var piece: Piece = null
	## Vector2i or null.
	var move: Variant = null
	## AttackPlan or null.
	var attack: AttackPlan = null
	var value: int = 0

	func copy() -> OrderCandidate:
		var c := OrderCandidate.new()
		c.piece = piece
		c.move = move
		c.attack = attack
		c.value = value
		return c


## The player this AI controls.
var player_index: int = 0


## Creates an AI for the given player of the controller's game.
func _init(controller: TurnController, player_index_: int) -> void:
	if controller == null:
		push_error("SimpleAi: controller is null")
	_controller = controller
	if player_index_ < 0 or player_index_ >= GameState.PLAYER_COUNT:
		push_error("SimpleAi: player_index out of range")
	player_index = player_index_


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


## Executes the whole turn synchronously via the TurnController (draws, cards, orders, VP conversions) and
## returns the executed steps in order. Does NOT call end_turn. Returns an empty list if it is not this AI's
## turn. Always leaves the game in Main phase (a started draw is completed).
func take_turn() -> Array[AiAction]:
	var actions: Array[AiAction] = []
	if not is_my_turn:
		return actions

	if _state.phase == GamePhase.DRAFT:
		_do_draft(actions, false)

	var ctx := PlanContext.new()
	ctx.sim_occupied = _occupied_set()
	var reinforced: bool = false
	for _step: int in range(MAX_STEPS):
		if _state.phase != GamePhase.MAIN or _state.current_player_index != player_index:
			break
		if _try_accelerate(actions):
			continue
		if _try_command(actions, ctx, HIGH_ORDER_VALUE, false):
			continue
		if not reinforced and _is_army_critical() and _try_play_best_card(actions, ctx, true):
			reinforced = true
			continue
		if _should_draw_early() and _try_draw(actions):
			continue
		if _try_play_best_card(actions, ctx, false, true):
			continue
		# Builders build before they would walk off toward the zone (where they could not build any more).
		if _try_build(actions):
			continue
		if _try_command(actions, ctx, 1, false):
			continue
		if _try_trap(actions):
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
## strongest unit (Attack + Hp + Shield + keywords); spells only score well once own pieces are on the board.
func choose_draft_index(offer: Array[CardData]) -> int:
	if offer == null or offer.size() == 0:
		return -1

	var me: PlayerState = _state.players[player_index]
	var my_pieces: Array[Piece] = _state.get_pieces_of(player_index)
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
	# Units above the AP income are dead weight until Mana Wells / VP conversions pay for them; while no unit in
	# hand is affordable at all, a cheap unit beats a strong one.
	var income: int = _income()
	var affordable_in_hand: bool = false
	for c: CardData in me.hand:
		if c != null and c.card_type == CardType.UNIT and _controller.get_card_cost(c) <= income:
			affordable_in_hand = true

	var best: int = -1
	var best_score: float = -INF
	for i: int in range(offer.size()):
		var card: CardData = offer[i]
		if card == null:
			continue
		var score: float
		if card.card_type == CardType.UNIT:
			score = _card_value(card)
			if card.role == UnitRole.RESOURCE and early and resource_count < 2:
				score += 10
			var over: int = _controller.get_card_cost(card) - income
			if over > 0:
				score -= 4 * over
			elif not affordable_in_hand:
				score += 6
		else:
			if my_pieces.size() > 0 or card.targets_tile:
				score = _spell_draft_value(card) * 1.5 + 1 - hand_spells * 2 + card.ap_gain * 2
			else:
				score = -5.0
			if not have_units:
				score -= 10
		if score > best_score:
			best_score = score
			best = i
	return best


# ---------------------------------------------------------------- draft

## Pays for a Draw and picks the best offered card. False if drawing is not possible.
func _try_draw(actions: Array[AiAction]) -> bool:
	# Do not hoard: with a full hand the AP is better spent on the board - unless no unit in hand is affordable
	# (a hand of spells and expensive units cannot reach the board and would stall the AI forever).
	if (_state.players[player_index].hand.size() >= MAX_HAND_TO_DRAW and _has_affordable_unit()) or not _controller.can_draw() or not _controller.draw():
		return false
	_do_draft(actions, true)
	return true


## True if a unit card in hand costs no more than the AP left.
func _has_affordable_unit() -> bool:
	var me: PlayerState = _state.players[player_index]
	for card: CardData in me.hand:
		if card.card_type == CardType.UNIT and _controller.get_card_cost(card) <= me.action_points:
			return true
	return false


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
	var a := AiAction.new()
	a.kind = AiActionKind.DRAFT
	a.player_index = player_index
	a.card = card
	if paid:
		a.description = "Drew (%d AP) and kept %s" % [_state.config.draw_ap_cost, _card_name(card)]
	else:
		a.description = "Drafted %s" % _card_name(card)
	actions.append(a)


## Fewer than 3 own units, or fewer units than the opponent (buildings do not count).
func _is_board_weak() -> bool:
	var mine: int = _count_units(_state.get_pieces_of(player_index))
	var theirs: int = _count_units(_state.get_pieces_of(1 - player_index))
	return mine < 3 or mine < theirs


## Reinforcing BEFORE moving is only worth it with almost no army (fewer than 2 units, or 2+ units behind the
## opponent); otherwise the existing units advance first and new units are deployed with the remaining AP.
func _is_army_critical() -> bool:
	var mine: int = _count_units(_state.get_pieces_of(player_index))
	var theirs: int = _count_units(_state.get_pieces_of(1 - player_index))
	return mine < 2 or mine + 2 <= theirs


## Draw before spending AP elsewhere if the hand is empty, or the board is weak and no unit is in hand.
func _should_draw_early() -> bool:
	var hand: Array[CardData] = _state.players[player_index].hand
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


## VP the AI may convert this turn to pay for a strong card (4+ AP): when not behind by more than 2, not about
## to win anyway and holding at least 3 VP - or when the opponent is about to win. 0 otherwise.
func _vp_for_cards() -> int:
	var me: PlayerState = _state.players[player_index]
	var opp: PlayerState = _state.players[1 - player_index]
	var left: int = mini(_controller.remaining_vp_conversions, me.victory_points)
	if left <= 0 or _state.phase != GamePhase.MAIN:
		return 0
	var target: int = _state.config.points_target
	var desperate: bool = opp.victory_points >= target - 4
	var comfortable: bool = me.victory_points >= 3 and me.victory_points + 2 >= opp.victory_points and me.victory_points < target - 3
	return left if desperate or comfortable else 0


func _try_convert_vp(actions: Array[AiAction], reason: String) -> bool:
	if not _should_spend_vp() or not _controller.convert_vp_to_ap():
		return false
	var a := AiAction.new()
	a.kind = AiActionKind.CONVERT_VP
	a.player_index = player_index
	a.description = "Converted 1 VP into 1 AP (%s)" % reason
	actions.append(a)
	return true


# ---------------------------------------------------------------- cards

## Plays one card of the most valuable affordable set: every playable card gets a value (_card_value for units,
## the target score for spells); a small knapsack picks the set with the highest total value within the AP
## budget (incl. _vp_for_cards for 4+ AP cards), and its most valuable card is played now (converting VP if
## needed). premium_only: only cards of 3+ AP worth at least 2.5 value per AP.
func _try_play_best_card(actions: Array[AiAction], ctx: PlanContext, units_only: bool, premium_only: bool = false) -> bool:
	var me: PlayerState = _state.players[player_index]
	var unit_count: int = _count_units(_state.get_pieces_of(player_index))
	var unit_slots: int = 1 if units_only else maxi(0, MAX_DESIRED_PIECES - unit_count)
	var vp_budget: int = _vp_for_cards()
	var options: Array[Dictionary] = []

	for card: CardData in me.hand.duplicate():
		if (card == null
				or (card.card_type == CardType.UNIT and unit_slots <= 0)
				or (card.card_type == CardType.SPELL and units_only)
				or _is_pure_accelerator(card)):
			continue
		var cost: int = _controller.get_card_cost(card)
		# VP only pays for strong cards.
		if cost > me.action_points and (cost < 4 or cost > me.action_points + vp_budget):
			continue

		var tile: Vector2i = Vector2i.ZERO
		var target: Piece = null
		var value: float
		if card.card_type == CardType.UNIT:
			var deploy: Variant = _find_deploy_tile(card)
			if deploy == null:
				continue
			tile = deploy
			value = _card_value(card)
		elif card.targets_tile:
			var found: Dictionary = _find_tile_spell_target(card, ctx)
			var anchor: Variant = found.result
			if anchor == null:
				continue
			tile = anchor
			value = float(found.best_value) + card.ap_gain * 2
		else:
			target = _find_spell_target(card)
			if target == null:
				continue
			value = maxi(1, absi(_spell_net(card))) * 1.5 + (2.0 if card.grant_status != StatusEffectType.NONE else 0.0) + card.ap_gain * 2
		if premium_only and (cost < 3 or value < cost * 2.5):
			continue
		options.append({"card": card, "tile": tile, "target": target, "cost": cost, "value": value})
	if options.is_empty():
		return false

	# Knapsack over at most 10 options (the hand is small): best total value, ties -> lower total cost.
	var n: int = mini(options.size(), 10)
	var budget: int = me.action_points + vp_budget
	var best_mask: int = 0
	var best_total: float = -1.0
	var best_total_cost: int = _INT_MAX
	for mask: int in range(1, 1 << n):
		var cost_sum: int = 0
		var units: int = 0
		var total: float = 0.0
		for i: int in range(n):
			if (mask & (1 << i)) == 0:
				continue
			cost_sum += int(options[i].cost)
			total += float(options[i].value)
			units += 1 if (options[i].card as CardData).card_type == CardType.UNIT else 0
		if cost_sum > budget or units > unit_slots:
			continue
		if total > best_total or (total == best_total and cost_sum < best_total_cost):
			best_total = total
			best_total_cost = cost_sum
			best_mask = mask
	if best_mask == 0:
		return false
	var pick: int = -1
	for i: int in range(n):
		if (best_mask & (1 << i)) != 0 and (pick < 0 or float(options[i].value) > float(options[pick].value)):
			pick = i
	var best_card: CardData = options[pick].card
	var best_tile: Vector2i = options[pick].tile
	var best_target: Piece = options[pick].target
	while int(options[pick].cost) > me.action_points:
		if not _controller.convert_vp_to_ap():
			return false
		var conv := AiAction.new()
		conv.kind = AiActionKind.CONVERT_VP
		conv.player_index = player_index
		conv.description = "Converted 1 VP into 1 AP (for %s)" % _card_name(best_card)
		actions.append(conv)

	if best_card.card_type == CardType.UNIT:
		var piece: Piece = _controller.play_unit_card(best_card, best_tile)
		if piece == null:
			return false
		ctx.sim_occupied[best_tile] = true
		var a := AiAction.new()
		a.kind = AiActionKind.PLAY_UNIT
		a.player_index = player_index
		a.card = best_card
		a.piece_id = piece.id
		a.target = best_tile
		a.description = "Deployed %s at %s" % [_card_name(best_card), str(best_tile)]
		actions.append(a)
	elif best_card.targets_tile:
		if not _controller.play_spell_on_tile(best_card, best_tile):
			return false
		# Kills from the spell free tiles; walls are respected by _simulated_reachable via the board.
		for p: Vector2i in ctx.sim_occupied.keys():
			if not _board.is_occupied(p):
				ctx.sim_occupied.erase(p)
		var a := AiAction.new()
		a.kind = AiActionKind.PLAY_SPELL
		a.player_index = player_index
		a.card = best_card
		a.piece_id = -1
		a.target = best_tile
		a.description = "Cast %s on %s" % [_card_name(best_card), str(best_tile)]
		actions.append(a)
	else:
		var target_pos: Vector2i = best_target.position
		if not _controller.play_spell_card(best_card, best_target):
			return false
		var a := AiAction.new()
		a.kind = AiActionKind.PLAY_SPELL
		a.player_index = player_index
		a.card = best_card
		a.piece_id = best_target.id
		a.target = target_pos
		a.description = "Cast %s on #%d %s at %s" % [_card_name(best_card), best_target.id, _card_name(best_target.source), str(target_pos)]
		actions.append(a)
	return true


## Free own deploy tile closest to the scoring zone (ties: free tile ahead, then center column). Avoids lava.
## Planted units may go forward (near own units): they are placed where they threaten the most enemies, close to the
## scoring zone, but not right next to an enemy that would kill them at once. Returns Vector2i or null.
func _find_deploy_tile(card: CardData) -> Variant:
	var best: Variant = null
	var best_score: int = _INT_MAX
	var forward: int = BoardState.forward_direction(player_index)
	var planted: bool = card.has_keyword(Keyword.PLANTED)
	for y: int in range(_board.height):
		for x: int in range(_board.width):
			var pos := Vector2i(x, y)
			if (not planted and not _board.is_in_deploy_zone(player_index, pos)) or _board.is_occupied(pos):
				continue
			if not _controller.can_play_unit_card(card, pos):
				continue
			var score: int
			if planted:
				var enemy_dist: int = _nearest_enemy_distance(pos)
				var reach: int = maxi(1, card.range)
				score = (_distance_to_zone_rect(pos) * 6
					+ (0 if enemy_dist <= reach else (enemy_dist - reach) * 8)
					+ (25 if enemy_dist <= 1 else 0)
					+ (50 if _board.get_tile_effect_type(pos) == TileEffectType.LAVA else 0))
			else:
				var ahead := Vector2i(x, y + forward)
				score = (_distance_to_zone_rect(pos) * 20
					+ (10 if _board.is_inside(ahead) and (_board.is_occupied(ahead) or _board.is_wall(ahead)) else 0)
					+ (50 if _board.get_tile_effect_type(pos) == TileEffectType.LAVA else 0)
					+ absi(2 * x - (_board.width - 1)))
			if score < best_score:
				best_score = score
				best = pos
	return best


## Buff (net positive deltas): own piece nearest the zone / most threatened. Debuff: strongest enemy.
## Overcharge-like status spells: own piece that can still act and has an enemy within striking distance.
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
			score -= 15
		if score > best_score and _controller.can_play_spell_card(card, p):
			best_score = score
			best = p
	return best


## Own piece (not yet Overcharged) that can still act this turn and reach an enemy with its attack.
func _find_overcharge_target(card: CardData) -> Piece:
	var best: Piece = null
	var best_value: int = 0
	for p: Piece in _state.get_pieces_of(player_index):
		if (p.has_status(StatusEffectType.OVERCHARGED) or p.effective_attack <= 0 or p.has_acted(_state.turn_number)
				or p.is_summoning_sick(_state.turn_number) or not _controller.can_play_spell_card(card, p)):
			continue
		var reach: int = p.effective_movement + p.effective_range
		for e: Piece in _state.pieces:
			if e.owner_index == player_index or GridPos.manhattan_distance(e.position, p.position) > reach:
				continue
			var value: int = p.effective_attack * 2 + (4 if e.current_hp + e.total_shield <= p.effective_attack * 2 else 1)
			if value > best_value:
				best_value = value
				best = p
	return best


## Best anchor for a tile/area spell, scored by: enemy damage / kills, lava under enemies (minus own pieces
## on lava), walls in front of advancing enemies (minus walls in front of own pieces), healing of
## damaged own pieces. Returns {"result": Vector2i or null, "best_value": int}.
func _find_tile_spell_target(card: CardData, ctx: PlanContext) -> Dictionary:
	var best_value: int = 0
	var best: Variant = null
	var min_value: int = 3 if card.tile_effect == TileEffectType.WALL else (2 if card.tile_effect == TileEffectType.HEALING else 4)
	for y: int in range(_board.height):
		for x: int in range(_board.width):
			var anchor := Vector2i(x, y)
			if not _controller.can_play_spell_on_tile(card, anchor):
				continue
			var value: int = _score_tile_spell(card, anchor, ctx)
			if value >= min_value and value > best_value:
				best_value = value
				best = anchor
	return {"result": best, "best_value": best_value}


func _score_tile_spell(card: CardData, anchor: Vector2i, ctx: PlanContext) -> int:
	var value: int = 0
	for t: Vector2i in _controller.get_spell_area_preview(card, anchor):
		var p: Piece = _board.get_piece_at(t)
		var enemy: bool = p != null and p.owner_index != player_index
		var mine: bool = p != null and p.owner_index == player_index
		if enemy and card.spell_damage > 0:
			var kills: bool = p.current_hp + p.total_shield <= card.spell_damage
			value += 6 if kills else 2
		if mine and card.spell_heal > 0:
			value += mini(card.spell_heal, p.max_hp - p.current_hp)
		if card.spell_push and p != null:
			var spot: int = (2 if _board.is_in_scoring_zone(t) else 0) + (2 if _board.is_in_hot_zone(t) else 0)
			value += (1 + spot) if enemy else -(1 + spot)
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

## Evaluates every own piece that can still act and executes the best action (TurnController.act, resolves
## immediately) whose value is at least min_value. If AP is missing and allow_vp is set, converts 1 VP into AP
## first (_should_spend_vp). False if none qualifies.
func _try_command(actions: Array[AiAction], ctx: PlanContext, min_value: int, allow_vp: bool) -> bool:
	var need_ap: bool = _state.config.order_ap_cost > _state.players[player_index].action_points
	if need_ap and not (allow_vp and _should_spend_vp()):
		return false
	if not need_ap and allow_vp:
		return false

	ctx.sim_occupied = _occupied_set()
	var best: OrderCandidate = null
	for piece: Piece in _state.get_pieces_of(player_index):
		if not _controller.can_command(piece):
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
	var attack_tile: Variant = pick.attack.tile if pick.attack != null else null
	while _state.config.order_ap_cost > _state.players[player_index].action_points:
		if not _try_convert_vp(actions, "for %s's action" % _card_name(p.source)):
			return false
	var description: String = _describe_order(p, pick.move, pick.attack)
	if _controller.act(p, pick.move, attack_tile) == null:
		return false
	ctx.sim_occupied = _occupied_set()

	var a := AiAction.new()
	a.kind = AiActionKind.COMMAND
	a.player_index = player_index
	a.card = p.source
	a.piece_id = p.id
	a.move_target = pick.move
	a.attack_target = attack_tile
	a.target = attack_tile if attack_tile != null else pick.move
	a.description = description + " (%d AP)" % _state.config.order_ap_cost
	actions.append(a)
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
	var attack: AttackPlan = _choose_attack(piece, dest, ctx)
	var move: Variant = dest if dest != piece.position else null

	if move != null and not _controller.get_valid_move_targets(piece).has(move):
		move = null
		attack = _choose_attack(piece, piece.position, ctx)
	var from_pos: Vector2i = move if move != null else piece.position
	if attack != null and not _board.is_in_attack_range(from_pos, attack.tile, piece.effective_range):
		attack = null
	if move == null and attack == null:
		return null
	# A Builder that could build stays and builds (_try_build) instead of only walking - attacks still go first.
	if attack == null and _wants_to_build(piece):
		return null

	var value: int = attack.value if attack != null else 0
	if move != null:
		var move_pos: Vector2i = move
		var was_in_zone: bool = _board.is_in_scoring_zone(piece.position)
		if not _board.is_in_hot_zone(piece.position) and _board.is_in_hot_zone(move_pos):
			value += 3 if was_in_zone else 6
		elif not was_in_zone and _board.is_in_scoring_zone(move_pos):
			value += 4
		else:
			var progress: int = _distance_to_zone_rect(piece.position) - _distance_to_zone_rect(move_pos)
			if progress > 0:
				value += 2 if progress >= 2 else 1
				# Getting units out of the home rows matters most: an army parked at home never scores.
				if _board.is_in_deploy_zone(player_index, piece.position) and not _board.is_in_deploy_zone(player_index, move_pos):
					value += 1
		if (_board.get_tile_effect_type(piece.position) == TileEffectType.LAVA
				and _board.get_tile_effect_type(move_pos) != TileEffectType.LAVA):
			value += 1
	if value <= 0:
		return null
	var c := OrderCandidate.new()
	c.piece = piece
	c.move = move
	c.attack = attack
	c.value = value
	return c


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
	for y: int in range(zone.position.y, zone.end.y):
		for x: int in range(zone.position.x, zone.end.x):
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
		if _board.is_in_hot_zone(c):
			score -= 12
		var effect: int = _board.get_tile_effect_type(c)
		if effect == TileEffectType.LAVA or effect == TileEffectType.STORM:
			score += LAVA_PENALTY * 3 if piece.current_hp <= _state.config.lava_damage else LAVA_PENALTY
		elif effect == TileEffectType.HEALING and piece.current_hp < piece.max_hp:
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


## Attack from 'from': every occupied tile in range is evaluated with TurnController.predict_attack (enemy
## damage, friendly fire, Mending heals) and scored by _score_preview. Null if nothing has a positive value.
func _choose_attack(piece: Piece, from: Vector2i, ctx: PlanContext) -> AttackPlan:
	var best: AttackPlan = null
	for tile: Vector2i in _controller.get_valid_attack_targets(piece, from):
		var target: Piece = _board.get_piece_at(tile)
		if target == null or target == piece or not target.is_alive:
			continue
		var friendly: bool = target.owner_index == player_index
		if friendly and not (piece.has_keyword(Keyword.MENDING) and target.current_hp < target.max_hp):
			continue
		var preview: ChainPreview = _controller.predict_attack(piece, from, tile)
		if not preview.is_valid:
			continue
		var plan: AttackPlan = _score_preview(preview, ctx, tile)
		if plan.value > 0 and (best == null or plan.value > best.value):
			best = plan
	return best


## Scores a preview: per enemy hit 3 (6 if it kills), +1 per keyword effect, + heals; friendly fire costs
## 3 per damaged own piece (8 if it dies).
func _score_preview(preview: ChainPreview, ctx: PlanContext, tile: Vector2i) -> AttackPlan:
	var local: Dictionary = {}
	var value: int = 0
	var hit_enemy_hp: int = 0
	for hit: PredictedHit in preview.hits:
		if hit.target_piece_id < 0:
			continue
		if hit.is_friendly:
			continue
		var enemy: Piece = _state.get_piece(hit.target_piece_id)
		if enemy == null:
			continue
		var already: int = int(local.get(enemy.id, 0))
		var ehp: int = _remaining_ehp(enemy, ctx.planned_damage) - already
		if ehp <= 0:
			continue
		if hit.damage > 0:
			value += 6 if ehp <= hit.damage else 3
			local[enemy.id] = already + hit.damage
			hit_enemy_hp += hit.hp_lost
		if (hit.effects & HitEffect.FROZEN) != 0:
			value += 1
		if (hit.effects & HitEffect.LAVA) != 0:
			value += 1
		if (hit.effects & HitEffect.PUSHED) != 0:
			var pushed_out: bool = (_board.is_in_scoring_zone(enemy.position) and hit.pushed_to != null
				and not _board.is_in_scoring_zone(hit.pushed_to))
			value += 3 if pushed_out else 1
	value += preview.friendly_healed
	# Everything that is not a direct hit: deathrattles, thorns, Arc / Pierce on own pieces.
	value += maxi(0, preview.enemy_hp_lost - hit_enemy_hp) * 2
	value -= preview.friendly_hp_lost * 2 + preview.friendly_kills * 6
	var plan := AttackPlan.new()
	plan.tile = tile
	plan.value = value
	return plan


## Lets an idle Builder start its building when AP allows, the player has fewer than two buildings of that kind
## and at most MAX_BUILDINGS in total (_wants_to_build). Turrets / Barricades go toward the scoring zone, the rest
## away from enemies.
func _try_build(actions: Array[AiAction]) -> bool:
	var ap: int = _state.players[player_index].action_points
	var total: int = 0
	for p: Piece in _state.get_pieces_of(player_index):
		total += 1 if p.is_building else 0
	if total >= MAX_BUILDINGS:
		return false
	for piece: Piece in _state.get_pieces_of(player_index):
		var type: int = _controller.get_build_type(piece)
		if not _wants_to_build(piece) or not _controller.can_command(piece) or BuildingInfo.get_cost(type) > ap:
			continue
		# Best tiles first (Barricades: the two best).
		var forward: bool = type == BuildingType.TURRET or type == BuildingType.BARRICADE
		var scored: Array[Dictionary] = []
		for tile: Vector2i in _controller.get_valid_build_tiles(piece):
			var score: int = _distance_to_zone_rect(tile) * 10 if forward else -_nearest_enemy_distance(tile) * 3
			if _board.get_tile_effect_type(tile) == TileEffectType.LAVA or (_board.is_in_scoring_zone(tile) and not forward):
				score += 30
			scored.append({"tile": tile, "score": score})
		if scored.size() == 0:
			continue
		scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.score) < int(b.score))
		var tiles: Array[Vector2i] = []
		var i: int = 0
		while i < scored.size() and tiles.size() < BuildingInfo.get_build_count(type):
			tiles.append(scored[i].tile)
			i += 1
		if _controller.build(piece, tiles, null) == null:
			continue
		var tile_texts := PackedStringArray()
		for t: Vector2i in tiles:
			tile_texts.append(str(t))
		var what: String
		if tiles.size() > 1:
			what = "%d %ss" % [tiles.size(), BuildingInfo.display_name(type, piece.source.clan)]
		else:
			what = "a %s" % BuildingInfo.display_name(type, piece.source.clan)
		var a := AiAction.new()
		a.kind = AiActionKind.BUILD
		a.player_index = player_index
		a.card = piece.source
		a.piece_id = piece.id
		a.target = tiles[0]
		a.description = ("#%d %s builds %s " % [piece.id, _card_name(piece.source), what]
			+ "at %s (%d AP)" % [" and ".join(tile_texts), BuildingInfo.get_cost(type)])
		actions.append(a)
		return true
	return false


## A Trapper with nothing better to do (no worthwhile move or attack this turn) hides a trap next to it when
## enemies are near: on the free neighbour tile closest to them, preferably inside the scoring zone.
## The AI knows nothing about the opponent's traps.
func _try_trap(actions: Array[AiAction]) -> bool:
	if _state.config.trap_ap_cost > _state.players[player_index].action_points:
		return false
	for piece: Piece in _state.get_pieces_of(player_index):
		if _controller.get_trap_type(piece) == null or not _controller.can_command(piece) or _nearest_enemy_distance(piece.position) > 7:
			continue
		var best: Variant = null
		var best_score: int = _INT_MAX
		for tile: Vector2i in _controller.get_valid_trap_tiles(piece):
			var score: int = (_nearest_enemy_distance(tile) * 3 + _distance_to_zone_rect(tile) * 2
				+ (10 if _board.get_tile_effect_type(tile) == TileEffectType.LAVA else 0))
			if score < best_score:
				best_score = score
				best = tile
		if best == null or _controller.set_trap(piece, best, null) == null:
			continue
		var a := AiAction.new()
		a.kind = AiActionKind.TRAP
		a.player_index = player_index
		a.card = piece.source
		a.piece_id = piece.id
		a.target = best
		a.description = "#%d %s hides a trap (%d AP)" % [piece.id, _card_name(piece.source), _state.config.trap_ap_cost]
		actions.append(a)
		return true
	return false


## True for an idle Builder outside the scoring zone (it would stop scoring while building) whose building is still
## worth raising: fewer than two of that kind, fewer than MAX_BUILDINGS in total and a free tile next to it.
func _wants_to_build(piece: Piece) -> bool:
	var type: int = _controller.get_build_type(piece)
	if type == BuildingType.NONE or piece.constructing_id >= 0 or _board.is_in_scoring_zone(piece.position):
		return false
	var same: int = 0
	var total: int = 0
	for p: Piece in _state.get_pieces_of(player_index):
		same += 1 if p.building == type else 0
		total += 1 if p.is_building else 0
	return same < 2 and total < MAX_BUILDINGS and _controller.get_valid_build_tiles(piece).size() > 0 and _is_building_useful(piece, type)


## Whether the building would pay off where the builder stands: Mana Wells early on, Turrets near the zone or
## enemies, Barricades when enemies approach, Shrines among allies, Obelisks with spells in hand. Clan buildings
## also qualify through their aura: Fire / Frost with enemies close, Healing / Stone / Storm with allies close.
func _is_building_useful(builder: Piece, type: int) -> bool:
	var at: Vector2i = builder.position
	var enemy_dist: int = _nearest_enemy_distance(at)
	var allies_near: int = 0
	for p: Piece in _state.get_pieces_of(player_index):
		if p != builder and not p.is_building and GridPos.manhattan_distance(p.position, at) <= 2:
			allies_near += 1
	var spells: int = 0
	for c: CardData in _state.players[player_index].hand:
		if c != null and c.card_type == CardType.SPELL:
			spells += 1
	var useful: bool = false
	match type:
		BuildingType.MANA_WELL:
			useful = _state.turn_number <= 14
		BuildingType.TURRET:
			useful = _distance_to_zone_rect(at) <= 2 or enemy_dist <= 5
		BuildingType.BARRICADE:
			useful = enemy_dist <= 4
		BuildingType.SHRINE:
			useful = allies_near >= 2
		BuildingType.OBELISK:
			useful = spells >= 2
	if useful:
		return true
	match builder.source.clan:
		Clan.FIRE, Clan.FROST:
			return enemy_dist <= 3
		Clan.HEALING, Clan.STONE, Clan.STORM:
			return allies_near >= 2
	return false


## Spells that only gain AP (net gain, no other effect), e.g. Mana Surge.
func _is_pure_accelerator(card: CardData) -> bool:
	return (card.card_type == CardType.SPELL and card.ap_gain > _controller.get_card_cost(card) and _spell_net(card) == 0
		and card.grant_status == StatusEffectType.NONE and not card.targets_tile)


## Casts an AP-gaining spell (net AP gain) on any own piece in reach, if the hand holds something else to spend
## the AP on. False otherwise.
func _try_accelerate(actions: Array[AiAction]) -> bool:
	var me: PlayerState = _state.players[player_index]
	for card: CardData in me.hand.duplicate():
		if card == null or not _is_pure_accelerator(card) or _controller.get_card_cost(card) > me.action_points:
			continue
		var useful: bool = false
		for c: CardData in me.hand:
			if c != null and c != card and not _is_pure_accelerator(c):
				useful = true
		if not useful:
			continue
		for p: Piece in _state.get_pieces_of(player_index):
			if not _controller.can_play_spell_card(card, p):
				continue
			var at: Vector2i = p.position
			if not _controller.play_spell_card(card, p):
				return false
			var a := AiAction.new()
			a.kind = AiActionKind.PLAY_SPELL
			a.player_index = player_index
			a.card = card
			a.piece_id = p.id
			a.target = at
			a.description = "Cast %s on #%d %s at %s" % [_card_name(card), p.id, _card_name(p.source), str(at)]
			actions.append(a)
			return true
	return false


## AP at the start of the next own turn: base + bonus + AP-producing pieces and Mana Wells.
func _income() -> int:
	var income: int = _state.config.base_ap + _state.players[player_index].bonus_ap_per_turn
	for p: Piece in _state.get_pieces_of(player_index):
		if p.is_building:
			income += _state.config.mana_well_ap if p.building == BuildingType.MANA_WELL and not p.under_construction else 0
		else:
			income += p.ap_bonus
	return income


## Rough worth of a unit card in stat points: Attack counts 1.5, HP and Shield 1, plus reach, speed, area attacks,
## AP income (3 per AP), keywords, legend effects and triggers. Planted units that bring no AP lose a little (they
## never score).
static func _card_value(card: CardData) -> float:
	if card.card_type != CardType.UNIT:
		return _spell_draft_value(card) + card.ap_gain * 2.0
	var value: float = (card.attack * 1.5 + card.hp + card.shield
		+ maxi(0, card.range - 1)
		+ (1 if card.movement >= 5 else (-1 if card.movement <= 1 else 0))
		+ (1.5 if card.attack_area != AreaShape.SINGLE else 0.0)
		+ card.ap_bonus * 3
		+ KeywordInfo.split(card.keywords).size()
		+ (4 if card.legend != LegendEffect.NONE else 0)
		+ (1 if card.deathrattle != DeathrattleType.NONE else 0)
		+ (1 if card.on_first_hit != FirstHitType.NONE else 0))
	if card.has_keyword(Keyword.PLANTED) and card.ap_bonus <= 0:
		value -= 1.0
	return value


func _nearest_enemy_distance(tile: Vector2i) -> int:
	var best: int = 99
	for p: Piece in _state.pieces:
		if p.owner_index != player_index:
			best = mini(best, GridPos.manhattan_distance(p.position, tile))
	return best


## Tiles reachable with the move rules (water costs extra movement, own pieces are passable) where the piece may
## END (not sim-occupied). Returns a Dictionary used as a set of Vector2i.
func _simulated_reachable(from: Vector2i, movement: int, occupied: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for tile: Vector2i in _board.get_reachable_tiles(from, movement, player_index):
		if not occupied.has(tile):
			result[tile] = true
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


## Set (Dictionary) of all currently occupied tiles (C#: new HashSet<GridPos>(Board.Occupancy.Keys)).
func _occupied_set() -> Dictionary:
	var result: Dictionary = {}
	for k: Vector2i in _board.occupancy.keys():
		result[k] = true
	return result


## Number of non-building pieces in the list (C#: FindAll(p => !p.IsBuilding).Count).
static func _count_units(pieces: Array[Piece]) -> int:
	var n: int = 0
	for p: Piece in pieces:
		if not p.is_building:
			n += 1
	return n


static func _remaining_ehp(target: Piece, planned_damage: Dictionary) -> int:
	var dmg: int = int(planned_damage.get(target.id, 0))
	return target.current_hp + target.total_shield - dmg


static func _has_spell(piece: Piece, card: CardData) -> bool:
	for s: ActiveSpell in piece.active_spells:
		if s.source == card:
			return true
	return false


static func _spell_net(card: CardData) -> int:
	return card.attack_delta + card.hp_delta + card.shield_delta + card.movement_delta + card.range_delta


static func _spell_draft_value(card: CardData) -> int:
	return (absi(_spell_net(card)) + card.spell_damage * 2 + card.spell_heal
		+ (2 if card.tile_effect != TileEffectType.NONE else 0) + (2 if card.grant_status != StatusEffectType.NONE else 0))


static func _card_name(card: CardData) -> String:
	return card.name if card != null else "?"


func _describe_order(piece: Piece, move: Variant, attack: AttackPlan) -> String:
	var text: String = "#%d %s" % [piece.id, _card_name(piece.source)]
	text += (" moves to %s" % str(move)) if move != null else " holds"
	if attack != null:
		var target: Piece = _board.get_piece_at(attack.tile)
		var target_name: String = ("#%d %s" % [target.id, _card_name(target.source)]) if target != null else "tile"
		text += ", attacks %s at %s" % [target_name, str(attack.tile)]
	return text
