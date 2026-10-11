using System;
using System.Collections.Generic;
using System.Text;

namespace ProjectClaude;

/// <summary>
/// AI vs. AI smoke test: builds games from in-memory cards, lets SimpleAi play both sides via
/// TakeTurn + EndTurn and checks state consistency after every step. Must run inside Godot
/// (CardData/GameConfig are Resources). Call Run() and print the report.
/// </summary>
public static class AiSelfTest
{
	private const int MaxTurns = 40;

	/// <summary>Runs several seeded AI-vs-AI games and returns a human-readable report.</summary>
	public static string Run()
	{
		var sb = new StringBuilder();
		sb.AppendLine("AiSelfTest");
		int failures = 0;
		foreach (int seed in new[] { 1, 2, 3 })
		{
			failures += RunGame(seed, MaxTurns, sb, BuildDeck("A"), BuildDeck("B"));
		}
		DeckData starter = Godot.GD.Load<DeckData>("res://Resources/Decks/StarterDeck.tres");
		if (starter == null || starter.Cards == null || starter.Cards.Count == 0)
		{
			sb.AppendLine("  [FAIL] could not load res://Resources/Decks/StarterDeck.tres");
			failures++;
		}
		else
		{
			var cards = new List<CardData>();
			foreach (CardData c in starter.Cards)
			{
				if (c != null)
				{
					cards.Add(c);
				}
			}
			foreach (int seed in new[] { 4, 5 })
			{
				failures += RunGame(seed, MaxTurns * 2, sb, cards, new List<CardData>(cards));
			}
		}
		sb.AppendLine(failures == 0 ? "Result: PASS" : $"Result: FAIL ({failures} problem(s))");
		return sb.ToString();
	}

	private static int RunGame(int seed, int maxTurns, StringBuilder sb, List<CardData> deck0, List<CardData> deck1)
	{
		var errors = new List<string>();
		var actionCounts = new Dictionary<AiActionKind, int>();
		var eventCounts = new Dictionary<ResolutionEventType, int>();
		int turnsPlayed = 0;
		GameState state = null;

		try
		{
			var config = new GameConfig();
			state = new GameState(config, deck0, deck1, new Random(seed));
			var controller = new TurnController(state);
			var ais = new[] { new SimpleAi(controller, 0), new SimpleAi(controller, 1) };
			int[] totalCards = { state.Players[0].Deck.Count, state.Players[1].Deck.Count };
			// Spells cast are consumed; units return to the deck when destroyed (pieces on board are counted live).
			int[] played = { 0, 0 };
			int[] lastVp = { 0, 0 };

			controller.StartGame();

			while (turnsPlayed < maxTurns && state.Phase != GamePhase.GameOver)
			{
				int current = state.CurrentPlayerIndex;
				int turnBefore = state.TurnNumber;
				int apBefore = state.Players[current].ActionPoints;
				if (state.Phase != GamePhase.Main)
				{
					errors.Add($"turn {turnBefore}: turn did not start in Main phase ({state.Phase})");
				}

				List<AiAction> actions = ais[current].TakeTurn();
				List<AiAction> other = ais[1 - current].TakeTurn();
				if (other.Count > 0)
				{
					errors.Add($"turn {turnBefore}: AI of inactive player acted");
				}
				if (state.Phase != GamePhase.Main)
				{
					errors.Add($"turn {turnBefore}: phase after TakeTurn is {state.Phase}, expected Main");
					break;
				}
				foreach (AiAction a in actions)
				{
					actionCounts.TryGetValue(a.Kind, out int n);
					actionCounts[a.Kind] = n + 1;
					if (a.Kind == AiActionKind.PlaySpell)
					{
						played[current]++;
					}
					if (a.PlayerIndex != current)
					{
						errors.Add($"turn {turnBefore}: action recorded for wrong player");
					}
				}
				if (state.Players[current].ActionPoints < 0)
				{
					errors.Add($"turn {turnBefore}: negative AP");
				}
				int spent = 0;
				foreach (AiAction a in actions)
				{
					spent += a.Kind switch
					{
						AiActionKind.Draft => config.DrawApCost,
						AiActionKind.PlayUnit or AiActionKind.PlaySpell => controller.GetCardCost(a.Card),
						AiActionKind.SetOrder => config.OrderApCost,
						AiActionKind.ConvertVp => -1,
						_ => 0,
					};
				}
				if (apBefore - spent != state.Players[current].ActionPoints)
				{
					errors.Add($"turn {turnBefore}: AP accounting {apBefore} - {spent} != {state.Players[current].ActionPoints}");
				}
				int converted = state.Players[current].VpConvertedThisTurn;
				int convertActions = actions.FindAll(a => a.Kind == AiActionKind.ConvertVp).Count;
				if (converted != convertActions || converted > config.MaxVpToApPerTurn)
				{
					errors.Add($"turn {turnBefore}: VP conversions {converted} (actions {convertActions}, max {config.MaxVpToApPerTurn})");
				}
				lastVp[current] -= converted;
				if (state.Players[current].VictoryPoints != lastVp[current])
				{
					errors.Add($"turn {turnBefore}: VP of P{current} changed during TakeTurn beyond conversions");
				}
				CheckOrders(state, current, actions, turnBefore, errors);
				CheckConsistency(state, totalCards, played, turnBefore, "after TakeTurn", errors);

				List<ResolutionEvent> events = controller.EndTurn();
				var allEvents = new List<ResolutionEvent>(events);
				allEvents.AddRange(controller.LastTurnStartEvents);
				foreach (ResolutionEvent e in allEvents)
				{
					eventCounts.TryGetValue(e.Type, out int n);
					eventCounts[e.Type] = n + 1;
				}
				turnsPlayed++;

				if (state.Phase != GamePhase.GameOver)
				{
					if (state.CurrentPlayerIndex != 1 - current)
					{
						errors.Add($"turn {turnBefore}: player did not swap");
					}
					if (state.TurnNumber != turnBefore + 1)
					{
						errors.Add($"turn {turnBefore}: turn number did not advance");
					}
				}
				foreach (Piece p in state.Pieces)
				{
					if (p.Order != null)
					{
						errors.Add($"turn {turnBefore}: order not cleared on {p}");
					}
				}
				for (int i = 0; i < GameState.PlayerCount; i++)
				{
					if (state.Players[i].VictoryPoints < lastVp[i])
					{
						errors.Add($"turn {turnBefore}: VP of P{i} decreased");
					}
					lastVp[i] = state.Players[i].VictoryPoints;
				}
				CheckConsistency(state, totalCards, played, turnBefore, "after EndTurn", errors);

				if (errors.Count > 20)
				{
					break;
				}
			}
		}
		catch (Exception e)
		{
			errors.Add($"exception after {turnsPlayed} turns: {e.GetType().Name}: {e.Message}\n{e.StackTrace}");
		}

		sb.AppendLine($"Game seed {seed}: {turnsPlayed} turns, winner {(state != null && state.Winner >= 0 ? "P" + state.Winner : "none")}, " +
			$"VP {state?.Players[0].VictoryPoints ?? 0}:{state?.Players[1].VictoryPoints ?? 0}, " +
			$"pieces alive {state?.GetPiecesOf(0).Count ?? 0}:{state?.GetPiecesOf(1).Count ?? 0}");
		sb.AppendLine("  actions: " + FormatCounts(actionCounts));
		sb.AppendLine("  events:  " + FormatCounts(eventCounts));
		if (errors.Count == 0)
		{
			sb.AppendLine("  [PASS] no exceptions, state consistent");
		}
		foreach (string err in errors)
		{
			sb.AppendLine("  [FAIL] " + err);
		}
		return errors.Count;
	}

	private static void CheckOrders(GameState state, int player, List<AiAction> actions, int turn, List<string> errors)
	{
		int orderActions = 0;
		foreach (AiAction a in actions)
		{
			if (a.Kind == AiActionKind.SetOrder)
			{
				orderActions++;
			}
		}
		int queued = 0;
		foreach (Piece p in state.Pieces)
		{
			if (p.Order == null)
			{
				continue;
			}
			queued++;
			if (p.OwnerIndex != player)
			{
				errors.Add($"turn {turn}: order on a piece of the inactive player {p}");
			}
			if (p.IsSummoningSick(state.TurnNumber))
			{
				errors.Add($"turn {turn}: summoning-sick piece received an order {p}");
			}
		}
		if (queued != orderActions)
		{
			errors.Add($"turn {turn}: {queued} queued orders but {orderActions} SetOrder actions");
		}

		foreach (AiAction a in actions)
		{
			if (a.Kind != AiActionKind.SetOrder)
			{
				continue;
			}
			Piece p = state.GetPiece(a.PieceId);
			if (p == null || p.OwnerIndex != player || p.Order == null)
			{
				errors.Add($"turn {turn}: SetOrder action without a queued order (piece {a.PieceId})");
				continue;
			}
			if (p.Order.MoveTarget != a.MoveTarget || p.Order.AttackTarget != a.AttackTarget)
			{
				errors.Add($"turn {turn}: recorded order differs from queued order on {p}");
			}
			if (a.AttackTarget.HasValue)
			{
				Piece target = state.Board.GetPieceAt(a.AttackTarget.Value);
				if (target == null)
				{
					errors.Add($"turn {turn}: {p} attacks an empty tile {a.AttackTarget.Value}");
				}
			}
		}
	}

	private static void CheckConsistency(GameState state, int[] totalCards, int[] played, int turn, string when, List<string> errors)
	{
		BoardState board = state.Board;
		if (board.Occupancy.Count != state.Pieces.Count)
		{
			errors.Add($"turn {turn} {when}: occupancy {board.Occupancy.Count} != pieces {state.Pieces.Count}");
		}
		var ids = new HashSet<int>();
		foreach (Piece p in state.Pieces)
		{
			if (!ids.Add(p.Id))
			{
				errors.Add($"turn {turn} {when}: duplicate piece id {p.Id}");
			}
			if (!p.IsAlive)
			{
				errors.Add($"turn {turn} {when}: dead piece still listed {p}");
			}
			if (!board.IsInside(p.Position) || board.GetPieceAt(p.Position) != p)
			{
				errors.Add($"turn {turn} {when}: piece/board mismatch {p}");
			}
			if (p.CurrentHp > p.MaxHp || p.CurrentShield < 0 || p.TotalShield < 0)
			{
				errors.Add($"turn {turn} {when}: invalid HP/shield {p}");
			}
			if (board.IsWall(p.Position))
			{
				errors.Add($"turn {turn} {when}: piece stands on a wall {p}");
			}
		}
		foreach (TileEffect effect in board.TileEffects.Values)
		{
			if (effect.ExpiryTurn < state.TurnNumber)
			{
				errors.Add($"turn {turn} {when}: stale tile effect {effect}");
			}
		}
		for (int i = 0; i < GameState.PlayerCount; i++)
		{
			PlayerState ps = state.Players[i];
			if (ps.VictoryPoints < 0)
			{
				errors.Add($"turn {turn} {when}: negative VP of P{i}");
			}
			int cards = ps.Hand.Count + ps.Deck.Count + ps.DraftOffer.Count + played[i] + state.GetPiecesOf(i).Count;
			if (cards != totalCards[i])
			{
				errors.Add($"turn {turn} {when}: card count of P{i} is {cards}, expected {totalCards[i]}");
			}
		}
	}

	private static string FormatCounts<T>(Dictionary<T, int> counts)
	{
		if (counts.Count == 0)
		{
			return "-";
		}
		var parts = new List<string>();
		foreach (KeyValuePair<T, int> kv in counts)
		{
			parts.Add($"{kv.Key}={kv.Value}");
		}
		return string.Join(", ", parts);
	}

	private static List<CardData> BuildDeck(string tag)
	{
		var deck = new List<CardData>();
		for (int i = 0; i < 2; i++)
		{
			deck.Add(Unit($"{tag} Soldier {i}", UnitRole.Attack, mov: 2, atk: 2, hp: 3));
			deck.Add(Unit($"{tag} Archer {i}", UnitRole.Attack, mov: 2, atk: 1, hp: 2, rng: 3));
			deck.Add(Unit($"{tag} Guard {i}", UnitRole.Utility, mov: 1, atk: 1, hp: 4, shd: 2));
			deck.Add(Unit($"{tag} Scout {i}", UnitRole.Utility, mov: 3, atk: 1, hp: 2));
			deck.Add(Unit($"{tag} Miner {i}", UnitRole.Resource, mov: 1, atk: 0, hp: 3, apBonus: 1));
			deck.Add(Spell($"{tag} Rage {i}", atkDelta: 2));
			deck.Add(Spell($"{tag} Bulwark {i}", shdDelta: 2, hpDelta: 1));
			deck.Add(Spell($"{tag} Weaken {i}", atkDelta: -1, movDelta: -1));
		}
		deck.Add(Unit($"{tag} Totem", UnitRole.Utility, mov: 0, atk: 1, hp: 3, rng: 2, kw: Keyword.Conduit));
		deck.Add(Unit($"{tag} Flame Archer", UnitRole.Attack, mov: 1, atk: 1, hp: 2, rng: 3, kw: Keyword.Burning));
		deck.Add(Unit($"{tag} Ram", UnitRole.Attack, mov: 1, atk: 2, hp: 4, kw: Keyword.Push));
		deck.Add(Unit($"{tag} Bone Knight", UnitRole.Attack, mov: 2, atk: 1, hp: 2, kw: Keyword.Undying));
		deck.Add(new CardData
		{
			Name = $"{tag} Meteor", CardType = CardType.Spell, SpellTarget = SpellTargetType.Area, AreaShape = AreaShape.Plus,
			TileEffect = TileEffectType.Lava, TileEffectDuration = 2, SpellDamage = 1,
		});
		deck.Add(new CardData
		{
			Name = $"{tag} Stone Wall", CardType = CardType.Spell, ApCost = 1, SpellTarget = SpellTargetType.Area,
			AreaShape = AreaShape.Row3, TileEffect = TileEffectType.Wall, TileEffectDuration = 2,
		});
		return deck;
	}

	private static CardData Unit(string name, UnitRole role, int mov, int atk, int hp, int rng = 1, int shd = 0, int apBonus = 0,
		Keyword kw = Keyword.None) =>
		new CardData
		{
			Name = name,
			CardType = CardType.Unit,
			Role = role,
			Movement = mov,
			Attack = atk,
			Hp = hp,
			Range = rng,
			Shield = shd,
			ApBonus = apBonus,
			Keywords = kw,
		};

	private static CardData Spell(string name, int atkDelta = 0, int hpDelta = 0, int shdDelta = 0, int movDelta = 0) =>
		new CardData
		{
			Name = name,
			CardType = CardType.Spell,
			AttackDelta = atkDelta,
			HpDelta = hpDelta,
			ShieldDelta = shdDelta,
			MovementDelta = movDelta,
		};
}
