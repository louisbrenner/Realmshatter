class_name AiSelfTest
extends RefCounted
## AI vs. AI smoke test: builds games from in-memory cards, lets SimpleAi play both sides via
## take_turn + end_turn and checks state consistency after every step. Must run inside Godot
## (CardData/GameConfig are Resources). Call run() and print the report.
## Note: GDScript has no exceptions, so the C# try/catch around a game is not reproduced; runtime errors
## surface as Godot script errors instead.

const MAX_TURNS := 40


## Runs several seeded AI-vs-AI games and returns a human-readable report.
static func run() -> String:
	var sb: PackedStringArray = PackedStringArray()
	sb.append("AiSelfTest")
	var failures: int = 0
	for seed_value: int in [1, 2, 3]:
		failures += _run_game(seed_value, MAX_TURNS, sb, _build_deck("A"), _build_deck("B"))
	var starter: DeckData = load("res://Resources/Decks/StarterDeck.tres") as DeckData
	if starter == null or starter.cards == null or starter.cards.size() == 0:
		sb.append("  [FAIL] could not load res://Resources/Decks/StarterDeck.tres")
		failures += 1
	else:
		var cards: Array[CardData] = []
		for c: CardData in starter.cards:
			if c != null:
				cards.append(c)
		for seed_value: int in [4, 5]:
			failures += _run_game(seed_value, MAX_TURNS * 2, sb, cards, cards.duplicate())
	sb.append("Result: PASS" if failures == 0 else "Result: FAIL (%d problem(s))" % failures)
	return "\n".join(sb) + "\n"


static func _run_game(seed_value: int, max_turns: int, sb: PackedStringArray, deck0: Array[CardData], deck1: Array[CardData]) -> int:
	var errors: Array[String] = []
	var action_counts: Dictionary = {}
	var event_counts: Dictionary = {}
	var turns_played: int = 0
	var state: GameState = null

	var config: GameConfig = GameConfig.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	state = GameState.new(config, deck0, deck1, rng)
	var controller: TurnController = TurnController.new(state)
	var ais: Array[SimpleAi] = [SimpleAi.new(controller, 0), SimpleAi.new(controller, 1)]
	var total_cards: Array[int] = [state.players[0].deck.size(), state.players[1].deck.size()]
	# Spells cast are consumed; units return to the deck when destroyed (pieces on board are counted live).
	var played: Array[int] = [0, 0]
	var last_vp: Array[int] = [0, 0]

	controller.start_game()

	while turns_played < max_turns and state.phase != GamePhase.GAME_OVER:
		var current: int = state.current_player_index
		var turn_before: int = state.turn_number
		var ap_before: int = state.players[current].action_points
		if state.phase != GamePhase.MAIN:
			errors.append("turn %d: turn did not start in Main phase (%s)" % [turn_before, GamePhase.name_of(state.phase)])

		var actions: Array[AiAction] = ais[current].take_turn()
		var other: Array[AiAction] = ais[1 - current].take_turn()
		if other.size() > 0:
			errors.append("turn %d: AI of inactive player acted" % turn_before)
		if state.phase != GamePhase.MAIN:
			errors.append("turn %d: phase after TakeTurn is %s, expected Main" % [turn_before, GamePhase.name_of(state.phase)])
			break
		for a: AiAction in actions:
			action_counts[a.kind] = int(action_counts.get(a.kind, 0)) + 1
			if a.kind == AiActionKind.PLAY_SPELL:
				played[current] += 1
			if a.player_index != current:
				errors.append("turn %d: action recorded for wrong player" % turn_before)
		if state.players[current].action_points < 0:
			errors.append("turn %d: negative AP" % turn_before)
		var spent: int = 0
		for a: AiAction in actions:
			match a.kind:
				AiActionKind.DRAFT:
					spent += config.draw_ap_cost
				AiActionKind.PLAY_UNIT, AiActionKind.PLAY_SPELL:
					spent += controller.get_card_cost(a.card)
				AiActionKind.SET_ORDER:
					spent += config.order_ap_cost
				AiActionKind.CONVERT_VP:
					spent += -1
				_:
					spent += 0
		if ap_before - spent != state.players[current].action_points:
			errors.append("turn %d: AP accounting %d - %d != %d" % [turn_before, ap_before, spent, state.players[current].action_points])
		var converted: int = state.players[current].vp_converted_this_turn
		var convert_actions: int = 0
		for a: AiAction in actions:
			if a.kind == AiActionKind.CONVERT_VP:
				convert_actions += 1
		if converted != convert_actions or converted > config.max_vp_to_ap_per_turn:
			errors.append("turn %d: VP conversions %d (actions %d, max %d)" % [turn_before, converted, convert_actions, config.max_vp_to_ap_per_turn])
		last_vp[current] -= converted
		if state.players[current].victory_points != last_vp[current]:
			errors.append("turn %d: VP of P%d changed during TakeTurn beyond conversions" % [turn_before, current])
		_check_orders(state, current, actions, turn_before, errors)
		_check_consistency(state, total_cards, played, turn_before, "after TakeTurn", errors)

		var events: Array = controller.end_turn()
		var all_events: Array = events.duplicate()
		all_events.append_array(controller.last_turn_start_events)
		for e: ResolutionEvent in all_events:
			event_counts[e.type] = int(event_counts.get(e.type, 0)) + 1
		turns_played += 1

		if state.phase != GamePhase.GAME_OVER:
			if state.current_player_index != 1 - current:
				errors.append("turn %d: player did not swap" % turn_before)
			if state.turn_number != turn_before + 1:
				errors.append("turn %d: turn number did not advance" % turn_before)
		for p: Piece in state.pieces:
			if p.order != null:
				errors.append("turn %d: order not cleared on %s" % [turn_before, str(p)])
		for i in range(GameState.PLAYER_COUNT):
			if state.players[i].victory_points < last_vp[i]:
				errors.append("turn %d: VP of P%d decreased" % [turn_before, i])
			last_vp[i] = state.players[i].victory_points
		_check_consistency(state, total_cards, played, turn_before, "after EndTurn", errors)

		if errors.size() > 20:
			break

	var winner_text: String = ("P%d" % state.winner) if (state != null and state.winner >= 0) else "none"
	var vp0: int = state.players[0].victory_points if state != null else 0
	var vp1: int = state.players[1].victory_points if state != null else 0
	var alive0: int = state.get_pieces_of(0).size() if state != null else 0
	var alive1: int = state.get_pieces_of(1).size() if state != null else 0
	sb.append("Game seed %d: %d turns, winner %s, VP %d:%d, pieces alive %d:%d"
		% [seed_value, turns_played, winner_text, vp0, vp1, alive0, alive1])
	sb.append("  actions: " + _format_counts(action_counts, func(k: int) -> String: return AiActionKind.name_of(k)))
	sb.append("  events:  " + _format_counts(event_counts, func(k: int) -> String: return ResolutionEventType.name_of(k)))
	if errors.size() == 0:
		sb.append("  [PASS] no exceptions, state consistent")
	for err: String in errors:
		sb.append("  [FAIL] " + err)
	return errors.size()


static func _check_orders(state: GameState, player: int, actions: Array[AiAction], turn: int, errors: Array[String]) -> void:
	var order_actions: int = 0
	for a: AiAction in actions:
		if a.kind == AiActionKind.SET_ORDER:
			order_actions += 1
	var queued: int = 0
	for p: Piece in state.pieces:
		if p.order == null:
			continue
		queued += 1
		if p.owner_index != player:
			errors.append("turn %d: order on a piece of the inactive player %s" % [turn, str(p)])
		if p.is_summoning_sick(state.turn_number):
			errors.append("turn %d: summoning-sick piece received an order %s" % [turn, str(p)])
	if queued != order_actions:
		errors.append("turn %d: %d queued orders but %d SetOrder actions" % [turn, queued, order_actions])

	for a: AiAction in actions:
		if a.kind != AiActionKind.SET_ORDER:
			continue
		var p: Piece = state.get_piece(a.piece_id)
		if p == null or p.owner_index != player or p.order == null:
			errors.append("turn %d: SetOrder action without a queued order (piece %d)" % [turn, a.piece_id])
			continue
		if p.order.move_target != a.move_target or p.order.attack_target != a.attack_target:
			errors.append("turn %d: recorded order differs from queued order on %s" % [turn, str(p)])
		if a.attack_target != null:
			var target: Piece = state.board.get_piece_at(a.attack_target)
			if target == null:
				errors.append("turn %d: %s attacks an empty tile %s" % [turn, str(p), str(a.attack_target)])


static func _check_consistency(state: GameState, total_cards: Array[int], played: Array[int], turn: int, when_text: String, errors: Array[String]) -> void:
	var board: BoardState = state.board
	if board.occupancy.size() != state.pieces.size():
		errors.append("turn %d %s: occupancy %d != pieces %d" % [turn, when_text, board.occupancy.size(), state.pieces.size()])
	var ids: Dictionary = {}
	for p: Piece in state.pieces:
		if ids.has(p.id):
			errors.append("turn %d %s: duplicate piece id %d" % [turn, when_text, p.id])
		ids[p.id] = true
		if not p.is_alive:
			errors.append("turn %d %s: dead piece still listed %s" % [turn, when_text, str(p)])
		if not board.is_inside(p.position) or board.get_piece_at(p.position) != p:
			errors.append("turn %d %s: piece/board mismatch %s" % [turn, when_text, str(p)])
		if p.current_hp > p.max_hp or p.current_shield < 0 or p.total_shield < 0:
			errors.append("turn %d %s: invalid HP/shield %s" % [turn, when_text, str(p)])
		if board.is_wall(p.position):
			errors.append("turn %d %s: piece stands on a wall %s" % [turn, when_text, str(p)])
	for effect: TileEffect in board.tile_effects.values():
		if effect.expiry_turn < state.turn_number:
			errors.append("turn %d %s: stale tile effect %s" % [turn, when_text, str(effect)])
	for i in range(GameState.PLAYER_COUNT):
		var ps: PlayerState = state.players[i]
		if ps.victory_points < 0:
			errors.append("turn %d %s: negative VP of P%d" % [turn, when_text, i])
		var cards: int = ps.hand.size() + ps.deck.size() + ps.draft_offer.size() + played[i] + state.get_pieces_of(i).size()
		if cards != total_cards[i]:
			errors.append("turn %d %s: card count of P%d is %d, expected %d" % [turn, when_text, i, cards, total_cards[i]])


## Formats "Key=count" pairs; name_of converts an enum key to its C# name.
static func _format_counts(counts: Dictionary, name_of: Callable) -> String:
	if counts.size() == 0:
		return "-"
	var parts: PackedStringArray = PackedStringArray()
	for key in counts:
		parts.append("%s=%d" % [name_of.call(key), counts[key]])
	return ", ".join(parts)


static func _build_deck(tag: String) -> Array[CardData]:
	var deck: Array[CardData] = []
	for i in range(2):
		deck.append(_unit("%s Soldier %d" % [tag, i], UnitRole.ATTACK, 2, 2, 3))
		deck.append(_unit("%s Archer %d" % [tag, i], UnitRole.ATTACK, 2, 1, 2, 3))
		deck.append(_unit("%s Guard %d" % [tag, i], UnitRole.UTILITY, 1, 1, 4, 1, 2))
		deck.append(_unit("%s Scout %d" % [tag, i], UnitRole.UTILITY, 3, 1, 2))
		deck.append(_unit("%s Miner %d" % [tag, i], UnitRole.RESOURCE, 1, 0, 3, 1, 0, 1))
		deck.append(_spell("%s Rage %d" % [tag, i], 2))
		deck.append(_spell("%s Bulwark %d" % [tag, i], 0, 1, 2))
		deck.append(_spell("%s Weaken %d" % [tag, i], -1, 0, 0, -1))
	deck.append(_unit("%s Totem" % tag, UnitRole.UTILITY, 0, 1, 3, 2, 0, 0, Keyword.CONDUIT))
	deck.append(_unit("%s Flame Archer" % tag, UnitRole.ATTACK, 1, 1, 2, 3, 0, 0, Keyword.BURNING))
	deck.append(_unit("%s Ram" % tag, UnitRole.ATTACK, 1, 2, 4, 1, 0, 0, Keyword.PUSH))
	deck.append(_unit("%s Bone Knight" % tag, UnitRole.ATTACK, 2, 1, 2, 1, 0, 0, Keyword.UNDYING))

	var meteor: CardData = CardData.new()
	meteor.name = "%s Meteor" % tag
	meteor.card_type = CardType.SPELL
	meteor.spell_target = SpellTargetType.AREA
	meteor.area_shape = AreaShape.PLUS
	meteor.tile_effect = TileEffectType.LAVA
	meteor.tile_effect_duration = 2
	meteor.spell_damage = 1
	deck.append(meteor)

	var wall: CardData = CardData.new()
	wall.name = "%s Stone Wall" % tag
	wall.card_type = CardType.SPELL
	wall.ap_cost = 1
	wall.spell_target = SpellTargetType.AREA
	wall.area_shape = AreaShape.ROW3
	wall.tile_effect = TileEffectType.WALL
	wall.tile_effect_duration = 2
	deck.append(wall)
	return deck


static func _unit(card_name: String, role: int, mov: int, atk: int, hp: int, rng: int = 1, shd: int = 0,
		ap_bonus: int = 0, kw: int = Keyword.NONE) -> CardData:
	var c: CardData = CardData.new()
	c.name = card_name
	c.card_type = CardType.UNIT
	c.role = role
	c.movement = mov
	c.attack = atk
	c.hp = hp
	c.range = rng
	c.shield = shd
	c.ap_bonus = ap_bonus
	c.keywords = kw
	return c


static func _spell(card_name: String, atk_delta: int = 0, hp_delta: int = 0, shd_delta: int = 0, mov_delta: int = 0) -> CardData:
	var c: CardData = CardData.new()
	c.name = card_name
	c.card_type = CardType.SPELL
	c.attack_delta = atk_delta
	c.hp_delta = hp_delta
	c.shield_delta = shd_delta
	c.movement_delta = mov_delta
	return c
