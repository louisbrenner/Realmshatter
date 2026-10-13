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
	var sb := PackedStringArray()
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
	if starter != null and starter.cards != null and starter.cards.size() > 0:
		var cards: Array[CardData] = []
		for c: CardData in starter.cards:
			if c != null:
				cards.append(c)
		for seed_value: int in [6, 7, 8]:
			failures += _run_vs_turtle(seed_value, sb, cards, cards, "Starter")
		var npc_decks: Array[String] = [
			"NpcFireApprentice", "NpcFireLeader", "NpcFrostApprentice", "NpcFrostLeader", "NpcHealingApprentice",
			"NpcHealingLeader", "NpcStoneApprentice", "NpcStoneLeader", "NpcStormApprentice", "NpcStormLeader",
		]
		for i: int in range(npc_decks.size()):
			var npc: Variant = _load_deck(npc_decks[i], sb)
			if npc == null:
				failures += 1
			else:
				failures += _run_vs_turtle(20 + i, sb, cards, npc, npc_decks[i])
	var themes: Array[String] = ["EmberLegion", "DawnCovenant", "Frostbound", "StormCircuit", "StoneBastion"]
	for i: int in range(themes.size()):
		var a: Variant = _load_deck(themes[i], sb)
		if a == null:
			failures += 1
		var b: Variant = _load_deck(themes[(i + 1) % themes.size()], sb)
		if b == null:
			failures += 1
		if a != null and b != null:
			sb.append("%s vs %s:" % [themes[i], themes[(i + 1) % themes.size()]])
			failures += _run_game(10 + i, MAX_TURNS * 2, sb, a, b)
	# The endboss deck (all five Legendary units) against a clan deck.
	var boss: Variant = _load_deck("BossRealmshatter", sb)
	if boss == null:
		failures += 1
	var clan_deck: Variant = _load_deck("StoneBastion", sb)
	if clan_deck == null:
		failures += 1
	if boss != null and clan_deck != null:
		sb.append("StoneBastion vs BossRealmshatter:")
		failures += _run_game(15, MAX_TURNS * 2, sb, clan_deck, boss, 2)
	sb.append("Result: PASS" if failures == 0 else "Result: FAIL (%d problem(s))" % failures)
	return "\n".join(sb) + "\n"


## Loads a deck's cards; on failure appends a FAIL line and returns null (the caller counts the failure,
## replacing the C# ref parameter). Returns Array[CardData] or null.
static func _load_deck(name: String, sb: PackedStringArray) -> Variant:
	var deck: DeckData = load("res://Resources/Decks/%s.tres" % name) as DeckData
	if deck == null or deck.cards == null or deck.cards.size() == 0:
		sb.append("  [FAIL] could not load %s" % name)
		return null
	var cards: Array[CardData] = []
	for c: CardData in deck.cards:
		if c != null:
			cards.append(c)
	return cards


static func _run_game(seed_value: int, max_turns: int, sb: PackedStringArray, deck0: Array[CardData], deck1: Array[CardData], boss_bonus_ap: int = 0) -> int:
	var errors: Array[String] = []
	var action_counts: Dictionary = {}
	var event_counts: Dictionary = {}
	var turns_played: int = 0
	var state: GameState = null
	var map: String = ""
	var zone_sum: Array[int] = [0, 0]
	var home_sum: Array[int] = [0, 0]
	var turns_of: Array[int] = [0, 0]

	var config := GameConfig.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	state = GameState.new(config, deck0, deck1, rng)
	# The themed matches play on generated battlefields (rivers, lava, rocks, springs).
	map = MapGenerator.generate(state).name if seed_value >= 10 else ""
	state.players[1].bonus_ap_per_turn = boss_bonus_ap
	var controller := TurnController.new(state)
	var ais: Array[SimpleAi] = [SimpleAi.new(controller, 0), SimpleAi.new(controller, 1)]
	var total_cards: Array[int] = [state.players[0].deck.size(), state.players[1].deck.size()]
	# Spells cast are consumed; destroyed units go to the graveyard (Undying: back to the deck); pieces on board are counted live.
	var played: Array[int] = [0, 0]
	var last_vp: Array[int] = [0, 0]
	# AP gained during the own turn (AP spells, Plunder kills) is added back in the AP accounting.
	# (A 1-element box: GDScript lambdas capture locals by value.)
	var gained_now: Array[int] = [0]
	var count_gains := func(events: Array) -> void:
		for e: ResolutionEvent in events:
			if e.type == ResolutionEventType.AP_GAINED and not e.is_secondary and e.player_index == state.current_player_index:
				gained_now[0] += e.amount
	controller.action_resolved.connect(count_gains)
	controller.spell_resolved.connect(count_gains)

	controller.start_game()

	while turns_played < max_turns and state.phase != GamePhase.GAME_OVER:
		var current: int = state.current_player_index
		var turn_before: int = state.turn_number
		var ap_before: int = state.players[current].action_points
		gained_now[0] = 0
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
				AiActionKind.COMMAND:
					spent += config.order_ap_cost
				AiActionKind.TRAP:
					spent += config.trap_ap_cost
				AiActionKind.BUILD:
					var unit_class: int = a.card.class_ if a.card != null else UnitClass.NONE
					spent += BuildingInfo.get_cost(BuildingInfo.for_class(unit_class))
				AiActionKind.CONVERT_VP:
					spent += -1
				_:
					spent += 0
		if ap_before - spent + gained_now[0] != state.players[current].action_points:
			errors.append("turn %d: AP accounting %d - %d + %d != %d" % [turn_before, ap_before, spent, gained_now[0], state.players[current].action_points])
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
		_check_actions(state, current, actions, turn_before, errors)
		turns_of[current] += 1
		for p: Piece in state.get_pieces_of(current):
			if not p.is_building:
				zone_sum[current] += 1 if state.board.is_in_scoring_zone(p.position) else 0
				home_sum[current] += 1 if state.board.is_in_deploy_zone(current, p.position) else 0
		_check_consistency(state, total_cards, played, turn_before, "after TakeTurn", errors)

		var events: Array[ResolutionEvent] = controller.end_turn()
		var all_events: Array[ResolutionEvent] = events.duplicate()
		all_events.append_array(controller.last_turn_start_events)
		for e: ResolutionEvent in all_events:
			event_counts[e.type] = int(event_counts.get(e.type, 0)) + 1
		turns_played += 1

		if state.phase != GamePhase.GAME_OVER:
			if state.current_player_index != 1 - current:
				errors.append("turn %d: player did not swap" % turn_before)
			if state.turn_number != turn_before + 1:
				errors.append("turn %d: turn number did not advance" % turn_before)
		for i: int in range(GameState.PLAYER_COUNT):
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
	var map_text: String = "" if map.is_empty() else " on %s" % map
	sb.append("Game seed %d%s: %d turns, winner %s, " % [seed_value, map_text, turns_played, winner_text]
		+ "VP %d:%d, " % [vp0, vp1]
		+ "pieces alive %d:%d" % [alive0, alive1])
	sb.append("  actions: " + _format_counts(action_counts, func(k: int) -> String: return AiActionKind.name_of(k)))
	sb.append("  units after own turn (avg in zone / in home rows): "
		+ "P0 %.1f / %.1f, " % [zone_sum[0] / float(maxi(1, turns_of[0])), home_sum[0] / float(maxi(1, turns_of[0]))]
		+ "P1 %.1f / %.1f" % [zone_sum[1] / float(maxi(1, turns_of[1])), home_sum[1] / float(maxi(1, turns_of[1]))])
	sb.append("  events:  " + _format_counts(event_counts, func(k: int) -> String: return ResolutionEventType.name_of(k)))
	if errors.size() == 0:
		sb.append("  [PASS] no exceptions, state consistent")
	for err: String in errors:
		sb.append("  [FAIL] " + err)
	return errors.size()


## Regression for "the AI stays in its base": player 0 only deploys units into its back rows (a human building up),
## player 1 is the SimpleAi. Within 12 AI turns the AI must have units standing in the scoring zone on average and
## must have scored victory points.
static func _run_vs_turtle(seed_value: int, sb: PackedStringArray, turtle_deck: Array[CardData], ai_deck: Array[CardData], ai_name: String) -> int:
	const AI_TURNS := 12
	var config := GameConfig.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var state := GameState.new(config, turtle_deck.duplicate(), ai_deck.duplicate(), rng)
	var controller := TurnController.new(state)
	var ai := SimpleAi.new(controller, 1)
	controller.start_game()
	var ai_turns: int = 0
	var zone_sum: int = 0
	var home_sum: int = 0
	while ai_turns < AI_TURNS and state.phase != GamePhase.GAME_OVER:
		if state.current_player_index == 0:
			var turtle: PlayerState = state.players[0]
			for card: CardData in turtle.hand.duplicate():
				if card.card_type != CardType.UNIT or controller.get_card_cost(card) > turtle.action_points:
					continue
				for i: int in range(config.board_width * config.deploy_rows):
					var pos := Vector2i(i % config.board_width, config.board_height - 1 - i / config.board_width)
					if controller.can_play_unit_card(card, pos):
						controller.play_unit_card(card, pos)
						break
		else:
			ai.take_turn()
			ai_turns += 1
			for p: Piece in state.get_pieces_of(1):
				if p.is_building:
					continue
				zone_sum += 1 if state.board.is_in_scoring_zone(p.position) else 0
				home_sum += 1 if state.board.is_in_deploy_zone(1, p.position) else 0
		controller.end_turn()
	var zone_avg: float = zone_sum / float(ai_turns) if ai_turns > 0 else 0.0
	var home_avg: float = home_sum / float(ai_turns) if ai_turns > 0 else 0.0
	var vp: int = state.players[1].victory_points
	var ok: bool = zone_avg >= 1.5 and vp >= 6
	sb.append("Turtle seed %d (%s): AI after %d turns: %d VP, avg units in zone %.1f, in home rows %.1f"
		% [seed_value, ai_name, ai_turns, vp, zone_avg, home_avg])
	sb.append("  [PASS] the AI advances into the scoring zone" if ok else "  [FAIL] the AI does not push into the scoring zone")
	return 0 if ok else 1


## Every Command action acted on an own, non-sick piece that is now marked as acted, at most once per piece.
static func _check_actions(state: GameState, player: int, actions: Array[AiAction], turn: int, errors: Array[String]) -> void:
	var commanded: Dictionary = {}
	for a: AiAction in actions:
		if a.kind != AiActionKind.COMMAND and a.kind != AiActionKind.BUILD and a.kind != AiActionKind.TRAP:
			continue
		if commanded.has(a.piece_id):
			errors.append("turn %d: piece %d was commanded twice" % [turn, a.piece_id])
		commanded[a.piece_id] = true
		var p: Piece = state.get_piece(a.piece_id)
		if p == null:
			continue # died during the turn (friendly fire / lava is possible)
		if p.owner_index != player:
			errors.append("turn %d: commanded a piece of the inactive player %s" % [turn, str(p)])
		if not p.has_acted(turn):
			errors.append("turn %d: commanded piece not marked as acted %s" % [turn, str(p)])
		if p.summoned_turn >= turn:
			errors.append("turn %d: summoning-sick piece acted %s" % [turn, str(p)])


static func _check_consistency(state: GameState, total_cards: Array[int], played: Array[int], turn: int, when: String, errors: Array[String]) -> void:
	var board: BoardState = state.board
	if board.occupancy.size() != state.pieces.size():
		errors.append("turn %d %s: occupancy %d != pieces %d" % [turn, when, board.occupancy.size(), state.pieces.size()])
	var ids: Dictionary = {}
	for p: Piece in state.pieces:
		if ids.has(p.id):
			errors.append("turn %d %s: duplicate piece id %d" % [turn, when, p.id])
		ids[p.id] = true
		if not p.is_alive:
			errors.append("turn %d %s: dead piece still listed %s" % [turn, when, str(p)])
		if not board.is_inside(p.position) or board.get_piece_at(p.position) != p:
			errors.append("turn %d %s: piece/board mismatch %s" % [turn, when, str(p)])
		if p.current_hp > p.max_hp or p.current_shield < 0 or p.total_shield < 0:
			errors.append("turn %d %s: invalid HP/shield %s" % [turn, when, str(p)])
		if board.is_wall(p.position):
			errors.append("turn %d %s: piece stands on a wall %s" % [turn, when, str(p)])
	for effect: TileEffect in board.tile_effects.values():
		if effect.expiry_turn < state.turn_number:
			errors.append("turn %d %s: stale tile effect %s" % [turn, when, str(effect)])
	for i: int in range(GameState.PLAYER_COUNT):
		var ps: PlayerState = state.players[i]
		if ps.victory_points < 0:
			errors.append("turn %d %s: negative VP of P%d" % [turn, when, i])
		var units: int = 0
		for p: Piece in state.get_pieces_of(i):
			if not p.is_building:
				units += 1
		var cards: int = ps.hand.size() + ps.deck.size() + ps.draft_offer.size() + ps.graveyard.size() + played[i] + units
		if cards != total_cards[i]:
			errors.append("turn %d %s: card count of P%d is %d, expected %d" % [turn, when, i, cards, total_cards[i]])


## C# FormatCounts<T>: key_name turns an enum key into its C# name.
static func _format_counts(counts: Dictionary, key_name: Callable) -> String:
	if counts.size() == 0:
		return "-"
	var parts := PackedStringArray()
	for k: Variant in counts.keys():
		parts.append("%s=%d" % [key_name.call(k), counts[k]])
	return ", ".join(parts)


static func _build_deck(tag: String) -> Array[CardData]:
	var deck: Array[CardData] = []
	for i: int in range(2):
		deck.append(_unit("%s Soldier %d" % [tag, i], UnitRole.ATTACK, 2, 2, 3))
		deck.append(_unit("%s Archer %d" % [tag, i], UnitRole.ATTACK, 2, 1, 2, 3))
		deck.append(_unit("%s Guard %d" % [tag, i], UnitRole.UTILITY, 1, 1, 4, 1, 2))
		deck.append(_unit("%s Scout %d" % [tag, i], UnitRole.UTILITY, 3, 1, 2))
		deck.append(_unit("%s Miner %d" % [tag, i], UnitRole.RESOURCE, 1, 0, 3, 1, 0, 1))
		deck.append(_spell("%s Rage %d" % [tag, i], 2))
		deck.append(_spell("%s Bulwark %d" % [tag, i], 0, 1, 2))
		deck.append(_spell("%s Weaken %d" % [tag, i], -1, 0, 0, -1))
	deck.append(_unit("%s Totem" % tag, UnitRole.UTILITY, 0, 1, 3, 2, 0, 0, Keyword.ARC))
	deck.append(_unit("%s Flame Archer" % tag, UnitRole.ATTACK, 1, 1, 2, 3, 0, 0, Keyword.BURNING))
	deck.append(_unit("%s Ram" % tag, UnitRole.ATTACK, 1, 2, 4, 1, 0, 0, Keyword.PUSH))
	deck.append(_unit("%s Bone Knight" % tag, UnitRole.ATTACK, 2, 1, 2, 1, 0, 0, Keyword.UNDYING))
	var meteor := CardData.new()
	meteor.name = "%s Meteor" % tag
	meteor.card_type = CardType.SPELL
	meteor.spell_target = SpellTargetType.AREA
	meteor.area_shape = AreaShape.PLUS
	meteor.tile_effect = TileEffectType.LAVA
	meteor.tile_effect_duration = 2
	meteor.spell_damage = 1
	deck.append(meteor)
	var wall := CardData.new()
	wall.name = "%s Stone Wall" % tag
	wall.card_type = CardType.SPELL
	wall.ap_cost = 1
	wall.spell_target = SpellTargetType.AREA
	wall.area_shape = AreaShape.ROW3
	wall.tile_effect = TileEffectType.WALL
	wall.tile_effect_duration = 2
	deck.append(wall)
	return deck


static func _unit(name: String, role: int, mov: int, atk: int, hp: int, rng: int = 1, shd: int = 0, ap_bonus: int = 0,
		kw: int = Keyword.NONE) -> CardData:
	var c := CardData.new()
	c.name = name
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


static func _spell(name: String, atk_delta: int = 0, hp_delta: int = 0, shd_delta: int = 0, mov_delta: int = 0) -> CardData:
	var c := CardData.new()
	c.name = name
	c.card_type = CardType.SPELL
	c.attack_delta = atk_delta
	c.hp_delta = hp_delta
	c.shield_delta = shd_delta
	c.movement_delta = mov_delta
	return c
