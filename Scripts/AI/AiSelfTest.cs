using System;
using System.Collections.Generic;
using System.Text;

namespace Realmshatter;

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
		if (starter != null && starter.Cards != null && starter.Cards.Count > 0)
		{
			var cards = new List<CardData>();
			foreach (CardData c in starter.Cards)
			{
				if (c != null)
				{
					cards.Add(c);
				}
			}
			foreach (int seed in new[] { 6, 7, 8 })
			{
				failures += RunVsTurtle(seed, sb, cards, cards, "Starter");
			}
			string[] npcDecks =
			{
				"NpcFireApprentice", "NpcFireLeader", "NpcFrostApprentice", "NpcFrostLeader", "NpcHealingApprentice",
				"NpcHealingLeader", "NpcStoneApprentice", "NpcStoneLeader", "NpcStormApprentice", "NpcStormLeader",
			};
			for (int i = 0; i < npcDecks.Length; i++)
			{
				List<CardData> npc = LoadDeck(npcDecks[i], sb, ref failures);
				if (npc != null)
				{
					failures += RunVsTurtle(20 + i, sb, cards, npc, npcDecks[i]);
				}
			}
		}
		string[] themes = { "EmberLegion", "DawnCovenant", "Frostbound", "StormCircuit", "StoneBastion" };
		for (int i = 0; i < themes.Length; i++)
		{
			List<CardData> a = LoadDeck(themes[i], sb, ref failures);
			List<CardData> b = LoadDeck(themes[(i + 1) % themes.Length], sb, ref failures);
			if (a != null && b != null)
			{
				sb.AppendLine($"{themes[i]} vs {themes[(i + 1) % themes.Length]}:");
				failures += RunGame(10 + i, MaxTurns * 2, sb, a, b);
			}
		}
		// The endboss deck (all five Legendary units) against a clan deck.
		List<CardData> boss = LoadDeck("BossRealmshatter", sb, ref failures);
		List<CardData> clanDeck = LoadDeck("StoneBastion", sb, ref failures);
		if (boss != null && clanDeck != null)
		{
			sb.AppendLine("StoneBastion vs BossRealmshatter:");
			failures += RunGame(15, MaxTurns * 2, sb, clanDeck, boss, bossBonusAp: 2);
		}
		sb.AppendLine(failures == 0 ? "Result: PASS" : $"Result: FAIL ({failures} problem(s))");
		return sb.ToString();
	}

	private static List<CardData> LoadDeck(string name, StringBuilder sb, ref int failures)
	{
		DeckData deck = Godot.GD.Load<DeckData>($"res://Resources/Decks/{name}.tres");
		if (deck == null || deck.Cards == null || deck.Cards.Count == 0)
		{
			sb.AppendLine($"  [FAIL] could not load {name}");
			failures++;
			return null;
		}
		var cards = new List<CardData>();
		foreach (CardData c in deck.Cards)
		{
			if (c != null)
			{
				cards.Add(c);
			}
		}
		return cards;
	}

	private static int RunGame(int seed, int maxTurns, StringBuilder sb, List<CardData> deck0, List<CardData> deck1, int bossBonusAp = 0)
	{
		var errors = new List<string>();
		var actionCounts = new Dictionary<AiActionKind, int>();
		var eventCounts = new Dictionary<ResolutionEventType, int>();
		int turnsPlayed = 0;
		GameState state = null;
		string map = "";
		int[] zoneSum = new int[2];
		int[] homeSum = new int[2];
		int[] turnsOf = new int[2];

		try
		{
			var config = new GameConfig();
			state = new GameState(config, deck0, deck1, new Random(seed));
			// The themed matches play on generated battlefields (rivers, lava, rocks, springs).
			map = seed >= 10 ? MapGenerator.Generate(state).Name : "";
			state.Players[1].BonusApPerTurn = bossBonusAp;
			var controller = new TurnController(state);
			var ais = new[] { new SimpleAi(controller, 0), new SimpleAi(controller, 1) };
			int[] totalCards = { state.Players[0].Deck.Count, state.Players[1].Deck.Count };
			// Spells cast are consumed; destroyed units go to the graveyard (Undying: back to the deck); pieces on board are counted live.
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
						AiActionKind.Command => config.OrderApCost,
						AiActionKind.Trap => config.TrapApCost,
						AiActionKind.Build => BuildingInfo.GetCost(BuildingInfo.ForClass(a.Card?.Class ?? UnitClass.None)),
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
				CheckActions(state, current, actions, turnBefore, errors);
				turnsOf[current]++;
				foreach (Piece p in state.GetPiecesOf(current))
				{
					if (!p.IsBuilding)
					{
						zoneSum[current] += state.Board.IsInScoringZone(p.Position) ? 1 : 0;
						homeSum[current] += state.Board.IsInDeployZone(current, p.Position) ? 1 : 0;
					}
				}
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

		sb.AppendLine($"Game seed {seed}{(string.IsNullOrEmpty(map) ? "" : $" on {map}")}: {turnsPlayed} turns, winner {(state != null && state.Winner >= 0 ? "P" + state.Winner : "none")}, " +
			$"VP {state?.Players[0].VictoryPoints ?? 0}:{state?.Players[1].VictoryPoints ?? 0}, " +
			$"pieces alive {state?.GetPiecesOf(0).Count ?? 0}:{state?.GetPiecesOf(1).Count ?? 0}");
		sb.AppendLine("  actions: " + FormatCounts(actionCounts));
		sb.AppendLine("  units after own turn (avg in zone / in home rows): " +
			$"P0 {zoneSum[0] / (float)Math.Max(1, turnsOf[0]):0.0} / {homeSum[0] / (float)Math.Max(1, turnsOf[0]):0.0}, " +
			$"P1 {zoneSum[1] / (float)Math.Max(1, turnsOf[1]):0.0} / {homeSum[1] / (float)Math.Max(1, turnsOf[1]):0.0}");
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

	/// <summary>
	/// Regression for "the AI stays in its base": player 0 only deploys units into its back rows (a human building up),
	/// player 1 is the SimpleAi. Within 12 AI turns the AI must have units standing in the scoring zone on average and
	/// must have scored victory points.
	/// </summary>
	private static int RunVsTurtle(int seed, StringBuilder sb, List<CardData> turtleDeck, List<CardData> aiDeck, string aiName)
	{
		const int AiTurns = 12;
		var config = new GameConfig();
		var state = new GameState(config, new List<CardData>(turtleDeck), new List<CardData>(aiDeck), new Random(seed));
		var controller = new TurnController(state);
		var ai = new SimpleAi(controller, 1);
		controller.StartGame();
		int aiTurns = 0;
		int zoneSum = 0;
		int homeSum = 0;
		try
		{
			while (aiTurns < AiTurns && state.Phase != GamePhase.GameOver)
			{
				if (state.CurrentPlayerIndex == 0)
				{
					PlayerState turtle = state.Players[0];
					foreach (CardData card in new List<CardData>(turtle.Hand))
					{
						if (card.CardType != CardType.Unit || controller.GetCardCost(card) > turtle.ActionPoints)
						{
							continue;
						}
						for (int i = 0; i < config.BoardWidth * config.DeployRows; i++)
						{
							var pos = new GridPos(i % config.BoardWidth, config.BoardHeight - 1 - i / config.BoardWidth);
							if (controller.CanPlayUnitCard(card, pos))
							{
								controller.PlayUnitCard(card, pos);
								break;
							}
						}
					}
				}
				else
				{
					ai.TakeTurn();
					aiTurns++;
					foreach (Piece p in state.GetPiecesOf(1))
					{
						if (p.IsBuilding)
						{
							continue;
						}
						zoneSum += state.Board.IsInScoringZone(p.Position) ? 1 : 0;
						homeSum += state.Board.IsInDeployZone(1, p.Position) ? 1 : 0;
					}
				}
				controller.EndTurn();
			}
		}
		catch (Exception e)
		{
			sb.AppendLine($"Turtle seed {seed}: [FAIL] exception: {e.GetType().Name}: {e.Message}");
			return 1;
		}
		float zoneAvg = aiTurns > 0 ? zoneSum / (float)aiTurns : 0f;
		float homeAvg = aiTurns > 0 ? homeSum / (float)aiTurns : 0f;
		int vp = state.Players[1].VictoryPoints;
		bool ok = zoneAvg >= 1.5f && vp >= 6;
		sb.AppendLine($"Turtle seed {seed} ({aiName}): AI after {aiTurns} turns: {vp} VP, avg units in zone {zoneAvg:0.0}, in home rows {homeAvg:0.0}");
		sb.AppendLine(ok ? "  [PASS] the AI advances into the scoring zone" : "  [FAIL] the AI does not push into the scoring zone");
		return ok ? 0 : 1;
	}

	/// <summary>Every Command action acted on an own, non-sick piece that is now marked as acted, at most once per piece.</summary>
	private static void CheckActions(GameState state, int player, List<AiAction> actions, int turn, List<string> errors)
	{
		var commanded = new HashSet<int>();
		foreach (AiAction a in actions)
		{
			if (a.Kind != AiActionKind.Command && a.Kind != AiActionKind.Build && a.Kind != AiActionKind.Trap)
			{
				continue;
			}
			if (!commanded.Add(a.PieceId))
			{
				errors.Add($"turn {turn}: piece {a.PieceId} was commanded twice");
			}
			Piece p = state.GetPiece(a.PieceId);
			if (p == null)
			{
				continue; // died during the turn (friendly fire / lava is possible)
			}
			if (p.OwnerIndex != player)
			{
				errors.Add($"turn {turn}: commanded a piece of the inactive player {p}");
			}
			if (!p.HasActed(turn))
			{
				errors.Add($"turn {turn}: commanded piece not marked as acted {p}");
			}
			if (p.SummonedTurn >= turn)
			{
				errors.Add($"turn {turn}: summoning-sick piece acted {p}");
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
			int cards = ps.Hand.Count + ps.Deck.Count + ps.DraftOffer.Count + ps.Graveyard.Count + played[i] + state.GetPiecesOf(i).FindAll(p => !p.IsBuilding).Count;
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
		deck.Add(Unit($"{tag} Totem", UnitRole.Utility, mov: 0, atk: 1, hp: 3, rng: 2, kw: Keyword.Arc));
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
