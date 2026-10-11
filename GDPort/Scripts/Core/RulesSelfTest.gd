class_name RulesSelfTest
extends RefCounted
## In-code sanity checks of the core rules. Call run() from the game and print the report.

## C# int.MinValue sentinel for _has (any piece id).
const _ANY_PIECE: int = -9223372036854775807 - 1


class Report:
	extends RefCounted
	var text: String = ""
	var passed: int = 0
	var failed: int = 0

	func append_line(line: String) -> void:
		text += line + "\n"

	func check(condition: bool, name: String) -> void:
		if condition:
			passed += 1
			append_line("  [PASS] %s" % name)
		else:
			failed += 1
			append_line("  [FAIL] %s" % name)


## Runs all checks and returns a human-readable report.
static func run() -> String:
	var r := Report.new()
	r.append_line("RulesSelfTest")
	_run_section(r, "Deploy + AP"); _test_deploy_and_ap(r)
	_run_section(r, "Draw costs AP + draft flow"); _test_draw(r)
	_run_section(r, "Order cost / refund / free replace"); _test_order_cost(r)
	_run_section(r, "Summoning sickness"); _test_summoning_sickness(r)
	_run_section(r, "VP scoring + win"); _test_scoring(r)
	_run_section(r, "Shield before HP"); _test_shield(r)
	_run_section(r, "Friendly chain"); _test_chain(r)
	_run_section(r, "Spell expiry"); _test_spell_expiry(r)
	_run_section(r, "v3: planning ignores friendlies"); _test_planning_pass_through(r)
	_run_section(r, "v3: pass-through + push at resolution"); _test_push_resolution(r)
	_run_section(r, "v3: destroyed pieces return to deck / Undying"); _test_return_to_deck(r)
	_run_section(r, "v3: VP -> AP conversion"); _test_vp_to_ap(r)
	_run_section(r, "v3: second player bonus AP"); _test_second_player_bonus(r)
	_run_section(r, "v3: lava / healing ticks"); _test_tile_ticks(r)
	_run_section(r, "v3: walls block + expire"); _test_walls(r)
	_run_section(r, "v3: tile spells"); _test_tile_spells(r)
	_run_section(r, "v3: keyword Burning"); _test_burning(r)
	_run_section(r, "v3: keyword Frost"); _test_frost(r)
	_run_section(r, "v3: keyword Push"); _test_push_keyword(r)
	_run_section(r, "v3: keyword Pierce"); _test_pierce(r)
	_run_section(r, "v3: keyword Mending"); _test_mending(r)
	_run_section(r, "v3: keyword Conduit"); _test_conduit(r)
	_run_section(r, "v3: keyword Echo + Overcharge"); _test_echo_overcharge(r)
	_run_section(r, "v3: chain preview == actual"); _test_chain_preview(r)
	_run_section(r, "v3: StarterDeck resource"); _test_starter_deck(r)
	r.append_line("Result: %d passed, %d failed" % [r.passed, r.failed])
	return r.text


## GDScript has no try/catch: a failing section stops with a script error instead of "[FAIL] exception".
static func _run_section(r: Report, title: String) -> void:
	r.append_line(title)


static func _unit(name: String, mov: int = 2, atk: int = 1, hp: int = 3, rng: int = 1, shd: int = 0, ap_bonus: int = 0, kw: int = Keyword.NONE) -> CardData:
	var c := CardData.new()
	c.name = name
	c.card_type = CardType.UNIT
	c.movement = mov
	c.attack = atk
	c.hp = hp
	c.range = rng
	c.shield = shd
	c.ap_bonus = ap_bonus
	c.keywords = kw
	return c


static func _spell(name: String, atk: int = 0, hp: int = 0, shd: int = 0) -> CardData:
	var c := CardData.new()
	c.name = name
	c.card_type = CardType.SPELL
	c.attack_delta = atk
	c.hp_delta = hp
	c.shield_delta = shd
	return c


static func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## New game with empty decks (nothing to draw) and player 0 in Main phase. The state is tc.state
## (replaces the C# out parameter).
static func _new_game() -> TurnController:
	var empty0: Array[CardData] = []
	var empty1: Array[CardData] = []
	var state := GameState.new(GameConfig.new(), empty0, empty1, _rng(1234))
	var tc := TurnController.new(state)
	tc.start_game()
	return tc


## Spawns a piece that is already commandable (as if summoned before the game started).
static func _spawn_ready(state: GameState, card: CardData, owner: int, pos: Vector2i) -> Piece:
	var p: Piece = state.spawn_piece(card, owner, pos)
	if p != null:
		p.summoned_turn = 0
	return p


static func _unit_deck(count: int) -> Array[CardData]:
	var deck: Array[CardData] = []
	for i: int in range(count):
		deck.append(_unit("U%d" % i))
	return deck


static func _test_deploy_and_ap(r: Report) -> void:
	var deck := _unit_deck(7)
	var state := GameState.new(GameConfig.new(), deck, deck.duplicate(), _rng(42))
	var tc := TurnController.new(state)
	tc.start_game()
	var p0: PlayerState = state.players[0]
	r.check(p0.hand.size() == 3, "starting hand is 3")
	r.check(state.phase == GamePhase.MAIN and p0.draft_offer.size() == 0, "no free draft at turn start (Main phase)")
	r.check(p0.action_points == 3, "base AP is 3")

	var c0: CardData = p0.hand[0]
	r.check(tc.play_unit_card(c0, Vector2i(4, 0)) == null, "player 0 cannot deploy in row 0")
	r.check(tc.play_unit_card(c0, Vector2i(4, 5)) == null, "player 0 cannot deploy in row 5")
	r.check(tc.play_unit_card(c0, Vector2i(4, 6)) != null, "player 0 can deploy in row 6")
	r.check(p0.action_points == 2, "unit costs 1 AP")
	r.check(tc.play_unit_card(p0.hand[0], Vector2i(4, 6)) == null, "cannot deploy on occupied tile")

	var spell := _spell("Buff", 1)
	p0.hand.append(spell)
	r.check(tc.get_card_cost(spell) == 2, "spell costs 2 AP")
	r.check(tc.play_spell_card(spell, state.board.get_piece_at(Vector2i(4, 6))) and p0.action_points == 0, "spell deducts 2 AP")
	r.check(tc.play_unit_card(p0.hand[0], Vector2i(5, 7)) == null, "cannot play without AP")

	tc.end_turn()
	r.check(state.current_player_index == 1 and state.turn_number == 2, "turn passes to player 1")
	r.check(state.phase == GamePhase.MAIN and state.players[1].draft_offer.size() == 0, "player 1 starts in Main phase")
	r.check(state.board.is_in_deploy_zone(1, Vector2i(0, 1)) and not state.board.is_in_deploy_zone(1, Vector2i(0, 2)), "player 1 deploy rows are 0-1")
	r.check(tc.play_unit_card(state.players[1].hand[0], Vector2i(3, 7)) == null, "player 1 cannot deploy in row 7")
	r.check(tc.play_unit_card(state.players[1].hand[0], Vector2i(3, 1)) != null, "player 1 can deploy in row 1")

	var res_unit := _unit("Miner", 2, 1, 3, 1, 0, 1)
	state.spawn_piece(res_unit, 0, Vector2i(0, 7))
	tc.end_turn()
	r.check(state.players[0].action_points == 4, "ApBonus adds to base AP")


static func _test_draw(r: Report) -> void:
	var deck := _unit_deck(7)
	var state := GameState.new(GameConfig.new(), deck, deck.duplicate(), _rng(7))
	var tc := TurnController.new(state)
	tc.start_game()
	var p0: PlayerState = state.players[0]
	var total := func() -> int: return p0.hand.size() + p0.deck.size() + p0.draft_offer.size()

	r.check(p0.deck.size() == 4 and p0.hand.size() == 3, "deck 4 / hand 3 after dealing")
	r.check(not tc.choose_draft_card(0), "cannot choose a draft card without drawing")
	r.check(tc.can_draw(), "can draw in main phase with AP and cards")
	r.check(tc.draw() and p0.action_points == 2, "draw costs 1 AP")
	r.check(state.phase == GamePhase.DRAFT and p0.draft_offer.size() == 3 and p0.deck.size() == 1, "draw offers 3 cards (Draft phase)")
	r.check(not tc.can_draw() and not tc.draw(), "cannot draw again while choosing")
	r.check(tc.play_unit_card(p0.hand[0], Vector2i(4, 6)) == null, "cannot play cards during draft")
	r.check(tc.end_turn().size() == 0 and state.phase == GamePhase.DRAFT and state.current_player_index == 0, "cannot end turn during draft")
	r.check(not tc.choose_draft_card(5), "invalid draft index rejected")
	var picked: CardData = p0.draft_offer[1]
	r.check(tc.choose_draft_card(1) and p0.hand.has(picked) and p0.hand.size() == 4, "chosen card goes to hand")
	r.check(p0.draft_offer.size() == 0 and p0.deck.size() == 3 and state.phase == GamePhase.MAIN, "rest returns to deck, back to Main")
	r.check(total.call() == 7, "card count conserved")

	r.check(tc.draw() and tc.choose_draft_card(0) and p0.action_points == 1 and p0.hand.size() == 5, "second draw in the same turn")
	r.check(tc.draw() and p0.draft_offer.size() == 2 and tc.choose_draft_card(0) and p0.action_points == 0, "third draw offers the remaining 2 cards")
	r.check(not tc.can_draw() and tc.last_error.contains("AP"), "cannot draw without AP")
	r.check(total.call() == 7, "card count conserved after several draws")

	tc.end_turn()
	r.check(state.phase == GamePhase.MAIN and state.players[1].action_points == 3 + state.config.second_player_first_turn_bonus_ap,
		"next turn starts in Main with full AP (+ second player bonus)")

	var empty := _new_game()
	var empty_state: GameState = empty.state
	r.check(not empty.can_draw() and not empty.draw() and empty_state.players[0].action_points == 3, "cannot draw from an empty deck (no AP spent)")


static func _test_order_cost(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var p0: PlayerState = state.players[0]
	var a := _spawn_ready(state, _unit("A", 2), 0, Vector2i(4, 5))
	var b := _spawn_ready(state, _unit("B", 2), 0, Vector2i(6, 5))

	r.check(tc.set_order(a, Vector2i(4, 4), null) and p0.action_points == 2, "new order costs 1 AP")
	var index: int = a.order.order_index
	r.check(tc.set_order(a, Vector2i(4, 3), null) and p0.action_points == 2 and a.order.order_index == index
		and a.order.move_target == Vector2i(4, 3), "replacing an order is free and keeps its index")
	r.check(tc.set_order(a, null, null) and a.order == null and p0.action_points == 3, "SetOrder(null, null) clears and refunds")
	r.check(tc.set_order(a, Vector2i(4, 4), null) and p0.action_points == 2, "re-order costs again")
	tc.clear_order(a)
	r.check(a.order == null and p0.action_points == 3, "ClearOrder refunds")
	r.check(tc.set_order(b, null, null) and p0.action_points == 3, "clearing a piece without order is free")

	r.check(tc.set_order(a, Vector2i(4, 4), null), "order A")
	p0.action_points = 0
	r.check(not tc.can_set_order(b, Vector2i(6, 4), null) and tc.last_error.contains("AP"), "new order rejected without AP")
	r.check(not tc.set_order(b, Vector2i(6, 4), null) and b.order == null and p0.action_points == 0, "failed order changes nothing")
	r.check(tc.set_order(a, Vector2i(3, 5), null) and p0.action_points == 0, "replacing works with 0 AP")

	tc.end_turn()
	r.check(a.order == null and p0.action_points == 0, "orders cleared at end of turn without refund")
	r.check(a.position == Vector2i(3, 5), "replaced order was executed")


static func _test_summoning_sickness(r: Report) -> void:
	var deck := _unit_deck(6)
	var state := GameState.new(GameConfig.new(), deck, deck.duplicate(), _rng(3))
	var tc := TurnController.new(state)
	tc.start_game()
	var p0: PlayerState = state.players[0]

	var p: Piece = tc.play_unit_card(p0.hand[0], Vector2i(4, 6))
	r.check(p != null and p.summoned_turn == 1 and p.is_summoning_sick(1), "played piece is summoning sick on turn 1")
	r.check(not tc.can_command(p) and tc.last_error.contains("Summoning"), "CanCommand false while sick")
	r.check(not tc.set_order(p, Vector2i(4, 5), null) and p.order == null and p0.action_points == 2, "sick piece cannot get orders (no AP spent)")

	tc.end_turn()
	r.check(not tc.can_command(p), "opponent cannot command it on turn 2")
	tc.end_turn()
	r.check(state.turn_number == 3 and not p.is_summoning_sick(3) and tc.can_command(p), "commandable on owner's next turn")
	r.check(tc.set_order(p, Vector2i(4, 5), null) and p0.action_points == 2, "order on owner's next turn costs 1 AP")

	var spawned: Piece = state.spawn_piece(_unit("Spawned"), 0, Vector2i(0, 7))
	r.check(spawned.summoned_turn == 3 and not tc.can_command(spawned), "SpawnPiece also marks summoning sickness")


static func _test_scoring(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	state.spawn_piece(_unit("Z1"), 0, Vector2i(2, 3))
	state.spawn_piece(_unit("Z2"), 0, Vector2i(7, 4))
	state.spawn_piece(_unit("Out"), 0, Vector2i(1, 3))
	r.check(state.board.is_in_scoring_zone(Vector2i(2, 3)) and state.board.is_in_scoring_zone(Vector2i(7, 4)), "zone corners inside")
	r.check(not state.board.is_in_scoring_zone(Vector2i(1, 3)) and not state.board.is_in_scoring_zone(Vector2i(8, 4)) and not state.board.is_in_scoring_zone(Vector2i(4, 5)), "outside zone")
	tc.end_turn()
	tc.end_turn()
	r.check(state.players[0].victory_points == 2, "+1 VP per piece in zone at turn start")

	state.players[0].victory_points = 18
	tc.end_turn()
	tc.end_turn()
	r.check(state.phase == GamePhase.GAME_OVER and state.winner == 0, "win at points target")


static func _test_shield(r: Report) -> void:
	var state: GameState = _new_game().state
	var p: Piece = state.spawn_piece(_unit("Tank", 2, 1, 3, 1, 2), 1, Vector2i(5, 2))
	var events: Array[ResolutionEvent] = []
	OrderResolver.apply_damage(state, p, 3, -1, events)
	r.check(p.current_shield == 0 and p.current_hp == 2, "3 dmg vs 2 shield/3 hp -> 0 shield, 2 hp")
	OrderResolver.apply_damage(state, p, 5, -1, events)
	r.check(not p.is_alive and state.get_piece(p.id) == null and not state.board.is_occupied(Vector2i(5, 2)), "piece dies and is removed")
	r.check(events.any(func(e: ResolutionEvent) -> bool: return e.type == ResolutionEventType.DIED), "Died event emitted")


static func _test_chain(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	# Row 5, player 0: A(2) B(3) C(4) enemy E(5).
	var a := _spawn_ready(state, _unit("A", 2, 1), 0, Vector2i(2, 5))
	var b := _spawn_ready(state, _unit("B", 2, 1), 0, Vector2i(3, 5))
	var c := _spawn_ready(state, _unit("C", 2, 1), 0, Vector2i(4, 5))
	var e := _spawn_ready(state, _unit("E", 2, 1, 5), 1, Vector2i(5, 5))
	r.check(tc.set_order(a, null, Vector2i(3, 5)), "A orders attack on friendly B")
	r.check(tc.set_order(c, null, Vector2i(5, 5)), "C orders attack on enemy E")
	r.check(not tc.set_order(a, null, Vector2i(5, 5)), "out-of-range attack rejected")
	r.check(not tc.set_order(e, null, Vector2i(4, 5)), "cannot order enemy piece")

	var events: Array[ResolutionEvent] = tc.end_turn()
	var chains: int = _count(events, ResolutionEventType.CHAIN_TRIGGERED)
	r.check(chains == 2, "chain A->B->C triggers twice")
	r.check(b.current_hp == 3 and a.current_hp == 3 and c.current_hp == 3, "friendly hits deal no damage")
	r.check(e.current_hp == 4, "enemy hit exactly once (C fires once, own order skipped)")
	# A piece "fires" either via its own (non-chain) attack or by being chain-triggered.
	var fire_count: Dictionary[int, int] = {}
	for ev: ResolutionEvent in events:
		if ev.type == ResolutionEventType.CHAIN_TRIGGERED or (ev.type == ResolutionEventType.ATTACKED and not ev.is_chain):
			fire_count[ev.piece_id] = fire_count[ev.piece_id] + 1 if fire_count.has(ev.piece_id) else 1
	var once: bool = fire_count.size() == 3
	for n: int in fire_count.values():
		once = once and n == 1
	r.check(once, "each unit fires exactly once")


static func _test_spell_expiry(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var p: Piece = state.spawn_piece(_unit("Target", 2, 1, 3), 0, Vector2i(4, 6))
	var buff := _spell("Rage", 2, 2, 1)
	state.players[0].hand.append(buff)
	r.check(tc.play_spell_card(buff, p), "cast spell turn 1")
	r.check(p.effective_attack == 3 and p.max_hp == 5 and p.current_hp == 5 and p.total_shield == 1, "modifiers applied")
	tc.end_turn() # end turn 1
	r.check(p.active_spells.size() == 1, "active during opponent's turn")
	tc.end_turn() # end turn 2
	r.check(p.active_spells.size() == 1 and p.effective_attack == 3, "active during caster's next turn")
	tc.end_turn() # end turn 3 (caster's next turn)
	r.check(p.active_spells.size() == 0 and p.effective_attack == 1 and p.max_hp == 3 and p.current_hp == 3 and p.total_shield == 0, "expired at end of caster's next turn")


# ------------------------------------------------------------------ rules v3

static func _g(x: int, y: int) -> Vector2i:
	return Vector2i(x, y)


static func _has(events: Array, type: int, piece_id: int = _ANY_PIECE) -> bool:
	for e: ResolutionEvent in events:
		if e.type == type and (piece_id == _ANY_PIECE or e.piece_id == piece_id):
			return true
	return false


static func _count(events: Array, type: int) -> int:
	var n: int = 0
	for e: ResolutionEvent in events:
		if e.type == type:
			n += 1
	return n


static func _place(state: GameState, type: int, pos: Vector2i, duration: int = 2) -> void:
	OrderResolver.apply_tile_effect(state, type, pos, duration, 0, "Test", -1, null)


static func _test_planning_pass_through(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var a := _spawn_ready(state, _unit("A", 2), 0, _g(4, 6))
	_spawn_ready(state, _unit("B"), 0, _g(4, 5))
	_spawn_ready(state, _unit("E"), 1, _g(5, 6))

	var targets: Array[Vector2i] = tc.get_valid_move_targets(a)
	r.check(targets.has(_g(4, 4)), "can plan a move through a friendly")
	r.check(targets.has(_g(4, 5)), "can plan a move ending on a friendly")
	r.check(not targets.has(_g(5, 6)) and not targets.has(_g(6, 6)), "enemies still block (no end on / passing)")
	var path: Array[Vector2i] = tc.get_planned_path(a, _g(4, 4))
	r.check(path.size() == 2 and path[0] == _g(4, 5) and path[1] == _g(4, 4), "GetPlannedPath goes through the friendly")
	r.check(tc.get_planned_path(a, _g(6, 6)).size() == 0, "no planned path past an enemy")
	r.check(tc.can_set_order(a, _g(4, 5), null), "order onto a friendly tile accepted")
	r.check(not tc.can_set_order(a, _g(5, 6), null), "order onto an enemy tile rejected")
	r.check(not state.board.get_reachable_tiles(_g(4, 6), 2).has(_g(4, 4)), "strict GetReachableTiles(from, mov) still blocks")


static func _test_push_resolution(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var a := _spawn_ready(state, _unit("A", 2), 0, _g(4, 6))
	var b := _spawn_ready(state, _unit("B"), 0, _g(4, 5))
	tc.set_order(a, _g(4, 4), null)
	tc.end_turn()
	r.check(a.position == _g(4, 4) and b.position == _g(4, 5), "mover passes through a friendly at resolution")

	tc = _new_game()
	state = tc.state
	a = _spawn_ready(state, _unit("A", 1), 0, _g(4, 6))
	b = _spawn_ready(state, _unit("B"), 0, _g(4, 5))
	var c := _spawn_ready(state, _unit("C"), 0, _g(4, 4))
	tc.set_order(a, _g(4, 5), null)
	var ev: Array[ResolutionEvent] = tc.end_turn()
	r.check(a.position == _g(4, 5) and b.position == _g(4, 4) and c.position == _g(4, 3), "ending on a friendly pushes it (chain push)")
	r.check(_count(ev, ResolutionEventType.PUSHED) == 2 and _has(ev, ResolutionEventType.MOVED, a.id), "Moved + 2 Pushed events")

	tc = _new_game()
	state = tc.state
	a = _spawn_ready(state, _unit("A", 2), 0, _g(4, 7))
	b = _spawn_ready(state, _unit("B"), 0, _g(4, 5))
	_spawn_ready(state, _unit("E"), 1, _g(4, 4))
	tc.set_order(a, _g(4, 5), null)
	ev = tc.end_turn()
	r.check(a.position == _g(4, 6) and b.position == _g(4, 5), "impossible push: mover stops on the last free tile")
	r.check(_has(ev, ResolutionEventType.PUSH_BLOCKED, b.id), "PushBlocked event")

	tc = _new_game()
	state = tc.state
	a = _spawn_ready(state, _unit("A", 1), 0, _g(4, 6))
	_spawn_ready(state, _unit("B"), 0, _g(4, 5))
	_spawn_ready(state, _unit("E"), 1, _g(4, 4))
	tc.set_order(a, _g(4, 5), null)
	ev = tc.end_turn()
	r.check(a.position == _g(4, 6) and _has(ev, ResolutionEventType.MOVE_BLOCKED, a.id), "no free tile on the path -> MoveBlocked")

	tc = _new_game()
	state = tc.state
	a = _spawn_ready(state, _unit("A", 2), 0, _g(4, 6))
	r.check(tc.set_order(a, _g(4, 4), null), "order through an empty tile")
	state.spawn_piece(_unit("E"), 1, _g(4, 5))
	ev = tc.end_turn()
	r.check(a.position == _g(4, 6) and _has(ev, ResolutionEventType.MOVE_BLOCKED, a.id), "enemy appearing in the path blocks (MoveBlocked)")


static func _test_return_to_deck(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var e: Piece = state.spawn_piece(_unit("Victim", 2, 1, 2), 1, _g(5, 2))
	var before: int = state.players[1].deck.size()
	var events: Array[ResolutionEvent] = []
	OrderResolver.apply_damage(state, e, 5, -1, events)
	r.check(state.players[1].deck.size() == before + 1 and state.players[1].deck.has(e.source), "destroyed piece's card returns to the owner's deck")
	r.check(events.any(func(x: ResolutionEvent) -> bool: return x.type == ResolutionEventType.RETURNED_TO_DECK and x.player_index == 1 and x.amount == 0), "ReturnedToDeck event")

	var card := _unit("Grimbone", 2, 1, 2, 1, 0, 0, Keyword.UNDYING)
	var k: Piece = state.spawn_piece(card, 0, _g(3, 6))
	OrderResolver.apply_damage(state, k, 10, -1, events)
	var deck0: Array[CardData] = state.players[0].deck
	var up: CardData = deck0[deck0.size() - 1] if deck0.size() > 0 else null
	r.check(up != null and up != card and up.level == 1 and up.attack == 2 and up.hp == 3 and up.name == "Grimbone +1"
		and up.has_keyword(Keyword.UNDYING), "Undying returns an upgraded copy (+1/+1, Level 1, name suffix)")
	r.check(card.level == 0 and card.attack == 1 and card.hp == 2 and card.name == "Grimbone", "original card resource unchanged")
	var k2: Piece = state.spawn_piece(up, 0, _g(3, 6))
	r.check(k2 != null and k2.effective_attack == 2 and k2.max_hp == 3, "upgraded card spawns a stronger piece")
	OrderResolver.apply_damage(state, k2, 10, -1, events)
	var up2: CardData = deck0[deck0.size() - 1]
	r.check(up2.level == 2 and up2.attack == 3 and up2.hp == 4 and up2.name == "Grimbone +2" and up2.base_name == "Grimbone", "second death: level 2")

	tc = _new_game()
	state = tc.state
	var att := _spawn_ready(state, _unit("Att", 2, 3), 0, _g(4, 5))
	var vic := _spawn_ready(state, _unit("Vic", 2, 1, 2), 1, _g(4, 4))
	tc.set_order(att, null, _g(4, 4))
	var ev: Array[ResolutionEvent] = tc.end_turn()
	r.check(not vic.is_alive and state.players[1].deck.has(vic.source) and _has(ev, ResolutionEventType.RETURNED_TO_DECK, vic.id),
		"kill during resolution returns the card too")


static func _test_vp_to_ap(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var p0: PlayerState = state.players[0]
	r.check(not tc.can_convert_vp_to_ap() and not tc.convert_vp_to_ap(), "cannot convert without VP")
	p0.victory_points = 3
	r.check(tc.convert_vp_to_ap() and p0.victory_points == 2 and p0.action_points == 4 and tc.vp_converted_this_turn == 1
		and tc.remaining_vp_conversions == 1, "1 VP -> 1 AP")
	r.check(tc.convert_vp_to_ap() and p0.victory_points == 1 and p0.action_points == 5 and tc.remaining_vp_conversions == 0, "second conversion")
	r.check(not tc.can_convert_vp_to_ap() and not tc.convert_vp_to_ap() and p0.victory_points == 1 and p0.action_points == 5, "max 2 per turn")
	tc.end_turn()
	tc.end_turn()
	r.check(tc.vp_converted_this_turn == 0 and tc.can_convert_vp_to_ap(), "limit resets on the next own turn")


static func _test_second_player_bonus(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var bonus: int = state.config.second_player_first_turn_bonus_ap
	r.check(bonus == 1 and state.players[0].action_points == 3, "first player: base AP")
	tc.end_turn()
	r.check(state.players[1].action_points == 3 + bonus, "second player: +1 AP on its first turn")
	tc.end_turn()
	tc.end_turn()
	r.check(state.current_player_index == 1 and state.players[1].action_points == 3, "bonus only on the first turn")


static func _test_tile_ticks(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var e := _spawn_ready(state, _unit("E", 2, 1, 3), 1, _g(5, 2))
	var f := _spawn_ready(state, _unit("F", 2, 1, 3), 0, _g(5, 6))
	_place(state, TileEffectType.LAVA, _g(5, 2))
	_place(state, TileEffectType.LAVA, _g(5, 6))
	tc.end_turn() # turn 2 (P1) starts
	r.check(e.current_hp == 2, "lava damages at the start of the occupant owner's turn")
	r.check(f.current_hp == 3, "lava does not tick for the other player's pieces")
	r.check(_has(tc.last_turn_start_events, ResolutionEventType.TILE_DAMAGE, e.id) and _has(tc.last_turn_start_events, ResolutionEventType.DAMAGED, e.id),
		"TileDamage + Damaged in LastTurnStartEvents")
	tc.end_turn() # turn 3 (P0)
	r.check(f.current_hp == 2, "lava ticks for player 0 on its turn")
	var ev: Array[ResolutionEvent] = tc.end_turn() # end of turn 3: lava (created turn 1, duration 2) expires
	r.check(state.board.get_tile_effect(_g(5, 2)) == null and _has(ev, ResolutionEventType.TILE_EFFECT_EXPIRED), "lava expires at the end of turn created + duration")
	r.check(e.current_hp == 2, "no tick after expiry")

	f.current_hp = 1
	_place(state, TileEffectType.HEALING, f.position)
	tc.end_turn() # turn 5 (P0)
	r.check(f.current_hp == 2 and _has(tc.last_turn_start_events, ResolutionEventType.TILE_HEAL, f.id), "healing tile heals 1 at owner's turn start")

	var weak := _spawn_ready(state, _unit("Weak", 2, 1, 1), 1, _g(7, 1))
	_place(state, TileEffectType.LAVA, _g(7, 1))
	var deck_before: int = state.players[1].deck.size()
	tc.end_turn() # turn 6 (P1)
	r.check(not weak.is_alive and _has(tc.last_turn_start_events, ResolutionEventType.DIED, weak.id)
		and state.players[1].deck.size() == deck_before + 1, "lava can kill (card returns to deck)")


static func _test_walls(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var a := _spawn_ready(state, _unit("A", 2), 0, _g(4, 6))
	r.check(OrderResolver.apply_tile_effect(state, TileEffectType.WALL, _g(4, 5), 2, 0, "Test", -1, null), "wall placed")
	var targets: Array[Vector2i] = tc.get_valid_move_targets(a)
	r.check(not targets.has(_g(4, 5)) and not targets.has(_g(4, 4)), "wall is impassable and unoccupiable")
	r.check(not OrderResolver.apply_tile_effect(state, TileEffectType.WALL, a.position, 2, 0, "Test", -1, null), "no wall on an occupied tile")
	_place(state, TileEffectType.WALL, _g(2, 6))
	var unit := _unit("Deploy")
	state.players[0].hand.append(unit)
	r.check(not tc.can_play_unit_card(unit, _g(2, 6)) and tc.last_error.contains("wall"), "cannot deploy on a wall")

	var x := _spawn_ready(state, _unit("X"), 0, _g(7, 7))
	_spawn_ready(state, _unit("T", 2, 1, 3, 2), 0, _g(7, 6))
	var en := _spawn_ready(state, _unit("En"), 1, _g(9, 6))
	_place(state, TileEffectType.WALL, _g(8, 6))
	tc.set_order(x, null, _g(7, 6))
	tc.end_turn() # end turn 1
	r.check(en.current_hp == 3, "wall stops a sideways chain shot")
	r.check(state.board.is_wall(_g(4, 5)), "wall active during the opponent's turn")
	tc.end_turn() # end turn 2
	r.check(state.board.is_wall(_g(4, 5)), "wall active during the creator's next turn")
	var ev: Array[ResolutionEvent] = tc.end_turn() # end turn 3
	r.check(not state.board.is_wall(_g(4, 5)) and _has(ev, ResolutionEventType.TILE_EFFECT_EXPIRED), "wall expired (TileEffectExpired)")
	r.check(tc.get_valid_move_targets(state.get_piece(a.id)).size() >= 0 and state.board.is_passable(_g(4, 5)), "tile passable again")


static func _test_tile_spells(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var p0: PlayerState = state.players[0]
	var meteor := CardData.new()
	meteor.name = "Meteor"
	meteor.card_type = CardType.SPELL
	meteor.ap_cost = 2
	meteor.spell_target = SpellTargetType.AREA
	meteor.area_shape = AreaShape.PLUS
	meteor.tile_effect = TileEffectType.LAVA
	meteor.tile_effect_duration = 2
	meteor.spell_damage = 1
	p0.hand.append(meteor)
	var e1 := _spawn_ready(state, _unit("E1", 2, 1, 3), 1, _g(5, 3))
	var e2 := _spawn_ready(state, _unit("E2", 2, 1, 1), 1, _g(5, 2))
	var f := _spawn_ready(state, _unit("F", 2, 1, 3), 0, _g(4, 3))
	r.check(tc.get_spell_area_preview(meteor, _g(5, 3)).size() == 5 and tc.get_spell_area_preview(meteor, _g(0, 0)).size() == 3, "area preview (plus, clipped)")
	r.check(tc.can_play_spell_card(meteor, e1) and tc.can_cast_spell_at(meteor, _g(5, 3)), "tile spell castable (also via piece redirect)")
	r.check(tc.play_spell_on_tile(meteor, _g(5, 3)) and p0.action_points == 1 and not p0.hand.has(meteor), "PlaySpellOnTile pays AP")
	r.check(e1.current_hp == 2 and not e2.is_alive and f.current_hp == 3, "area damage hits enemies only")
	var all_lava: bool = true
	for p: Vector2i in tc.get_spell_area_preview(meteor, _g(5, 3)):
		all_lava = all_lava and state.board.get_tile_effect_type(p) == TileEffectType.LAVA
	r.check(all_lava, "lava on every area tile")
	r.check(tc.last_spell_events.size() > 0 and tc.last_spell_events[0].type == ResolutionEventType.SPELL_CAST
		and _has(tc.last_spell_events, ResolutionEventType.DIED, e2.id) and _count(tc.last_spell_events, ResolutionEventType.TILE_EFFECT_APPLIED) == 5,
		"LastSpellEvents: SpellCast, Died, 5x TileEffectApplied")

	var buff := _spell("Buff", 1)
	p0.hand.append(buff)
	r.check(not tc.can_play_spell_on_tile(buff, _g(5, 5)), "piece spell cannot target a tile")
	var wall := CardData.new()
	wall.name = "Stone Wall"
	wall.card_type = CardType.SPELL
	wall.ap_cost = 1
	wall.spell_target = SpellTargetType.AREA
	wall.area_shape = AreaShape.ROW3
	wall.tile_effect = TileEffectType.WALL
	wall.tile_effect_duration = 2
	p0.hand.append(wall)
	r.check(tc.play_spell_on_tile(wall, _g(4, 4)) and state.board.is_wall(_g(3, 4)) and state.board.is_wall(_g(4, 4)) and state.board.is_wall(_g(5, 4))
		and p0.action_points == 0, "stone wall: 3 wall tiles in a row")


static func _test_burning(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var fa := _spawn_ready(state, _unit("FA", 1, 1, 2, 3, 0, 0, Keyword.BURNING), 0, _g(2, 5))
	var e := _spawn_ready(state, _unit("E", 2, 1, 5), 1, _g(2, 3))
	tc.set_order(fa, null, _g(2, 3))
	var ev: Array[ResolutionEvent] = tc.end_turn()
	r.check(_has(ev, ResolutionEventType.TILE_EFFECT_APPLIED) and state.board.get_tile_effect_type(_g(2, 3)) == TileEffectType.LAVA, "Burning hit leaves lava")
	r.check(e.current_hp == 3, "1 attack damage + 1 lava tick at the victim's turn start")


static func _test_frost(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var m := _spawn_ready(state, _unit("M", 2, 1, 3, 2, 0, 0, Keyword.FROST), 0, _g(2, 5))
	var e := _spawn_ready(state, _unit("E", 2, 1, 5), 1, _g(4, 5))
	tc.set_order(m, null, _g(4, 5))
	tc.end_turn() # P1's turn
	r.check(e.is_frozen and e.has_status(StatusEffectType.FROZEN) and e.effective_movement == 0, "Frost: target is Frozen")
	r.check(not tc.can_set_order(e, _g(4, 4), null) and tc.get_valid_move_targets(e).size() == 0, "Frozen piece cannot move")
	r.check(tc.can_set_order(e, null, _g(3, 5)), "Frozen piece can still attack")
	var ev: Array[ResolutionEvent] = tc.end_turn()
	r.check(not e.is_frozen and e.effective_movement == 2 and _has(ev, ResolutionEventType.STATUS_EXPIRED, e.id), "Frozen expires after the victim's turn")


static func _test_push_keyword(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var ram := _spawn_ready(state, _unit("Ram", 1, 2, 4, 1, 0, 0, Keyword.PUSH), 0, _g(2, 5))
	var e := _spawn_ready(state, _unit("E", 2, 1, 5), 1, _g(3, 5))
	tc.set_order(ram, null, _g(3, 5))
	var ev: Array[ResolutionEvent] = tc.end_turn()
	r.check(e.position == _g(4, 5) and e.current_hp == 3 and _has(ev, ResolutionEventType.PUSHED, e.id), "Push knocks the target 1 tile away")

	tc = _new_game()
	state = tc.state
	ram = _spawn_ready(state, _unit("Ram", 1, 2, 4, 1, 0, 0, Keyword.PUSH), 0, _g(2, 5))
	e = _spawn_ready(state, _unit("E", 2, 1, 5), 1, _g(3, 5))
	_place(state, TileEffectType.WALL, _g(4, 5))
	tc.set_order(ram, null, _g(3, 5))
	ev = tc.end_turn()
	r.check(e.position == _g(3, 5) and _has(ev, ResolutionEventType.PUSH_BLOCKED, e.id), "Push into a wall is blocked")


static func _test_pierce(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var l := _spawn_ready(state, _unit("L", 2, 2, 3, 1, 0, 0, Keyword.PIERCE), 0, _g(2, 5))
	var e1 := _spawn_ready(state, _unit("E1", 2, 1, 5), 1, _g(3, 5))
	var e2 := _spawn_ready(state, _unit("E2", 2, 1, 5), 1, _g(4, 5))
	tc.set_order(l, null, _g(3, 5))
	var ev: Array[ResolutionEvent] = tc.end_turn()
	r.check(e1.current_hp == 3 and e2.current_hp == 3 and ev.any(func(x: ResolutionEvent) -> bool: return x.type == ResolutionEventType.ATTACKED and x.is_pierce),
		"Pierce also hits the piece behind")

	tc = _new_game()
	state = tc.state
	l = _spawn_ready(state, _unit("L", 2, 2, 3, 1, 0, 0, Keyword.PIERCE), 0, _g(2, 5))
	e1 = _spawn_ready(state, _unit("E1", 2, 1, 5), 1, _g(3, 5))
	var f := _spawn_ready(state, _unit("F"), 0, _g(4, 5))
	var e3 := _spawn_ready(state, _unit("E3", 2, 1, 5), 1, _g(5, 5))
	tc.set_order(l, null, _g(3, 5))
	ev = tc.end_turn()
	r.check(_has(ev, ResolutionEventType.CHAIN_TRIGGERED, f.id) and e1.current_hp == 2 and e3.current_hp == 4, "Pierce chain-triggers a friendly behind")


static func _test_mending(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var c := _spawn_ready(state, _unit("C", 2, 1, 3, 2, 0, 0, Keyword.MENDING), 0, _g(2, 6))
	var f := _spawn_ready(state, _unit("F", 2, 1, 3), 0, _g(3, 6))
	f.current_hp = 1
	var e := _spawn_ready(state, _unit("E", 2, 1, 5), 1, _g(4, 6))
	tc.set_order(c, null, _g(3, 6))
	var ev: Array[ResolutionEvent] = tc.end_turn()
	r.check(f.current_hp == 2 and _has(ev, ResolutionEventType.HEALED, f.id), "Mending heals the friendly")
	r.check(_has(ev, ResolutionEventType.CHAIN_TRIGGERED, f.id) and e.current_hp == 4, "and still triggers its chain")


static func _test_conduit(r: Report) -> void:
	for conduit: bool in [true, false]:
		var tc := _new_game()
		var state: GameState = tc.state
		var a := _spawn_ready(state, _unit("A"), 0, _g(2, 6))
		_spawn_ready(state, _unit("T", 2, 1, 3, 2, 0, 0, Keyword.CONDUIT if conduit else Keyword.NONE), 0, _g(3, 6))
		var e := _spawn_ready(state, _unit("E", 2, 1, 5), 1, _g(3, 4))
		tc.set_order(a, null, _g(3, 6))
		tc.end_turn()
		r.check(e.current_hp == (4 if conduit else 5), "Conduit fires forward too" if conduit else "without Conduit only sideways")


static func _test_echo_overcharge(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var a := _spawn_ready(state, _unit("A"), 0, _g(2, 6))
	_spawn_ready(state, _unit("B", 2, 1, 3, 2, 0, 0, Keyword.ECHO), 0, _g(3, 6))
	var e := _spawn_ready(state, _unit("E", 2, 1, 5), 1, _g(4, 6))
	tc.set_order(a, null, _g(3, 6))
	tc.end_turn()
	r.check(e.current_hp == 3, "Echo chain shot deals +1")

	tc = _new_game()
	state = tc.state
	a = _spawn_ready(state, _unit("A"), 0, _g(2, 6))
	var b := _spawn_ready(state, _unit("B"), 0, _g(3, 6))
	e = _spawn_ready(state, _unit("E", 2, 1, 5), 1, _g(4, 6))
	var over := CardData.new()
	over.name = "Overcharge"
	over.card_type = CardType.SPELL
	over.ap_cost = 1
	over.grant_status = StatusEffectType.OVERCHARGED
	state.players[0].hand.append(over)
	r.check(tc.play_spell_card(over, b) and b.has_status(StatusEffectType.OVERCHARGED) and b.active_spells.size() == 0, "Overcharge grants the status")
	tc.set_order(a, null, _g(3, 6))
	var ev: Array[ResolutionEvent] = tc.end_turn()
	r.check(e.current_hp == 3 and not b.has_status(StatusEffectType.OVERCHARGED)
		and ev.any(func(x: ResolutionEvent) -> bool: return x.type == ResolutionEventType.STATUS_EXPIRED and x.is_chain), "Overcharged chain shot deals double and is consumed")


static func _test_chain_preview(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var a := _spawn_ready(state, _unit("A"), 0, _g(2, 6))
	var t := _spawn_ready(state, _unit("T", 2, 1, 3, 2, 0, 0, Keyword.CONDUIT | Keyword.BURNING), 0, _g(3, 6))
	var b := _spawn_ready(state, _unit("B", 2, 1, 3, 2, 0, 0, Keyword.ECHO), 0, _g(5, 6))
	var e1 := _spawn_ready(state, _unit("E1", 2, 1, 3), 1, _g(6, 6))
	var e2 := _spawn_ready(state, _unit("E2", 2, 1, 1), 1, _g(3, 4))

	var p: ChainPreview = tc.predict_attack(a, a.position, _g(3, 6))
	r.check(p.is_valid and p.triggered_piece_ids.has(t.id) and p.triggered_piece_ids.has(b.id), "preview: both friendlies triggered")
	r.check(p.killed_piece_ids.has(e2.id) and p.enemy_kills == 1 and p.new_tile_effects.size() == 1, "preview: kill + burning lava")
	var hit_e1: PredictedHit = null
	for h: PredictedHit in p.hits:
		if h.target_piece_id == e1.id:
			hit_e1 = h
			break
	r.check(hit_e1 != null and hit_e1.damage == 2 and hit_e1.is_chain and not hit_e1.is_friendly, "preview: Echo hit on E1 for 2")
	r.check(e1.current_hp == 3 and e2.is_alive and state.board.tile_effects.size() == 0 and state.players[1].deck.size() == 0
		and t.position == _g(3, 6), "preview does not mutate the real state")
	r.check(not tc.predict_attack(a, a.position, _g(5, 6)).is_valid, "out-of-range preview is invalid")

	tc.set_order(a, null, _g(3, 6))
	var ev: Array[ResolutionEvent] = tc.end_turn()
	var same: bool = ev.size() >= p.events.size()
	var i: int = 0
	while same and i < p.events.size():
		var x: ResolutionEvent = p.events[i]
		var y: ResolutionEvent = ev[i]
		same = x.type == y.type and x.piece_id == y.piece_id and x.other_piece_id == y.other_piece_id and x.from == y.from and x.to == y.to \
			and x.amount == y.amount and x.hp_lost == y.hp_lost and x.is_chain == y.is_chain and x.is_pierce == y.is_pierce
		i += 1
	r.check(same and p.events.size() > 5, "preview events == actual resolution events")
	r.check(e1.current_hp == 1 and not e2.is_alive, "actual result matches the preview")

	tc = _new_game()
	state = tc.state
	a = _spawn_ready(state, _unit("A", 2), 0, _g(2, 7))
	_spawn_ready(state, _unit("F"), 0, _g(2, 6))
	var en := _spawn_ready(state, _unit("En", 2, 1, 3), 1, _g(2, 4))
	var moved: ChainPreview = tc.predict_attack(a, _g(2, 5), _g(2, 4))
	r.check(moved.is_valid and moved.enemy_hp_lost == 1 and en.current_hp == 3, "preview from a planned position through a friendly")


static func _test_starter_deck(r: Report) -> void:
	var deck := load("res://Resources/Decks/StarterDeck.tres") as DeckData
	r.check(deck != null and deck.cards != null and deck.cards.size() == 20, "StarterDeck.tres loads with 20 cards")
	if deck == null:
		return
	var keyword_cards: int = 0
	var tile_spells: int = 0
	var all_valid: bool = true
	var cards: Array[CardData] = []
	for c: CardData in deck.cards:
		all_valid = all_valid and c != null and not c.name.is_empty()
		if c == null:
			continue
		cards.append(c)
		keyword_cards += 1 if c.keywords != Keyword.NONE else 0
		tile_spells += 1 if c.targets_tile else 0
	r.check(all_valid and keyword_cards >= 8 and tile_spells >= 3, "deck has keyword units (%d) and tile spells (%d)" % [keyword_cards, tile_spells])
	var state := GameState.new(GameConfig.new(), cards, cards.duplicate(), _rng(5))
	var tc := TurnController.new(state)
	tc.start_game()
	r.check(state.players[0].hand.size() == 3 and state.players[0].deck.size() == 17, "game starts with the deck")
