using System;
using System.Collections.Generic;

namespace Realmshatter;

/// <summary>
/// Heuristic AI opponent. Uses only the public TurnController command API.
/// AP is budgeted greedily in priority order, re-evaluated after every action:
/// 1. finish a pending draft (free), 2. high-value actions (attacks, entering the scoring zone),
/// 3. one reinforcement per turn while the own army is critically small, 4. draw if the hand has nothing useful,
/// 5. strong expensive cards (3+ AP, high value per AP) before low-value moves,
/// 6. buildings (before the builders walk off), 7. advance toward the scoring zone (before any further deploys,
/// so the army never camps in its base), 8. remaining cards (spells incl. tile spells, units up to a cap),
/// 9. draw with leftover AP, 10. convert VP into AP for a very valuable action (kills) when the VP lead is safe
/// or the opponent is about to win.
/// AP-gaining spells (Mana Surge) are cast first. Cards are chosen by CardValue with a small knapsack over the hand
/// (the most valuable set the AP budget allows), and VP may be converted to pay for a strong card of 4+ AP.
/// Actions resolve immediately (TurnController.Act), so every decision sees the real board. A piece moves toward
/// a free scoring-zone tile (avoiding lava, friendlies may be passed) and attacks the target whose
/// TurnController.PredictAttack outcome is best: enemy damage and kills minus friendly fire (Pierce / Arc can
/// hit own pieces), keyword effects and Mending heals.
/// It never calls EndTurn; the caller does that after presenting the actions.
/// </summary>
public sealed class SimpleAi
{
	private const int MaxSteps = 64;
	private const int HighOrderValue = 3;
	private const int MaxDesiredPieces = 6;
	private const int VpOrderValue = 6;
	private const int LavaPenalty = 25;
	private const int MaxHandToDraw = 6;
	private const int MaxBuildings = 4;

	private readonly TurnController _controller;

	/// <summary>Board knowledge of the current turn (actions resolve immediately, so it mirrors the real board).</summary>
	private sealed class PlanContext
	{
		public HashSet<GridPos> SimOccupied;
		/// <summary>Always empty now (no queued damage); kept so the scoring helpers stay uniform.</summary>
		public readonly Dictionary<int, int> PlannedDamage = new Dictionary<int, int>();
	}

	private struct OrderCandidate
	{
		public Piece Piece;
		public GridPos? Move;
		public AttackPlan? Attack;
		public int Value;
	}

	private struct AttackPlan
	{
		public GridPos Tile;
		public int Value;
	}

	/// <summary>The player this AI controls.</summary>
	public int PlayerIndex { get; }

	/// <summary>Creates an AI for the given player of the controller's game.</summary>
	public SimpleAi(TurnController controller, int playerIndex)
	{
		_controller = controller ?? throw new ArgumentNullException(nameof(controller));
		if (playerIndex < 0 || playerIndex >= GameState.PlayerCount)
		{
			throw new ArgumentOutOfRangeException(nameof(playerIndex));
		}
		PlayerIndex = playerIndex;
	}

	private GameState State => _controller.State;
	private BoardState Board => _controller.State.Board;

	/// <summary>True if it is this AI's turn and the game is in Draft or Main phase.</summary>
	public bool IsMyTurn =>
		State.Winner < 0 &&
		State.CurrentPlayerIndex == PlayerIndex &&
		(State.Phase == GamePhase.Draft || State.Phase == GamePhase.Main);

	/// <summary>
	/// Executes the whole turn synchronously via the TurnController (draws, cards, orders, VP conversions) and
	/// returns the executed steps in order. Does NOT call EndTurn. Returns an empty list if it is not this AI's
	/// turn. Always leaves the game in Main phase (a started draw is completed).
	/// </summary>
	public List<AiAction> TakeTurn()
	{
		var actions = new List<AiAction>();
		if (!IsMyTurn)
		{
			return actions;
		}

		if (State.Phase == GamePhase.Draft)
		{
			DoDraft(actions, false);
		}

		var ctx = new PlanContext { SimOccupied = new HashSet<GridPos>(Board.Occupancy.Keys) };
		bool reinforced = false;
		for (int step = 0; step < MaxSteps; step++)
		{
			if (State.Phase != GamePhase.Main || State.CurrentPlayerIndex != PlayerIndex)
			{
				break;
			}
			if (TryAccelerate(actions))
			{
				continue;
			}
			if (TryCommand(actions, ctx, HighOrderValue, false))
			{
				continue;
			}
			if (!reinforced && IsArmyCritical() && TryPlayBestCard(actions, ctx, unitsOnly: true))
			{
				reinforced = true;
				continue;
			}
			if (ShouldDrawEarly() && TryDraw(actions))
			{
				continue;
			}
			if (TryPlayBestCard(actions, ctx, unitsOnly: false, premiumOnly: true))
			{
				continue;
			}
			// Builders build before they would walk off toward the zone (where they could not build any more).
			if (TryBuild(actions))
			{
				continue;
			}
			if (TryCommand(actions, ctx, 1, false))
			{
				continue;
			}
			if (TryTrap(actions))
			{
				continue;
			}
			if (TryPlayBestCard(actions, ctx, unitsOnly: false))
			{
				continue;
			}
			if (TryDraw(actions))
			{
				continue;
			}
			if (TryCommand(actions, ctx, VpOrderValue, true))
			{
				continue;
			}
			break;
		}

		// Safety net: never leave an unfinished draft behind.
		if (State.Phase == GamePhase.Draft && State.CurrentPlayerIndex == PlayerIndex)
		{
			DoDraft(actions, false);
		}
		return actions;
	}

	/// <summary>
	/// Picks the index of the best card in a draft offer, or -1 for an empty offer.
	/// Early on, Resource units are preferred while few own Resource pieces exist; otherwise the
	/// strongest unit (Attack + Hp + Shield + keywords); spells only score well once own pieces are on the board.
	/// </summary>
	public int ChooseDraftIndex(IReadOnlyList<CardData> offer)
	{
		if (offer == null || offer.Count == 0)
		{
			return -1;
		}

		PlayerState me = State.Players[PlayerIndex];
		List<Piece> myPieces = State.GetPiecesOf(PlayerIndex);
		int resourceCount = 0;
		int handUnits = 0;
		int handSpells = 0;
		foreach (Piece p in myPieces)
		{
			if (p.Role == UnitRole.Resource)
			{
				resourceCount++;
			}
		}
		foreach (CardData c in me.Hand)
		{
			if (c == null)
			{
				continue;
			}
			if (c.CardType == CardType.Spell)
			{
				handSpells++;
			}
			else
			{
				handUnits++;
				if (c.Role == UnitRole.Resource)
				{
					resourceCount++;
				}
			}
		}
		bool early = State.TurnNumber <= 8;
		bool haveUnits = myPieces.Count + handUnits > 0;
		// Units above the AP income are dead weight until Mana Wells / VP conversions pay for them; while no unit in
		// hand is affordable at all, a cheap unit beats a strong one.
		int income = Income();
		bool affordableInHand = false;
		foreach (CardData c in me.Hand)
		{
			affordableInHand |= c != null && c.CardType == CardType.Unit && _controller.GetCardCost(c) <= income;
		}

		int best = -1;
		double bestScore = double.MinValue;
		for (int i = 0; i < offer.Count; i++)
		{
			CardData card = offer[i];
			if (card == null)
			{
				continue;
			}
			double score;
			if (card.CardType == CardType.Unit)
			{
				score = CardValue(card);
				if (card.Role == UnitRole.Resource && early && resourceCount < 2)
				{
					score += 10;
				}
				int over = _controller.GetCardCost(card) - income;
				if (over > 0)
				{
					score -= 4 * over;
				}
				else if (!affordableInHand)
				{
					score += 6;
				}
			}
			else
			{
				score = myPieces.Count > 0 || card.TargetsTile
					? SpellDraftValue(card) * 1.5 + 1 - handSpells * 2 + card.ApGain * 2
					: -5;
				if (!haveUnits)
				{
					score -= 10;
				}
			}
			if (score > bestScore)
			{
				bestScore = score;
				best = i;
			}
		}
		return best;
	}

	// ---------------------------------------------------------------- draft

	/// <summary>Pays for a Draw and picks the best offered card. False if drawing is not possible.</summary>
	private bool TryDraw(List<AiAction> actions)
	{
		// Do not hoard: with a full hand the AP is better spent on the board - unless no unit in hand is affordable
		// (a hand of spells and expensive units cannot reach the board and would stall the AI forever).
		if ((State.Players[PlayerIndex].Hand.Count >= MaxHandToDraw && HasAffordableUnit()) || !_controller.CanDraw() || !_controller.Draw())
		{
			return false;
		}
		DoDraft(actions, true);
		return true;
	}

	/// <summary>True if a unit card in hand costs no more than the AP left.</summary>
	private bool HasAffordableUnit()
	{
		PlayerState me = State.Players[PlayerIndex];
		foreach (CardData card in me.Hand)
		{
			if (card.CardType == CardType.Unit && _controller.GetCardCost(card) <= me.ActionPoints)
			{
				return true;
			}
		}
		return false;
	}

	private void DoDraft(List<AiAction> actions, bool paid)
	{
		PlayerState me = State.Players[PlayerIndex];
		if (me.DraftOffer.Count == 0)
		{
			return;
		}
		int index = ChooseDraftIndex(me.DraftOffer);
		if (index < 0 || index >= me.DraftOffer.Count)
		{
			index = 0;
		}
		CardData card = me.DraftOffer[index];
		if (!_controller.ChooseDraftCard(index) && !_controller.ChooseDraftCard(0))
		{
			return;
		}
		actions.Add(new AiAction
		{
			Kind = AiActionKind.Draft,
			PlayerIndex = PlayerIndex,
			Card = card,
			Description = paid
				? $"Drew ({State.Config.DrawApCost} AP) and kept {CardName(card)}"
				: $"Drafted {CardName(card)}",
		});
	}

	/// <summary>Few own pieces, or fewer than the opponent.</summary>
	/// <summary>Fewer than 3 own units, or fewer units than the opponent (buildings do not count).</summary>
	private bool IsBoardWeak()
	{
		int mine = State.GetPiecesOf(PlayerIndex).FindAll(p => !p.IsBuilding).Count;
		int theirs = State.GetPiecesOf(1 - PlayerIndex).FindAll(p => !p.IsBuilding).Count;
		return mine < 3 || mine < theirs;
	}

	/// <summary>
	/// Reinforcing BEFORE moving is only worth it with almost no army (fewer than 2 units, or 2+ units behind the
	/// opponent); otherwise the existing units advance first and new units are deployed with the remaining AP.
	/// </summary>
	private bool IsArmyCritical()
	{
		int mine = State.GetPiecesOf(PlayerIndex).FindAll(p => !p.IsBuilding).Count;
		int theirs = State.GetPiecesOf(1 - PlayerIndex).FindAll(p => !p.IsBuilding).Count;
		return mine < 2 || mine + 2 <= theirs;
	}

	/// <summary>Draw before spending AP elsewhere if the hand is empty, or the board is weak and no unit is in hand.</summary>
	private bool ShouldDrawEarly()
	{
		List<CardData> hand = State.Players[PlayerIndex].Hand;
		if (hand.Count == 0)
		{
			return true;
		}
		if (!IsBoardWeak())
		{
			return false;
		}
		foreach (CardData c in hand)
		{
			if (c != null && c.CardType == CardType.Unit)
			{
				return false;
			}
		}
		return true;
	}

	// ---------------------------------------------------------------- VP -> AP

	/// <summary>
	/// Converting VP is worth it only if the lead is safe (>= 3 VP ahead and not about to win anyway)
	/// or the opponent is close to winning (spend to fight back).
	/// </summary>
	private bool ShouldSpendVp()
	{
		PlayerState me = State.Players[PlayerIndex];
		PlayerState opp = State.Players[1 - PlayerIndex];
		if (me.VictoryPoints < 1 || !_controller.CanConvertVpToAp())
		{
			return false;
		}
		int target = State.Config.PointsTarget;
		bool safeLead = me.VictoryPoints - opp.VictoryPoints >= 3 && me.VictoryPoints < target - 3;
		bool desperate = opp.VictoryPoints >= target - 4;
		return safeLead || desperate;
	}

	/// <summary>
	/// VP the AI may convert this turn to pay for a strong card (4+ AP): when not behind by more than 2, not about
	/// to win anyway and holding at least 3 VP - or when the opponent is about to win. 0 otherwise.
	/// </summary>
	private int VpForCards()
	{
		PlayerState me = State.Players[PlayerIndex];
		PlayerState opp = State.Players[1 - PlayerIndex];
		int left = Math.Min(_controller.RemainingVpConversions, me.VictoryPoints);
		if (left <= 0 || State.Phase != GamePhase.Main)
		{
			return 0;
		}
		int target = State.Config.PointsTarget;
		bool desperate = opp.VictoryPoints >= target - 4;
		bool comfortable = me.VictoryPoints >= 3 && me.VictoryPoints + 2 >= opp.VictoryPoints && me.VictoryPoints < target - 3;
		return desperate || comfortable ? left : 0;
	}

	private bool TryConvertVp(List<AiAction> actions, string reason)
	{
		if (!ShouldSpendVp() || !_controller.ConvertVpToAp())
		{
			return false;
		}
		actions.Add(new AiAction
		{
			Kind = AiActionKind.ConvertVp,
			PlayerIndex = PlayerIndex,
			Description = $"Converted 1 VP into 1 AP ({reason})",
		});
		return true;
	}

	// ---------------------------------------------------------------- cards

	/// <summary>
	/// Plays one card of the most valuable affordable set: every playable card gets a value (CardValue for units,
	/// the target score for spells); a small knapsack picks the set with the highest total value within the AP
	/// budget (incl. VpForCards for 4+ AP cards), and its most valuable card is played now (converting VP if
	/// needed). premiumOnly: only cards of 3+ AP worth at least 2.5 value per AP.
	/// </summary>
	private bool TryPlayBestCard(List<AiAction> actions, PlanContext ctx, bool unitsOnly, bool premiumOnly = false)
	{
		PlayerState me = State.Players[PlayerIndex];
		int unitCount = State.GetPiecesOf(PlayerIndex).FindAll(p => !p.IsBuilding).Count;
		int unitSlots = unitsOnly ? 1 : Math.Max(0, MaxDesiredPieces - unitCount);
		int vpBudget = VpForCards();
		var options = new List<(CardData Card, GridPos Tile, Piece Target, int Cost, double Value)>();

		foreach (CardData card in new List<CardData>(me.Hand))
		{
			if (card == null
				|| (card.CardType == CardType.Unit && unitSlots <= 0)
				|| (card.CardType == CardType.Spell && unitsOnly)
				|| IsPureAccelerator(card))
			{
				continue;
			}
			int cost = _controller.GetCardCost(card);
			// VP only pays for strong cards.
			if (cost > me.ActionPoints && (cost < 4 || cost > me.ActionPoints + vpBudget))
			{
				continue;
			}

			GridPos tile = default;
			Piece target = null;
			double value;
			if (card.CardType == CardType.Unit)
			{
				GridPos? deploy = FindDeployTile(card);
				if (!deploy.HasValue)
				{
					continue;
				}
				tile = deploy.Value;
				value = CardValue(card);
			}
			else if (card.TargetsTile)
			{
				GridPos? anchor = FindTileSpellTarget(card, ctx, out int tileValue);
				if (!anchor.HasValue)
				{
					continue;
				}
				tile = anchor.Value;
				value = tileValue + card.ApGain * 2;
			}
			else
			{
				target = FindSpellTarget(card);
				if (target == null)
				{
					continue;
				}
				value = Math.Max(1, Math.Abs(SpellNet(card))) * 1.5 + (card.GrantStatus != StatusEffectType.None ? 2 : 0) + card.ApGain * 2;
			}
			if (premiumOnly && (cost < 3 || value < cost * 2.5))
			{
				continue;
			}
			options.Add((card, tile, target, cost, value));
		}
		if (options.Count == 0)
		{
			return false;
		}

		// Knapsack over at most 10 options (the hand is small): best total value, ties -> lower total cost.
		int n = Math.Min(options.Count, 10);
		int budget = me.ActionPoints + vpBudget;
		int bestMask = 0;
		double bestTotal = -1;
		int bestTotalCost = int.MaxValue;
		for (int mask = 1; mask < 1 << n; mask++)
		{
			int cost = 0;
			int units = 0;
			double total = 0;
			for (int i = 0; i < n; i++)
			{
				if ((mask & (1 << i)) == 0)
				{
					continue;
				}
				cost += options[i].Cost;
				total += options[i].Value;
				units += options[i].Card.CardType == CardType.Unit ? 1 : 0;
			}
			if (cost > budget || units > unitSlots)
			{
				continue;
			}
			if (total > bestTotal || (total == bestTotal && cost < bestTotalCost))
			{
				bestTotal = total;
				bestTotalCost = cost;
				bestMask = mask;
			}
		}
		if (bestMask == 0)
		{
			return false;
		}
		int pick = -1;
		for (int i = 0; i < n; i++)
		{
			if ((bestMask & (1 << i)) != 0 && (pick < 0 || options[i].Value > options[pick].Value))
			{
				pick = i;
			}
		}
		CardData bestCard = options[pick].Card;
		GridPos bestTile = options[pick].Tile;
		Piece bestTarget = options[pick].Target;
		while (options[pick].Cost > me.ActionPoints)
		{
			if (!_controller.ConvertVpToAp())
			{
				return false;
			}
			actions.Add(new AiAction
			{
				Kind = AiActionKind.ConvertVp,
				PlayerIndex = PlayerIndex,
				Description = $"Converted 1 VP into 1 AP (for {CardName(bestCard)})",
			});
		}

		if (bestCard.CardType == CardType.Unit)
		{
			Piece piece = _controller.PlayUnitCard(bestCard, bestTile);
			if (piece == null)
			{
				return false;
			}
			ctx.SimOccupied.Add(bestTile);
			actions.Add(new AiAction
			{
				Kind = AiActionKind.PlayUnit,
				PlayerIndex = PlayerIndex,
				Card = bestCard,
				PieceId = piece.Id,
				Target = bestTile,
				Description = $"Deployed {CardName(bestCard)} at {bestTile}",
			});
		}
		else if (bestCard.TargetsTile)
		{
			if (!_controller.PlaySpellOnTile(bestCard, bestTile))
			{
				return false;
			}
			// Kills from the spell free tiles; walls are respected by SimulatedReachable via the board.
			ctx.SimOccupied.RemoveWhere(p => !Board.IsOccupied(p));
			actions.Add(new AiAction
			{
				Kind = AiActionKind.PlaySpell,
				PlayerIndex = PlayerIndex,
				Card = bestCard,
				PieceId = -1,
				Target = bestTile,
				Description = $"Cast {CardName(bestCard)} on {bestTile}",
			});
		}
		else
		{
			GridPos targetPos = bestTarget.Position;
			if (!_controller.PlaySpellCard(bestCard, bestTarget))
			{
				return false;
			}
			actions.Add(new AiAction
			{
				Kind = AiActionKind.PlaySpell,
				PlayerIndex = PlayerIndex,
				Card = bestCard,
				PieceId = bestTarget.Id,
				Target = targetPos,
				Description = $"Cast {CardName(bestCard)} on #{bestTarget.Id} {CardName(bestTarget.Source)} at {targetPos}",
			});
		}
		return true;
	}

	/// <summary>
	/// Free own deploy tile closest to the scoring zone (ties: free tile ahead, then center column). Avoids lava.
	/// Planted units may go forward (near own units): they are placed where they threaten the most enemies, close to the
	/// scoring zone, but not right next to an enemy that would kill them at once.
	/// </summary>
	private GridPos? FindDeployTile(CardData card)
	{
		GridPos? best = null;
		int bestScore = int.MaxValue;
		int forward = BoardState.ForwardDirection(PlayerIndex);
		bool planted = card.HasKeyword(Keyword.Planted);
		for (int y = 0; y < Board.Height; y++)
		{
			for (int x = 0; x < Board.Width; x++)
			{
				var pos = new GridPos(x, y);
				if ((!planted && !Board.IsInDeployZone(PlayerIndex, pos)) || Board.IsOccupied(pos))
				{
					continue;
				}
				if (!_controller.CanPlayUnitCard(card, pos))
				{
					continue;
				}
				int score;
				if (planted)
				{
					int enemyDist = NearestEnemyDistance(pos);
					int reach = Math.Max(1, card.Range);
					score = DistanceToZoneRect(pos) * 6
						+ (enemyDist <= reach ? 0 : (enemyDist - reach) * 8)
						+ (enemyDist <= 1 ? 25 : 0)
						+ (Board.GetTileEffectType(pos) == TileEffectType.Lava ? 50 : 0);
				}
				else
				{
					var ahead = new GridPos(x, y + forward);
					score = DistanceToZoneRect(pos) * 20
						+ (Board.IsInside(ahead) && (Board.IsOccupied(ahead) || Board.IsWall(ahead)) ? 10 : 0)
						+ (Board.GetTileEffectType(pos) == TileEffectType.Lava ? 50 : 0)
						+ Math.Abs(2 * x - (Board.Width - 1));
				}
				if (score < bestScore)
				{
					bestScore = score;
					best = pos;
				}
			}
		}
		return best;
	}

	/// <summary>
	/// Buff (net positive deltas): own piece nearest the zone / most threatened. Debuff: strongest enemy.
	/// Overcharge-like status spells: own piece that can still act and has an enemy within striking distance.
	/// </summary>
	private Piece FindSpellTarget(CardData card)
	{
		if (card.GrantStatus == StatusEffectType.Overcharged)
		{
			return FindOverchargeTarget(card);
		}
		int net = SpellNet(card);
		if (net == 0)
		{
			return null;
		}
		bool buff = net > 0;
		Piece best = null;
		double bestScore = double.MinValue;
		foreach (Piece p in State.Pieces)
		{
			if (!p.IsAlive)
			{
				continue;
			}
			bool mine = p.OwnerIndex == PlayerIndex;
			if (mine != buff)
			{
				continue;
			}
			double score;
			if (buff)
			{
				score = (Board.IsInScoringZone(p.Position) ? 20 : 0)
					- DistanceToZoneRect(p.Position) * 2
					+ ThreatCount(p) * 5
					+ p.EffectiveAttack;
			}
			else
			{
				score = p.EffectiveAttack * 2 + p.CurrentHp + p.TotalShield
					+ (Board.IsInScoringZone(p.Position) ? 10 : 0);
			}
			if (HasSpell(p, card))
			{
				score -= 15;
			}
			if (score > bestScore && _controller.CanPlaySpellCard(card, p))
			{
				bestScore = score;
				best = p;
			}
		}
		return best;
	}

	/// <summary>Own piece (not yet Overcharged) that can still act this turn and reach an enemy with its attack.</summary>
	private Piece FindOverchargeTarget(CardData card)
	{
		Piece best = null;
		int bestValue = 0;
		foreach (Piece p in State.GetPiecesOf(PlayerIndex))
		{
			if (p.HasStatus(StatusEffectType.Overcharged) || p.EffectiveAttack <= 0 || p.HasActed(State.TurnNumber)
				|| p.IsSummoningSick(State.TurnNumber) || !_controller.CanPlaySpellCard(card, p))
			{
				continue;
			}
			int reach = p.EffectiveMovement + p.EffectiveRange;
			foreach (Piece e in State.Pieces)
			{
				if (e.OwnerIndex == PlayerIndex || e.Position.ManhattanDistance(p.Position) > reach)
				{
					continue;
				}
				int value = p.EffectiveAttack * 2 + (e.CurrentHp + e.TotalShield <= p.EffectiveAttack * 2 ? 4 : 1);
				if (value > bestValue)
				{
					bestValue = value;
					best = p;
				}
			}
		}
		return best;
	}

	/// <summary>
	/// Best anchor for a tile/area spell, scored by: enemy damage / kills, lava under enemies (minus own pieces
	/// on lava), walls in front of advancing enemies (minus walls in front of own pieces), healing of
	/// damaged own pieces. Null if nothing reaches the minimum value.
	/// </summary>
	private GridPos? FindTileSpellTarget(CardData card, PlanContext ctx, out int bestValue)
	{
		bestValue = 0;
		GridPos? best = null;
		int minValue = card.TileEffect == TileEffectType.Wall ? 3 : (card.TileEffect == TileEffectType.Healing ? 2 : 4);
		for (int y = 0; y < Board.Height; y++)
		{
			for (int x = 0; x < Board.Width; x++)
			{
				var anchor = new GridPos(x, y);
				if (!_controller.CanPlaySpellOnTile(card, anchor))
				{
					continue;
				}
				int value = ScoreTileSpell(card, anchor, ctx);
				if (value >= minValue && value > bestValue)
				{
					bestValue = value;
					best = anchor;
				}
			}
		}
		return best;
	}

	private int ScoreTileSpell(CardData card, GridPos anchor, PlanContext ctx)
	{
		int value = 0;
		foreach (GridPos t in _controller.GetSpellAreaPreview(card, anchor))
		{
			Piece p = Board.GetPieceAt(t);
			bool enemy = p != null && p.OwnerIndex != PlayerIndex;
			bool mine = p != null && p.OwnerIndex == PlayerIndex;
			if (enemy && card.SpellDamage > 0)
			{
				bool kills = p.CurrentHp + p.TotalShield <= card.SpellDamage;
				value += kills ? 6 : 2;
			}
			if (mine && card.SpellHeal > 0)
			{
				value += Math.Min(card.SpellHeal, p.MaxHp - p.CurrentHp);
			}
			if (card.SpellPush && p != null)
			{
				int spot = (Board.IsInScoringZone(t) ? 2 : 0) + (Board.IsInHotZone(t) ? 2 : 0);
				value += enemy ? 1 + spot : -(1 + spot);
			}
			switch (card.TileEffect)
			{
				case TileEffectType.Lava:
					value += enemy ? 1 : 0;
					value -= mine ? 3 : 0;
					break;
				case TileEffectType.Healing:
					if (mine)
					{
						value += Math.Min(2, p.MaxHp - p.CurrentHp) + (Board.IsInScoringZone(t) ? 1 : 0);
					}
					break;
				case TileEffectType.Wall:
					if (p == null)
					{
						value += WallValue(t);
					}
					break;
			}
		}
		return value;
	}

	/// <summary>+2 per enemy whose next 1-2 forward tiles include t, -2 per own piece likewise, +1 if t is a zone tile an enemy can reach.</summary>
	private int WallValue(GridPos t)
	{
		int value = 0;
		foreach (Piece p in State.Pieces)
		{
			int fwd = BoardState.ForwardDirection(p.OwnerIndex);
			bool inFront = t == new GridPos(p.Position.X, p.Position.Y + fwd) || t == new GridPos(p.Position.X, p.Position.Y + 2 * fwd);
			if (p.OwnerIndex != PlayerIndex)
			{
				value += inFront ? 2 : 0;
				if (Board.IsInScoringZone(t) && p.Position.ManhattanDistance(t) <= p.EffectiveMovement)
				{
					value += 1;
				}
			}
			else if (inFront)
			{
				value -= 2;
			}
		}
		return value;
	}

	// ---------------------------------------------------------------- orders

	/// <summary>
	/// Evaluates every own piece that can still act and executes the best action (TurnController.Act, resolves
	/// immediately) whose value is at least minValue. If AP is missing and allowVp is set, converts 1 VP into AP
	/// first (ShouldSpendVp). False if none qualifies.
	/// </summary>
	private bool TryCommand(List<AiAction> actions, PlanContext ctx, int minValue, bool allowVp)
	{
		bool needAp = State.Config.OrderApCost > State.Players[PlayerIndex].ActionPoints;
		if (needAp && !(allowVp && ShouldSpendVp()))
		{
			return false;
		}
		if (!needAp && allowVp)
		{
			return false;
		}

		ctx.SimOccupied = new HashSet<GridPos>(Board.Occupancy.Keys);
		OrderCandidate? best = null;
		foreach (Piece piece in State.GetPiecesOf(PlayerIndex))
		{
			if (!_controller.CanCommand(piece))
			{
				continue;
			}
			OrderCandidate? c = EvaluateOrder(piece, ctx);
			if (!c.HasValue || c.Value.Value < minValue)
			{
				continue;
			}
			if (!best.HasValue || IsBetter(c.Value, best.Value))
			{
				best = c;
			}
		}
		if (!best.HasValue)
		{
			return false;
		}

		OrderCandidate pick = best.Value;
		Piece p = pick.Piece;
		GridPos? attackTile = pick.Attack?.Tile;
		while (State.Config.OrderApCost > State.Players[PlayerIndex].ActionPoints)
		{
			if (!TryConvertVp(actions, $"for {CardName(p.Source)}'s action"))
			{
				return false;
			}
		}
		string description = DescribeOrder(p, pick.Move, pick.Attack);
		if (_controller.Act(p, pick.Move, attackTile) == null)
		{
			return false;
		}
		ctx.SimOccupied = new HashSet<GridPos>(Board.Occupancy.Keys);

		actions.Add(new AiAction
		{
			Kind = AiActionKind.Command,
			PlayerIndex = PlayerIndex,
			Card = p.Source,
			PieceId = p.Id,
			MoveTarget = pick.Move,
			AttackTarget = attackTile,
			Target = attackTile ?? pick.Move,
			Description = description + $" ({State.Config.OrderApCost} AP)",
		});
		return true;
	}

	private bool IsBetter(OrderCandidate a, OrderCandidate b)
	{
		if (a.Value != b.Value)
		{
			return a.Value > b.Value;
		}
		int da = DistanceToZoneRect(a.Piece.Position);
		int db = DistanceToZoneRect(b.Piece.Position);
		return da != db ? da < db : a.Piece.Id < b.Piece.Id;
	}

	/// <summary>
	/// Plans move + attack for a piece and scores it: attack = predicted value (3 per enemy hit, 6 per kill,
	/// +1 per keyword effect), entering the scoring zone = 4, advancing toward it = 1-2, leaving lava = 1.
	/// Null if the order would do nothing useful. Validity is checked without AP (TryCommand handles AP).
	/// </summary>
	private OrderCandidate? EvaluateOrder(Piece piece, PlanContext ctx)
	{
		GridPos dest = ChooseMove(piece, ctx.SimOccupied, ctx.PlannedDamage);
		AttackPlan? attack = ChooseAttack(piece, dest, ctx);
		GridPos? move = dest != piece.Position ? dest : null;

		if (move.HasValue && !_controller.GetValidMoveTargets(piece).Contains(move.Value))
		{
			move = null;
			attack = ChooseAttack(piece, piece.Position, ctx);
		}
		if (attack.HasValue && !Board.IsInAttackRange(move ?? piece.Position, attack.Value.Tile, piece.EffectiveRange))
		{
			attack = null;
		}
		if (!move.HasValue && !attack.HasValue)
		{
			return null;
		}
		// A Builder that could build stays and builds (TryBuild) instead of only walking - attacks still go first.
		if (!attack.HasValue && WantsToBuild(piece))
		{
			return null;
		}

		int value = attack?.Value ?? 0;
		if (move.HasValue)
		{
			bool wasInZone = Board.IsInScoringZone(piece.Position);
			if (!Board.IsInHotZone(piece.Position) && Board.IsInHotZone(move.Value))
			{
				value += wasInZone ? 3 : 6;
			}
			else if (!wasInZone && Board.IsInScoringZone(move.Value))
			{
				value += 4;
			}
			else
			{
				int progress = DistanceToZoneRect(piece.Position) - DistanceToZoneRect(move.Value);
				if (progress > 0)
				{
					value += progress >= 2 ? 2 : 1;
					// Getting units out of the home rows matters most: an army parked at home never scores.
					if (Board.IsInDeployZone(PlayerIndex, piece.Position) && !Board.IsInDeployZone(PlayerIndex, move.Value))
					{
						value += 1;
					}
				}
			}
			if (Board.GetTileEffectType(piece.Position) == TileEffectType.Lava
				&& Board.GetTileEffectType(move.Value) != TileEffectType.Lava)
			{
				value += 1;
			}
		}
		if (value <= 0)
		{
			return null;
		}
		return new OrderCandidate { Piece = piece, Move = move, Attack = attack, Value = value };
	}

	/// <summary>
	/// Chooses a destination: nearest to a free scoring-zone tile, then best attack opportunity, then fewest steps.
	/// Lava tiles are penalized; friendlies may be passed but not used as destinations (no pushes planned).
	/// </summary>
	private GridPos ChooseMove(Piece piece, HashSet<GridPos> simOccupied, Dictionary<int, int> plannedDamage)
	{
		GridPos start = piece.Position;
		bool inZone = Board.IsInScoringZone(start);

		var candidates = new List<GridPos> { start };
		if (piece.EffectiveMovement > 0)
		{
			HashSet<GridPos> simReach = SimulatedReachable(start, piece.EffectiveMovement, simOccupied);
			foreach (GridPos t in _controller.GetValidMoveTargets(piece))
			{
				if (simReach.Contains(t) && (!inZone || Board.IsInScoringZone(t)))
				{
					candidates.Add(t);
				}
			}
		}

		var freeZone = new List<GridPos>();
		Godot.Rect2I zone = Board.ScoringZone;
		for (int y = zone.Position.Y; y < zone.End.Y; y++)
		{
			for (int x = zone.Position.X; x < zone.End.X; x++)
			{
				var z = new GridPos(x, y);
				if (Board.IsPassable(z) && (z == start || !simOccupied.Contains(z)))
				{
					freeZone.Add(z);
				}
			}
		}

		GridPos best = start;
		int bestScore = int.MaxValue;
		foreach (GridPos c in candidates)
		{
			int dist;
			if (Board.IsInScoringZone(c))
			{
				dist = 0;
			}
			else if (freeZone.Count > 0)
			{
				dist = int.MaxValue;
				foreach (GridPos z in freeZone)
				{
					dist = Math.Min(dist, c.ManhattanDistance(z));
				}
			}
			else
			{
				dist = DistanceToZoneRect(c);
			}
			int score = dist * 10 - AttackOpportunity(piece, c, plannedDamage) * 2 + start.ManhattanDistance(c);
			if (Board.IsInHotZone(c))
			{
				score -= 12;
			}
			if (Board.GetTileEffectType(c) is TileEffectType.Lava or TileEffectType.Storm)
			{
				score += piece.CurrentHp <= State.Config.LavaDamage ? LavaPenalty * 3 : LavaPenalty;
			}
			else if (Board.GetTileEffectType(c) == TileEffectType.Healing && piece.CurrentHp < piece.MaxHp)
			{
				score -= 5;
			}
			if (score < bestScore)
			{
				bestScore = score;
				best = c;
			}
		}
		return best;
	}

	/// <summary>2 if a killable enemy is in range from 'from', 1 if any enemy is, else 0.</summary>
	private int AttackOpportunity(Piece piece, GridPos from, Dictionary<int, int> plannedDamage)
	{
		int atk = piece.EffectiveAttack;
		if (atk <= 0)
		{
			return 0;
		}
		int result = 0;
		foreach (GridPos tile in Board.GetTilesInRange(from, piece.EffectiveRange))
		{
			Piece target = Board.GetPieceAt(tile);
			if (target == null || target.OwnerIndex == PlayerIndex)
			{
				continue;
			}
			int ehp = RemainingEhp(target, plannedDamage);
			if (ehp <= 0)
			{
				continue;
			}
			if (ehp <= atk)
			{
				return 2;
			}
			result = 1;
		}
		return result;
	}

	/// <summary>
	/// Attack from 'from': every occupied tile in range is evaluated with TurnController.PredictAttack (enemy
	/// damage, friendly fire, Mending heals) and scored by ScorePreview. Null if nothing has a positive value.
	/// </summary>
	private AttackPlan? ChooseAttack(Piece piece, GridPos from, PlanContext ctx)
	{
		AttackPlan? best = null;
		foreach (GridPos tile in _controller.GetValidAttackTargets(piece, from))
		{
			Piece target = Board.GetPieceAt(tile);
			if (target == null || target == piece || !target.IsAlive)
			{
				continue;
			}
			bool friendly = target.OwnerIndex == PlayerIndex;
			if (friendly && !(piece.HasKeyword(Keyword.Mending) && target.CurrentHp < target.MaxHp))
			{
				continue;
			}
			ChainPreview preview = _controller.PredictAttack(piece, from, tile);
			if (!preview.IsValid)
			{
				continue;
			}
			AttackPlan plan = ScorePreview(preview, ctx, tile);
			if (plan.Value > 0 && (!best.HasValue || plan.Value > best.Value.Value))
			{
				best = plan;
			}
		}
		return best;
	}

	/// <summary>
	/// Scores a preview: per enemy hit 3 (6 if it kills), +1 per keyword effect, + heals; friendly fire costs
	/// 3 per damaged own piece (8 if it dies).
	/// </summary>
	private AttackPlan ScorePreview(ChainPreview preview, PlanContext ctx, GridPos tile)
	{
		var local = new Dictionary<int, int>();
		int value = 0;
		int hitEnemyHp = 0;
		foreach (PredictedHit hit in preview.Hits)
		{
			if (hit.TargetPieceId < 0)
			{
				continue;
			}
			if (hit.IsFriendly)
			{
				continue;
			}
			Piece enemy = State.GetPiece(hit.TargetPieceId);
			if (enemy == null)
			{
				continue;
			}
			local.TryGetValue(enemy.Id, out int already);
			int ehp = RemainingEhp(enemy, ctx.PlannedDamage) - already;
			if (ehp <= 0)
			{
				continue;
			}
			if (hit.Damage > 0)
			{
				value += ehp <= hit.Damage ? 6 : 3;
				local[enemy.Id] = already + hit.Damage;
				hitEnemyHp += hit.HpLost;
			}
			if ((hit.Effects & HitEffect.Frozen) != 0) value += 1;
			if ((hit.Effects & HitEffect.Lava) != 0) value += 1;
			if ((hit.Effects & HitEffect.Pushed) != 0)
			{
				value += Board.IsInScoringZone(enemy.Position) && hit.PushedTo.HasValue && !Board.IsInScoringZone(hit.PushedTo.Value) ? 3 : 1;
			}
		}
		value += preview.FriendlyHealed;
		// Everything that is not a direct hit: deathrattles, thorns, Arc / Pierce on own pieces.
		value += Math.Max(0, preview.EnemyHpLost - hitEnemyHp) * 2;
		value -= preview.FriendlyHpLost * 2 + preview.FriendlyKills * 6;
		return new AttackPlan { Tile = tile, Value = value };
	}

	/// <summary>
	/// Lets an idle Builder start its building when AP allows (keeping 1 AP spare), the player has fewer than two
	/// buildings of that kind and at most MaxBuildings in total. Turrets / Barricades go toward the scoring zone, the
	/// rest away from enemies.
	/// </summary>
	private bool TryBuild(List<AiAction> actions)
	{
		int ap = State.Players[PlayerIndex].ActionPoints;
		if (State.GetPiecesOf(PlayerIndex).FindAll(p => p.IsBuilding).Count >= MaxBuildings)
		{
			return false;
		}
		foreach (Piece piece in State.GetPiecesOf(PlayerIndex))
		{
			BuildingType type = _controller.GetBuildType(piece);
			if (!WantsToBuild(piece) || !_controller.CanCommand(piece) || BuildingInfo.GetCost(type) > ap)
			{
				continue;
			}
			// Best tiles first (Barricades: the two best).
			bool forward = type == BuildingType.Turret || type == BuildingType.Barricade;
			var scored = new List<(GridPos Tile, int Score)>();
			foreach (GridPos tile in _controller.GetValidBuildTiles(piece))
			{
				int score = forward ? DistanceToZoneRect(tile) * 10 : -NearestEnemyDistance(tile) * 3;
				if (Board.GetTileEffectType(tile) == TileEffectType.Lava || Board.IsInScoringZone(tile) && !forward)
				{
					score += 30;
				}
				scored.Add((tile, score));
			}
			if (scored.Count == 0)
			{
				continue;
			}
			scored.Sort((a, b) => a.Score.CompareTo(b.Score));
			var tiles = new List<GridPos>();
			for (int i = 0; i < scored.Count && tiles.Count < BuildingInfo.GetBuildCount(type); i++)
			{
				tiles.Add(scored[i].Tile);
			}
			if (_controller.Build(piece, tiles, null) == null)
			{
				continue;
			}
			actions.Add(new AiAction
			{
				Kind = AiActionKind.Build,
				PlayerIndex = PlayerIndex,
				Card = piece.Source,
				PieceId = piece.Id,
				Target = tiles[0],
				Description = $"#{piece.Id} {CardName(piece.Source)} builds {(tiles.Count > 1 ? $"{tiles.Count} {BuildingInfo.GetName(type, piece.Source.Clan)}s" : $"a {BuildingInfo.GetName(type, piece.Source.Clan)}")} " +
					$"at {string.Join(" and ", tiles)} ({BuildingInfo.GetCost(type)} AP)",
			});
			return true;
		}
		return false;
	}

	/// <summary>
	/// A Trapper with nothing better to do (no worthwhile move or attack this turn) hides a trap next to it when
	/// enemies are near: on the free neighbour tile closest to them, preferably inside the scoring zone.
	/// The AI knows nothing about the opponent's traps.
	/// </summary>
	private bool TryTrap(List<AiAction> actions)
	{
		if (State.Config.TrapApCost > State.Players[PlayerIndex].ActionPoints)
		{
			return false;
		}
		foreach (Piece piece in State.GetPiecesOf(PlayerIndex))
		{
			if (!_controller.GetTrapType(piece).HasValue || !_controller.CanCommand(piece) || NearestEnemyDistance(piece.Position) > 7)
			{
				continue;
			}
			GridPos? best = null;
			int bestScore = int.MaxValue;
			foreach (GridPos tile in _controller.GetValidTrapTiles(piece))
			{
				int score = NearestEnemyDistance(tile) * 3 + DistanceToZoneRect(tile) * 2
					+ (Board.GetTileEffectType(tile) == TileEffectType.Lava ? 10 : 0);
				if (score < bestScore)
				{
					bestScore = score;
					best = tile;
				}
			}
			if (!best.HasValue || _controller.SetTrap(piece, best.Value, null) == null)
			{
				continue;
			}
			actions.Add(new AiAction
			{
				Kind = AiActionKind.Trap,
				PlayerIndex = PlayerIndex,
				Card = piece.Source,
				PieceId = piece.Id,
				Target = best.Value,
				Description = $"#{piece.Id} {CardName(piece.Source)} hides a trap ({State.Config.TrapApCost} AP)",
			});
			return true;
		}
		return false;
	}

	/// <summary>
	/// True for an idle Builder outside the scoring zone (it would stop scoring while building) whose building is still
	/// worth raising: fewer than two of that kind, fewer than MaxBuildings in total and a free tile next to it.
	/// </summary>
	private bool WantsToBuild(Piece piece)
	{
		BuildingType type = _controller.GetBuildType(piece);
		if (type == BuildingType.None || piece.ConstructingId >= 0 || Board.IsInScoringZone(piece.Position))
		{
			return false;
		}
		int same = 0;
		int total = 0;
		foreach (Piece p in State.GetPiecesOf(PlayerIndex))
		{
			same += p.Building == type ? 1 : 0;
			total += p.IsBuilding ? 1 : 0;
		}
		return same < 2 && total < MaxBuildings && _controller.GetValidBuildTiles(piece).Count > 0 && IsBuildingUseful(piece, type);
	}

	/// <summary>
	/// Whether the building would pay off where the builder stands: Mana Wells early on, Turrets near the zone or
	/// enemies, Barricades when enemies approach, Shrines among allies, Obelisks with spells in hand. Clan buildings
	/// also qualify through their aura: Fire / Frost with enemies close, Healing / Stone / Storm with allies close.
	/// </summary>
	private bool IsBuildingUseful(Piece builder, BuildingType type)
	{
		GridPos at = builder.Position;
		int enemyDist = NearestEnemyDistance(at);
		int alliesNear = State.GetPiecesOf(PlayerIndex).FindAll(p => p != builder && !p.IsBuilding && p.Position.ManhattanDistance(at) <= 2).Count;
		int spells = State.Players[PlayerIndex].Hand.FindAll(c => c != null && c.CardType == CardType.Spell).Count;
		bool useful = type switch
		{
			BuildingType.ManaWell => State.TurnNumber <= 14,
			BuildingType.Turret => DistanceToZoneRect(at) <= 2 || enemyDist <= 5,
			BuildingType.Barricade => enemyDist <= 4,
			BuildingType.Shrine => alliesNear >= 2,
			BuildingType.Obelisk => spells >= 2,
			_ => false,
		};
		return useful || (builder.Source.Clan switch
		{
			Clan.Fire or Clan.Frost => enemyDist <= 3,
			Clan.Healing or Clan.Stone or Clan.Storm => alliesNear >= 2,
			_ => false,
		});
	}

	/// <summary>Spells that only gain AP (net gain, no other effect), e.g. Mana Surge.</summary>
	private bool IsPureAccelerator(CardData card) =>
		card.CardType == CardType.Spell && card.ApGain > _controller.GetCardCost(card) && SpellNet(card) == 0
		&& card.GrantStatus == StatusEffectType.None && !card.TargetsTile;

	/// <summary>
	/// Casts an AP-gaining spell (net AP gain) on any own piece in reach, if the hand holds something else to spend
	/// the AP on. False otherwise.
	/// </summary>
	private bool TryAccelerate(List<AiAction> actions)
	{
		PlayerState me = State.Players[PlayerIndex];
		foreach (CardData card in new List<CardData>(me.Hand))
		{
			if (card == null || !IsPureAccelerator(card) || _controller.GetCardCost(card) > me.ActionPoints)
			{
				continue;
			}
			bool useful = me.Hand.Exists(c => c != null && c != card && !IsPureAccelerator(c));
			if (!useful)
			{
				continue;
			}
			foreach (Piece p in State.GetPiecesOf(PlayerIndex))
			{
				if (!_controller.CanPlaySpellCard(card, p))
				{
					continue;
				}
				GridPos at = p.Position;
				if (!_controller.PlaySpellCard(card, p))
				{
					return false;
				}
				actions.Add(new AiAction
				{
					Kind = AiActionKind.PlaySpell,
					PlayerIndex = PlayerIndex,
					Card = card,
					PieceId = p.Id,
					Target = at,
					Description = $"Cast {CardName(card)} on #{p.Id} {CardName(p.Source)} at {at}",
				});
				return true;
			}
		}
		return false;
	}

	/// <summary>AP at the start of the next own turn: base + bonus + AP-producing pieces and Mana Wells.</summary>
	private int Income()
	{
		int income = State.Config.BaseAp + State.Players[PlayerIndex].BonusApPerTurn;
		foreach (Piece p in State.GetPiecesOf(PlayerIndex))
		{
			income += p.IsBuilding
				? (p.Building == BuildingType.ManaWell && !p.UnderConstruction ? State.Config.ManaWellAp : 0)
				: p.ApBonus;
		}
		return income;
	}

	/// <summary>
	/// Rough worth of a unit card in stat points: Attack counts 1.5, HP and Shield 1, plus reach, speed, area attacks,
	/// AP income (3 per AP), keywords, legend effects and triggers. Planted units that bring no AP lose a little (they
	/// never score).
	/// </summary>
	private static double CardValue(CardData card)
	{
		if (card.CardType != CardType.Unit)
		{
			return SpellDraftValue(card) + card.ApGain * 2;
		}
		double value = card.Attack * 1.5 + card.Hp + card.Shield
			+ Math.Max(0, card.Range - 1)
			+ (card.Movement >= 5 ? 1 : card.Movement <= 1 ? -1 : 0)
			+ (card.AttackArea != AreaShape.Single ? 1.5 : 0)
			+ card.ApBonus * 3
			+ KeywordInfo.Split(card.Keywords).Count
			+ (card.Legend != LegendEffect.None ? 4 : 0)
			+ (card.Deathrattle != DeathrattleType.None ? 1 : 0)
			+ (card.OnFirstHit != FirstHitType.None ? 1 : 0);
		if (card.HasKeyword(Keyword.Planted) && card.ApBonus <= 0)
		{
			value -= 1;
		}
		return value;
	}

	private int NearestEnemyDistance(GridPos tile)
	{
		int best = 99;
		foreach (Piece p in State.Pieces)
		{
			if (p.OwnerIndex != PlayerIndex)
			{
				best = Math.Min(best, p.Position.ManhattanDistance(tile));
			}
		}
		return best;
	}

	/// <summary>
	/// Tiles reachable with the move rules (water costs extra movement, own pieces are passable) where the piece may
	/// END (not sim-occupied).
	/// </summary>
	private HashSet<GridPos> SimulatedReachable(GridPos from, int movement, HashSet<GridPos> occupied)
	{
		var result = new HashSet<GridPos>();
		foreach (GridPos tile in Board.GetReachableTiles(from, movement, PlayerIndex))
		{
			if (!occupied.Contains(tile))
			{
				result.Add(tile);
			}
		}
		return result;
	}

	// ---------------------------------------------------------------- helpers

	private int DistanceToZoneRect(GridPos pos)
	{
		Godot.Rect2I zone = Board.ScoringZone;
		int dx = Math.Max(0, Math.Max(zone.Position.X - pos.X, pos.X - (zone.End.X - 1)));
		int dy = Math.Max(0, Math.Max(zone.Position.Y - pos.Y, pos.Y - (zone.End.Y - 1)));
		return dx + dy;
	}

	private int ThreatCount(Piece piece)
	{
		int threats = 0;
		foreach (Piece e in State.Pieces)
		{
			if (e.OwnerIndex != piece.OwnerIndex && e.IsAlive
				&& e.Position.ManhattanDistance(piece.Position) <= e.EffectiveMovement + e.EffectiveRange)
			{
				threats++;
			}
		}
		return threats;
	}

	private static int RemainingEhp(Piece target, Dictionary<int, int> plannedDamage)
	{
		plannedDamage.TryGetValue(target.Id, out int dmg);
		return target.CurrentHp + target.TotalShield - dmg;
	}

	private static bool HasSpell(Piece piece, CardData card)
	{
		foreach (ActiveSpell s in piece.ActiveSpells)
		{
			if (s.Source == card)
			{
				return true;
			}
		}
		return false;
	}

	private static int SpellNet(CardData card) =>
		card.AttackDelta + card.HpDelta + card.ShieldDelta + card.MovementDelta + card.RangeDelta;

	private static int SpellDraftValue(CardData card) =>
		Math.Abs(SpellNet(card)) + card.SpellDamage * 2 + card.SpellHeal
		+ (card.TileEffect != TileEffectType.None ? 2 : 0) + (card.GrantStatus != StatusEffectType.None ? 2 : 0);

	private static string CardName(CardData card) => card?.Name ?? "?";

	private string DescribeOrder(Piece piece, GridPos? move, AttackPlan? attack)
	{
		string text = $"#{piece.Id} {CardName(piece.Source)}";
		text += move.HasValue ? $" moves to {move.Value}" : " holds";
		if (attack.HasValue)
		{
			Piece target = Board.GetPieceAt(attack.Value.Tile);
			string targetName = target != null ? $"#{target.Id} {CardName(target.Source)}" : "tile";
			text += $", attacks {targetName} at {attack.Value.Tile}";
		}
		return text;
	}
}
