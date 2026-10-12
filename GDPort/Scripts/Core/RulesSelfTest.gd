class_name RulesSelfTest
extends RefCounted
## In-code sanity checks of the core rules (v4: immediate actions, friendly fire, 12x16 board). Call run() and print the report.
## Note: GDScript has no exceptions, so a crashing section stops with a script error instead of "[FAIL] exception".

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
	_run_section(r, "Board layout 12x16 + crown field"); _test_board_layout(r)
	_run_section(r, "Deploy + AP"); _test_deploy_and_ap(r)
	_run_section(r, "Draw costs AP + draft flow"); _test_draw(r)
	_run_section(r, "Actions resolve immediately, once per turn"); _test_actions(r)
	_run_section(r, "Summoning sickness"); _test_summoning_sickness(r)
	_run_section(r, "VP scoring + win"); _test_scoring(r)
	_run_section(r, "Shield before HP"); _test_shield(r)
	_run_section(r, "Friendly fire, no chains"); _test_friendly_fire(r)
	_run_section(r, "Spell expiry"); _test_spell_expiry(r)
	_run_section(r, "Move pass-through + push"); _test_push(r)
	_run_section(r, "Destroyed pieces are lost / Undying returns"); _test_return_to_deck(r)
	_run_section(r, "Planted units"); _test_planted(r)
	_run_section(r, "AP from cards"); _test_ap_cards(r)
	_run_section(r, "Terrain and map generator"); _test_terrain(r)
	_run_section(r, "Obelisk empowers spells"); _test_obelisk(r)
	_run_section(r, "Traps"); _test_traps(r)
	_run_section(r, "Clan attacks leave ground effects"); _test_attack_ground(r)
	_run_section(r, "Push collisions"); _test_push_collisions(r)
	_run_section(r, "Legendary effects and the endboss"); _test_legends(r)
	_run_section(r, "VP -> AP conversion"); _test_vp_to_ap(r)
	_run_section(r, "Second player bonus AP"); _test_second_player_bonus(r)
	_run_section(r, "Lava / healing ticks"); _test_tile_ticks(r)
	_run_section(r, "Walls block + expire"); _test_walls(r)
	_run_section(r, "Tile spells"); _test_tile_spells(r)
	_run_section(r, "Keyword Burning"); _test_burning(r)
	_run_section(r, "Keyword Frost"); _test_frost(r)
	_run_section(r, "Keyword Push"); _test_push_keyword(r)
	_run_section(r, "Keyword Pierce"); _test_pierce(r)
	_run_section(r, "Keyword Mending"); _test_mending(r)
	_run_section(r, "Keyword Arc"); _test_arc(r)
	_run_section(r, "Keyword Echo + Overcharge"); _test_echo_overcharge(r)
	_run_section(r, "Attack preview == actual"); _test_preview(r)
	_run_section(r, "Deathrattles"); _test_deathrattles(r)
	_run_section(r, "First-hit effects"); _test_first_hit(r)
	_run_section(r, "Buildings + turrets"); _test_buildings(r)
	_run_section(r, "Auras"); _test_auras(r)
	_run_section(r, "Spell cast radius"); _test_spell_range(r)
	_run_section(r, "Push spell"); _test_push_spell(r)
	_run_section(r, "Deck resources"); _test_decks(r)
	_run_section(r, "Town NPCs, vendors, prices"); _test_town(r)
	r.append_line("Result: %d passed, %d failed" % [r.passed, r.failed])
	return r.text


## Writes the section title (the test itself is called right after; no try/catch in GDScript).
static func _run_section(r: Report, title: String) -> void:
	r.append_line(title)


# ------------------------------------------------------------------ helpers

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


static func _empty_deck() -> Array[CardData]:
	var deck: Array[CardData] = []
	return deck


static func _no_events() -> Array[ResolutionEvent]:
	var events: Array[ResolutionEvent] = []
	return events


static func _tiles(list: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for t: Vector2i in list:
		result.append(t)
	return result


## New game with empty decks (nothing to draw) and player 0 in Main phase. The state is tc.state
## (replaces the C# out parameter).
static func _new_game() -> TurnController:
	var state := GameState.new(GameConfig.new(), _empty_deck(), _empty_deck(), _rng(1234))
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


static func _g(x: int, y: int) -> Vector2i:
	return Vector2i(x, y)


static func _has(events: Variant, type: int, piece_id: int = _ANY_PIECE) -> bool:
	if events == null:
		return false
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
	OrderResolver.apply_tile_effect(state, type, pos, duration, 0, "Test", -1, _no_events())


# ------------------------------------------------------------------ tests

static func _test_board_layout(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var b: BoardState = state.board
	r.check(b.width == 12 and b.height == 16, "board is 12x16")
	r.check(b.is_in_deploy_zone(0, _g(5, 15)) and b.is_in_deploy_zone(0, _g(5, 14)) and not b.is_in_deploy_zone(0, _g(5, 13)), "player 0 deploys in rows 14-15")
	r.check(b.is_in_deploy_zone(1, _g(5, 0)) and b.is_in_deploy_zone(1, _g(5, 1)) and not b.is_in_deploy_zone(1, _g(5, 2)), "player 1 deploys in rows 0-1")
	r.check(b.is_in_scoring_zone(_g(2, 4)) and b.is_in_scoring_zone(_g(9, 11)) and b.scoring_zone.size == Vector2i(8, 8), "scoring zone is 8x8")
	r.check(not b.is_in_scoring_zone(_g(1, 7)) and not b.is_in_scoring_zone(_g(10, 7)) and not b.is_in_scoring_zone(_g(5, 3)) and not b.is_in_scoring_zone(_g(5, 12))
		and not b.is_in_scoring_zone(_g(0, 7)) and not b.is_in_scoring_zone(_g(5, 2)) and not b.is_in_scoring_zone(_g(5, 13)), "2-tile neutral border around the zone")
	r.check(b.is_in_hot_zone(_g(5, 7)) and b.is_in_hot_zone(_g(6, 8)) and not b.is_in_hot_zone(_g(4, 7)) and not b.is_in_hot_zone(_g(7, 8)), "2x2 crown field in the centre")
	r.check(b.score_value(_g(5, 7)) == 2 and b.score_value(_g(3, 4)) == 1 and b.score_value(_g(0, 0)) == 0, "crown 2 VP, zone 1 VP, outside 0")
	r.check(state.config.burning_lava_duration == 4, "Burning lava lasts 4 turns")


static func _test_deploy_and_ap(r: Report) -> void:
	var deck := _unit_deck(7)
	var state := GameState.new(GameConfig.new(), deck, deck.duplicate(), _rng(42))
	var tc := TurnController.new(state)
	tc.start_game()
	var p0: PlayerState = state.players[0]
	r.check(p0.hand.size() == 5, "starting hand is 5")
	r.check(state.phase == GamePhase.MAIN and p0.draft_offer.size() == 0, "turn starts in Main phase")
	r.check(p0.action_points == 3, "base AP is 3")

	var c0: CardData = p0.hand[0]
	r.check(tc.play_unit_card(c0, _g(4, 0)) == null, "player 0 cannot deploy in row 0")
	r.check(tc.play_unit_card(c0, _g(4, 13)) == null, "player 0 cannot deploy in the neutral row 13")
	r.check(tc.play_unit_card(c0, _g(4, 15)) != null, "player 0 can deploy in row 15")
	r.check(p0.action_points == 2, "unit costs 1 AP")
	r.check(tc.play_unit_card(p0.hand[0], _g(4, 15)) == null, "cannot deploy on occupied tile")

	var spell := _spell("Buff", 1)
	p0.hand.append(spell)
	r.check(tc.get_card_cost(spell) == 2, "spell costs 2 AP")
	r.check(tc.play_spell_card(spell, state.board.get_piece_at(_g(4, 15))) and p0.action_points == 0, "spell deducts 2 AP")
	r.check(tc.play_unit_card(p0.hand[0], _g(5, 15)) == null, "cannot play without AP")

	tc.end_turn()
	r.check(state.current_player_index == 1 and state.turn_number == 2, "turn passes to player 1")
	r.check(tc.play_unit_card(state.players[1].hand[0], _g(3, 15)) == null, "player 1 cannot deploy in row 15")
	r.check(tc.play_unit_card(state.players[1].hand[0], _g(3, 0)) != null, "player 1 can deploy in row 0")

	state.spawn_piece(_unit("Miner", 2, 1, 3, 1, 0, 1), 0, _g(0, 15))
	tc.end_turn()
	r.check(state.players[0].action_points == 4, "ApBonus adds to base AP")


static func _test_draw(r: Report) -> void:
	var deck := _unit_deck(9)
	var state := GameState.new(GameConfig.new(), deck, deck.duplicate(), _rng(7))
	var tc := TurnController.new(state)
	tc.start_game()
	var p0: PlayerState = state.players[0]

	r.check(p0.deck.size() == 4 and p0.hand.size() == 5, "deck 4 / hand 5 after dealing")
	r.check(not tc.choose_draft_card(0), "cannot choose a draft card without drawing")
	r.check(tc.draw() and p0.action_points == 2, "draw costs 1 AP")
	r.check(state.phase == GamePhase.DRAFT and p0.draft_offer.size() == 3 and p0.deck.size() == 1, "draw offers 3 cards (Draft phase)")
	r.check(not tc.can_draw() and not tc.draw(), "cannot draw again while choosing")
	r.check(tc.play_unit_card(p0.hand[0], _g(4, 15)) == null, "cannot play cards during draft")
	r.check(tc.end_turn().size() == 0 and state.phase == GamePhase.DRAFT and state.current_player_index == 0, "cannot end turn during draft")
	var picked: CardData = p0.draft_offer[1]
	r.check(tc.choose_draft_card(1) and p0.hand.has(picked) and p0.hand.size() == 6, "chosen card goes to hand")
	r.check(p0.draft_offer.size() == 0 and p0.deck.size() == 3 and state.phase == GamePhase.MAIN, "rest returns to deck, back to Main")
	r.check(p0.hand.size() + p0.deck.size() + p0.draft_offer.size() == 9, "card count conserved")

	var empty := _new_game()
	var empty_state: GameState = empty.state
	r.check(not empty.can_draw() and not empty.draw() and empty_state.players[0].action_points == 3, "cannot draw from an empty deck (no AP spent)")


static func _test_actions(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var p0: PlayerState = state.players[0]
	var a := _spawn_ready(state, _unit("A", 4, 1), 0, _g(4, 12))
	var b := _spawn_ready(state, _unit("B", 4), 0, _g(8, 12))
	var en := _spawn_ready(state, _unit("En", 2, 1, 3), 1, _g(4, 9))

	r.check(not tc.can_act(a, null, null) and "Nothing" in tc.last_error, "an action needs a move or an attack")
	var ev: Variant = tc.act(a, _g(4, 10), _g(4, 9))
	r.check(ev != null and p0.action_points == 2, "action costs 1 AP")
	r.check(a.position == _g(4, 10) and en.current_hp == 2, "move and attack resolve immediately")
	r.check(_has(ev, ResolutionEventType.MOVED, a.id) and _has(ev, ResolutionEventType.ATTACKED, a.id) and _has(ev, ResolutionEventType.DAMAGED, en.id),
		"events: Moved, Attacked, Damaged")
	r.check(tc.last_action_events == ev, "LastActionEvents holds the action")
	r.check(a.has_acted(state.turn_number) and not tc.can_command(a) and "Already" in tc.last_error, "a piece acts once per turn")
	r.check(tc.act(a, _g(4, 11), null) == null and a.position == _g(4, 10) and p0.action_points == 2, "second action rejected without changes")

	r.check(not tc.can_act(b, _g(8, 7), null), "move beyond movement rejected")
	r.check(not tc.can_act(b, null, _g(8, 10)), "attack out of range rejected")
	p0.action_points = 0
	r.check(tc.act(b, _g(8, 11), null) == null and b.position == _g(8, 12) and "AP" in tc.last_error, "no action without AP")

	var end_events: Variant = tc.end_turn()
	r.check(not _has(end_events, ResolutionEventType.ATTACKED) and not _has(end_events, ResolutionEventType.MOVED), "end turn resolves no actions")
	r.check(a.position == _g(4, 10) and en.current_hp == 2, "end turn does not replay actions")
	tc.end_turn()
	r.check(tc.can_command(a), "the piece can act again on its owner's next turn")


static func _test_summoning_sickness(r: Report) -> void:
	var deck := _unit_deck(6)
	var state := GameState.new(GameConfig.new(), deck, deck.duplicate(), _rng(3))
	var tc := TurnController.new(state)
	tc.start_game()
	var p0: PlayerState = state.players[0]

	var p: Piece = tc.play_unit_card(p0.hand[0], _g(4, 15))
	r.check(p != null and p.is_summoning_sick(1), "played piece is summoning sick on turn 1")
	r.check(not tc.can_command(p) and "Summoning" in tc.last_error, "CanCommand false while sick")
	r.check(tc.act(p, _g(4, 14), null) == null and p0.action_points == 2, "sick piece cannot act (no AP spent)")
	tc.end_turn()
	tc.end_turn()
	r.check(tc.can_command(p) and tc.act(p, _g(4, 14), null) != null and p.position == _g(4, 14), "acts on its owner's next turn")


static func _test_scoring(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	state.spawn_piece(_unit("Z1"), 0, _g(2, 4))
	state.spawn_piece(_unit("Z2"), 0, _g(9, 11))
	state.spawn_piece(_unit("Out"), 0, _g(1, 10))
	state.spawn_piece(_unit("Crown"), 0, _g(6, 8))
	tc.end_turn()
	tc.end_turn()
	r.check(state.players[0].victory_points == 4, "+1 VP per piece in the zone, +2 on the crown field")
	state.players[0].victory_points = state.config.points_target - 2
	tc.end_turn()
	tc.end_turn()
	r.check(state.phase == GamePhase.GAME_OVER and state.winner == 0, "win at points target")


static func _test_shield(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var p: Piece = state.spawn_piece(_unit("Tank", 2, 1, 3, 1, 2), 1, _g(5, 2))
	var events := _no_events()
	OrderResolver.apply_damage(state, p, 3, -1, events)
	r.check(p.current_shield == 0 and p.current_hp == 2, "3 dmg vs 2 shield/3 hp -> 0 shield, 2 hp")
	OrderResolver.apply_damage(state, p, 5, -1, events)
	r.check(not p.is_alive and state.get_piece(p.id) == null and not state.board.is_occupied(_g(5, 2)), "piece dies and is removed")


static func _test_friendly_fire(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var a := _spawn_ready(state, _unit("A", 2, 2), 0, _g(5, 10))
	var f := _spawn_ready(state, _unit("F", 2, 3, 3, 3), 0, _g(5, 9))
	var en := _spawn_ready(state, _unit("En", 2, 1, 3), 1, _g(4, 9))
	var ev: Variant = tc.act(a, null, _g(5, 9))
	r.check(ev != null and f.current_hp == 1, "hitting a friendly damages it")
	r.check(en.current_hp == 3, "no chain: the friendly does not fire")
	r.check(f.has_acted(state.turn_number) == false and tc.can_command(f), "the hit friendly can still act normally")
	var weak := _spawn_ready(state, _unit("Weak", 2, 1, 1), 0, _g(6, 10))
	var b := _spawn_ready(state, _unit("B", 2, 1), 0, _g(7, 10))
	tc.act(b, null, _g(6, 10))
	r.check(not weak.is_alive and state.players[0].graveyard.has(weak.source), "friendly fire can kill (card is lost)")


static func _test_spell_expiry(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var p: Piece = state.spawn_piece(_unit("Target", 2, 1, 3), 0, _g(4, 15))
	var buff := _spell("Rage", 2, 2, 1)
	state.players[0].hand.append(buff)
	r.check(tc.play_spell_card(buff, p), "cast spell turn 1")
	r.check(p.effective_attack == 3 and p.max_hp == 5 and p.current_hp == 5 and p.total_shield == 1, "modifiers applied")
	tc.end_turn()
	tc.end_turn()
	r.check(p.active_spells.size() == 1, "active during the caster's next turn")
	tc.end_turn()
	r.check(p.active_spells.size() == 0 and p.effective_attack == 1 and p.max_hp == 3, "expired at the end of the caster's next turn")


static func _test_push(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var a := _spawn_ready(state, _unit("A", 4), 0, _g(6, 12))
	var f := _spawn_ready(state, _unit("F"), 0, _g(6, 11))
	r.check(tc.get_valid_move_targets(a).has(_g(6, 9)), "friendlies can be passed")
	r.check(tc.act(a, _g(6, 11), null) != null and a.position == _g(6, 11) and f.position == _g(6, 10), "moving onto a friendly pushes it")
	var e := _spawn_ready(state, _unit("E"), 1, _g(9, 12))
	var c := _spawn_ready(state, _unit("C", 2), 0, _g(10, 12))
	r.check(not tc.get_valid_move_targets(c).has(_g(8, 12)), "enemies block movement")
	r.check(e.is_alive, "enemy untouched")


static func _test_return_to_deck(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var card := _unit("Grimbone", 2, 1, 2, 1, 0, 0, Keyword.UNDYING)
	var k: Piece = state.spawn_piece(card, 0, _g(3, 15))
	var events := _no_events()
	OrderResolver.apply_damage(state, k, 10, -1, events)
	var deck0: Array[CardData] = state.players[0].deck
	var up: CardData = deck0.back() if deck0.size() > 0 else null
	r.check(up != null and up != card and up.level == 1 and up.attack == 2 and up.hp == 3 and up.name == "Grimbone +1",
		"Undying returns an upgraded copy")
	r.check(card.level == 0 and card.attack == 1, "original card resource unchanged")

	var att := _spawn_ready(state, _unit("Att", 2, 3), 0, _g(4, 10))
	var vic := _spawn_ready(state, _unit("Vic", 2, 1, 2), 1, _g(4, 9))
	var ev: Variant = tc.act(att, null, _g(4, 9))
	r.check(not vic.is_alive and not state.players[1].deck.has(vic.source) and state.players[1].graveyard.has(vic.source)
		and not _has(ev, ResolutionEventType.RETURNED_TO_DECK, vic.id),
		"a killed normal unit is lost (graveyard), not returned to the deck")


static func _test_terrain(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var walker := _spawn_ready(state, _unit("Walker", 3), 0, _g(5, 12))
	state.board.set_terrain(_g(5, 11), TerrainType.WATER)
	r.check(state.board.move_cost(_g(5, 11)) == 2, "entering water costs 2 movement")
	var reach: Array[Vector2i] = tc.get_valid_move_targets(walker)
	r.check(reach.has(_g(5, 10)) and not reach.has(_g(5, 9)), "a river slows a straight crossing (3 movement: water + 1 tile)")
	state.board.set_terrain(_g(5, 11), TerrainType.BRIDGE)
	r.check(state.board.move_cost(_g(5, 11)) == 1, "bridges cost normal movement")

	state.board.set_terrain(_g(6, 11), TerrainType.ROCK, 3)
	r.check(state.board.is_wall(_g(6, 11)) and not tc.get_valid_move_targets(walker).has(_g(6, 11)), "rocks block movement")
	var hitter := _spawn_ready(state, _unit("Hitter", 2, 2), 0, _g(6, 12))
	var ev: Variant = tc.act(hitter, null, _g(6, 11))
	r.check(state.board.get_terrain_hp(_g(6, 11)) == 1 and _has(ev, ResolutionEventType.TERRAIN_DAMAGED, -1), "attacks damage rocks")
	state.players[0].action_points = 5
	hitter.acted_turn = -1
	tc.act(hitter, null, _g(6, 11))
	r.check(state.board.get_terrain(_g(6, 11)) == TerrainType.NONE and state.board.is_passable(_g(6, 11)), "a broken rock becomes plain ground")

	# The generator: symmetric, never on deploy rows or the crown, always a way through.
	var all_ok: bool = true
	var themes: Dictionary = {}
	for seed_value: int in range(1, 61):
		var gs := GameState.new(GameConfig.new(), _empty_deck(), _empty_deck(), _rng(seed_value))
		var info: MapGenerator.MapInfo = MapGenerator.generate(gs)
		themes[info.name] = true
		var b: BoardState = gs.board
		for key: Vector2i in b.terrain.keys():
			var mirror := Vector2i(b.width - 1 - key.x, b.height - 1 - key.y)
			all_ok = all_ok and b.get_terrain(mirror) == b.terrain[key] and not b.is_in_deploy_zone(0, key) and not b.is_in_deploy_zone(1, key) and not b.is_in_hot_zone(key)
		for key: Vector2i in b.tile_effects.keys():
			var mirror := Vector2i(b.width - 1 - key.x, b.height - 1 - key.y)
			var effect: TileEffect = b.tile_effects[key]
			all_ok = all_ok and effect.is_permanent and b.get_tile_effect_type(mirror) == effect.type and not b.is_in_hot_zone(key)
		var path: Variant = b.find_path(_g(5, 15), _g(5, 0), 999, 0)
		all_ok = all_ok and path != null and (path as Array).size() > 0
	r.check(all_ok, "generated maps are mirror-symmetric, keep deploy rows / crown free and stay crossable")
	var theme_names := PackedStringArray()
	for t: String in themes.keys():
		theme_names.append(t)
	r.check(themes.size() >= 4, "several map themes appear (%s)" % ", ".join(theme_names))

	# The crown field stays clean: no buildings, no tile effects, map features only as decoration.
	tc = _new_game()
	state = tc.state
	var builder := _spawn_ready(state, _classed("Crowner", UnitClass.ARCHER, Clan.NONE, Keyword.BUILDER), 0, _g(5, 9))
	r.check(not tc.get_valid_build_tiles(builder).has(_g(5, 8)) and tc.get_valid_build_tiles(builder).has(_g(4, 8)),
		"buildings cannot be placed on the crown field")
	r.check(not OrderResolver.apply_tile_effect(state, TileEffectType.LAVA, _g(5, 8), 3, 0, "Test", -1, _no_events())
		and state.board.get_tile_effect_type(_g(5, 8)) == TileEffectType.NONE, "tile effects never land on the crown field")
	var crown_clean: bool = true
	for seed_value: int in range(100, 160):
		var gs := GameState.new(GameConfig.new(), _empty_deck(), _empty_deck(), _rng(seed_value))
		MapGenerator.generate(gs)
		for c: Vector2i in [_g(5, 7), _g(6, 7), _g(5, 8), _g(6, 8)]:
			crown_clean = crown_clean and gs.board.get_terrain(c) == TerrainType.NONE and gs.board.get_tile_effect(c) == null and gs.board.move_cost(c) == 1
	r.check(crown_clean, "rivers and walls only pass the crown field as decoration")


static func _legend(name: String, effect: int, hp: int = 6) -> CardData:
	var c := _unit(name, 2, 1, hp)
	c.legend = effect
	c.rarity = CardRarity.LEGENDARY
	return c


static func _test_legends(r: Report) -> void:
	# Unbreakable: never more than 1 damage per hit.
	var tc := _new_game()
	var state: GameState = tc.state
	var gorran := _spawn_ready(state, _legend("Gorran", LegendEffect.UNBREAKABLE, 8), 0, _g(5, 10))
	OrderResolver.apply_damage(state, gorran, 5, -1, _no_events())
	r.check(gorran.current_hp == 7, "Unbreakable takes at most 1 damage from a hit")

	# Dawnlight, Glacial Grip, Chain Lightning and Wildfire fire at their owner's turn start.
	tc = _new_game()
	state = tc.state
	var _solenne := _spawn_ready(state, _legend("Solenne", LegendEffect.DAWNLIGHT), 0, _g(2, 12))
	var hurt := _spawn_ready(state, _unit("Hurt", 2, 1, 5), 0, _g(3, 12))
	var far := _spawn_ready(state, _unit("Far", 2, 1, 5), 0, _g(9, 12))
	hurt.current_hp = 1
	far.current_hp = 1
	var _hrimgar := _spawn_ready(state, _legend("Hrimgar", LegendEffect.GLACIAL_GRIP), 0, _g(8, 8))
	var chilled := _spawn_ready(state, _unit("Chilled", 2, 1, 5), 1, _g(8, 6))
	var _voltaris := _spawn_ready(state, _legend("Voltaris", LegendEffect.CHAIN_LIGHTNING), 0, _g(2, 5))
	var z1 := _spawn_ready(state, _unit("Z1", 2, 1, 5), 1, _g(2, 3))
	var z2 := _spawn_ready(state, _unit("Z2", 2, 1, 5), 1, _g(3, 4))
	var z3 := _spawn_ready(state, _unit("Z3", 2, 1, 5), 1, _g(1, 2))
	var z4 := _spawn_ready(state, _unit("Z4", 2, 1, 5), 1, _g(4, 1))
	var _ignis := _spawn_ready(state, _legend("Ignis", LegendEffect.WILDFIRE), 0, _g(10, 12))
	var burnt := _spawn_ready(state, _unit("Burnt", 2, 1, 5), 1, _g(10, 2))
	state.board.set_tile_effect(TileEffect.new(TileEffectType.LAVA, _g(10, 2), 0, 1, TileEffect.PERMANENT, "Test"))
	tc.end_turn()
	var burnt_after_own_turn: int = burnt.current_hp
	tc.end_turn()
	r.check(hurt.current_hp == hurt.max_hp and far.current_hp == 1, "Dawnlight heals nearby units to full (not far ones)")
	r.check(chilled.is_frozen, "Glacial Grip freezes enemies within 2 tiles")
	r.check(z1.current_hp == 4 and z2.current_hp == 4 and z3.current_hp == 4 and z4.current_hp == 5, "Chain Lightning strikes the 3 nearest enemies")
	r.check(burnt.current_hp == burnt_after_own_turn - LegendInfo.WILDFIRE_DAMAGE, "Wildfire burns enemies standing on lava")

	# The endboss: locked behind the five clan leaders, rewards one of the five legends.
	var boss: NpcData = load("res://Resources/Npcs/Realmshatter.tres") as NpcData
	var legends_ok: bool = boss != null and boss.reward_one_of.size() == 5
	var clans: Dictionary = {}
	if boss != null:
		for c: CardData in boss.reward_one_of:
			var ok: bool = c != null and c.rarity == CardRarity.LEGENDARY and c.legend != LegendEffect.NONE
			if ok:
				ok = not clans.has(c.clan)
				clans[c.clan] = true
			legends_ok = legends_ok and ok
	r.check(legends_ok and clans.size() == 5, "five Legendary cards, one per clan, each with its own effect")
	r.check(boss != null and boss.requires_defeated.size() == 5 and boss.deck != null and boss.deck.cards.size() == 30, "the endboss needs all five clan leaders and has a 30-card deck")
	r.check(boss != null and CardEconomy.buy_price(boss.reward_one_of[0]) >= 900, "Legendary cards are very expensive in the shop")


static func _test_push_collisions(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	state.players[0].action_points = 20
	# Pushed into another piece: no move, 1 collision damage (on top of the hit).
	var pusher := _spawn_ready(state, _unit("Pusher", 2, 1, 3, 1, 0, 0, Keyword.PUSH), 0, _g(5, 12))
	var target := _spawn_ready(state, _unit("Target", 2, 1, 5), 1, _g(5, 11))
	var wall := _spawn_ready(state, _unit("Behind", 2, 1, 5), 1, _g(5, 10))
	tc.act(pusher, null, _g(5, 11))
	r.check(target.position == _g(5, 11) and target.current_hp == 3 and wall.current_hp == 5,
		"a piece pushed into another piece stays and takes 1 extra damage (the other one is unharmed)")

	# Pushed into a rock: same.
	var pusher2 := _spawn_ready(state, _unit("Pusher2", 2, 1, 3, 1, 0, 0, Keyword.PUSH), 0, _g(8, 12))
	var target2 := _spawn_ready(state, _unit("Target2", 2, 1, 5), 1, _g(8, 11))
	state.board.set_terrain(_g(8, 10), TerrainType.ROCK, 3)
	tc.act(pusher2, null, _g(8, 11))
	r.check(target2.position == _g(8, 11) and target2.current_hp == 3, "a piece pushed into a rock takes 1 extra damage")

	# Pushed against the board edge: only blocked.
	var pusher3 := _spawn_ready(state, _unit("Pusher3", 2, 1, 3, 1, 0, 0, Keyword.PUSH), 0, _g(1, 3))
	var target3 := _spawn_ready(state, _unit("Target3", 2, 1, 5), 1, _g(0, 3))
	tc.act(pusher3, null, _g(0, 3))
	r.check(target3.position == _g(0, 3) and target3.current_hp == 4, "the board edge only blocks a push (no extra damage)")

	# Moving into your own pieces still nudges them aside without damage.
	var mover := _spawn_ready(state, _unit("Mover", 3), 0, _g(10, 12))
	var friend := _spawn_ready(state, _unit("Friend", 2, 1, 3), 0, _g(10, 11))
	tc.act(mover, _g(10, 11), null)
	r.check(mover.position == _g(10, 11) and friend.position == _g(10, 10) and friend.current_hp == 3, "moving onto a friend still pushes it without damage")


static func _test_attack_ground(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	state.players[0].action_points = 20
	var fire := _spawn_ready(state, _unit("Fire", 2, 1, 3, 1, 0, 0, Keyword.BURNING), 0, _g(1, 10))
	var frost := _spawn_ready(state, _unit("Frost", 2, 1, 3, 1, 0, 0, Keyword.FROST), 0, _g(3, 10))
	var arc := _spawn_ready(state, _unit("Arc", 2, 1, 3, 1, 0, 0, Keyword.ARC), 0, _g(8, 10))
	var mend := _spawn_ready(state, _unit("Mend", 2, 1, 3, 1, 0, 0, Keyword.MENDING), 0, _g(10, 10))
	var push := _spawn_ready(state, _unit("Push", 2, 1, 3, 1, 0, 0, Keyword.PUSH), 0, _g(1, 13))
	tc.act(fire, null, _g(1, 9))
	tc.act(frost, null, _g(3, 9))
	tc.act(arc, null, _g(8, 9))
	tc.act(mend, null, _g(10, 9))
	tc.act(push, null, _g(1, 12))
	r.check(state.board.get_tile_effect_type(_g(1, 9)) == TileEffectType.LAVA, "Burning attacks set even an empty tile on fire")
	r.check(state.board.get_tile_effect_type(_g(3, 9)) == TileEffectType.ICE, "Frost attacks leave Ice")
	r.check(state.board.get_tile_effect_type(_g(8, 9)) == TileEffectType.STORM, "Arc attacks leave a Storm cell")
	r.check(state.board.get_tile_effect_type(_g(10, 9)) == TileEffectType.HEALING, "Mending attacks leave a Healing spring")
	r.check(state.board.get_tile_effect_type(_g(1, 12)) == TileEffectType.MUD and state.board.move_cost(_g(1, 12)) == 2, "Push attacks leave Mud (2 movement)")

	# Ice stops any move onto it - for both players.
	var runner := _spawn_ready(state, _unit("Runner", 5), 0, _g(3, 11))
	tc.act(runner, _g(3, 7), null)
	r.check(runner.position == _g(3, 9), "a piece moving onto Ice slides to a halt there")

	# Storm cells crackle at the occupant's turn start: it and its neighbours take 1 damage.
	tc.end_turn()
	var victim := _spawn_ready(state, _unit("Victim", 2, 1, 4), 1, _g(8, 9))
	var beside := _spawn_ready(state, _unit("Beside", 2, 1, 4), 1, _g(8, 8))
	tc.end_turn()
	tc.end_turn()
	r.check(victim.current_hp == 3 and beside.current_hp == 3, "a Storm cell hits its occupant and every piece next to it")

	# Permanent map lava is not replaced by a passing attack.
	state.board.set_tile_effect(TileEffect.new(TileEffectType.LAVA, _g(6, 12), -1, 0, TileEffect.PERMANENT, "Map"))
	r.check(not OrderResolver.apply_tile_effect(state, TileEffectType.ICE, _g(6, 12), 3, 0, "Test", -1, _no_events())
		and state.board.get_tile_effect(_g(6, 12)).is_permanent, "map lava fields are not overwritten")


static func _test_traps(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var scout_card := _classed("Trapper", UnitClass.SCOUT, Clan.NONE, Keyword.TRAPPER)
	var scout := _spawn_ready(state, scout_card, 0, _g(3, 10))
	r.check(tc.get_trap_type(scout) == TrapType.SPIKE, "a basic Trapper sets Spike traps")
	var set_ok: bool = tc.set_trap(scout, _g(3, 9), null) != null
	var trap: Trap = state.board.get_trap(_g(3, 9))
	r.check(set_ok and trap != null and trap.owner_index == 0 and state.players[0].action_points == 2,
		"setting a trap costs 1 AP and uses the action")
	r.check(not tc.can_command(scout), "the Trapper has acted")

	var friend := _spawn_ready(state, _unit("Friend", 4), 0, _g(3, 11))
	tc.act(friend, _g(3, 7), null)
	r.check(friend.position == _g(3, 7) and state.board.get_trap(_g(3, 9)) != null, "own pieces walk over their traps")

	tc.end_turn()
	var enemy := _spawn_ready(state, _unit("Enemy", 5, 1, 5), 1, _g(4, 9))
	var ev: Variant = tc.act(enemy, _g(2, 9), null)
	r.check(enemy.position == _g(3, 9) and enemy.current_hp == 3 and state.board.get_trap(_g(3, 9)) == null and _has(ev, ResolutionEventType.TRAP_TRIGGERED, enemy.id),
		"an enemy stepping on the trap is stopped there, takes 2 damage and the trap is gone")

	# Clan traps.
	tc = _new_game()
	state = tc.state
	var fire_card := _classed("Fire Trapper", UnitClass.SCOUT, Clan.FIRE, Keyword.TRAPPER)
	var fire := _spawn_ready(state, fire_card, 0, _g(8, 10))
	tc.set_trap(fire, _g(8, 9), null)
	var frost_card := _classed("Frost Trapper", UnitClass.SCOUT, Clan.FROST, Keyword.TRAPPER)
	var frost := _spawn_ready(state, frost_card, 0, _g(2, 10))
	tc.set_trap(frost, _g(2, 9), null)
	tc.end_turn()
	var e1 := _spawn_ready(state, _unit("E1", 4, 1, 5), 1, _g(8, 7))
	tc.act(e1, _g(8, 10 - 1), null)
	r.check(e1.current_hp == 4 and state.board.get_tile_effect_type(_g(8, 9)) == TileEffectType.LAVA, "Fire trap: 1 damage and lava")
	var e2 := _spawn_ready(state, _unit("E2", 4, 1, 5), 1, _g(2, 7))
	tc.act(e2, _g(2, 9), null)
	tc.end_turn()
	tc.end_turn()
	r.check(e2.current_hp == 4 and e2.is_frozen, "Frost trap: 1 damage and frozen through its next turn")

	# Limits.
	tc = _new_game()
	state = tc.state
	var busy := _spawn_ready(state, _classed("Busy", UnitClass.SCOUT, Clan.NONE, Keyword.TRAPPER), 0, _g(5, 10))
	state.players[0].action_points = 9
	tc.set_trap(busy, _g(4, 10), null)
	busy.acted_turn = -1
	tc.set_trap(busy, _g(6, 10), null)
	busy.acted_turn = -1
	tc.set_trap(busy, _g(5, 11), null)
	r.check(state.board.get_trap(_g(4, 10)) == null and state.board.get_trap(_g(6, 10)) != null and state.board.get_trap(_g(5, 11)) != null,
		"a Trapper keeps at most 2 traps (the oldest goes)")
	var crown_side := _spawn_ready(state, _classed("Crown", UnitClass.SCOUT, Clan.NONE, Keyword.TRAPPER), 0, _g(5, 9))
	r.check(not tc.get_valid_trap_tiles(crown_side).has(_g(5, 8)), "no traps on the crown field")


static func _test_obelisk(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var _caster := _spawn_ready(state, _unit("Caster"), 0, _g(5, 12))
	var enemy := _spawn_ready(state, _unit("Enemy", 2, 2, 9), 1, _g(5, 10))
	var weaken := _spell("Weaken", -1)
	state.players[0].hand.append(weaken)
	tc.play_spell_card(weaken, enemy)
	r.check(enemy.effective_attack == 1, "without an Obelisk: -1 Attack")

	var obelisk: Piece = state.spawn_building(BuildingType.OBELISK, 0, _g(4, 11), 0, -1)
	obelisk.under_construction = false
	var weaken2 := _spell("Weaken", -1)
	state.players[0].hand.append(weaken2)
	state.players[0].action_points = 5
	tc.play_spell_card(weaken2, enemy)
	r.check(enemy.active_spells.size() == 2 and enemy.active_spells[1].effect.attack_delta == -2, "near an Obelisk the same spell removes 2 Attack")
	r.check(tc.spell_power(_g(5, 10)) == 1 and tc.spell_power(_g(11, 0)) == 0, "the Obelisk only empowers spells aimed within its radius")
	r.check(not tc.is_in_spell_range(_g(4, 6)), "Obelisks no longer extend the cast range")


static func _test_ap_cards(r: Report) -> void:
	# Mana Surge: a spell that gives AP when it resolves.
	var tc := _new_game()
	var state: GameState = tc.state
	var mine := _spawn_ready(state, _unit("Mine"), 0, _g(5, 12))
	var surge := CardData.new()
	surge.name = "Surge"
	surge.card_type = CardType.SPELL
	surge.ap_cost = 1
	surge.ap_gain = 2
	state.players[0].hand.append(surge)
	var before: int = state.players[0].action_points
	r.check(tc.play_spell_card(surge, mine) and state.players[0].action_points == before + 1 and mine.active_spells.size() == 0,
		"an AP spell pays 1 and gives 2 (net +1), no empty spell on its target")

	# Plunder: a kill on your own turn gives 1 AP right away.
	var raider := _spawn_ready(state, _unit("Raider", 2, 3, 3, 1, 0, 0, Keyword.PLUNDER), 0, _g(4, 10))
	var victim := _spawn_ready(state, _unit("Victim", 2, 1, 2), 1, _g(4, 9))
	var ap_before: int = state.players[0].action_points
	var ev: Variant = tc.act(raider, null, _g(4, 9))
	r.check(not victim.is_alive and state.players[0].action_points == ap_before - 1 + 1 and _has(ev, ResolutionEventType.AP_GAINED, raider.id),
		"Plunder: destroying an enemy refunds 1 AP")

	# Tribute: the AP arrives at the start of the owner's next turn.
	tc = _new_game()
	state = tc.state
	var pilgrim := _unit("Pilgrim", 2, 1, 1)
	pilgrim.deathrattle = DeathrattleType.TRIBUTE
	pilgrim.deathrattle_amount = 2
	var p := _spawn_ready(state, pilgrim, 0, _g(5, 10))
	OrderResolver.apply_damage(state, p, 5, -1, _no_events())
	tc.end_turn()
	r.check(state.players[0].pending_ap == 2, "Tribute stores 2 AP for the owner's next turn")
	tc.end_turn()
	r.check(state.players[0].action_points == state.config.base_ap + 2 and state.players[0].pending_ap == 0, "Tribute AP is added at the turn start")


static func _test_planted(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var totem := _unit("Totem", 0, 1, 3, 1, 0, 0, Keyword.PLANTED)
	state.players[0].hand.append(totem)
	state.players[0].action_points = 10
	_spawn_ready(state, _unit("Runner"), 0, _g(3, 8))
	r.check(tc.can_play_unit_card(totem, _g(3, 15)), "Planted units may still use the deploy rows")
	r.check(tc.can_play_unit_card(totem, _g(3, 6)), "Planted units may be placed 2 tiles from an own unit")
	r.check(not tc.can_play_unit_card(totem, _g(3, 5)), "but not 3 tiles away")
	_spawn_ready(state, _unit("Crowner"), 0, _g(4, 7))
	r.check(not tc.can_play_unit_card(totem, _g(5, 7)), "never on the crown field")
	r.check(not tc.can_play_unit_card(_unit("Walker"), _g(3, 6)), "normal units still deploy only in the back rows")

	var planted: Piece = tc.play_unit_card(totem, _g(3, 6))
	r.check(planted != null and planted.has_keyword(Keyword.PLANTED), "Planted unit deployed forward")
	planted.summoned_turn = -1
	r.check(tc.get_valid_move_targets(planted).size() == 0, "a Planted unit cannot move")
	r.check(not planted.can_score, "a Planted unit never scores")
	var vp_before: int = state.players[0].victory_points
	tc.end_turn()
	tc.end_turn()
	# Runner (3, 8) and Crowner (4, 7) score 1 each; the Planted piece in the zone (3, 6) scores nothing.
	r.check(state.players[0].victory_points - vp_before == 2, "only the mobile units scored (%d VP)" % (state.players[0].victory_points - vp_before))


static func _test_vp_to_ap(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var p0: PlayerState = state.players[0]
	r.check(not tc.convert_vp_to_ap(), "cannot convert without VP")
	p0.victory_points = 3
	r.check(tc.convert_vp_to_ap() and p0.victory_points == 2 and p0.action_points == 4, "1 VP -> 1 AP")
	r.check(tc.convert_vp_to_ap() and not tc.convert_vp_to_ap() and p0.action_points == 5, "max 2 per turn")


static func _test_second_player_bonus(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	tc.end_turn()
	r.check(state.players[1].action_points == 3 + state.config.second_player_first_turn_bonus_ap, "second player: bonus AP on its first turn")
	tc.end_turn()
	tc.end_turn()
	r.check(state.players[1].action_points == 3, "bonus only on the first turn")


static func _test_tile_ticks(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var e := _spawn_ready(state, _unit("E", 2, 1, 3), 1, _g(5, 2))
	var f := _spawn_ready(state, _unit("F", 2, 1, 3), 0, _g(5, 15))
	_place(state, TileEffectType.LAVA, _g(5, 2))
	_place(state, TileEffectType.LAVA, _g(5, 15))
	tc.end_turn()
	r.check(e.current_hp == 2 and f.current_hp == 3, "lava damages at the start of the occupant owner's turn")
	tc.end_turn()
	r.check(f.current_hp == 2, "lava ticks for player 0 on its turn")
	var ev: Variant = tc.end_turn()
	r.check(state.board.get_tile_effect(_g(5, 2)) == null and _has(ev, ResolutionEventType.TILE_EFFECT_EXPIRED), "lava expires after its duration")

	f.current_hp = 1
	_place(state, TileEffectType.HEALING, f.position)
	tc.end_turn()
	r.check(f.current_hp == 2 and _has(tc.last_turn_start_events, ResolutionEventType.TILE_HEAL, f.id), "healing tile heals 1 at owner's turn start")


static func _test_walls(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var a := _spawn_ready(state, _unit("A", 2), 0, _g(4, 12))
	r.check(OrderResolver.apply_tile_effect(state, TileEffectType.WALL, _g(4, 11), 2, 0, "Test", -1, _no_events()), "wall placed")
	var targets: Array[Vector2i] = tc.get_valid_move_targets(a)
	r.check(not targets.has(_g(4, 11)) and not targets.has(_g(4, 10)), "wall is impassable")
	r.check(not OrderResolver.apply_tile_effect(state, TileEffectType.WALL, a.position, 2, 0, "Test", -1, _no_events()), "no wall on an occupied tile")
	tc.end_turn()
	tc.end_turn()
	r.check(state.board.is_wall(_g(4, 11)), "wall active during the creator's next turn")
	var ev: Variant = tc.end_turn()
	r.check(not state.board.is_wall(_g(4, 11)) and _has(ev, ResolutionEventType.TILE_EFFECT_EXPIRED), "wall expired")


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
	meteor.tile_effect_duration = 4
	meteor.spell_damage = 1
	p0.hand.append(meteor)
	var e1 := _spawn_ready(state, _unit("E1", 2, 1, 3), 1, _g(5, 8))
	var e2 := _spawn_ready(state, _unit("E2", 2, 1, 1), 1, _g(5, 7))
	var f := _spawn_ready(state, _unit("F", 2, 1, 3), 0, _g(4, 8))
	r.check(tc.get_spell_area_preview(meteor, _g(5, 8)).size() == 5 and tc.get_spell_area_preview(meteor, _g(0, 0)).size() == 3, "area preview (plus, clipped)")
	r.check(tc.play_spell_on_tile(meteor, _g(5, 8)) and p0.action_points == 1, "PlaySpellOnTile pays AP")
	r.check(e1.current_hp == 2 and not e2.is_alive and f.current_hp == 3, "area damage hits enemies only")
	# (5, 8) is a crown tile and stays clean; the rest of the cross turns to lava.
	var lava: TileEffect = state.board.get_tile_effect(_g(4, 8))
	r.check(lava != null and lava.expiry_turn == state.turn_number + 4 and state.board.get_tile_effect(_g(5, 8)) == null,
		"lava lasts the card's duration (never on the crown field)")


static func _test_burning(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var a := _spawn_ready(state, _unit("Burner", 2, 1, 3, 1, 0, 0, Keyword.BURNING), 0, _g(5, 10))
	var en := _spawn_ready(state, _unit("En", 2, 1, 3), 1, _g(5, 9))
	tc.act(a, null, _g(5, 9))
	r.check(en.current_hp == 2 and state.board.get_tile_effect_type(_g(5, 9)) == TileEffectType.LAVA, "Burning hit leaves lava")
	r.check(state.board.get_tile_effect(_g(5, 9)).expiry_turn == state.turn_number + state.config.burning_lava_duration, "lava duration = BurningLavaDuration")


static func _test_frost(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var a := _spawn_ready(state, _unit("Frost", 2, 1, 3, 1, 0, 0, Keyword.FROST), 0, _g(5, 10))
	var en := _spawn_ready(state, _unit("En", 2, 1, 3), 1, _g(5, 9))
	tc.act(a, null, _g(5, 9))
	r.check(en.is_frozen and en.effective_movement == 0, "Frost freezes the target")
	tc.end_turn()
	r.check(en.is_frozen and not tc.can_act(en, _g(5, 8), null), "frozen enemy cannot move on its turn")
	tc.end_turn()
	r.check(not en.is_frozen, "frost thaws after the victim's turn")


static func _test_push_keyword(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var a := _spawn_ready(state, _unit("Ram", 2, 1, 3, 1, 0, 0, Keyword.PUSH), 0, _g(5, 10))
	var en := _spawn_ready(state, _unit("En", 2, 1, 3), 1, _g(5, 9))
	tc.act(a, null, _g(5, 9))
	r.check(en.position == _g(5, 8) and en.current_hp == 2, "Push knocks the target back 1 tile")


static func _test_pierce(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var a := _spawn_ready(state, _unit("Lancer", 2, 2, 3, 1, 0, 0, Keyword.PIERCE), 0, _g(5, 10))
	var e1 := _spawn_ready(state, _unit("E1", 2, 1, 3), 1, _g(5, 9))
	var f := _spawn_ready(state, _unit("F", 2, 1, 3), 0, _g(5, 8))
	tc.act(a, null, _g(5, 9))
	r.check(e1.current_hp == 1 and f.current_hp == 1, "Pierce hits the piece behind too - even a friendly")


static func _test_mending(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var a := _spawn_ready(state, _unit("Cleric", 2, 1, 3, 1, 0, 0, Keyword.MENDING), 0, _g(5, 10))
	var f := _spawn_ready(state, _unit("F", 2, 1, 3), 0, _g(5, 9))
	f.current_hp = 1
	var ev: Variant = tc.act(a, null, _g(5, 9))
	r.check(f.current_hp == 2 and _has(ev, ResolutionEventType.HEALED, f.id) and not _has(ev, ResolutionEventType.DAMAGED), "Mending heals a friendly instead of damaging it")


static func _test_arc(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var a := _spawn_ready(state, _unit("Arc", 2, 2, 3, 2, 0, 0, Keyword.ARC), 0, _g(5, 12))
	var target := _spawn_ready(state, _unit("T", 2, 1, 4), 1, _g(5, 10))
	var side := _spawn_ready(state, _unit("S", 2, 1, 3), 1, _g(6, 10))
	var own := _spawn_ready(state, _unit("O", 2, 1, 3), 0, _g(4, 10))
	var far := _spawn_ready(state, _unit("Far", 2, 1, 3), 1, _g(7, 10))
	tc.act(a, null, _g(5, 10))
	r.check(target.current_hp == 2, "Arc: main target takes full damage")
	r.check(side.current_hp == 2 and own.current_hp == 2, "Arc zaps every adjacent piece for 1 - friend or foe")
	r.check(far.current_hp == 3, "Arc does not jump further")


static func _test_echo_overcharge(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var a := _spawn_ready(state, _unit("Echo", 2, 1, 3, 1, 0, 0, Keyword.ECHO), 0, _g(5, 10))
	var en := _spawn_ready(state, _unit("En", 2, 1, 4), 1, _g(5, 9))
	tc.act(a, null, _g(5, 9))
	r.check(en.current_hp == 2, "Echo strikes twice (1 + 1)")

	var b := _spawn_ready(state, _unit("B", 2, 2), 0, _g(8, 10))
	var en2 := _spawn_ready(state, _unit("En2", 2, 1, 6), 1, _g(8, 9))
	OrderResolver.apply_status(state, b, StatusEffectType.OVERCHARGED, 2, "Test", -1, _no_events())
	var ev: Variant = tc.act(b, null, _g(8, 9))
	r.check(en2.current_hp == 2 and not b.has_status(StatusEffectType.OVERCHARGED), "Overcharged doubles the next attack and is consumed")
	var consumed: bool = false
	for e: ResolutionEvent in ev:
		if e.type == ResolutionEventType.STATUS_EXPIRED and e.is_secondary:
			consumed = true
	r.check(consumed, "consumption event emitted")


static func _test_preview(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var a := _spawn_ready(state, _unit("Lancer", 2, 2, 3, 1, 0, 0, Keyword.PIERCE | Keyword.ARC), 0, _g(5, 10))
	_spawn_ready(state, _unit("E1", 2, 1, 2), 1, _g(5, 9))
	_spawn_ready(state, _unit("F", 2, 1, 3), 0, _g(5, 8))
	_spawn_ready(state, _unit("E2", 2, 1, 3), 1, _g(6, 9))
	var p: ChainPreview = tc.predict_attack(a, a.position, _g(5, 9))
	var enemy_hp_before: int = 0
	var friendly_hp_before: int = 0
	for piece: Piece in state.pieces:
		if piece.owner_index == 1:
			enemy_hp_before += piece.current_hp
		elif piece != a:
			friendly_hp_before += piece.current_hp
	tc.act(a, null, _g(5, 9))
	var enemy_hp_after: int = 0
	var friendly_hp_after: int = 0
	for piece: Piece in state.pieces:
		if piece.owner_index == 1:
			enemy_hp_after += piece.current_hp
		elif piece != a:
			friendly_hp_after += piece.current_hp
	r.check(p.is_valid and p.enemy_hp_lost == enemy_hp_before - enemy_hp_after, "preview enemy damage matches the action")
	r.check(p.friendly_hp_lost == friendly_hp_before - friendly_hp_after and p.friendly_hp_lost > 0, "preview friendly fire matches the action")
	r.check(p.enemy_kills == 1, "preview kill count")


static func _trigger(name: String, dr: int = DeathrattleType.NONE, dr_amount: int = 1,
		fh: int = FirstHitType.NONE, fh_amount: int = 1, hp: int = 3, atk: int = 1) -> CardData:
	var c := _unit(name, 2, atk, hp)
	c.deathrattle = dr
	c.deathrattle_amount = dr_amount
	c.on_first_hit = fh
	c.on_first_hit_amount = fh_amount
	return c


static func _test_deathrattles(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var keg := _spawn_ready(state, _trigger("Keg", DeathrattleType.EXPLODE, 2, FirstHitType.NONE, 1, 1), 1, _g(5, 8))
	var e := _spawn_ready(state, _unit("E", 2, 1, 4), 1, _g(5, 7))
	var own := _spawn_ready(state, _unit("Own", 2, 1, 4), 0, _g(6, 8))
	var a := _spawn_ready(state, _unit("A", 2, 1, 3, 2), 0, _g(5, 10))
	var ev: Variant = tc.act(a, null, _g(5, 8))
	r.check(not keg.is_alive and _has(ev, ResolutionEventType.DEATHRATTLE, keg.id), "deathrattle triggers on death")
	r.check(e.current_hp == 2 and own.current_hp == 2 and a.current_hp == 3, "Explode hits every adjacent piece - friend or foe")

	tc = _new_game()
	state = tc.state
	var shock := _spawn_ready(state, _trigger("Shock", DeathrattleType.SHOCKWAVE, 1, FirstHitType.NONE, 1, 1), 1, _g(5, 8))
	var n1 := _spawn_ready(state, _unit("N1"), 1, _g(5, 7))
	var n2 := _spawn_ready(state, _unit("N2"), 0, _g(4, 8))
	OrderResolver.apply_damage(state, shock, 5, -1, _no_events())
	r.check(n1.position == _g(5, 6) and n2.position == _g(3, 8), "Shockwave pushes neighbours away")

	var lava := _spawn_ready(state, _trigger("Lava", DeathrattleType.LAVA_POOL, 1, FirstHitType.NONE, 1, 1), 1, _g(8, 8))
	OrderResolver.apply_damage(state, lava, 5, -1, _no_events())
	r.check(state.board.get_tile_effect_type(_g(8, 8)) == TileEffectType.LAVA and state.board.get_tile_effect_type(_g(9, 8)) == TileEffectType.LAVA,
		"Lava Pool covers its tile and the neighbours")

	var healer := _spawn_ready(state, _trigger("Healer", DeathrattleType.HEAL_ALLIES, 2, FirstHitType.NONE, 1, 1), 0, _g(2, 12))
	var hurt := _spawn_ready(state, _unit("Hurt", 2, 1, 4), 0, _g(3, 13))
	hurt.current_hp = 1
	OrderResolver.apply_damage(state, healer, 5, -1, _no_events())
	r.check(hurt.current_hp == 3, "Last Blessing heals allies within 2 tiles")

	var rubble := _spawn_ready(state, _trigger("Rubble", DeathrattleType.RAISE_WALLS, 1, FirstHitType.NONE, 1, 1), 0, _g(9, 13))
	OrderResolver.apply_damage(state, rubble, 5, -1, _no_events())
	r.check(state.board.is_wall(_g(9, 12)) and state.board.is_wall(_g(10, 13)), "Rubble raises walls next to it")

	state.players[0].deck.append(_unit("Spare"))
	var hand: int = state.players[0].hand.size()
	var word := _spawn_ready(state, _trigger("Word", DeathrattleType.DRAW_CARD, 1, FirstHitType.NONE, 1, 1), 0, _g(0, 14))
	OrderResolver.apply_damage(state, word, 5, -1, _no_events())
	r.check(state.players[0].hand.size() == hand + 1, "Last Word draws a card")

	var nova := _spawn_ready(state, _trigger("Nova", DeathrattleType.FROST_NOVA, 1, FirstHitType.NONE, 1, 1), 0, _g(10, 6))
	var victim := _spawn_ready(state, _unit("Victim"), 1, _g(10, 5))
	OrderResolver.apply_damage(state, nova, 5, -1, _no_events())
	r.check(victim.is_frozen, "Frost Nova freezes adjacent enemies")


static func _test_first_hit(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var thorny := _spawn_ready(state, _trigger("Thorny", DeathrattleType.NONE, 1, FirstHitType.THORNS, 2, 5), 1, _g(5, 9))
	var a := _spawn_ready(state, _unit("A", 2, 1, 3), 0, _g(5, 10))
	tc.act(a, null, _g(5, 9))
	r.check(a.current_hp == 1 and thorny.was_hit, "Thorns hurts the attacker on the first hit")
	var b := _spawn_ready(state, _unit("B", 2, 1, 3), 0, _g(4, 9))
	tc.act(b, null, _g(5, 9))
	r.check(b.current_hp == 3, "first-hit effects trigger only once")

	var _repel := _spawn_ready(state, _trigger("Repel", DeathrattleType.NONE, 1, FirstHitType.REPEL, 1, 5), 1, _g(8, 9))
	var c := _spawn_ready(state, _unit("C", 2, 1), 0, _g(8, 10))
	tc.act(c, null, _g(8, 9))
	r.check(c.position == _g(8, 11), "Repel pushes the attacker away")

	var hard := _spawn_ready(state, _trigger("Hard", DeathrattleType.NONE, 1, FirstHitType.HARDEN, 2, 5), 1, _g(2, 9))
	OrderResolver.apply_damage(state, hard, 1, -1, _no_events())
	r.check(hard.current_hp == 4 and hard.total_shield == 2, "Harden grants shield after the first hit")

	var rage := _spawn_ready(state, _trigger("Rage", DeathrattleType.NONE, 1, FirstHitType.ENRAGE, 2, 5, 1), 1, _g(2, 5))
	OrderResolver.apply_damage(state, rage, 1, -1, _no_events())
	r.check(rage.effective_attack == 3, "Enrage adds permanent attack")
	var prober := _spawn_ready(state, _unit("P", 2, 1, 2), 0, _g(9, 10))
	var preview: ChainPreview = tc.predict_attack(prober, prober.position, _g(9, 9))
	r.check(not preview.is_valid or preview.friendly_hp_lost == 0, "preview runs with triggers")


static func _classed(name: String, cls: int, clan: int = Clan.NONE, kw: int = Keyword.NONE, mov: int = 4, hp: int = 3) -> CardData:
	var c := _unit(name, mov, 1, hp, 1, 0, 0, kw)
	c.class_ = cls
	c.clan = clan
	return c


static func _test_buildings(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var archer := _spawn_ready(state, _classed("Arch", UnitClass.ARCHER, Clan.NONE, Keyword.BUILDER), 0, _g(5, 12))
	r.check(tc.get_build_type(archer) == BuildingType.TURRET, "Archers build Turrets")
	var ev: Variant = tc.build(archer, _tiles([_g(5, 11)]), null)
	var turret: Piece = state.board.get_piece_at(_g(5, 11))
	r.check(ev != null and turret != null and turret.is_building and turret.under_construction and state.players[0].action_points == 1,
		"building started (2 AP), unfinished")
	r.check(archer.constructing_id == turret.id and not tc.can_act(archer, _g(4, 12), null), "the builder cannot move while building")
	r.check(not tc.can_command(turret), "buildings cannot be commanded")
	tc.end_turn()
	tc.end_turn()
	r.check(turret.under_construction, "still unfinished after one own turn")
	tc.end_turn()
	tc.end_turn()
	r.check(not turret.under_construction and archer.constructing_id == -1 and _has(tc.last_turn_start_events, ResolutionEventType.BUILDING_COMPLETED, turret.id),
		"finished at the start of the second own turn, builder freed")
	r.check(state.players[0].victory_points == 0, "buildings do not score")

	# A unit busy building does not score either, until its building is finished.
	var tz := _new_game()
	var zs: GameState = tz.state
	var zone_builder := _spawn_ready(zs, _classed("ZoneBuilder", UnitClass.ARCHER, Clan.NONE, Keyword.BUILDER), 0, _g(4, 6))
	var zone_runner := _spawn_ready(zs, _unit("Runner"), 0, _g(7, 6))
	tz.build(zone_builder, _tiles([_g(4, 5)]), null)
	tz.end_turn()
	tz.end_turn()
	r.check(zs.players[0].victory_points == 1 and not zone_builder.can_score and zone_runner.can_score,
		"a builder busy building in the zone scores no VP (the runner next to it does)")
	tz.end_turn()
	tz.end_turn()
	r.check(zone_builder.constructing_id < 0 and zs.players[0].victory_points == 3, "once the building is finished it scores again")

	tc.end_turn()
	var e1 := _spawn_ready(state, _unit("E1", 4, 1, 3), 1, _g(5, 5))
	var e2 := _spawn_ready(state, _unit("E2", 4, 1, 3), 1, _g(6, 5))
	tc.act(e1, _g(5, 8), null)
	r.check(e1.current_hp == 2, "the turret shoots an enemy that moves into range")
	tc.act(e2, _g(6, 8), null)
	r.check(e2.current_hp == 3, "the turret fires only once per turn")

	tc = _new_game()
	state = tc.state
	var sword := _spawn_ready(state, _classed("Sword", UnitClass.SWORDSMAN, Clan.NONE, Keyword.BUILDER), 0, _g(3, 12))
	tc.build(sword, _tiles([_g(3, 11)]), null)
	var barricade: Piece = state.board.get_piece_at(_g(3, 11))
	r.check(barricade != null and barricade.building == BuildingType.BARRICADE, "Swordsmen build Barricades")
	OrderResolver.apply_damage(state, sword, 99, -1, _no_events())
	r.check(state.get_piece(barricade.id) == null and state.board.get_tile_effect_type(_g(3, 11)) == TileEffectType.RUBBLE and state.board.is_wall(_g(3, 11)),
		"the builder's death destroys the unfinished building, leaving impassable rubble")

	tc = _new_game()
	state = tc.state
	var worker := _spawn_ready(state, _classed("Worker", UnitClass.WORKER, Clan.NONE, Keyword.BUILDER), 0, _g(8, 14))
	tc.build(worker, _tiles([_g(8, 13)]), null)
	for _i: int in range(4):
		tc.end_turn()
	r.check(state.players[0].action_points == 4, "a finished Mana Well gives +1 AP")

	# Move, then build (the build replaces the attack).
	tc = _new_game()
	state = tc.state
	var mover := _spawn_ready(state, _classed("Mover", UnitClass.ARCHER, Clan.NONE, Keyword.BUILDER), 0, _g(5, 14))
	var move_build: Variant = tc.build(mover, _tiles([_g(5, 11)]), _g(5, 12))
	var placed: Piece = state.board.get_piece_at(_g(5, 11))
	r.check(move_build != null and mover.position == _g(5, 12) and placed != null and placed.building == BuildingType.TURRET
		and _has(move_build, ResolutionEventType.MOVED, mover.id) and state.players[0].action_points == 1,
		"a Builder can move and then build (pays only the building's AP)")
	r.check(not tc.can_command(mover), "moving + building uses the unit's action")

	# One Barricade build places two Barricades; the builder's death collapses both.
	tc = _new_game()
	state = tc.state
	var pair := _spawn_ready(state, _classed("Pair", UnitClass.SWORDSMAN, Clan.NONE, Keyword.BUILDER), 0, _g(6, 12))
	r.check(not tc.can_build(pair, _tiles([_g(5, 11), _g(6, 11), _g(7, 11)]), null), "at most two Barricades per build")
	var two: Variant = tc.build(pair, _tiles([_g(5, 11), _g(7, 11)]), null)
	var b1: Piece = state.board.get_piece_at(_g(5, 11))
	var b2: Piece = state.board.get_piece_at(_g(7, 11))
	r.check(two != null and b1 != null and b1.building == BuildingType.BARRICADE and b2 != null and b2.building == BuildingType.BARRICADE, "a Barricade build places two")
	OrderResolver.apply_damage(state, pair, 99, -1, _no_events())
	r.check(state.get_piece(b1.id) == null and state.get_piece(b2.id) == null, "the builder's death collapses both unfinished Barricades")


static func _test_auras(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	_spawn_ready(state, _classed("Heat", UnitClass.MAGE, Clan.FIRE, Keyword.AURA), 0, _g(5, 8))
	var enemy := _spawn_ready(state, _unit("E", 2, 1, 3), 1, _g(6, 9))
	var far := _spawn_ready(state, _unit("F", 2, 1, 3), 1, _g(8, 9))
	tc.end_turn()
	tc.end_turn()
	r.check(enemy.current_hp == 2 and far.current_hp == 3 and _has(tc.last_turn_start_events, ResolutionEventType.AURA_PULSE),
		"Fire aura burns diagonal neighbours at its turn start")

	tc = _new_game()
	state = tc.state
	_spawn_ready(state, _classed("Static", UnitClass.MAGE, Clan.STORM, Keyword.AURA), 0, _g(5, 8))
	var ally := _spawn_ready(state, _unit("A", 2, 1), 0, _g(5, 9))
	tc.end_turn()
	tc.end_turn()
	r.check(ally.effective_attack == 2, "Storm aura: +1 Attack this turn")
	tc.end_turn()
	r.check(ally.effective_attack == 1, "the bonus expires at the end of the turn")


static func _test_spell_range(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var bolt := CardData.new()
	bolt.name = "Bolt"
	bolt.card_type = CardType.SPELL
	bolt.ap_cost = 1
	bolt.spell_target = SpellTargetType.TILE
	bolt.spell_damage = 1
	state.players[0].hand.append(bolt)
	_spawn_ready(state, _unit("Own"), 0, _g(5, 12))
	_spawn_ready(state, _unit("Far"), 1, _g(5, 2))
	_spawn_ready(state, _unit("Near"), 1, _g(5, 8))
	r.check(not tc.can_play_spell_on_tile(bolt, _g(5, 2)) and "Too far" in tc.last_error, "no spells beyond 4 tiles of your units")
	r.check(tc.can_play_spell_on_tile(bolt, _g(5, 8)), "spells within 4 tiles are fine")


static func _test_push_spell(r: Report) -> void:
	var tc := _new_game()
	var state: GameState = tc.state
	var gale := CardData.new()
	gale.name = "Gale"
	gale.card_type = CardType.SPELL
	gale.ap_cost = 1
	gale.spell_target = SpellTargetType.AREA
	gale.area_shape = AreaShape.PLUS
	gale.spell_push = true
	state.players[0].hand.append(gale)
	var up := _spawn_ready(state, _unit("Up"), 1, _g(5, 7))
	var mid := _spawn_ready(state, _unit("Mid"), 1, _g(5, 8))
	var right := _spawn_ready(state, _unit("Right"), 0, _g(6, 8))
	r.check(tc.play_spell_on_tile(gale, _g(5, 8)), "push spell castable")
	r.check(up.position == _g(5, 6) and right.position == _g(7, 8), "pieces around the centre are pushed outward")
	r.check(mid.position == _g(5, 7), "the centre piece is pushed away from the caster")


static func _test_town(r: Report) -> void:
	var npcs: Array[String] = ["FireApprentice", "HealingApprentice", "FrostApprentice", "StormApprentice", "StoneApprentice",
		"Sellsword", "HedgeWitch"]
	for clan: String in ["Fire", "Healing", "Frost", "Storm", "Stone"]:
		for tier: String in ["Initiate", "Adept", "Champion", "Leader"]:
			npcs.append(clan + tier)
	var ids: Dictionary = {}
	var by_id: Dictionary = {}
	var all_ok: bool = true
	var legal: bool = true
	var epic_rewards: int = 0
	for n: String in npcs:
		var npc: NpcData = load("res://Resources/Npcs/%s.tres" % n) as NpcData
		var ok: bool = npc != null and npc.deck != null and npc.deck.cards.size() == 30 and npc.reward_gold > 0
		if ok:
			ok = not ids.has(npc.id)
			ids[npc.id] = true
		ok = ok and npc.reward_cards.size() > 0
		if ok:
			by_id[npc.id] = npc
			for c: CardData in npc.reward_cards:
				epic_rewards += 1 if c.rarity == CardRarity.EPIC else 0
			var copies: Dictionary = {}
			for c: CardData in npc.deck.cards:
				copies[c] = int(copies.get(c, 0)) + 1
				legal = legal and c != null and int(copies[c]) <= (1 if c.rarity == CardRarity.LEGENDARY else 3)
		all_ok = all_ok and ok
	r.check(all_ok, "%d NPCs load with a 30-card deck, unique id and rewards" % npcs.size())
	r.check(legal, "NPC decks keep the copy limits (3, Legendary 1)")
	r.check(epic_rewards == 5, "every clan leader rewards an Epic card")
	var halls: bool = true
	for clan: String in ["Fire", "Healing", "Frost", "Storm", "Stone"]:
		var leader: NpcData = load("res://Resources/Npcs/%sLeader.tres" % clan) as NpcData
		halls = halls and leader != null and leader.house == leader.clan and leader.requires_defeated.size() == 3 and leader.bonus_ap_per_turn > 0
		var required: Array[String] = []
		if leader != null:
			required = leader.requires_defeated
		for id: String in required:
			var member: NpcData = by_id.get(id, null)
			halls = halls and member != null and member.house == leader.house and member.requires_defeated.size() == 0
	r.check(halls, "each clan leader waits in its hall behind its three duelists")
	var boss: NpcData = load("res://Resources/Npcs/Realmshatter.tres") as NpcData
	r.check(boss != null and boss.house == Clan.NONE and boss.requires_defeated.size() == 5 and boss.reward_one_of.size() == 5,
		"the endboss waits in town for the five clan leaders and gives a Legendary")
	var stock: int = 0
	for v: String in ["MarketStall", "ArcaneEmporium", "WanderingTrader"]:
		var vendor: VendorData = load("res://Resources/Vendors/%s.tres" % v) as VendorData
		stock += vendor.stock.size() if vendor != null else 0
	r.check(stock >= 30, "vendors offer %d cards" % stock)
	var common: CardData = load("res://Resources/Cards/Swordsman.tres") as CardData
	var epic: CardData = load("res://Resources/Cards/Phoenix.tres") as CardData
	r.check(CardEconomy.buy_price(epic) > CardEconomy.buy_price(common) and CardEconomy.sell_price(common) < CardEconomy.buy_price(common),
		"epic costs more than common, selling pays less than buying")


static func _test_decks(r: Report) -> void:
	for name: String in ["StarterDeck", "EmberLegion", "DawnCovenant", "Frostbound", "StormCircuit", "StoneBastion"]:
		var deck: DeckData = load("res://Resources/Decks/%s.tres" % name) as DeckData
		var ok: bool = deck != null and deck.cards != null and deck.cards.size() == 30
		if ok:
			for c: CardData in deck.cards:
				ok = ok and c != null and not c.name.is_empty()
		r.check(ok, "%s.tres loads with 30 valid cards" % name)
		if ok and name != "StarterDeck":
			var classed: bool = true
			for c: CardData in deck.cards:
				classed = classed and (c.card_type != CardType.UNIT or c.class_ != UnitClass.NONE)
			r.check(classed, "%s: every unit has a class" % name)
