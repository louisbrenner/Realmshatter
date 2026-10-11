using System;
using System.Collections.Generic;
using System.Text;

namespace Realmshatter;

/// <summary>In-code sanity checks of the core rules. Call Run() from the game and print the report.</summary>
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
		RunSection(r, "Deploy + AP", TestDeployAndAp);
		RunSection(r, "Draw costs AP + draft flow", TestDraw);
		RunSection(r, "Order cost / refund / free replace", TestOrderCost);
		RunSection(r, "Summoning sickness", TestSummoningSickness);
		RunSection(r, "VP scoring + win", TestScoring);
		RunSection(r, "Shield before HP", TestShield);
		RunSection(r, "Friendly chain", TestChain);
		RunSection(r, "Spell expiry", TestSpellExpiry);
		RunSection(r, "v3: planning ignores friendlies", TestPlanningPassThrough);
		RunSection(r, "v3: pass-through + push at resolution", TestPushResolution);
		RunSection(r, "v3: destroyed pieces return to deck / Undying", TestReturnToDeck);
		RunSection(r, "v3: VP -> AP conversion", TestVpToAp);
		RunSection(r, "v3: second player bonus AP", TestSecondPlayerBonus);
		RunSection(r, "v3: lava / healing ticks", TestTileTicks);
		RunSection(r, "v3: walls block + expire", TestWalls);
		RunSection(r, "v3: tile spells", TestTileSpells);
		RunSection(r, "v3: keyword Burning", TestBurning);
		RunSection(r, "v3: keyword Frost", TestFrost);
		RunSection(r, "v3: keyword Push", TestPushKeyword);
		RunSection(r, "v3: keyword Pierce", TestPierce);
		RunSection(r, "v3: keyword Mending", TestMending);
		RunSection(r, "v3: keyword Conduit", TestConduit);
		RunSection(r, "v3: keyword Echo + Overcharge", TestEchoOvercharge);
		RunSection(r, "v3: chain preview == actual", TestChainPreview);
		RunSection(r, "v3: StarterDeck resource", TestStarterDeck);
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

	private static void TestDeployAndAp(Report r)
	{
		var deck = UnitDeck(7);
		var state = new GameState(new GameConfig(), deck, new List<CardData>(deck), new Random(42));
		var tc = new TurnController(state);
		tc.StartGame();
		PlayerState p0 = state.Players[0];
		r.Check(p0.Hand.Count == 3, "starting hand is 3");
		r.Check(state.Phase == GamePhase.Main && p0.DraftOffer.Count == 0, "no free draft at turn start (Main phase)");
		r.Check(p0.ActionPoints == 3, "base AP is 3");

		CardData c0 = p0.Hand[0];
		r.Check(tc.PlayUnitCard(c0, new GridPos(4, 0)) == null, "player 0 cannot deploy in row 0");
		r.Check(tc.PlayUnitCard(c0, new GridPos(4, 5)) == null, "player 0 cannot deploy in row 5");
		r.Check(tc.PlayUnitCard(c0, new GridPos(4, 6)) != null, "player 0 can deploy in row 6");
		r.Check(p0.ActionPoints == 2, "unit costs 1 AP");
		r.Check(tc.PlayUnitCard(p0.Hand[0], new GridPos(4, 6)) == null, "cannot deploy on occupied tile");

		CardData spell = Spell("Buff", atk: 1);
		p0.Hand.Add(spell);
		r.Check(tc.GetCardCost(spell) == 2, "spell costs 2 AP");
		r.Check(tc.PlaySpellCard(spell, state.Board.GetPieceAt(new GridPos(4, 6))) && p0.ActionPoints == 0, "spell deducts 2 AP");
		r.Check(tc.PlayUnitCard(p0.Hand[0], new GridPos(5, 7)) == null, "cannot play without AP");

		tc.EndTurn();
		r.Check(state.CurrentPlayerIndex == 1 && state.TurnNumber == 2, "turn passes to player 1");
		r.Check(state.Phase == GamePhase.Main && state.Players[1].DraftOffer.Count == 0, "player 1 starts in Main phase");
		r.Check(state.Board.IsInDeployZone(1, new GridPos(0, 1)) && !state.Board.IsInDeployZone(1, new GridPos(0, 2)), "player 1 deploy rows are 0-1");
		r.Check(tc.PlayUnitCard(state.Players[1].Hand[0], new GridPos(3, 7)) == null, "player 1 cannot deploy in row 7");
		r.Check(tc.PlayUnitCard(state.Players[1].Hand[0], new GridPos(3, 1)) != null, "player 1 can deploy in row 1");

		var resUnit = Unit("Miner", apBonus: 1);
		state.SpawnPiece(resUnit, 0, new GridPos(0, 7));
		tc.EndTurn();
		r.Check(state.Players[0].ActionPoints == 4, "ApBonus adds to base AP");
	}

	private static void TestDraw(Report r)
	{
		var deck = UnitDeck(7);
		var state = new GameState(new GameConfig(), deck, new List<CardData>(deck), new Random(7));
		var tc = new TurnController(state);
		tc.StartGame();
		PlayerState p0 = state.Players[0];
		int Total() => p0.Hand.Count + p0.Deck.Count + p0.DraftOffer.Count;

		r.Check(p0.Deck.Count == 4 && p0.Hand.Count == 3, "deck 4 / hand 3 after dealing");
		r.Check(!tc.ChooseDraftCard(0), "cannot choose a draft card without drawing");
		r.Check(tc.CanDraw(), "can draw in main phase with AP and cards");
		r.Check(tc.Draw() && p0.ActionPoints == 2, "draw costs 1 AP");
		r.Check(state.Phase == GamePhase.Draft && p0.DraftOffer.Count == 3 && p0.Deck.Count == 1, "draw offers 3 cards (Draft phase)");
		r.Check(!tc.CanDraw() && !tc.Draw(), "cannot draw again while choosing");
		r.Check(tc.PlayUnitCard(p0.Hand[0], new GridPos(4, 6)) == null, "cannot play cards during draft");
		r.Check(tc.EndTurn().Count == 0 && state.Phase == GamePhase.Draft && state.CurrentPlayerIndex == 0, "cannot end turn during draft");
		r.Check(!tc.ChooseDraftCard(5), "invalid draft index rejected");
		CardData picked = p0.DraftOffer[1];
		r.Check(tc.ChooseDraftCard(1) && p0.Hand.Contains(picked) && p0.Hand.Count == 4, "chosen card goes to hand");
		r.Check(p0.DraftOffer.Count == 0 && p0.Deck.Count == 3 && state.Phase == GamePhase.Main, "rest returns to deck, back to Main");
		r.Check(Total() == 7, "card count conserved");

		r.Check(tc.Draw() && tc.ChooseDraftCard(0) && p0.ActionPoints == 1 && p0.Hand.Count == 5, "second draw in the same turn");
		r.Check(tc.Draw() && p0.DraftOffer.Count == 2 && tc.ChooseDraftCard(0) && p0.ActionPoints == 0, "third draw offers the remaining 2 cards");
		r.Check(!tc.CanDraw() && tc.LastError.Contains("AP"), "cannot draw without AP");
		r.Check(Total() == 7, "card count conserved after several draws");

		tc.EndTurn();
		r.Check(state.Phase == GamePhase.Main && state.Players[1].ActionPoints == 3 + state.Config.SecondPlayerFirstTurnBonusAp,
			"next turn starts in Main with full AP (+ second player bonus)");

		TurnController empty = NewGame(out GameState emptyState);
		r.Check(!empty.CanDraw() && !empty.Draw() && emptyState.Players[0].ActionPoints == 3, "cannot draw from an empty deck (no AP spent)");
	}

	private static void TestOrderCost(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		PlayerState p0 = state.Players[0];
		Piece a = SpawnReady(state, Unit("A", mov: 2), 0, new GridPos(4, 5));
		Piece b = SpawnReady(state, Unit("B", mov: 2), 0, new GridPos(6, 5));

		r.Check(tc.SetOrder(a, new GridPos(4, 4), null) && p0.ActionPoints == 2, "new order costs 1 AP");
		int index = a.Order.OrderIndex;
		r.Check(tc.SetOrder(a, new GridPos(4, 3), null) && p0.ActionPoints == 2 && a.Order.OrderIndex == index
			&& a.Order.MoveTarget == new GridPos(4, 3), "replacing an order is free and keeps its index");
		r.Check(tc.SetOrder(a, null, null) && a.Order == null && p0.ActionPoints == 3, "SetOrder(null, null) clears and refunds");
		r.Check(tc.SetOrder(a, new GridPos(4, 4), null) && p0.ActionPoints == 2, "re-order costs again");
		tc.ClearOrder(a);
		r.Check(a.Order == null && p0.ActionPoints == 3, "ClearOrder refunds");
		r.Check(tc.SetOrder(b, null, null) && p0.ActionPoints == 3, "clearing a piece without order is free");

		r.Check(tc.SetOrder(a, new GridPos(4, 4), null), "order A");
		p0.ActionPoints = 0;
		r.Check(!tc.CanSetOrder(b, new GridPos(6, 4), null) && tc.LastError.Contains("AP"), "new order rejected without AP");
		r.Check(!tc.SetOrder(b, new GridPos(6, 4), null) && b.Order == null && p0.ActionPoints == 0, "failed order changes nothing");
		r.Check(tc.SetOrder(a, new GridPos(3, 5), null) && p0.ActionPoints == 0, "replacing works with 0 AP");

		tc.EndTurn();
		r.Check(a.Order == null && p0.ActionPoints == 0, "orders cleared at end of turn without refund");
		r.Check(a.Position == new GridPos(3, 5), "replaced order was executed");
	}

	private static void TestSummoningSickness(Report r)
	{
		var deck = UnitDeck(6);
		var state = new GameState(new GameConfig(), deck, new List<CardData>(deck), new Random(3));
		var tc = new TurnController(state);
		tc.StartGame();
		PlayerState p0 = state.Players[0];

		Piece p = tc.PlayUnitCard(p0.Hand[0], new GridPos(4, 6));
		r.Check(p != null && p.SummonedTurn == 1 && p.IsSummoningSick(1), "played piece is summoning sick on turn 1");
		r.Check(!tc.CanCommand(p) && tc.LastError.Contains("Summoning"), "CanCommand false while sick");
		r.Check(!tc.SetOrder(p, new GridPos(4, 5), null) && p.Order == null && p0.ActionPoints == 2, "sick piece cannot get orders (no AP spent)");

		tc.EndTurn();
		r.Check(!tc.CanCommand(p), "opponent cannot command it on turn 2");
		tc.EndTurn();
		r.Check(state.TurnNumber == 3 && !p.IsSummoningSick(3) && tc.CanCommand(p), "commandable on owner's next turn");
		r.Check(tc.SetOrder(p, new GridPos(4, 5), null) && p0.ActionPoints == 2, "order on owner's next turn costs 1 AP");

		Piece spawned = state.SpawnPiece(Unit("Spawned"), 0, new GridPos(0, 7));
		r.Check(spawned.SummonedTurn == 3 && !tc.CanCommand(spawned), "SpawnPiece also marks summoning sickness");
	}

	private static void TestScoring(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		state.SpawnPiece(Unit("Z1"), 0, new GridPos(2, 3));
		state.SpawnPiece(Unit("Z2"), 0, new GridPos(7, 4));
		state.SpawnPiece(Unit("Out"), 0, new GridPos(1, 3));
		r.Check(state.Board.IsInScoringZone(new GridPos(2, 3)) && state.Board.IsInScoringZone(new GridPos(7, 4)), "zone corners inside");
		r.Check(!state.Board.IsInScoringZone(new GridPos(1, 3)) && !state.Board.IsInScoringZone(new GridPos(8, 4)) && !state.Board.IsInScoringZone(new GridPos(4, 5)), "outside zone");
		tc.EndTurn();
		tc.EndTurn();
		r.Check(state.Players[0].VictoryPoints == 2, "+1 VP per piece in zone at turn start");

		state.Players[0].VictoryPoints = 18;
		tc.EndTurn();
		tc.EndTurn();
		r.Check(state.Phase == GamePhase.GameOver && state.Winner == 0, "win at points target");
	}

	private static void TestShield(Report r)
	{
		NewGame(out GameState state);
		Piece p = state.SpawnPiece(Unit("Tank", hp: 3, shd: 2), 1, new GridPos(5, 2));
		var events = new List<ResolutionEvent>();
		OrderResolver.ApplyDamage(state, p, 3, -1, events);
		r.Check(p.CurrentShield == 0 && p.CurrentHp == 2, "3 dmg vs 2 shield/3 hp -> 0 shield, 2 hp");
		OrderResolver.ApplyDamage(state, p, 5, -1, events);
		r.Check(!p.IsAlive && state.GetPiece(p.Id) == null && !state.Board.IsOccupied(new GridPos(5, 2)), "piece dies and is removed");
		r.Check(events.Exists(e => e.Type == ResolutionEventType.Died), "Died event emitted");
	}

	private static void TestChain(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		// Row 5, player 0: A(2) B(3) C(4) enemy E(5).
		Piece a = SpawnReady(state, Unit("A", atk: 1), 0, new GridPos(2, 5));
		Piece b = SpawnReady(state, Unit("B", atk: 1), 0, new GridPos(3, 5));
		Piece c = SpawnReady(state, Unit("C", atk: 1), 0, new GridPos(4, 5));
		Piece e = SpawnReady(state, Unit("E", hp: 5), 1, new GridPos(5, 5));
		r.Check(tc.SetOrder(a, null, new GridPos(3, 5)), "A orders attack on friendly B");
		r.Check(tc.SetOrder(c, null, new GridPos(5, 5)), "C orders attack on enemy E");
		r.Check(!tc.SetOrder(a, null, new GridPos(5, 5)), "out-of-range attack rejected");
		r.Check(!tc.SetOrder(e, null, new GridPos(4, 5)), "cannot order enemy piece");

		List<ResolutionEvent> events = tc.EndTurn();
		int chains = events.FindAll(x => x.Type == ResolutionEventType.ChainTriggered).Count;
		r.Check(chains == 2, "chain A->B->C triggers twice");
		r.Check(b.CurrentHp == 3 && a.CurrentHp == 3 && c.CurrentHp == 3, "friendly hits deal no damage");
		r.Check(e.CurrentHp == 4, "enemy hit exactly once (C fires once, own order skipped)");
		// A piece "fires" either via its own (non-chain) attack or by being chain-triggered.
		var fireCount = new Dictionary<int, int>();
		foreach (ResolutionEvent ev in events)
		{
			if (ev.Type == ResolutionEventType.ChainTriggered || (ev.Type == ResolutionEventType.Attacked && !ev.IsChain))
			{
				fireCount[ev.PieceId] = fireCount.TryGetValue(ev.PieceId, out int n) ? n + 1 : 1;
			}
		}
		bool once = fireCount.Count == 3;
		foreach (int n in fireCount.Values)
		{
			once &= n == 1;
		}
		r.Check(once, "each unit fires exactly once");
	}

	private static void TestSpellExpiry(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece p = state.SpawnPiece(Unit("Target", atk: 1, hp: 3), 0, new GridPos(4, 6));
		CardData buff = Spell("Rage", atk: 2, hp: 2, shd: 1);
		state.Players[0].Hand.Add(buff);
		r.Check(tc.PlaySpellCard(buff, p), "cast spell turn 1");
		r.Check(p.EffectiveAttack == 3 && p.MaxHp == 5 && p.CurrentHp == 5 && p.TotalShield == 1, "modifiers applied");
		tc.EndTurn(); // end turn 1
		r.Check(p.ActiveSpells.Count == 1, "active during opponent's turn");
		tc.EndTurn(); // end turn 2
		r.Check(p.ActiveSpells.Count == 1 && p.EffectiveAttack == 3, "active during caster's next turn");
		tc.EndTurn(); // end turn 3 (caster's next turn)
		r.Check(p.ActiveSpells.Count == 0 && p.EffectiveAttack == 1 && p.MaxHp == 3 && p.CurrentHp == 3 && p.TotalShield == 0, "expired at end of caster's next turn");
	}

	// ------------------------------------------------------------------ rules v3

	private static GridPos G(int x, int y) => new GridPos(x, y);

	private static bool Has(IReadOnlyList<ResolutionEvent> events, ResolutionEventType type, int pieceId = int.MinValue)
	{
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

	private static void TestPlanningPassThrough(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece a = SpawnReady(state, Unit("A", mov: 2), 0, G(4, 6));
		SpawnReady(state, Unit("B"), 0, G(4, 5));
		SpawnReady(state, Unit("E"), 1, G(5, 6));

		List<GridPos> targets = tc.GetValidMoveTargets(a);
		r.Check(targets.Contains(G(4, 4)), "can plan a move through a friendly");
		r.Check(targets.Contains(G(4, 5)), "can plan a move ending on a friendly");
		r.Check(!targets.Contains(G(5, 6)) && !targets.Contains(G(6, 6)), "enemies still block (no end on / passing)");
		List<GridPos> path = tc.GetPlannedPath(a, G(4, 4));
		r.Check(path.Count == 2 && path[0] == G(4, 5) && path[1] == G(4, 4), "GetPlannedPath goes through the friendly");
		r.Check(tc.GetPlannedPath(a, G(6, 6)).Count == 0, "no planned path past an enemy");
		r.Check(tc.CanSetOrder(a, G(4, 5), null), "order onto a friendly tile accepted");
		r.Check(!tc.CanSetOrder(a, G(5, 6), null), "order onto an enemy tile rejected");
		r.Check(!state.Board.GetReachableTiles(G(4, 6), 2).Contains(G(4, 4)), "strict GetReachableTiles(from, mov) still blocks");
	}

	private static void TestPushResolution(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece a = SpawnReady(state, Unit("A", mov: 2), 0, G(4, 6));
		Piece b = SpawnReady(state, Unit("B"), 0, G(4, 5));
		tc.SetOrder(a, G(4, 4), null);
		tc.EndTurn();
		r.Check(a.Position == G(4, 4) && b.Position == G(4, 5), "mover passes through a friendly at resolution");

		tc = NewGame(out state);
		a = SpawnReady(state, Unit("A", mov: 1), 0, G(4, 6));
		b = SpawnReady(state, Unit("B"), 0, G(4, 5));
		Piece c = SpawnReady(state, Unit("C"), 0, G(4, 4));
		tc.SetOrder(a, G(4, 5), null);
		List<ResolutionEvent> ev = tc.EndTurn();
		r.Check(a.Position == G(4, 5) && b.Position == G(4, 4) && c.Position == G(4, 3), "ending on a friendly pushes it (chain push)");
		r.Check(Count(ev, ResolutionEventType.Pushed) == 2 && Has(ev, ResolutionEventType.Moved, a.Id), "Moved + 2 Pushed events");

		tc = NewGame(out state);
		a = SpawnReady(state, Unit("A", mov: 2), 0, G(4, 7));
		b = SpawnReady(state, Unit("B"), 0, G(4, 5));
		SpawnReady(state, Unit("E"), 1, G(4, 4));
		tc.SetOrder(a, G(4, 5), null);
		ev = tc.EndTurn();
		r.Check(a.Position == G(4, 6) && b.Position == G(4, 5), "impossible push: mover stops on the last free tile");
		r.Check(Has(ev, ResolutionEventType.PushBlocked, b.Id), "PushBlocked event");

		tc = NewGame(out state);
		a = SpawnReady(state, Unit("A", mov: 1), 0, G(4, 6));
		SpawnReady(state, Unit("B"), 0, G(4, 5));
		SpawnReady(state, Unit("E"), 1, G(4, 4));
		tc.SetOrder(a, G(4, 5), null);
		ev = tc.EndTurn();
		r.Check(a.Position == G(4, 6) && Has(ev, ResolutionEventType.MoveBlocked, a.Id), "no free tile on the path -> MoveBlocked");

		tc = NewGame(out state);
		a = SpawnReady(state, Unit("A", mov: 2), 0, G(4, 6));
		r.Check(tc.SetOrder(a, G(4, 4), null), "order through an empty tile");
		state.SpawnPiece(Unit("E"), 1, G(4, 5));
		ev = tc.EndTurn();
		r.Check(a.Position == G(4, 6) && Has(ev, ResolutionEventType.MoveBlocked, a.Id), "enemy appearing in the path blocks (MoveBlocked)");
	}

	private static void TestReturnToDeck(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece e = state.SpawnPiece(Unit("Victim", hp: 2), 1, G(5, 2));
		int before = state.Players[1].Deck.Count;
		var events = new List<ResolutionEvent>();
		OrderResolver.ApplyDamage(state, e, 5, -1, events);
		r.Check(state.Players[1].Deck.Count == before + 1 && state.Players[1].Deck.Contains(e.Source), "destroyed piece's card returns to the owner's deck");
		r.Check(events.Exists(x => x.Type == ResolutionEventType.ReturnedToDeck && x.PlayerIndex == 1 && x.Amount == 0), "ReturnedToDeck event");

		CardData card = Unit("Grimbone", atk: 1, hp: 2, kw: Keyword.Undying);
		Piece k = state.SpawnPiece(card, 0, G(3, 6));
		OrderResolver.ApplyDamage(state, k, 10, -1, events);
		List<CardData> deck0 = state.Players[0].Deck;
		CardData up = deck0.Count > 0 ? deck0[^1] : null;
		r.Check(up != null && up != card && up.Level == 1 && up.Attack == 2 && up.Hp == 3 && up.Name == "Grimbone +1"
			&& up.HasKeyword(Keyword.Undying), "Undying returns an upgraded copy (+1/+1, Level 1, name suffix)");
		r.Check(card.Level == 0 && card.Attack == 1 && card.Hp == 2 && card.Name == "Grimbone", "original card resource unchanged");
		Piece k2 = state.SpawnPiece(up, 0, G(3, 6));
		r.Check(k2 != null && k2.EffectiveAttack == 2 && k2.MaxHp == 3, "upgraded card spawns a stronger piece");
		OrderResolver.ApplyDamage(state, k2, 10, -1, events);
		CardData up2 = deck0[^1];
		r.Check(up2.Level == 2 && up2.Attack == 3 && up2.Hp == 4 && up2.Name == "Grimbone +2" && up2.BaseName == "Grimbone", "second death: level 2");

		tc = NewGame(out state);
		Piece att = SpawnReady(state, Unit("Att", atk: 3), 0, G(4, 5));
		Piece vic = SpawnReady(state, Unit("Vic", hp: 2), 1, G(4, 4));
		tc.SetOrder(att, null, G(4, 4));
		List<ResolutionEvent> ev = tc.EndTurn();
		r.Check(!vic.IsAlive && state.Players[1].Deck.Contains(vic.Source) && Has(ev, ResolutionEventType.ReturnedToDeck, vic.Id),
			"kill during resolution returns the card too");
	}

	private static void TestVpToAp(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		PlayerState p0 = state.Players[0];
		r.Check(!tc.CanConvertVpToAp() && !tc.ConvertVpToAp(), "cannot convert without VP");
		p0.VictoryPoints = 3;
		r.Check(tc.ConvertVpToAp() && p0.VictoryPoints == 2 && p0.ActionPoints == 4 && tc.VpConvertedThisTurn == 1
			&& tc.RemainingVpConversions == 1, "1 VP -> 1 AP");
		r.Check(tc.ConvertVpToAp() && p0.VictoryPoints == 1 && p0.ActionPoints == 5 && tc.RemainingVpConversions == 0, "second conversion");
		r.Check(!tc.CanConvertVpToAp() && !tc.ConvertVpToAp() && p0.VictoryPoints == 1 && p0.ActionPoints == 5, "max 2 per turn");
		tc.EndTurn();
		tc.EndTurn();
		r.Check(tc.VpConvertedThisTurn == 0 && tc.CanConvertVpToAp(), "limit resets on the next own turn");
	}

	private static void TestSecondPlayerBonus(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		int bonus = state.Config.SecondPlayerFirstTurnBonusAp;
		r.Check(bonus == 1 && state.Players[0].ActionPoints == 3, "first player: base AP");
		tc.EndTurn();
		r.Check(state.Players[1].ActionPoints == 3 + bonus, "second player: +1 AP on its first turn");
		tc.EndTurn();
		tc.EndTurn();
		r.Check(state.CurrentPlayerIndex == 1 && state.Players[1].ActionPoints == 3, "bonus only on the first turn");
	}

	private static void TestTileTicks(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece e = SpawnReady(state, Unit("E", hp: 3), 1, G(5, 2));
		Piece f = SpawnReady(state, Unit("F", hp: 3), 0, G(5, 6));
		Place(state, TileEffectType.Lava, G(5, 2));
		Place(state, TileEffectType.Lava, G(5, 6));
		tc.EndTurn(); // turn 2 (P1) starts
		r.Check(e.CurrentHp == 2, "lava damages at the start of the occupant owner's turn");
		r.Check(f.CurrentHp == 3, "lava does not tick for the other player's pieces");
		r.Check(Has(tc.LastTurnStartEvents, ResolutionEventType.TileDamage, e.Id) && Has(tc.LastTurnStartEvents, ResolutionEventType.Damaged, e.Id),
			"TileDamage + Damaged in LastTurnStartEvents");
		tc.EndTurn(); // turn 3 (P0)
		r.Check(f.CurrentHp == 2, "lava ticks for player 0 on its turn");
		List<ResolutionEvent> ev = tc.EndTurn(); // end of turn 3: lava (created turn 1, duration 2) expires
		r.Check(state.Board.GetTileEffect(G(5, 2)) == null && Has(ev, ResolutionEventType.TileEffectExpired), "lava expires at the end of turn created + duration");
		r.Check(e.CurrentHp == 2, "no tick after expiry");

		f.CurrentHp = 1;
		Place(state, TileEffectType.Healing, f.Position);
		tc.EndTurn(); // turn 5 (P0)
		r.Check(f.CurrentHp == 2 && Has(tc.LastTurnStartEvents, ResolutionEventType.TileHeal, f.Id), "healing tile heals 1 at owner's turn start");

		Piece weak = SpawnReady(state, Unit("Weak", hp: 1), 1, G(7, 1));
		Place(state, TileEffectType.Lava, G(7, 1));
		int deckBefore = state.Players[1].Deck.Count;
		tc.EndTurn(); // turn 6 (P1)
		r.Check(!weak.IsAlive && Has(tc.LastTurnStartEvents, ResolutionEventType.Died, weak.Id)
			&& state.Players[1].Deck.Count == deckBefore + 1, "lava can kill (card returns to deck)");
	}

	private static void TestWalls(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece a = SpawnReady(state, Unit("A", mov: 2), 0, G(4, 6));
		r.Check(OrderResolver.ApplyTileEffect(state, TileEffectType.Wall, G(4, 5), 2, 0, "Test", -1, null), "wall placed");
		List<GridPos> targets = tc.GetValidMoveTargets(a);
		r.Check(!targets.Contains(G(4, 5)) && !targets.Contains(G(4, 4)), "wall is impassable and unoccupiable");
		r.Check(!OrderResolver.ApplyTileEffect(state, TileEffectType.Wall, a.Position, 2, 0, "Test", -1, null), "no wall on an occupied tile");
		Place(state, TileEffectType.Wall, G(2, 6));
		CardData unit = Unit("Deploy");
		state.Players[0].Hand.Add(unit);
		r.Check(!tc.CanPlayUnitCard(unit, G(2, 6)) && tc.LastError.Contains("wall"), "cannot deploy on a wall");

		Piece x = SpawnReady(state, Unit("X"), 0, G(7, 7));
		SpawnReady(state, Unit("T", rng: 2), 0, G(7, 6));
		Piece en = SpawnReady(state, Unit("En"), 1, G(9, 6));
		Place(state, TileEffectType.Wall, G(8, 6));
		tc.SetOrder(x, null, G(7, 6));
		tc.EndTurn(); // end turn 1
		r.Check(en.CurrentHp == 3, "wall stops a sideways chain shot");
		r.Check(state.Board.IsWall(G(4, 5)), "wall active during the opponent's turn");
		tc.EndTurn(); // end turn 2
		r.Check(state.Board.IsWall(G(4, 5)), "wall active during the creator's next turn");
		List<ResolutionEvent> ev = tc.EndTurn(); // end turn 3
		r.Check(!state.Board.IsWall(G(4, 5)) && Has(ev, ResolutionEventType.TileEffectExpired), "wall expired (TileEffectExpired)");
		r.Check(tc.GetValidMoveTargets(state.GetPiece(a.Id)).Count >= 0 && state.Board.IsPassable(G(4, 5)), "tile passable again");
	}

	private static void TestTileSpells(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		PlayerState p0 = state.Players[0];
		var meteor = new CardData
		{
			Name = "Meteor", CardType = CardType.Spell, ApCost = 2, SpellTarget = SpellTargetType.Area, AreaShape = AreaShape.Plus,
			TileEffect = TileEffectType.Lava, TileEffectDuration = 2, SpellDamage = 1,
		};
		p0.Hand.Add(meteor);
		Piece e1 = SpawnReady(state, Unit("E1", hp: 3), 1, G(5, 3));
		Piece e2 = SpawnReady(state, Unit("E2", hp: 1), 1, G(5, 2));
		Piece f = SpawnReady(state, Unit("F", hp: 3), 0, G(4, 3));
		r.Check(tc.GetSpellAreaPreview(meteor, G(5, 3)).Count == 5 && tc.GetSpellAreaPreview(meteor, G(0, 0)).Count == 3, "area preview (plus, clipped)");
		r.Check(tc.CanPlaySpellCard(meteor, e1) && tc.CanCastSpellAt(meteor, G(5, 3)), "tile spell castable (also via piece redirect)");
		r.Check(tc.PlaySpellOnTile(meteor, G(5, 3)) && p0.ActionPoints == 1 && !p0.Hand.Contains(meteor), "PlaySpellOnTile pays AP");
		r.Check(e1.CurrentHp == 2 && !e2.IsAlive && f.CurrentHp == 3, "area damage hits enemies only");
		bool allLava = true;
		foreach (GridPos p in tc.GetSpellAreaPreview(meteor, G(5, 3)))
		{
			allLava &= state.Board.GetTileEffectType(p) == TileEffectType.Lava;
		}
		r.Check(allLava, "lava on every area tile");
		r.Check(tc.LastSpellEvents.Count > 0 && tc.LastSpellEvents[0].Type == ResolutionEventType.SpellCast
			&& Has(tc.LastSpellEvents, ResolutionEventType.Died, e2.Id) && Count(tc.LastSpellEvents, ResolutionEventType.TileEffectApplied) == 5,
			"LastSpellEvents: SpellCast, Died, 5x TileEffectApplied");

		CardData buff = Spell("Buff", atk: 1);
		p0.Hand.Add(buff);
		r.Check(!tc.CanPlaySpellOnTile(buff, G(5, 5)), "piece spell cannot target a tile");
		var wall = new CardData
		{
			Name = "Stone Wall", CardType = CardType.Spell, ApCost = 1, SpellTarget = SpellTargetType.Area, AreaShape = AreaShape.Row3,
			TileEffect = TileEffectType.Wall, TileEffectDuration = 2,
		};
		p0.Hand.Add(wall);
		r.Check(tc.PlaySpellOnTile(wall, G(4, 4)) && state.Board.IsWall(G(3, 4)) && state.Board.IsWall(G(4, 4)) && state.Board.IsWall(G(5, 4))
			&& p0.ActionPoints == 0, "stone wall: 3 wall tiles in a row");
	}

	private static void TestBurning(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece fa = SpawnReady(state, Unit("FA", mov: 1, atk: 1, hp: 2, rng: 3, kw: Keyword.Burning), 0, G(2, 5));
		Piece e = SpawnReady(state, Unit("E", hp: 5), 1, G(2, 3));
		tc.SetOrder(fa, null, G(2, 3));
		List<ResolutionEvent> ev = tc.EndTurn();
		r.Check(Has(ev, ResolutionEventType.TileEffectApplied) && state.Board.GetTileEffectType(G(2, 3)) == TileEffectType.Lava, "Burning hit leaves lava");
		r.Check(e.CurrentHp == 3, "1 attack damage + 1 lava tick at the victim's turn start");
	}

	private static void TestFrost(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece m = SpawnReady(state, Unit("M", rng: 2, kw: Keyword.Frost), 0, G(2, 5));
		Piece e = SpawnReady(state, Unit("E", mov: 2, hp: 5), 1, G(4, 5));
		tc.SetOrder(m, null, G(4, 5));
		tc.EndTurn(); // P1's turn
		r.Check(e.IsFrozen && e.HasStatus(StatusEffectType.Frozen) && e.EffectiveMovement == 0, "Frost: target is Frozen");
		r.Check(!tc.CanSetOrder(e, G(4, 4), null) && tc.GetValidMoveTargets(e).Count == 0, "Frozen piece cannot move");
		r.Check(tc.CanSetOrder(e, null, G(3, 5)), "Frozen piece can still attack");
		List<ResolutionEvent> ev = tc.EndTurn();
		r.Check(!e.IsFrozen && e.EffectiveMovement == 2 && Has(ev, ResolutionEventType.StatusExpired, e.Id), "Frozen expires after the victim's turn");
	}

	private static void TestPushKeyword(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece ram = SpawnReady(state, Unit("Ram", mov: 1, atk: 2, hp: 4, kw: Keyword.Push), 0, G(2, 5));
		Piece e = SpawnReady(state, Unit("E", hp: 5), 1, G(3, 5));
		tc.SetOrder(ram, null, G(3, 5));
		List<ResolutionEvent> ev = tc.EndTurn();
		r.Check(e.Position == G(4, 5) && e.CurrentHp == 3 && Has(ev, ResolutionEventType.Pushed, e.Id), "Push knocks the target 1 tile away");

		tc = NewGame(out state);
		ram = SpawnReady(state, Unit("Ram", mov: 1, atk: 2, hp: 4, kw: Keyword.Push), 0, G(2, 5));
		e = SpawnReady(state, Unit("E", hp: 5), 1, G(3, 5));
		Place(state, TileEffectType.Wall, G(4, 5));
		tc.SetOrder(ram, null, G(3, 5));
		ev = tc.EndTurn();
		r.Check(e.Position == G(3, 5) && Has(ev, ResolutionEventType.PushBlocked, e.Id), "Push into a wall is blocked");
	}

	private static void TestPierce(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece l = SpawnReady(state, Unit("L", atk: 2, kw: Keyword.Pierce), 0, G(2, 5));
		Piece e1 = SpawnReady(state, Unit("E1", hp: 5), 1, G(3, 5));
		Piece e2 = SpawnReady(state, Unit("E2", hp: 5), 1, G(4, 5));
		tc.SetOrder(l, null, G(3, 5));
		List<ResolutionEvent> ev = tc.EndTurn();
		r.Check(e1.CurrentHp == 3 && e2.CurrentHp == 3 && ev.Exists(x => x.Type == ResolutionEventType.Attacked && x.IsPierce),
			"Pierce also hits the piece behind");

		tc = NewGame(out state);
		l = SpawnReady(state, Unit("L", atk: 2, kw: Keyword.Pierce), 0, G(2, 5));
		e1 = SpawnReady(state, Unit("E1", hp: 5), 1, G(3, 5));
		Piece f = SpawnReady(state, Unit("F"), 0, G(4, 5));
		Piece e3 = SpawnReady(state, Unit("E3", hp: 5), 1, G(5, 5));
		tc.SetOrder(l, null, G(3, 5));
		ev = tc.EndTurn();
		r.Check(Has(ev, ResolutionEventType.ChainTriggered, f.Id) && e1.CurrentHp == 2 && e3.CurrentHp == 4, "Pierce chain-triggers a friendly behind");
	}

	private static void TestMending(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece c = SpawnReady(state, Unit("C", rng: 2, kw: Keyword.Mending), 0, G(2, 6));
		Piece f = SpawnReady(state, Unit("F", hp: 3), 0, G(3, 6));
		f.CurrentHp = 1;
		Piece e = SpawnReady(state, Unit("E", hp: 5), 1, G(4, 6));
		tc.SetOrder(c, null, G(3, 6));
		List<ResolutionEvent> ev = tc.EndTurn();
		r.Check(f.CurrentHp == 2 && Has(ev, ResolutionEventType.Healed, f.Id), "Mending heals the friendly");
		r.Check(Has(ev, ResolutionEventType.ChainTriggered, f.Id) && e.CurrentHp == 4, "and still triggers its chain");
	}

	private static void TestConduit(Report r)
	{
		foreach (bool conduit in new[] { true, false })
		{
			TurnController tc = NewGame(out GameState state);
			Piece a = SpawnReady(state, Unit("A"), 0, G(2, 6));
			SpawnReady(state, Unit("T", rng: 2, kw: conduit ? Keyword.Conduit : Keyword.None), 0, G(3, 6));
			Piece e = SpawnReady(state, Unit("E", hp: 5), 1, G(3, 4));
			tc.SetOrder(a, null, G(3, 6));
			tc.EndTurn();
			r.Check(e.CurrentHp == (conduit ? 4 : 5), conduit ? "Conduit fires forward too" : "without Conduit only sideways");
		}
	}

	private static void TestEchoOvercharge(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece a = SpawnReady(state, Unit("A"), 0, G(2, 6));
		SpawnReady(state, Unit("B", rng: 2, kw: Keyword.Echo), 0, G(3, 6));
		Piece e = SpawnReady(state, Unit("E", hp: 5), 1, G(4, 6));
		tc.SetOrder(a, null, G(3, 6));
		tc.EndTurn();
		r.Check(e.CurrentHp == 3, "Echo chain shot deals +1");

		tc = NewGame(out state);
		a = SpawnReady(state, Unit("A"), 0, G(2, 6));
		Piece b = SpawnReady(state, Unit("B"), 0, G(3, 6));
		e = SpawnReady(state, Unit("E", hp: 5), 1, G(4, 6));
		var over = new CardData { Name = "Overcharge", CardType = CardType.Spell, ApCost = 1, GrantStatus = StatusEffectType.Overcharged };
		state.Players[0].Hand.Add(over);
		r.Check(tc.PlaySpellCard(over, b) && b.HasStatus(StatusEffectType.Overcharged) && b.ActiveSpells.Count == 0, "Overcharge grants the status");
		tc.SetOrder(a, null, G(3, 6));
		List<ResolutionEvent> ev = tc.EndTurn();
		r.Check(e.CurrentHp == 3 && !b.HasStatus(StatusEffectType.Overcharged)
			&& ev.Exists(x => x.Type == ResolutionEventType.StatusExpired && x.IsChain), "Overcharged chain shot deals double and is consumed");
	}

	private static void TestChainPreview(Report r)
	{
		TurnController tc = NewGame(out GameState state);
		Piece a = SpawnReady(state, Unit("A"), 0, G(2, 6));
		Piece t = SpawnReady(state, Unit("T", rng: 2, kw: Keyword.Conduit | Keyword.Burning), 0, G(3, 6));
		Piece b = SpawnReady(state, Unit("B", rng: 2, kw: Keyword.Echo), 0, G(5, 6));
		Piece e1 = SpawnReady(state, Unit("E1", hp: 3), 1, G(6, 6));
		Piece e2 = SpawnReady(state, Unit("E2", hp: 1), 1, G(3, 4));

		ChainPreview p = tc.PredictAttack(a, a.Position, G(3, 6));
		r.Check(p.IsValid && p.TriggeredPieceIds.Contains(t.Id) && p.TriggeredPieceIds.Contains(b.Id), "preview: both friendlies triggered");
		r.Check(p.KilledPieceIds.Contains(e2.Id) && p.EnemyKills == 1 && p.NewTileEffects.Count == 1, "preview: kill + burning lava");
		PredictedHit hitE1 = p.Hits.Find(h => h.TargetPieceId == e1.Id);
		r.Check(hitE1 != null && hitE1.Damage == 2 && hitE1.IsChain && !hitE1.IsFriendly, "preview: Echo hit on E1 for 2");
		r.Check(e1.CurrentHp == 3 && e2.IsAlive && state.Board.TileEffects.Count == 0 && state.Players[1].Deck.Count == 0
			&& t.Position == G(3, 6), "preview does not mutate the real state");
		r.Check(!tc.PredictAttack(a, a.Position, G(5, 6)).IsValid, "out-of-range preview is invalid");

		tc.SetOrder(a, null, G(3, 6));
		List<ResolutionEvent> ev = tc.EndTurn();
		bool same = ev.Count >= p.Events.Count;
		for (int i = 0; same && i < p.Events.Count; i++)
		{
			ResolutionEvent x = p.Events[i];
			ResolutionEvent y = ev[i];
			same = x.Type == y.Type && x.PieceId == y.PieceId && x.OtherPieceId == y.OtherPieceId && x.From == y.From && x.To == y.To
				&& x.Amount == y.Amount && x.HpLost == y.HpLost && x.IsChain == y.IsChain && x.IsPierce == y.IsPierce;
		}
		r.Check(same && p.Events.Count > 5, "preview events == actual resolution events");
		r.Check(e1.CurrentHp == 1 && !e2.IsAlive, "actual result matches the preview");

		tc = NewGame(out state);
		a = SpawnReady(state, Unit("A", mov: 2), 0, G(2, 7));
		SpawnReady(state, Unit("F"), 0, G(2, 6));
		Piece en = SpawnReady(state, Unit("En", hp: 3), 1, G(2, 4));
		ChainPreview moved = tc.PredictAttack(a, G(2, 5), G(2, 4));
		r.Check(moved.IsValid && moved.EnemyHpLost == 1 && en.CurrentHp == 3, "preview from a planned position through a friendly");
	}

	private static void TestStarterDeck(Report r)
	{
		DeckData deck = Godot.GD.Load<DeckData>("res://Resources/Decks/StarterDeck.tres");
		r.Check(deck != null && deck.Cards != null && deck.Cards.Count == 20, "StarterDeck.tres loads with 20 cards");
		if (deck == null)
		{
			return;
		}
		int keywordCards = 0;
		int tileSpells = 0;
		bool allValid = true;
		var cards = new List<CardData>();
		foreach (CardData c in deck.Cards)
		{
			allValid &= c != null && !string.IsNullOrEmpty(c.Name);
			if (c == null)
			{
				continue;
			}
			cards.Add(c);
			keywordCards += c.Keywords != Keyword.None ? 1 : 0;
			tileSpells += c.TargetsTile ? 1 : 0;
		}
		r.Check(allValid && keywordCards >= 8 && tileSpells >= 3, $"deck has keyword units ({keywordCards}) and tile spells ({tileSpells})");
		var state = new GameState(new GameConfig(), cards, new List<CardData>(cards), new Random(5));
		var tc = new TurnController(state);
		tc.StartGame();
		r.Check(state.Players[0].Hand.Count == 3 && state.Players[0].Deck.Count == 17, "game starts with the deck");
	}
}
