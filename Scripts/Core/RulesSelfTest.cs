using System;
using System.Collections.Generic;
using System.Text;

namespace Realmshatter;

/// <summary>In-code sanity checks of the core rules (v4: immediate actions, friendly fire, 12x16 board). Call Run() and print the report.</summary>
public static class RulesSelfTest
{
	private sealed class Report
	{
		public readonly StringBuilder Text = new StringBuilder();
		public int Passed;
		public int Failed;

		public void Check(bool condition, string name)
		{
			if (condition)
			{
				Passed++;
				Text.AppendLine($"  [PASS] {name}");
			}
			else
			{
				Failed++;
				Text.AppendLine($"  [FAIL] {name}");
			}
		}
	}

	/// <summary>Runs all checks and returns a human-readable report.</summary>
	public static string Run()
	{
		var r = new Report();
		r.Text.AppendLine("RulesSelfTest");
		RunSection(r, "Board layout 12x16 + crown field", TestBoardLayout);
		RunSection(r, "Deploy + AP", TestDeployAndAp);
		RunSection(r, "Draw costs AP + draft flow", TestDraw);
		RunSection(r, "Actions resolve immediately, once per turn", TestActions);
		RunSection(r, "Summoning sickness", TestSummoningSickness);
		RunSection(r, "VP scoring + win", TestScoring);
		RunSection(r, "Shield before HP", TestShield);
		RunSection(r, "Friendly fire, no chains", TestFriendlyFire);
		RunSection(r, "Spell expiry", TestSpellExpiry);
		RunSection(r, "Move pass-through + push", TestPush);
		RunSection(r, "Destroyed pieces are lost / Undying returns", TestReturnToDeck);
		RunSection(r, "Planted units", TestPlanted);
		RunSection(r, "AP from cards", TestApCards);
		RunSection(r, "Terrain and map generator", TestTerrain);
		RunSection(r, "Obelisk empowers spells", TestObelisk);
		RunSection(r, "Traps", TestTraps);
		RunSection(r, "Clan attacks leave ground effects", TestAttackGround);
		RunSection(r, "Push collisions", TestPushCollisions);
		RunSection(r, "Legendary effects and the endboss", TestLegends);
		RunSection(r, "VP -> AP conversion", TestVpToAp);
		RunSection(r, "Second player bonus AP", TestSecondPlayerBonus);
		RunSection(r, "Lava / healing ticks", TestTileTicks);
		RunSection(r, "Walls block + expire", TestWalls);
		RunSection(r, "Tile spells", TestTileSpells);
		RunSection(r, "Keyword Burning", TestBurning);
		RunSection(r, "Keyword Frost", TestFrost);
		RunSection(r, "Keyword Push", TestPushKeyword);
		RunSection(r, "Keyword Pierce", TestPierce);
		RunSection(r, "Keyword Mending", TestMending);
		RunSection(r, "Keyword Arc", TestArc);
		RunSection(r, "Keyword Echo + Overcharge", TestEchoOvercharge);
		RunSection(r, "Attack preview == actual", TestPreview);
		RunSection(r, "Deathrattles", TestDeathrattles);
		RunSection(r, "First-hit effects", TestFirstHit);
		RunSection(r, "Buildings + turrets", TestBuildings);
		RunSection(r, "Auras", TestAuras);
		RunSection(r, "Spell cast radius", TestSpellRange);
		RunSection(r, "Push spell", TestPushSpell);
		RunSection(r, "Deck resources", TestDecks);
		RunSection(r, "Town NPCs, vendors, prices", TestTown);
		r.Text.AppendLine($"Result: {r.Passed} passed, {r.Failed} failed");
		return r.Text.ToString();
	}

	private static void RunSection(Report r, string title, Action<Report> test)
	{
		r.Text.AppendLine(title);
		try
		{
			test(r);
		}
		catch (Exception e)
		{
			r.Failed++;
			r.Text.AppendLine($"  [FAIL] exception: {e.Message}");
		}
	}

	// ------------------------------------------------------------------ helpers

	private static CardData Unit(string name, int mov = 2, int atk = 1, int hp = 3, int rng = 1, int shd = 0, int apBonus = 0, Keyword kw = Keyword.None) =>
		new CardData { Name = name, CardType = CardType.Unit, Movement = mov, Attack = atk, Hp = hp, Range = rng, Shield = shd, ApBonus = apBonus, Keywords = kw };

	private static CardData Spell(string name, int atk = 0, int hp = 0, int shd = 0) =>
		new CardData { Name = name, CardType = CardType.Spell, AttackDelta = atk, HpDelta = hp, ShieldDelta = shd };

	/// <summary>New game with empty decks (nothing to draw) and player 0 in Main phase.</summary>
	private static TurnController NewGame(out GameState state)
	{
		state = new GameState(new GameConfig(), new List<CardData>(), new List<CardData>(), new Random(1234));
		var tc = new TurnController(state);
		tc.StartGame();
		return tc;
	}

	/// <summary>Spawns a piece that is already commandable (as if summoned before the game started).</summary>
	private static Piece SpawnReady(GameState state, CardData card, int owner, GridPos pos)
	{
		Piece p = state.SpawnPiece(card, owner, pos);
		if (p != null)
		{
			p.SummonedTurn = 0;
		}
		return p;
	}

	private static List<CardData> UnitDeck(int count)
	{
		var deck = new List<CardData>();
		for (int i = 0; i < count; i++)
		{
			deck.Add(Unit($"U{i}"));
		}
		return deck;
	}

	private static GridPos G(int x, int y) => new GridPos(x, y);

	private static bool Has(IReadOnlyList<ResolutionEvent> events, ResolutionEventType type, int pieceId = int.MinValue)
	{
		if (events == null)
		{
			return false;
		}
		foreach (ResolutionEvent e in events)
		{
			if (e.Type == type && (pieceId == int.MinValue || e.PieceId == pieceId))
			{
				return true;
			}
		}
		return false;
	}

	private static int Count(IReadOnlyList<ResolutionEvent> events, ResolutionEventType type)
	{
		int n = 0;
		foreach (ResolutionEvent e in events)
		{
			if (e.Type == type)
			{
				n++;
			}
		}
		return n;
	}

	private static void Place(GameState state, TileEffectType type, GridPos pos, int duration = 2) =>
		OrderResolver.ApplyTileEffect(state, type, pos, duration, 0, "Test", -1, null);

	// ------------------------------------------------------------------ tests

	private static void TestBoardLayout(Report r)
	{
		NewGame(out GameState state);
		BoardState b = state.Board;
		r.Check(b.Width == 12 && b.Height == 16, "board is 12x16");
		r.Check(b.IsInDeployZone(0, G(5, 15)) && b.IsInDeployZone(0, G(5, 14)) && !b.IsInDeployZone(0, G(5, 13)), "player 0 deploys in rows 14-15");
		r.Check(b.IsInDeployZone(1, G(5, 0)) && b.IsInDeployZone(1, G(5, 1)) && !b.IsInDeployZone(1, G(5, 2)), "player 1 deploys in rows 0-1");
		r.Check(b.IsInScoringZone(G(2, 4)) && b.IsInScoringZone(G(9, 11)) && b.ScoringZone.Size == new Godot.Vector2I(8, 8), "scoring zone is 8x8");
		r.Check(!b.IsInScoringZone(G(1, 7)) && !b.IsInScoringZone(G(10, 7)) && !b.IsInScoringZone(G(5, 3)) && !b.IsInScoringZone(G(5, 12))
			&& !b.IsInScoringZone(G(0, 7)) && !b.IsInScoringZone(G(5, 2)) && !b.IsInScoringZone(G(5, 13)), "2-tile neutral border around the zone");
		r.Check(b.IsInHotZone(G(5, 7)) && b.IsInHotZone(G(6, 8)) && !b.IsInHotZone(G(4, 7)) && !b.IsInHotZone(G(7, 8)), "2x2 crown field in the centre");
		r.Check(b.ScoreValue(G(5, 7)) == 2 && b.ScoreValue(G(3, 4)) == 1 && b.ScoreValue(G(0, 0)) == 0, "crown 2 VP, zone 1 VP, outside 0");
		r.Check(state.Config.BurningLavaDuration == 4, "Burning lava lasts 4 turns");
	}

	private static void TestDeployAndAp(Report r)
	{
		var deck = UnitDeck(7);
		var state = new GameState(new GameConfig(), deck, new List<CardData>(deck), new Random(42));
		var tc = new TurnController(state);
		tc.StartGame();
		PlayerState p0 = state.Players[0];
		r.Check(p0.Hand.Count == 5, "starting hand is 5");
		r.Check(state.Phase == GamePhase.Main && p0.DraftOffer.Count == 0, "turn starts in Main phase");
		r.Check(p0.ActionPoints == 3, "base AP is 3");

		CardData c0 = p0.Hand[0];
		r.Check(tc.PlayUnitCard(c0, G(4, 0)) == null, "player 0 cannot deploy in row 0");
		r.Check(tc.PlayUnitCard(c0, G(4, 13)) == null, "player 0 cannot deploy in the neutral row 13");
		r.Check(tc.PlayUnitCard(c0, G(4, 15)) != null, "player 0 can deploy in row 15");
		r.Check(p0.ActionPoints == 2, "unit costs 1 AP");
		r.Check(tc.PlayUnitCard(p0.Hand[0], G(4, 15)) == null, "cannot deploy on occupied tile");

		CardData spell = Spell("Buff", atk: 1);
		p0.Hand.Add(spell);
		r.Check(tc.GetCardCost(spell) == 2, "spell costs 2 AP");
		r.Check(tc.PlaySpellCard(spell, state.Board.GetPieceAt(G(4, 15))) && p0.ActionPoints == 0, "spell deducts 2 AP");
		r.Check(tc.PlayUnitCard(p0.Hand[0], G(5, 15)) == null, "cannot play without AP");

		tc.EndTurn();
		r.Check(state.CurrentPlayerIndex == 1 && state.TurnNumber == 2, "turn passes to player 1");
		r.Check(tc.PlayUnitCard(state.Players[1].Hand[0], G(3, 15)) == null, "player 1 cannot deploy in row 15");
		r.Check(tc.PlayUnitCard(state.Players[1].Hand[0], G(3, 0)) != null, "player 1 can deploy in row 0");

		state.SpawnPiece(Unit("Miner", apBonus: 1), 0, G(0, 15));
		tc.EndTurn();
		r.Check(state.Players[0].ActionPoints == 4, "ApBonus adds to base AP");
	}

	private static void TestDraw(Report r)
	{
		var deck = UnitDeck(9);
		var state = new GameState(new GameConfig(), deck, new List<CardData>(deck), new Random(7));
		var tc = new TurnController(state);
		tc.StartGame();
		PlayerState p0 = state.Players[0];
		int Total() => p0.Hand.Count + p0.Deck.Count + p0.DraftOffer.Count;

		r.Check(p0.Deck.Count == 4 && p0.Hand.Count == 5, "deck 4 / hand 5 after dealing");
		r.Check(!tc.ChooseDraftCard(0), "cannot choose a draft card without drawing");
		r.Check(tc.Draw() && p0.ActionPoints == 2, "draw costs 1 AP");
		r.Check(state.Phase == GamePhase.Draft && p0.DraftOffer.Count == 3 && p0.Deck.Count == 1, "draw offers 3 cards (Draft phase)");
		r.Check(!tc.CanDraw() && !tc.Draw(), "cannot draw again while choosing");
		r.Check(tc.PlayUnitCard(p0.Hand[0], G(4, 15)) == null, "cannot play cards during draft");
		r.Check(tc.EndTurn().Count == 0 && state.Phase == GamePhase.Draft && state.CurrentPlayerIndex == 0, "cannot end turn during draft");
		CardData picked = p0.DraftOffer[1];
		r.Check(tc.ChooseDraftCard(1) && p0.Hand.Contains(picked) && p0.Hand.Count == 6, "chosen card goes to hand");
		r.Check(p0.DraftOffer.Count == 0 && p0.Deck.Count == 3 && state.Phase == GamePhase.Main, "rest returns to deck, back to Main");
		r.Check(Total() == 9, "card count conserved");

		TurnController empty = NewGame(out GameState emptyState);
		r.Check(!empty.CanDraw() && !empty.Draw() && emptyState.Players[0].ActionPoints == 3, "cannot draw from an empty deck (no AP spent)");
	}

	private static void TestActions(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		PlayerState p0 = state.Players[0];
		Piece a = SpawnReady(state, Unit("A", mov: 4, atk: 1), 0, G(4, 12));
		Piece b = SpawnReady(state, Unit("B", mov: 4), 0, G(8, 12));
		Piece en = SpawnReady(state, Unit("En", hp: 3), 1, G(4, 9));

		r.Check(!tc.CanAct(a, null, null) && tc.LastError.Contains("Nothing"), "an action needs a move or an attack");
		List<ResolutionEvent> ev = tc.Act(a, G(4, 10), G(4, 9));
		r.Check(ev != null && p0.ActionPoints == 2, "action costs 1 AP");
		r.Check(a.Position == G(4, 10) && en.CurrentHp == 2, "move and attack resolve immediately");
		r.Check(Has(ev, ResolutionEventType.Moved, a.Id) && Has(ev, ResolutionEventType.Attacked, a.Id) && Has(ev, ResolutionEventType.Damaged, en.Id),
			"events: Moved, Attacked, Damaged");
		r.Check(tc.LastActionEvents == ev, "LastActionEvents holds the action");
		r.Check(a.HasActed(state.TurnNumber) && !tc.CanCommand(a) && tc.LastError.Contains("Already"), "a piece acts once per turn");
		r.Check(tc.Act(a, G(4, 11), null) == null && a.Position == G(4, 10) && p0.ActionPoints == 2, "second action rejected without changes");

		r.Check(!tc.CanAct(b, G(8, 7), null), "move beyond movement rejected");
		r.Check(!tc.CanAct(b, null, G(8, 10)), "attack out of range rejected");
		p0.ActionPoints = 0;
		r.Check(tc.Act(b, G(8, 11), null) == null && b.Position == G(8, 12) && tc.LastError.Contains("AP"), "no action without AP");

		List<ResolutionEvent> endEvents = tc.EndTurn();
		r.Check(!Has(endEvents, ResolutionEventType.Attacked) && !Has(endEvents, ResolutionEventType.Moved), "end turn resolves no actions");
		r.Check(a.Position == G(4, 10) && en.CurrentHp == 2, "end turn does not replay actions");
		tc.EndTurn();
		r.Check(tc.CanCommand(a), "the piece can act again on its owner's next turn");
	}

	private static void TestSummoningSickness(Report r)
	{
		var deck = UnitDeck(6);
		var state = new GameState(new GameConfig(), deck, new List<CardData>(deck), new Random(3));
		var tc = new TurnController(state);
		tc.StartGame();
		PlayerState p0 = state.Players[0];

		Piece p = tc.PlayUnitCard(p0.Hand[0], G(4, 15));
		r.Check(p != null && p.IsSummoningSick(1), "played piece is summoning sick on turn 1");
		r.Check(!tc.CanCommand(p) && tc.LastError.Contains("Summoning"), "CanCommand false while sick");
		r.Check(tc.Act(p, G(4, 14), null) == null && p0.ActionPoints == 2, "sick piece cannot act (no AP spent)");
		tc.EndTurn();
		tc.EndTurn();
		r.Check(tc.CanCommand(p) && tc.Act(p, G(4, 14), null) != null && p.Position == G(4, 14), "acts on its owner's next turn");
	}

	private static void TestScoring(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		state.SpawnPiece(Unit("Z1"), 0, G(2, 4));
		state.SpawnPiece(Unit("Z2"), 0, G(9, 11));
		state.SpawnPiece(Unit("Out"), 0, G(1, 10));
		state.SpawnPiece(Unit("Crown"), 0, G(6, 8));
		tc.EndTurn();
		tc.EndTurn();
		r.Check(state.Players[0].VictoryPoints == 4, "+1 VP per piece in the zone, +2 on the crown field");
		state.Players[0].VictoryPoints = state.Config.PointsTarget - 2;
		tc.EndTurn();
		tc.EndTurn();
		r.Check(state.Phase == GamePhase.GameOver && state.Winner == 0, "win at points target");
	}

	private static void TestShield(Report r)
	{
		NewGame(out GameState state);
		Piece p = state.SpawnPiece(Unit("Tank", hp: 3, shd: 2), 1, G(5, 2));
		var events = new List<ResolutionEvent>();
		OrderResolver.ApplyDamage(state, p, 3, -1, events);
		r.Check(p.CurrentShield == 0 && p.CurrentHp == 2, "3 dmg vs 2 shield/3 hp -> 0 shield, 2 hp");
		OrderResolver.ApplyDamage(state, p, 5, -1, events);
		r.Check(!p.IsAlive && state.GetPiece(p.Id) == null && !state.Board.IsOccupied(G(5, 2)), "piece dies and is removed");
	}

	private static void TestFriendlyFire(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece a = SpawnReady(state, Unit("A", atk: 2), 0, G(5, 10));
		Piece f = SpawnReady(state, Unit("F", atk: 3, hp: 3, rng: 3), 0, G(5, 9));
		Piece en = SpawnReady(state, Unit("En", hp: 3), 1, G(4, 9));
		List<ResolutionEvent> ev = tc.Act(a, null, G(5, 9));
		r.Check(ev != null && f.CurrentHp == 1, "hitting a friendly damages it");
		r.Check(en.CurrentHp == 3, "no chain: the friendly does not fire");
		r.Check(f.HasActed(state.TurnNumber) == false && tc.CanCommand(f), "the hit friendly can still act normally");
		Piece weak = SpawnReady(state, Unit("Weak", hp: 1), 0, G(6, 10));
		Piece b = SpawnReady(state, Unit("B", atk: 1), 0, G(7, 10));
		tc.Act(b, null, G(6, 10));
		r.Check(!weak.IsAlive && state.Players[0].Graveyard.Contains(weak.Source), "friendly fire can kill (card is lost)");
	}

	private static void TestSpellExpiry(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece p = state.SpawnPiece(Unit("Target", atk: 1, hp: 3), 0, G(4, 15));
		CardData buff = Spell("Rage", atk: 2, hp: 2, shd: 1);
		state.Players[0].Hand.Add(buff);
		r.Check(tc.PlaySpellCard(buff, p), "cast spell turn 1");
		r.Check(p.EffectiveAttack == 3 && p.MaxHp == 5 && p.CurrentHp == 5 && p.TotalShield == 1, "modifiers applied");
		tc.EndTurn();
		tc.EndTurn();
		r.Check(p.ActiveSpells.Count == 1, "active during the caster's next turn");
		tc.EndTurn();
		r.Check(p.ActiveSpells.Count == 0 && p.EffectiveAttack == 1 && p.MaxHp == 3, "expired at the end of the caster's next turn");
	}

	private static void TestPush(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece a = SpawnReady(state, Unit("A", mov: 4), 0, G(6, 12));
		Piece f = SpawnReady(state, Unit("F"), 0, G(6, 11));
		r.Check(tc.GetValidMoveTargets(a).Contains(G(6, 9)), "friendlies can be passed");
		r.Check(tc.Act(a, G(6, 11), null) != null && a.Position == G(6, 11) && f.Position == G(6, 10), "moving onto a friendly pushes it");
		Piece e = SpawnReady(state, Unit("E"), 1, G(9, 12));
		Piece c = SpawnReady(state, Unit("C", mov: 2), 0, G(10, 12));
		r.Check(!tc.GetValidMoveTargets(c).Contains(G(8, 12)), "enemies block movement");
		r.Check(e.IsAlive, "enemy untouched");
	}

	private static void TestReturnToDeck(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		CardData card = Unit("Grimbone", atk: 1, hp: 2, kw: Keyword.Undying);
		Piece k = state.SpawnPiece(card, 0, G(3, 15));
		var events = new List<ResolutionEvent>();
		OrderResolver.ApplyDamage(state, k, 10, -1, events);
		List<CardData> deck0 = state.Players[0].Deck;
		CardData up = deck0.Count > 0 ? deck0[^1] : null;
		r.Check(up != null && up != card && up.Level == 1 && up.Attack == 2 && up.Hp == 3 && up.Name == "Grimbone +1",
			"Undying returns an upgraded copy");
		r.Check(card.Level == 0 && card.Attack == 1, "original card resource unchanged");

		Piece att = SpawnReady(state, Unit("Att", atk: 3), 0, G(4, 10));
		Piece vic = SpawnReady(state, Unit("Vic", hp: 2), 1, G(4, 9));
		List<ResolutionEvent> ev = tc.Act(att, null, G(4, 9));
		r.Check(!vic.IsAlive && !state.Players[1].Deck.Contains(vic.Source) && state.Players[1].Graveyard.Contains(vic.Source)
			&& !Has(ev, ResolutionEventType.ReturnedToDeck, vic.Id),
			"a killed normal unit is lost (graveyard), not returned to the deck");
	}

	private static void TestTerrain(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece walker = SpawnReady(state, Unit("Walker", mov: 3), 0, G(5, 12));
		state.Board.SetTerrain(G(5, 11), TerrainType.Water);
		r.Check(state.Board.MoveCost(G(5, 11)) == 2, "entering water costs 2 movement");
		List<GridPos> reach = tc.GetValidMoveTargets(walker);
		r.Check(reach.Contains(G(5, 10)) && !reach.Contains(G(5, 9)), "a river slows a straight crossing (3 movement: water + 1 tile)");
		state.Board.SetTerrain(G(5, 11), TerrainType.Bridge);
		r.Check(state.Board.MoveCost(G(5, 11)) == 1, "bridges cost normal movement");

		state.Board.SetTerrain(G(6, 11), TerrainType.Rock, 3);
		r.Check(state.Board.IsWall(G(6, 11)) && !tc.GetValidMoveTargets(walker).Contains(G(6, 11)), "rocks block movement");
		Piece hitter = SpawnReady(state, Unit("Hitter", atk: 2), 0, G(6, 12));
		List<ResolutionEvent> ev = tc.Act(hitter, null, G(6, 11));
		r.Check(state.Board.GetTerrainHp(G(6, 11)) == 1 && Has(ev, ResolutionEventType.TerrainDamaged, -1), "attacks damage rocks");
		state.Players[0].ActionPoints = 5;
		hitter.ActedTurn = -1;
		tc.Act(hitter, null, G(6, 11));
		r.Check(state.Board.GetTerrain(G(6, 11)) == TerrainType.None && state.Board.IsPassable(G(6, 11)), "a broken rock becomes plain ground");

		// The generator: symmetric, never on deploy rows or the crown, always a way through.
		bool allOk = true;
		var themes = new HashSet<string>();
		for (int seed = 1; seed <= 60; seed++)
		{
			var gs = new GameState(new GameConfig(), new List<CardData>(), new List<CardData>(), new Random(seed));
			MapGenerator.MapInfo info = MapGenerator.Generate(gs);
			themes.Add(info.Name);
			BoardState b = gs.Board;
			foreach (KeyValuePair<GridPos, TerrainType> kv in b.Terrain)
			{
				var mirror = new GridPos(b.Width - 1 - kv.Key.X, b.Height - 1 - kv.Key.Y);
				allOk &= b.GetTerrain(mirror) == kv.Value && !b.IsInDeployZone(0, kv.Key) && !b.IsInDeployZone(1, kv.Key) && !b.IsInHotZone(kv.Key);
			}
			foreach (KeyValuePair<GridPos, TileEffect> kv in b.TileEffects)
			{
				var mirror = new GridPos(b.Width - 1 - kv.Key.X, b.Height - 1 - kv.Key.Y);
				allOk &= kv.Value.IsPermanent && b.GetTileEffectType(mirror) == kv.Value.Type && !b.IsInHotZone(kv.Key);
			}
			allOk &= b.FindPath(G(5, 15), G(5, 0), 999, 0) != null;
		}
		r.Check(allOk, "generated maps are mirror-symmetric, keep deploy rows / crown free and stay crossable");
		r.Check(themes.Count >= 4, $"several map themes appear ({string.Join(", ", themes)})");

		// The crown field stays clean: no buildings, no tile effects, map features only as decoration.
		tc = NewGame(out state);
		Piece builder = SpawnReady(state, Classed("Crowner", UnitClass.Archer, kw: Keyword.Builder), 0, G(5, 9));
		r.Check(!tc.GetValidBuildTiles(builder).Contains(G(5, 8)) && tc.GetValidBuildTiles(builder).Contains(G(4, 8)),
			"buildings cannot be placed on the crown field");
		r.Check(!OrderResolver.ApplyTileEffect(state, TileEffectType.Lava, G(5, 8), 3, 0, "Test", -1, null)
			&& state.Board.GetTileEffectType(G(5, 8)) == TileEffectType.None, "tile effects never land on the crown field");
		bool crownClean = true;
		for (int seed = 100; seed < 160; seed++)
		{
			var gs = new GameState(new GameConfig(), new List<CardData>(), new List<CardData>(), new Random(seed));
			MapGenerator.Generate(gs);
			foreach (GridPos c in new[] { G(5, 7), G(6, 7), G(5, 8), G(6, 8) })
			{
				crownClean &= gs.Board.GetTerrain(c) == TerrainType.None && gs.Board.GetTileEffect(c) == null && gs.Board.MoveCost(c) == 1;
			}
		}
		r.Check(crownClean, "rivers and walls only pass the crown field as decoration");
	}

	private static CardData Legend(string name, LegendEffect effect, int hp = 6)
	{
		CardData c = Unit(name, hp: hp);
		c.Legend = effect;
		c.Rarity = CardRarity.Legendary;
		return c;
	}

	private static void TestLegends(Report r)
	{
		// Unbreakable: never more than 1 damage per hit.
		TurnController tc = NewGame(out GameState state);
		Piece gorran = SpawnReady(state, Legend("Gorran", LegendEffect.Unbreakable, hp: 8), 0, G(5, 10));
		OrderResolver.ApplyDamage(state, gorran, 5, -1, new List<ResolutionEvent>());
		r.Check(gorran.CurrentHp == 7, "Unbreakable takes at most 1 damage from a hit");

		// Dawnlight, Glacial Grip, Chain Lightning and Wildfire fire at their owner's turn start.
		tc = NewGame(out state);
		Piece solenne = SpawnReady(state, Legend("Solenne", LegendEffect.Dawnlight), 0, G(2, 12));
		Piece hurt = SpawnReady(state, Unit("Hurt", hp: 5), 0, G(3, 12));
		Piece far = SpawnReady(state, Unit("Far", hp: 5), 0, G(9, 12));
		hurt.CurrentHp = 1;
		far.CurrentHp = 1;
		Piece hrimgar = SpawnReady(state, Legend("Hrimgar", LegendEffect.GlacialGrip), 0, G(8, 8));
		Piece chilled = SpawnReady(state, Unit("Chilled", hp: 5), 1, G(8, 6));
		Piece voltaris = SpawnReady(state, Legend("Voltaris", LegendEffect.ChainLightning), 0, G(2, 5));
		Piece z1 = SpawnReady(state, Unit("Z1", hp: 5), 1, G(2, 3));
		Piece z2 = SpawnReady(state, Unit("Z2", hp: 5), 1, G(3, 4));
		Piece z3 = SpawnReady(state, Unit("Z3", hp: 5), 1, G(1, 2));
		Piece z4 = SpawnReady(state, Unit("Z4", hp: 5), 1, G(4, 1));
		Piece ignis = SpawnReady(state, Legend("Ignis", LegendEffect.Wildfire), 0, G(10, 12));
		Piece burnt = SpawnReady(state, Unit("Burnt", hp: 5), 1, G(10, 2));
		state.Board.SetTileEffect(new TileEffect(TileEffectType.Lava, G(10, 2), 0, 1, TileEffect.Permanent, "Test"));
		tc.EndTurn();
		int burntAfterOwnTurn = burnt.CurrentHp;
		tc.EndTurn();
		r.Check(hurt.CurrentHp == hurt.MaxHp && far.CurrentHp == 1, "Dawnlight heals nearby units to full (not far ones)");
		r.Check(chilled.IsFrozen, "Glacial Grip freezes enemies within 2 tiles");
		r.Check(z1.CurrentHp == 4 && z2.CurrentHp == 4 && z3.CurrentHp == 4 && z4.CurrentHp == 5, "Chain Lightning strikes the 3 nearest enemies");
		r.Check(burnt.CurrentHp == burntAfterOwnTurn - LegendInfo.WildfireDamage, "Wildfire burns enemies standing on lava");

		// The endboss: locked behind the five clan leaders, rewards one of the five legends.
		NpcData boss = Godot.GD.Load<NpcData>("res://Resources/Npcs/Realmshatter.tres");
		bool legendsOk = boss != null && boss.RewardOneOf.Count == 5;
		var clans = new HashSet<Clan>();
		if (boss != null)
		{
			foreach (CardData c in boss.RewardOneOf)
			{
				legendsOk &= c != null && c.Rarity == CardRarity.Legendary && c.Legend != LegendEffect.None && clans.Add(c.Clan);
			}
		}
		r.Check(legendsOk && clans.Count == 5, "five Legendary cards, one per clan, each with its own effect");
		r.Check(boss != null && boss.RequiresDefeated.Count == 5 && boss.Deck?.Cards.Count == 30, "the endboss needs all five clan leaders and has a 30-card deck");
		r.Check(boss != null && CardEconomy.BuyPrice(boss.RewardOneOf[0]) >= 900, "Legendary cards are very expensive in the shop");
	}

	private static void TestPushCollisions(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		state.Players[0].ActionPoints = 20;
		// Pushed into another piece: no move, 1 collision damage (on top of the hit).
		Piece pusher = SpawnReady(state, Unit("Pusher", atk: 1, kw: Keyword.Push), 0, G(5, 12));
		Piece target = SpawnReady(state, Unit("Target", hp: 5), 1, G(5, 11));
		Piece wall = SpawnReady(state, Unit("Behind", hp: 5), 1, G(5, 10));
		tc.Act(pusher, null, G(5, 11));
		r.Check(target.Position == G(5, 11) && target.CurrentHp == 3 && wall.CurrentHp == 5,
			"a piece pushed into another piece stays and takes 1 extra damage (the other one is unharmed)");

		// Pushed into a rock: same.
		Piece pusher2 = SpawnReady(state, Unit("Pusher2", atk: 1, kw: Keyword.Push), 0, G(8, 12));
		Piece target2 = SpawnReady(state, Unit("Target2", hp: 5), 1, G(8, 11));
		state.Board.SetTerrain(G(8, 10), TerrainType.Rock, 3);
		tc.Act(pusher2, null, G(8, 11));
		r.Check(target2.Position == G(8, 11) && target2.CurrentHp == 3, "a piece pushed into a rock takes 1 extra damage");

		// Pushed against the board edge: only blocked.
		Piece pusher3 = SpawnReady(state, Unit("Pusher3", atk: 1, kw: Keyword.Push), 0, G(1, 3));
		Piece target3 = SpawnReady(state, Unit("Target3", hp: 5), 1, G(0, 3));
		tc.Act(pusher3, null, G(0, 3));
		r.Check(target3.Position == G(0, 3) && target3.CurrentHp == 4, "the board edge only blocks a push (no extra damage)");

		// Moving into your own pieces still nudges them aside without damage.
		Piece mover = SpawnReady(state, Unit("Mover", mov: 3), 0, G(10, 12));
		Piece friend = SpawnReady(state, Unit("Friend", hp: 3), 0, G(10, 11));
		tc.Act(mover, G(10, 11), null);
		r.Check(mover.Position == G(10, 11) && friend.Position == G(10, 10) && friend.CurrentHp == 3, "moving onto a friend still pushes it without damage");
	}

	private static void TestAttackGround(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		state.Players[0].ActionPoints = 20;
		Piece fire = SpawnReady(state, Unit("Fire", kw: Keyword.Burning), 0, G(1, 10));
		Piece frost = SpawnReady(state, Unit("Frost", kw: Keyword.Frost), 0, G(3, 10));
		Piece arc = SpawnReady(state, Unit("Arc", kw: Keyword.Arc), 0, G(8, 10));
		Piece mend = SpawnReady(state, Unit("Mend", kw: Keyword.Mending), 0, G(10, 10));
		Piece push = SpawnReady(state, Unit("Push", kw: Keyword.Push), 0, G(1, 13));
		tc.Act(fire, null, G(1, 9));
		tc.Act(frost, null, G(3, 9));
		tc.Act(arc, null, G(8, 9));
		tc.Act(mend, null, G(10, 9));
		tc.Act(push, null, G(1, 12));
		r.Check(state.Board.GetTileEffectType(G(1, 9)) == TileEffectType.Lava, "Burning attacks set even an empty tile on fire");
		r.Check(state.Board.GetTileEffectType(G(3, 9)) == TileEffectType.Ice, "Frost attacks leave Ice");
		r.Check(state.Board.GetTileEffectType(G(8, 9)) == TileEffectType.Storm, "Arc attacks leave a Storm cell");
		r.Check(state.Board.GetTileEffectType(G(10, 9)) == TileEffectType.Healing, "Mending attacks leave a Healing spring");
		r.Check(state.Board.GetTileEffectType(G(1, 12)) == TileEffectType.Mud && state.Board.MoveCost(G(1, 12)) == 2, "Push attacks leave Mud (2 movement)");

		// Ice stops any move onto it - for both players.
		Piece runner = SpawnReady(state, Unit("Runner", mov: 5), 0, G(3, 11));
		tc.Act(runner, G(3, 7), null);
		r.Check(runner.Position == G(3, 9), "a piece moving onto Ice slides to a halt there");

		// Storm cells crackle at the occupant's turn start: it and its neighbours take 1 damage.
		tc.EndTurn();
		Piece victim = SpawnReady(state, Unit("Victim", hp: 4), 1, G(8, 9));
		Piece beside = SpawnReady(state, Unit("Beside", hp: 4), 1, G(8, 8));
		tc.EndTurn();
		tc.EndTurn();
		r.Check(victim.CurrentHp == 3 && beside.CurrentHp == 3, "a Storm cell hits its occupant and every piece next to it");

		// Permanent map lava is not replaced by a passing attack.
		state.Board.SetTileEffect(new TileEffect(TileEffectType.Lava, G(6, 12), -1, 0, TileEffect.Permanent, "Map"));
		r.Check(!OrderResolver.ApplyTileEffect(state, TileEffectType.Ice, G(6, 12), 3, 0, "Test", -1, null)
			&& state.Board.GetTileEffect(G(6, 12)).IsPermanent, "map lava fields are not overwritten");
	}

	private static void TestTraps(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		CardData scoutCard = Classed("Trapper", UnitClass.Scout, kw: Keyword.Trapper);
		Piece scout = SpawnReady(state, scoutCard, 0, G(3, 10));
		r.Check(tc.GetTrapType(scout) == TrapType.Spike, "a basic Trapper sets Spike traps");
		r.Check(tc.SetTrap(scout, G(3, 9), null) != null && state.Board.GetTrap(G(3, 9))?.OwnerIndex == 0 && state.Players[0].ActionPoints == 2,
			"setting a trap costs 1 AP and uses the action");
		r.Check(!tc.CanCommand(scout), "the Trapper has acted");

		Piece friend = SpawnReady(state, Unit("Friend", mov: 4), 0, G(3, 11));
		tc.Act(friend, G(3, 7), null);
		r.Check(friend.Position == G(3, 7) && state.Board.GetTrap(G(3, 9)) != null, "own pieces walk over their traps");

		tc.EndTurn();
		Piece enemy = SpawnReady(state, Unit("Enemy", mov: 5, hp: 5), 1, G(4, 9));
		List<ResolutionEvent> ev = tc.Act(enemy, G(2, 9), null);
		r.Check(enemy.Position == G(3, 9) && enemy.CurrentHp == 3 && state.Board.GetTrap(G(3, 9)) == null && Has(ev, ResolutionEventType.TrapTriggered, enemy.Id),
			"an enemy stepping on the trap is stopped there, takes 2 damage and the trap is gone");

		// Clan traps.
		tc = NewGame(out state);
		CardData fireCard = Classed("Fire Trapper", UnitClass.Scout, Clan.Fire, Keyword.Trapper);
		Piece fire = SpawnReady(state, fireCard, 0, G(8, 10));
		tc.SetTrap(fire, G(8, 9), null);
		CardData frostCard = Classed("Frost Trapper", UnitClass.Scout, Clan.Frost, Keyword.Trapper);
		Piece frost = SpawnReady(state, frostCard, 0, G(2, 10));
		tc.SetTrap(frost, G(2, 9), null);
		tc.EndTurn();
		Piece e1 = SpawnReady(state, Unit("E1", mov: 4, hp: 5), 1, G(8, 7));
		tc.Act(e1, G(8, 10 - 1), null);
		r.Check(e1.CurrentHp == 4 && state.Board.GetTileEffectType(G(8, 9)) == TileEffectType.Lava, "Fire trap: 1 damage and lava");
		Piece e2 = SpawnReady(state, Unit("E2", mov: 4, hp: 5), 1, G(2, 7));
		tc.Act(e2, G(2, 9), null);
		tc.EndTurn();
		tc.EndTurn();
		r.Check(e2.CurrentHp == 4 && e2.IsFrozen, "Frost trap: 1 damage and frozen through its next turn");

		// Limits.
		tc = NewGame(out state);
		Piece busy = SpawnReady(state, Classed("Busy", UnitClass.Scout, kw: Keyword.Trapper), 0, G(5, 10));
		state.Players[0].ActionPoints = 9;
		tc.SetTrap(busy, G(4, 10), null);
		busy.ActedTurn = -1;
		tc.SetTrap(busy, G(6, 10), null);
		busy.ActedTurn = -1;
		tc.SetTrap(busy, G(5, 11), null);
		r.Check(state.Board.GetTrap(G(4, 10)) == null && state.Board.GetTrap(G(6, 10)) != null && state.Board.GetTrap(G(5, 11)) != null,
			"a Trapper keeps at most 2 traps (the oldest goes)");
		Piece crownSide = SpawnReady(state, Classed("Crown", UnitClass.Scout, kw: Keyword.Trapper), 0, G(5, 9));
		r.Check(!tc.GetValidTrapTiles(crownSide).Contains(G(5, 8)), "no traps on the crown field");
	}

	private static void TestObelisk(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece caster = SpawnReady(state, Unit("Caster"), 0, G(5, 12));
		Piece enemy = SpawnReady(state, Unit("Enemy", atk: 2, hp: 9), 1, G(5, 10));
		CardData weaken = Spell("Weaken", atk: -1);
		state.Players[0].Hand.Add(weaken);
		tc.PlaySpellCard(weaken, enemy);
		r.Check(enemy.EffectiveAttack == 1, "without an Obelisk: -1 Attack");

		Piece obelisk = state.SpawnBuilding(BuildingType.Obelisk, 0, G(4, 11), 0, -1);
		obelisk.UnderConstruction = false;
		CardData weaken2 = Spell("Weaken", atk: -1);
		state.Players[0].Hand.Add(weaken2);
		state.Players[0].ActionPoints = 5;
		tc.PlaySpellCard(weaken2, enemy);
		r.Check(enemy.ActiveSpells.Count == 2 && enemy.ActiveSpells[1].Effect.AttackDelta == -2, "near an Obelisk the same spell removes 2 Attack");
		r.Check(tc.SpellPower(G(5, 10)) == 1 && tc.SpellPower(G(11, 0)) == 0, "the Obelisk only empowers spells aimed within its radius");
		r.Check(!tc.IsInSpellRange(G(4, 6)), "Obelisks no longer extend the cast range");
	}

	private static void TestApCards(Report r)
	{
		// Mana Surge: a spell that gives AP when it resolves.
		TurnController tc = NewGame(out GameState state);
		Piece mine = SpawnReady(state, Unit("Mine"), 0, G(5, 12));
		CardData surge = new CardData { Name = "Surge", CardType = CardType.Spell, ApCost = 1, ApGain = 2 };
		state.Players[0].Hand.Add(surge);
		int before = state.Players[0].ActionPoints;
		r.Check(tc.PlaySpellCard(surge, mine) && state.Players[0].ActionPoints == before + 1 && mine.ActiveSpells.Count == 0,
			"an AP spell pays 1 and gives 2 (net +1), no empty spell on its target");

		// Plunder: a kill on your own turn gives 1 AP right away.
		Piece raider = SpawnReady(state, Unit("Raider", atk: 3, kw: Keyword.Plunder), 0, G(4, 10));
		Piece victim = SpawnReady(state, Unit("Victim", hp: 2), 1, G(4, 9));
		int apBefore = state.Players[0].ActionPoints;
		List<ResolutionEvent> ev = tc.Act(raider, null, G(4, 9));
		r.Check(!victim.IsAlive && state.Players[0].ActionPoints == apBefore - 1 + 1 && Has(ev, ResolutionEventType.ApGained, raider.Id),
			"Plunder: destroying an enemy refunds 1 AP");

		// Tribute: the AP arrives at the start of the owner's next turn.
		tc = NewGame(out state);
		CardData pilgrim = Unit("Pilgrim", hp: 1);
		pilgrim.Deathrattle = DeathrattleType.Tribute;
		pilgrim.DeathrattleAmount = 2;
		Piece p = SpawnReady(state, pilgrim, 0, G(5, 10));
		OrderResolver.ApplyDamage(state, p, 5, -1, new List<ResolutionEvent>());
		tc.EndTurn();
		r.Check(state.Players[0].PendingAp == 2, "Tribute stores 2 AP for the owner's next turn");
		tc.EndTurn();
		r.Check(state.Players[0].ActionPoints == state.Config.BaseAp + 2 && state.Players[0].PendingAp == 0, "Tribute AP is added at the turn start");
	}

	private static void TestPlanted(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		CardData totem = Unit("Totem", mov: 0, kw: Keyword.Planted);
		state.Players[0].Hand.Add(totem);
		state.Players[0].ActionPoints = 10;
		SpawnReady(state, Unit("Runner"), 0, G(3, 8));
		r.Check(tc.CanPlayUnitCard(totem, G(3, 15)), "Planted units may still use the deploy rows");
		r.Check(tc.CanPlayUnitCard(totem, G(3, 6)), "Planted units may be placed 2 tiles from an own unit");
		r.Check(!tc.CanPlayUnitCard(totem, G(3, 5)), "but not 3 tiles away");
		SpawnReady(state, Unit("Crowner"), 0, G(4, 7));
		r.Check(!tc.CanPlayUnitCard(totem, G(5, 7)), "never on the crown field");
		r.Check(!tc.CanPlayUnitCard(Unit("Walker"), G(3, 6)), "normal units still deploy only in the back rows");

		Piece planted = tc.PlayUnitCard(totem, G(3, 6));
		r.Check(planted != null && planted.HasKeyword(Keyword.Planted), "Planted unit deployed forward");
		planted.SummonedTurn = -1;
		r.Check(tc.GetValidMoveTargets(planted).Count == 0, "a Planted unit cannot move");
		r.Check(!planted.CanScore, "a Planted unit never scores");
		int vpBefore = state.Players[0].VictoryPoints;
		tc.EndTurn();
		tc.EndTurn();
		// Runner (3, 8) and Crowner (4, 7) score 1 each; the Planted piece in the zone (3, 6) scores nothing.
		r.Check(state.Players[0].VictoryPoints - vpBefore == 2, $"only the mobile units scored ({state.Players[0].VictoryPoints - vpBefore} VP)");
	}

	private static void TestVpToAp(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		PlayerState p0 = state.Players[0];
		r.Check(!tc.ConvertVpToAp(), "cannot convert without VP");
		p0.VictoryPoints = 3;
		r.Check(tc.ConvertVpToAp() && p0.VictoryPoints == 2 && p0.ActionPoints == 4, "1 VP -> 1 AP");
		r.Check(tc.ConvertVpToAp() && !tc.ConvertVpToAp() && p0.ActionPoints == 5, "max 2 per turn");
	}

	private static void TestSecondPlayerBonus(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		tc.EndTurn();
		r.Check(state.Players[1].ActionPoints == 3 + state.Config.SecondPlayerFirstTurnBonusAp, "second player: bonus AP on its first turn");
		tc.EndTurn();
		tc.EndTurn();
		r.Check(state.Players[1].ActionPoints == 3, "bonus only on the first turn");
	}

	private static void TestTileTicks(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece e = SpawnReady(state, Unit("E", hp: 3), 1, G(5, 2));
		Piece f = SpawnReady(state, Unit("F", hp: 3), 0, G(5, 15));
		Place(state, TileEffectType.Lava, G(5, 2));
		Place(state, TileEffectType.Lava, G(5, 15));
		tc.EndTurn();
		r.Check(e.CurrentHp == 2 && f.CurrentHp == 3, "lava damages at the start of the occupant owner's turn");
		tc.EndTurn();
		r.Check(f.CurrentHp == 2, "lava ticks for player 0 on its turn");
		List<ResolutionEvent> ev = tc.EndTurn();
		r.Check(state.Board.GetTileEffect(G(5, 2)) == null && Has(ev, ResolutionEventType.TileEffectExpired), "lava expires after its duration");

		f.CurrentHp = 1;
		Place(state, TileEffectType.Healing, f.Position);
		tc.EndTurn();
		r.Check(f.CurrentHp == 2 && Has(tc.LastTurnStartEvents, ResolutionEventType.TileHeal, f.Id), "healing tile heals 1 at owner's turn start");
	}

	private static void TestWalls(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece a = SpawnReady(state, Unit("A", mov: 2), 0, G(4, 12));
		r.Check(OrderResolver.ApplyTileEffect(state, TileEffectType.Wall, G(4, 11), 2, 0, "Test", -1, null), "wall placed");
		List<GridPos> targets = tc.GetValidMoveTargets(a);
		r.Check(!targets.Contains(G(4, 11)) && !targets.Contains(G(4, 10)), "wall is impassable");
		r.Check(!OrderResolver.ApplyTileEffect(state, TileEffectType.Wall, a.Position, 2, 0, "Test", -1, null), "no wall on an occupied tile");
		tc.EndTurn();
		tc.EndTurn();
		r.Check(state.Board.IsWall(G(4, 11)), "wall active during the creator's next turn");
		List<ResolutionEvent> ev = tc.EndTurn();
		r.Check(!state.Board.IsWall(G(4, 11)) && Has(ev, ResolutionEventType.TileEffectExpired), "wall expired");
	}

	private static void TestTileSpells(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		PlayerState p0 = state.Players[0];
		var meteor = new CardData
		{
			Name = "Meteor", CardType = CardType.Spell, ApCost = 2, SpellTarget = SpellTargetType.Area, AreaShape = AreaShape.Plus,
			TileEffect = TileEffectType.Lava, TileEffectDuration = 4, SpellDamage = 1,
		};
		p0.Hand.Add(meteor);
		Piece e1 = SpawnReady(state, Unit("E1", hp: 3), 1, G(5, 8));
		Piece e2 = SpawnReady(state, Unit("E2", hp: 1), 1, G(5, 7));
		Piece f = SpawnReady(state, Unit("F", hp: 3), 0, G(4, 8));
		r.Check(tc.GetSpellAreaPreview(meteor, G(5, 8)).Count == 5 && tc.GetSpellAreaPreview(meteor, G(0, 0)).Count == 3, "area preview (plus, clipped)");
		r.Check(tc.PlaySpellOnTile(meteor, G(5, 8)) && p0.ActionPoints == 1, "PlaySpellOnTile pays AP");
		r.Check(e1.CurrentHp == 2 && !e2.IsAlive && f.CurrentHp == 3, "area damage hits enemies only");
		// (5, 8) is a crown tile and stays clean; the rest of the cross turns to lava.
		r.Check(state.Board.GetTileEffect(G(4, 8))?.ExpiryTurn == state.TurnNumber + 4 && state.Board.GetTileEffect(G(5, 8)) == null,
			"lava lasts the card's duration (never on the crown field)");
	}

	private static void TestBurning(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece a = SpawnReady(state, Unit("Burner", kw: Keyword.Burning), 0, G(5, 10));
		Piece en = SpawnReady(state, Unit("En", hp: 3), 1, G(5, 9));
		tc.Act(a, null, G(5, 9));
		r.Check(en.CurrentHp == 2 && state.Board.GetTileEffectType(G(5, 9)) == TileEffectType.Lava, "Burning hit leaves lava");
		r.Check(state.Board.GetTileEffect(G(5, 9)).ExpiryTurn == state.TurnNumber + state.Config.BurningLavaDuration, "lava duration = BurningLavaDuration");
	}

	private static void TestFrost(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece a = SpawnReady(state, Unit("Frost", kw: Keyword.Frost), 0, G(5, 10));
		Piece en = SpawnReady(state, Unit("En", hp: 3, mov: 2), 1, G(5, 9));
		tc.Act(a, null, G(5, 9));
		r.Check(en.IsFrozen && en.EffectiveMovement == 0, "Frost freezes the target");
		tc.EndTurn();
		r.Check(en.IsFrozen && !tc.CanAct(en, G(5, 8), null), "frozen enemy cannot move on its turn");
		tc.EndTurn();
		r.Check(!en.IsFrozen, "frost thaws after the victim's turn");
	}

	private static void TestPushKeyword(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece a = SpawnReady(state, Unit("Ram", kw: Keyword.Push), 0, G(5, 10));
		Piece en = SpawnReady(state, Unit("En", hp: 3), 1, G(5, 9));
		tc.Act(a, null, G(5, 9));
		r.Check(en.Position == G(5, 8) && en.CurrentHp == 2, "Push knocks the target back 1 tile");
	}

	private static void TestPierce(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece a = SpawnReady(state, Unit("Lancer", atk: 2, kw: Keyword.Pierce), 0, G(5, 10));
		Piece e1 = SpawnReady(state, Unit("E1", hp: 3), 1, G(5, 9));
		Piece f = SpawnReady(state, Unit("F", hp: 3), 0, G(5, 8));
		tc.Act(a, null, G(5, 9));
		r.Check(e1.CurrentHp == 1 && f.CurrentHp == 1, "Pierce hits the piece behind too - even a friendly");
	}

	private static void TestMending(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece a = SpawnReady(state, Unit("Cleric", kw: Keyword.Mending), 0, G(5, 10));
		Piece f = SpawnReady(state, Unit("F", hp: 3), 0, G(5, 9));
		f.CurrentHp = 1;
		List<ResolutionEvent> ev = tc.Act(a, null, G(5, 9));
		r.Check(f.CurrentHp == 2 && Has(ev, ResolutionEventType.Healed, f.Id) && !Has(ev, ResolutionEventType.Damaged), "Mending heals a friendly instead of damaging it");
	}

	private static void TestArc(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece a = SpawnReady(state, Unit("Arc", atk: 2, rng: 2, kw: Keyword.Arc), 0, G(5, 12));
		Piece target = SpawnReady(state, Unit("T", hp: 4), 1, G(5, 10));
		Piece side = SpawnReady(state, Unit("S", hp: 3), 1, G(6, 10));
		Piece own = SpawnReady(state, Unit("O", hp: 3), 0, G(4, 10));
		Piece far = SpawnReady(state, Unit("Far", hp: 3), 1, G(7, 10));
		tc.Act(a, null, G(5, 10));
		r.Check(target.CurrentHp == 2, "Arc: main target takes full damage");
		r.Check(side.CurrentHp == 2 && own.CurrentHp == 2, "Arc zaps every adjacent piece for 1 - friend or foe");
		r.Check(far.CurrentHp == 3, "Arc does not jump further");
	}

	private static void TestEchoOvercharge(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece a = SpawnReady(state, Unit("Echo", atk: 1, kw: Keyword.Echo), 0, G(5, 10));
		Piece en = SpawnReady(state, Unit("En", hp: 4), 1, G(5, 9));
		tc.Act(a, null, G(5, 9));
		r.Check(en.CurrentHp == 2, "Echo strikes twice (1 + 1)");

		Piece b = SpawnReady(state, Unit("B", atk: 2), 0, G(8, 10));
		Piece en2 = SpawnReady(state, Unit("En2", hp: 6), 1, G(8, 9));
		OrderResolver.ApplyStatus(state, b, StatusEffectType.Overcharged, 2, "Test", -1, null);
		List<ResolutionEvent> ev = tc.Act(b, null, G(8, 9));
		r.Check(en2.CurrentHp == 2 && !b.HasStatus(StatusEffectType.Overcharged), "Overcharged doubles the next attack and is consumed");
		r.Check(ev.Exists(e => e.Type == ResolutionEventType.StatusExpired && e.IsSecondary), "consumption event emitted");
	}

	private static void TestPreview(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece a = SpawnReady(state, Unit("Lancer", atk: 2, kw: Keyword.Pierce | Keyword.Arc), 0, G(5, 10));
		SpawnReady(state, Unit("E1", hp: 2), 1, G(5, 9));
		SpawnReady(state, Unit("F", hp: 3), 0, G(5, 8));
		SpawnReady(state, Unit("E2", hp: 3), 1, G(6, 9));
		ChainPreview p = tc.PredictAttack(a, G(5, 9));
		int enemyHpBefore = 0;
		int friendlyHpBefore = 0;
		foreach (Piece piece in state.Pieces)
		{
			if (piece.OwnerIndex == 1) enemyHpBefore += piece.CurrentHp;
			else if (piece != a) friendlyHpBefore += piece.CurrentHp;
		}
		tc.Act(a, null, G(5, 9));
		int enemyHpAfter = 0;
		int friendlyHpAfter = 0;
		foreach (Piece piece in state.Pieces)
		{
			if (piece.OwnerIndex == 1) enemyHpAfter += piece.CurrentHp;
			else if (piece != a) friendlyHpAfter += piece.CurrentHp;
		}
		r.Check(p.IsValid && p.EnemyHpLost == enemyHpBefore - enemyHpAfter, "preview enemy damage matches the action");
		r.Check(p.FriendlyHpLost == friendlyHpBefore - friendlyHpAfter && p.FriendlyHpLost > 0, "preview friendly fire matches the action");
		r.Check(p.EnemyKills == 1, "preview kill count");
	}

	private static CardData Trigger(string name, DeathrattleType dr = DeathrattleType.None, int drAmount = 1,
		FirstHitType fh = FirstHitType.None, int fhAmount = 1, int hp = 3, int atk = 1)
	{
		CardData c = Unit(name, atk: atk, hp: hp);
		c.Deathrattle = dr;
		c.DeathrattleAmount = drAmount;
		c.OnFirstHit = fh;
		c.OnFirstHitAmount = fhAmount;
		return c;
	}

	private static void TestDeathrattles(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece keg = SpawnReady(state, Trigger("Keg", DeathrattleType.Explode, 2, hp: 1), 1, G(5, 8));
		Piece e = SpawnReady(state, Unit("E", hp: 4), 1, G(5, 7));
		Piece own = SpawnReady(state, Unit("Own", hp: 4), 0, G(6, 8));
		Piece a = SpawnReady(state, Unit("A", atk: 1, rng: 2), 0, G(5, 10));
		List<ResolutionEvent> ev = tc.Act(a, null, G(5, 8));
		r.Check(!keg.IsAlive && Has(ev, ResolutionEventType.Deathrattle, keg.Id), "deathrattle triggers on death");
		r.Check(e.CurrentHp == 2 && own.CurrentHp == 2 && a.CurrentHp == 3, "Explode hits every adjacent piece - friend or foe");

		tc = NewGame(out state);
		Piece shock = SpawnReady(state, Trigger("Shock", DeathrattleType.Shockwave, hp: 1), 1, G(5, 8));
		Piece n1 = SpawnReady(state, Unit("N1"), 1, G(5, 7));
		Piece n2 = SpawnReady(state, Unit("N2"), 0, G(4, 8));
		OrderResolver.ApplyDamage(state, shock, 5, -1, new List<ResolutionEvent>());
		r.Check(n1.Position == G(5, 6) && n2.Position == G(3, 8), "Shockwave pushes neighbours away");

		Piece lava = SpawnReady(state, Trigger("Lava", DeathrattleType.LavaPool, hp: 1), 1, G(8, 8));
		OrderResolver.ApplyDamage(state, lava, 5, -1, null);
		r.Check(state.Board.GetTileEffectType(G(8, 8)) == TileEffectType.Lava && state.Board.GetTileEffectType(G(9, 8)) == TileEffectType.Lava,
			"Lava Pool covers its tile and the neighbours");

		Piece healer = SpawnReady(state, Trigger("Healer", DeathrattleType.HealAllies, 2, hp: 1), 0, G(2, 12));
		Piece hurt = SpawnReady(state, Unit("Hurt", hp: 4), 0, G(3, 13));
		hurt.CurrentHp = 1;
		OrderResolver.ApplyDamage(state, healer, 5, -1, null);
		r.Check(hurt.CurrentHp == 3, "Last Blessing heals allies within 2 tiles");

		Piece rubble = SpawnReady(state, Trigger("Rubble", DeathrattleType.RaiseWalls, hp: 1), 0, G(9, 13));
		OrderResolver.ApplyDamage(state, rubble, 5, -1, null);
		r.Check(state.Board.IsWall(G(9, 12)) && state.Board.IsWall(G(10, 13)), "Rubble raises walls next to it");

		state.Players[0].Deck.Add(Unit("Spare"));
		int hand = state.Players[0].Hand.Count;
		Piece word = SpawnReady(state, Trigger("Word", DeathrattleType.DrawCard, 1, hp: 1), 0, G(0, 14));
		OrderResolver.ApplyDamage(state, word, 5, -1, null);
		r.Check(state.Players[0].Hand.Count == hand + 1, "Last Word draws a card");

		Piece nova = SpawnReady(state, Trigger("Nova", DeathrattleType.FrostNova, hp: 1), 0, G(10, 6));
		Piece victim = SpawnReady(state, Unit("Victim"), 1, G(10, 5));
		OrderResolver.ApplyDamage(state, nova, 5, -1, null);
		r.Check(victim.IsFrozen, "Frost Nova freezes adjacent enemies");
	}

	private static void TestFirstHit(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece thorny = SpawnReady(state, Trigger("Thorny", fh: FirstHitType.Thorns, fhAmount: 2, hp: 5), 1, G(5, 9));
		Piece a = SpawnReady(state, Unit("A", atk: 1, hp: 3), 0, G(5, 10));
		tc.Act(a, null, G(5, 9));
		r.Check(a.CurrentHp == 1 && thorny.WasHit, "Thorns hurts the attacker on the first hit");
		Piece b = SpawnReady(state, Unit("B", atk: 1, hp: 3), 0, G(4, 9));
		tc.Act(b, null, G(5, 9));
		r.Check(b.CurrentHp == 3, "first-hit effects trigger only once");

		Piece repel = SpawnReady(state, Trigger("Repel", fh: FirstHitType.Repel, hp: 5), 1, G(8, 9));
		Piece c = SpawnReady(state, Unit("C", atk: 1), 0, G(8, 10));
		tc.Act(c, null, G(8, 9));
		r.Check(c.Position == G(8, 11), "Repel pushes the attacker away");

		Piece hard = SpawnReady(state, Trigger("Hard", fh: FirstHitType.Harden, fhAmount: 2, hp: 5), 1, G(2, 9));
		OrderResolver.ApplyDamage(state, hard, 1, -1, null);
		r.Check(hard.CurrentHp == 4 && hard.TotalShield == 2, "Harden grants shield after the first hit");

		Piece rage = SpawnReady(state, Trigger("Rage", fh: FirstHitType.Enrage, fhAmount: 2, hp: 5, atk: 1), 1, G(2, 5));
		OrderResolver.ApplyDamage(state, rage, 1, -1, null);
		r.Check(rage.EffectiveAttack == 3, "Enrage adds permanent attack");
		ChainPreview preview = tc.PredictAttack(SpawnReady(state, Unit("P", atk: 1, hp: 2), 0, G(9, 10)), G(9, 9));
		r.Check(!preview.IsValid || preview.FriendlyHpLost == 0, "preview runs with triggers");
	}

	private static CardData Classed(string name, UnitClass cls, Clan clan = Clan.None, Keyword kw = Keyword.None, int mov = 4, int hp = 3)
	{
		CardData c = Unit(name, mov: mov, hp: hp, kw: kw);
		c.Class = cls;
		c.Clan = clan;
		return c;
	}

	private static void TestBuildings(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece archer = SpawnReady(state, Classed("Arch", UnitClass.Archer, kw: Keyword.Builder), 0, G(5, 12));
		r.Check(tc.GetBuildType(archer) == BuildingType.Turret, "Archers build Turrets");
		List<ResolutionEvent> ev = tc.Build(archer, G(5, 11));
		Piece turret = state.Board.GetPieceAt(G(5, 11));
		r.Check(ev != null && turret != null && turret.IsBuilding && turret.UnderConstruction && state.Players[0].ActionPoints == 1,
			"building started (2 AP), unfinished");
		r.Check(archer.ConstructingId == turret.Id && !tc.CanAct(archer, G(4, 12), null), "the builder cannot move while building");
		r.Check(!tc.CanCommand(turret), "buildings cannot be commanded");
		tc.EndTurn();
		tc.EndTurn();
		r.Check(turret.UnderConstruction, "still unfinished after one own turn");
		tc.EndTurn();
		tc.EndTurn();
		r.Check(!turret.UnderConstruction && archer.ConstructingId == -1 && Has(tc.LastTurnStartEvents, ResolutionEventType.BuildingCompleted, turret.Id),
			"finished at the start of the second own turn, builder freed");
		r.Check(state.Players[0].VictoryPoints == 0, "buildings do not score");

		// A unit busy building does not score either, until its building is finished.
		{
			TurnController tz = NewGame(out GameState zs);
			Piece zoneBuilder = SpawnReady(zs, Classed("ZoneBuilder", UnitClass.Archer, kw: Keyword.Builder), 0, G(4, 6));
			Piece zoneRunner = SpawnReady(zs, Unit("Runner"), 0, G(7, 6));
			tz.Build(zoneBuilder, G(4, 5));
			tz.EndTurn();
			tz.EndTurn();
			r.Check(zs.Players[0].VictoryPoints == 1 && !zoneBuilder.CanScore && zoneRunner.CanScore,
				"a builder busy building in the zone scores no VP (the runner next to it does)");
			tz.EndTurn();
			tz.EndTurn();
			r.Check(zoneBuilder.ConstructingId < 0 && zs.Players[0].VictoryPoints == 3, "once the building is finished it scores again");
		}
		tc.EndTurn();
		Piece e1 = SpawnReady(state, Unit("E1", mov: 4, hp: 3), 1, G(5, 5));
		Piece e2 = SpawnReady(state, Unit("E2", mov: 4, hp: 3), 1, G(6, 5));
		tc.Act(e1, G(5, 8), null);
		r.Check(e1.CurrentHp == 2, "the turret shoots an enemy that moves into range");
		tc.Act(e2, G(6, 8), null);
		r.Check(e2.CurrentHp == 3, "the turret fires only once per turn");

		tc = NewGame(out state);
		Piece sword = SpawnReady(state, Classed("Sword", UnitClass.Swordsman, kw: Keyword.Builder), 0, G(3, 12));
		tc.Build(sword, G(3, 11));
		Piece barricade = state.Board.GetPieceAt(G(3, 11));
		r.Check(barricade?.Building == BuildingType.Barricade, "Swordsmen build Barricades");
		OrderResolver.ApplyDamage(state, sword, 99, -1, null);
		r.Check(state.GetPiece(barricade.Id) == null && state.Board.GetTileEffectType(G(3, 11)) == TileEffectType.Rubble && state.Board.IsWall(G(3, 11)),
			"the builder's death destroys the unfinished building, leaving impassable rubble");

		tc = NewGame(out state);
		Piece worker = SpawnReady(state, Classed("Worker", UnitClass.Worker, kw: Keyword.Builder), 0, G(8, 14));
		tc.Build(worker, G(8, 13));
		for (int i = 0; i < 4; i++)
		{
			tc.EndTurn();
		}
		r.Check(state.Players[0].ActionPoints == 4, "a finished Mana Well gives +1 AP");

		// Move, then build (the build replaces the attack).
		tc = NewGame(out state);
		Piece mover = SpawnReady(state, Classed("Mover", UnitClass.Archer, kw: Keyword.Builder), 0, G(5, 14));
		List<ResolutionEvent> moveBuild = tc.Build(mover, new[] { G(5, 11) }, G(5, 12));
		Piece placed = state.Board.GetPieceAt(G(5, 11));
		r.Check(moveBuild != null && mover.Position == G(5, 12) && placed?.Building == BuildingType.Turret
			&& Has(moveBuild, ResolutionEventType.Moved, mover.Id) && state.Players[0].ActionPoints == 1,
			"a Builder can move and then build (pays only the building's AP)");
		r.Check(!tc.CanCommand(mover), "moving + building uses the unit's action");

		// One Barricade build places two Barricades; the builder's death collapses both.
		tc = NewGame(out state);
		Piece pair = SpawnReady(state, Classed("Pair", UnitClass.Swordsman, kw: Keyword.Builder), 0, G(6, 12));
		r.Check(!tc.CanBuild(pair, new[] { G(5, 11), G(6, 11), G(7, 11) }, null), "at most two Barricades per build");
		List<ResolutionEvent> two = tc.Build(pair, new[] { G(5, 11), G(7, 11) }, null);
		Piece b1 = state.Board.GetPieceAt(G(5, 11));
		Piece b2 = state.Board.GetPieceAt(G(7, 11));
		r.Check(two != null && b1?.Building == BuildingType.Barricade && b2?.Building == BuildingType.Barricade, "a Barricade build places two");
		OrderResolver.ApplyDamage(state, pair, 99, -1, null);
		r.Check(state.GetPiece(b1.Id) == null && state.GetPiece(b2.Id) == null, "the builder's death collapses both unfinished Barricades");
	}

	private static void TestAuras(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		SpawnReady(state, Classed("Heat", UnitClass.Mage, Clan.Fire, Keyword.Aura), 0, G(5, 8));
		Piece enemy = SpawnReady(state, Unit("E", hp: 3), 1, G(6, 9));
		Piece far = SpawnReady(state, Unit("F", hp: 3), 1, G(8, 9));
		tc.EndTurn();
		tc.EndTurn();
		r.Check(enemy.CurrentHp == 2 && far.CurrentHp == 3 && Has(tc.LastTurnStartEvents, ResolutionEventType.AuraPulse),
			"Fire aura burns diagonal neighbours at its turn start");

		tc = NewGame(out state);
		SpawnReady(state, Classed("Static", UnitClass.Mage, Clan.Storm, Keyword.Aura), 0, G(5, 8));
		Piece ally = SpawnReady(state, Unit("A", atk: 1), 0, G(5, 9));
		tc.EndTurn();
		tc.EndTurn();
		r.Check(ally.EffectiveAttack == 2, "Storm aura: +1 Attack this turn");
		tc.EndTurn();
		r.Check(ally.EffectiveAttack == 1, "the bonus expires at the end of the turn");
	}

	private static void TestSpellRange(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		CardData bolt = new CardData { Name = "Bolt", CardType = CardType.Spell, ApCost = 1, SpellTarget = SpellTargetType.Tile, SpellDamage = 1 };
		state.Players[0].Hand.Add(bolt);
		SpawnReady(state, Unit("Own"), 0, G(5, 12));
		SpawnReady(state, Unit("Far"), 1, G(5, 2));
		SpawnReady(state, Unit("Near"), 1, G(5, 8));
		r.Check(!tc.CanPlaySpellOnTile(bolt, G(5, 2)) && tc.LastError.Contains("Too far"), "no spells beyond 4 tiles of your units");
		r.Check(tc.CanPlaySpellOnTile(bolt, G(5, 8)), "spells within 4 tiles are fine");
	}

	private static void TestPushSpell(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		var gale = new CardData
		{
			Name = "Gale", CardType = CardType.Spell, ApCost = 1, SpellTarget = SpellTargetType.Area, AreaShape = AreaShape.Plus, SpellPush = true,
		};
		state.Players[0].Hand.Add(gale);
		Piece up = SpawnReady(state, Unit("Up"), 1, G(5, 7));
		Piece mid = SpawnReady(state, Unit("Mid"), 1, G(5, 8));
		Piece right = SpawnReady(state, Unit("Right"), 0, G(6, 8));
		r.Check(tc.PlaySpellOnTile(gale, G(5, 8)), "push spell castable");
		r.Check(up.Position == G(5, 6) && right.Position == G(7, 8), "pieces around the centre are pushed outward");
		r.Check(mid.Position == G(5, 7), "the centre piece is pushed away from the caster");
	}

	private static void TestTown(Report r)
	{
		var npcs = new List<string> { "FireApprentice", "HealingApprentice", "FrostApprentice", "StormApprentice", "StoneApprentice",
			"Sellsword", "HedgeWitch" };
		foreach (string clan in new[] { "Fire", "Healing", "Frost", "Storm", "Stone" })
		{
			foreach (string tier in new[] { "Initiate", "Adept", "Champion", "Leader" })
			{
				npcs.Add(clan + tier);
			}
		}
		var ids = new HashSet<string>();
		var byId = new Dictionary<string, NpcData>();
		bool allOk = true;
		bool legal = true;
		int epicRewards = 0;
		foreach (string n in npcs)
		{
			NpcData npc = Godot.GD.Load<NpcData>($"res://Resources/Npcs/{n}.tres");
			bool ok = npc != null && npc.Deck != null && npc.Deck.Cards.Count == 30 && npc.RewardGold > 0
				&& ids.Add(npc.Id) && npc.RewardCards.Count > 0;
			if (ok)
			{
				byId[npc.Id] = npc;
				foreach (CardData c in npc.RewardCards)
				{
					epicRewards += c.Rarity == CardRarity.Epic ? 1 : 0;
				}
				var copies = new Dictionary<CardData, int>();
				foreach (CardData c in npc.Deck.Cards)
				{
					copies.TryGetValue(c, out int k);
					copies[c] = k + 1;
					legal &= c != null && copies[c] <= (c.Rarity == CardRarity.Legendary ? 1 : 3);
				}
			}
			allOk &= ok;
		}
		r.Check(allOk, $"{npcs.Count} NPCs load with a 30-card deck, unique id and rewards");
		r.Check(legal, "NPC decks keep the copy limits (3, Legendary 1)");
		r.Check(epicRewards == 5, "every clan leader rewards an Epic card");
		bool halls = true;
		foreach (string clan in new[] { "Fire", "Healing", "Frost", "Storm", "Stone" })
		{
			NpcData leader = Godot.GD.Load<NpcData>($"res://Resources/Npcs/{clan}Leader.tres");
			halls &= leader != null && leader.House == leader.Clan && leader.RequiresDefeated.Count == 3 && leader.BonusApPerTurn > 0;
			foreach (string id in leader?.RequiresDefeated ?? new Godot.Collections.Array<string>())
			{
				halls &= byId.TryGetValue(id, out NpcData member) && member.House == leader.House && member.RequiresDefeated.Count == 0;
			}
		}
		r.Check(halls, "each clan leader waits in its hall behind its three duelists");
		NpcData boss = Godot.GD.Load<NpcData>("res://Resources/Npcs/Realmshatter.tres");
		r.Check(boss != null && boss.House == Clan.None && boss.RequiresDefeated.Count == 5 && boss.RewardOneOf.Count == 5,
			"the endboss waits in town for the five clan leaders and gives a Legendary");
		int stock = 0;
		foreach (string v in new[] { "MarketStall", "ArcaneEmporium", "WanderingTrader" })
		{
			VendorData vendor = Godot.GD.Load<VendorData>($"res://Resources/Vendors/{v}.tres");
			stock += vendor?.Stock.Count ?? 0;
		}
		r.Check(stock >= 30, $"vendors offer {stock} cards");
		CardData common = Godot.GD.Load<CardData>("res://Resources/Cards/Swordsman.tres");
		CardData epic = Godot.GD.Load<CardData>("res://Resources/Cards/Phoenix.tres");
		r.Check(CardEconomy.BuyPrice(epic) > CardEconomy.BuyPrice(common) && CardEconomy.SellPrice(common) < CardEconomy.BuyPrice(common),
			"epic costs more than common, selling pays less than buying");
	}

	private static void TestDecks(Report r)
	{
		foreach (string name in new[] { "StarterDeck", "EmberLegion", "DawnCovenant", "Frostbound", "StormCircuit", "StoneBastion" })
		{
			DeckData deck = Godot.GD.Load<DeckData>($"res://Resources/Decks/{name}.tres");
			bool ok = deck != null && deck.Cards != null && deck.Cards.Count == 30;
			if (ok)
			{
				foreach (CardData c in deck.Cards)
				{
					ok &= c != null && !string.IsNullOrEmpty(c.Name);
				}
			}
			r.Check(ok, $"{name}.tres loads with 30 valid cards");
			if (ok && name != "StarterDeck")
			{
				bool classed = true;
				foreach (CardData c in deck.Cards)
				{
					classed &= c.CardType != CardType.Unit || c.Class != UnitClass.None;
				}
				r.Check(classed, $"{name}: every unit has a class");
			}
		}
	}
}
