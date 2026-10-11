using System;
using System.Collections.Generic;

namespace ProjectClaude;

/// <summary>
/// Heuristic AI opponent. Uses only the public TurnController command API.
/// AP is budgeted greedily in priority order, re-evaluated after every action:
/// 1. finish a pending draft (free), 2. high-value orders (attacks, entering the scoring zone),
/// 3. units while the own board is weak, 4. draw if the hand has nothing useful,
/// 5. low-value orders (advance toward the zone), 6. remaining cards (spells incl. tile spells, units up to a cap),
/// 7. draw with leftover AP, 8. convert VP into AP for a very valuable order (kills) when the VP lead is safe
/// or the opponent is about to win.
/// Orders: move toward a free scoring-zone tile (avoiding lava, friendlies may be passed), attack the target
/// whose TurnController.PredictAttack outcome is best (direct hits, chains through friendlies, keyword effects).
/// It never calls EndTurn; the caller does that after presenting the actions.
/// </summary>
public sealed class SimpleAi
{
	private const int MaxSteps = 64;
	private const int HighOrderValue = 3;
	private const int MaxDesiredPieces = 6;
	private const int VpOrderValue = 6;
	private const int LavaPenalty = 25;

	private readonly TurnController _controller;

	/// <summary>Simulated resolution-time knowledge for the orders already queued this turn.</summary>
	private sealed class PlanContext
	{
		public HashSet<GridPos> SimOccupied;
		public readonly Dictionary<int, int> PlannedDamage = new Dictionary<int, int>();
		public readonly HashSet<int> Planned = new HashSet<int>();
		public readonly HashSet<int> ChainFired = new HashSet<int>();
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
		public int ChainPieceId;
		public int Value;
		public List<(int PieceId, int Damage)> Hits;
		public List<int> Triggered;
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
		for (int step = 0; step < MaxSteps; step++)
		{
			if (State.Phase != GamePhase.Main || State.CurrentPlayerIndex != PlayerIndex)
			{
				break;
			}
			if (TryCommand(actions, ctx, HighOrderValue, false))
			{
				continue;
			}
			if (IsBoardWeak() && TryPlayBestCard(actions, ctx, unitsOnly: true))
			{
				continue;
			}
			if (ShouldDrawEarly() && TryDraw(actions))
			{
				continue;
			}
			if (TryCommand(actions, ctx, 1, false))
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
				score = UnitStrength(card);
				if (card.Role == UnitRole.Resource && early && resourceCount < 2)
				{
					score += 10;
				}
			}
			else
			{
				score = myPieces.Count > 0 || card.TargetsTile
					? SpellDraftValue(card) * 1.5 + 1 - handSpells * 2
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
		if (!_controller.CanDraw() || !_controller.Draw())
		{
			return false;
		}
		DoDraft(actions, true);
		return true;
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
	private bool IsBoardWeak()
	{
		int mine = State.GetPiecesOf(PlayerIndex).Count;
		int theirs = State.GetPiecesOf(1 - PlayerIndex).Count;
		return mine < 3 || mine < theirs;
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

	private bool TryPlayBestCard(List<AiAction> actions, PlanContext ctx, bool unitsOnly)
	{
		PlayerState me = State.Players[PlayerIndex];
		bool unitsAllowed = unitsOnly || State.GetPiecesOf(PlayerIndex).Count < MaxDesiredPieces;
		CardData bestCard = null;
		GridPos bestTile = default;
		Piece bestTarget = null;
		int bestCost = int.MaxValue;
		double bestValue = double.MinValue;

		foreach (CardData card in new List<CardData>(me.Hand))
		{
			if (card == null
				|| (card.CardType == CardType.Unit && !unitsAllowed)
				|| (card.CardType == CardType.Spell && unitsOnly))
			{
				continue;
			}
			int cost = _controller.GetCardCost(card);
			if (cost > me.ActionPoints)
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
				value = UnitStrength(card);
			}
			else if (card.TargetsTile)
			{
				GridPos? anchor = FindTileSpellTarget(card, ctx, out int tileValue);
				if (!anchor.HasValue)
				{
					continue;
				}
				tile = anchor.Value;
				value = tileValue;
			}
			else
			{
				target = FindSpellTarget(card);
				if (target == null)
				{
					continue;
				}
				value = Math.Max(1, Math.Abs(SpellNet(card)));
			}

			if (cost < bestCost || (cost == bestCost && value > bestValue))
			{
				bestCard = card;
				bestTile = tile;
				bestTarget = target;
				bestCost = cost;
				bestValue = value;
			}
		}

		if (bestCard == null)
		{
			return false;
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
			ctx.SimOccupied.RemoveWhere(p => !Board.IsOccupied(p) && !IsPlannedDestination(ctx, p));
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

	private bool IsPlannedDestination(PlanContext ctx, GridPos pos)
	{
		foreach (Piece p in State.GetPiecesOf(PlayerIndex))
		{
			if (ctx.Planned.Contains(p.Id) && p.Order?.MoveTarget == pos)
			{
				return true;
			}
		}
		return false;
	}

	/// <summary>Free own deploy tile closest to the scoring zone (ties: free tile ahead, then center column). Avoids lava.</summary>
	private GridPos? FindDeployTile(CardData card)
	{
		GridPos? best = null;
		int bestScore = int.MaxValue;
		int forward = BoardState.ForwardDirection(PlayerIndex);
		for (int y = 0; y < Board.Height; y++)
		{
			for (int x = 0; x < Board.Width; x++)
			{
				var pos = new GridPos(x, y);
				if (!Board.IsInDeployZone(PlayerIndex, pos) || Board.IsOccupied(pos))
				{
					continue;
				}
				if (!_controller.CanPlayUnitCard(card, pos))
				{
					continue;
				}
				var ahead = new GridPos(x, y + forward);
				int score = DistanceToZoneRect(pos) * 20
					+ (Board.IsInside(ahead) && (Board.IsOccupied(ahead) || Board.IsWall(ahead)) ? 10 : 0)
					+ (Board.GetTileEffectType(pos) == TileEffectType.Lava ? 50 : 0)
					+ Math.Abs(2 * x - (Board.Width - 1));
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
	/// Overcharge-like status spells: own piece whose chain would hit the most enemies.
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

	/// <summary>Own piece (not yet Overcharged) whose chain directions hold enemies and that a friendly can trigger.</summary>
	private Piece FindOverchargeTarget(CardData card)
	{
		Piece best = null;
		int bestValue = 1;
		foreach (Piece p in State.GetPiecesOf(PlayerIndex))
		{
			if (p.HasStatus(StatusEffectType.Overcharged) || p.EffectiveAttack <= 0 || !_controller.CanPlaySpellCard(card, p))
			{
				continue;
			}
			int enemies = ChainHits(p).Count;
			if (enemies == 0 || !CanBeTriggered(p))
			{
				continue;
			}
			int value = enemies * 2 + p.EffectiveAttack;
			if (value > bestValue)
			{
				bestValue = value;
				best = p;
			}
		}
		return best;
	}

	/// <summary>True if another own commandable piece has this piece within attack range (from its current tile).</summary>
	private bool CanBeTriggered(Piece target)
	{
		foreach (Piece p in State.GetPiecesOf(PlayerIndex))
		{
			if (p != target && p.Order == null && !p.IsSummoningSick(State.TurnNumber)
				&& Board.IsInAttackRange(p.Position, target.Position, p.EffectiveRange))
			{
				return true;
			}
		}
		return false;
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
				if (kills && ctx.PlannedDamage.ContainsKey(p.Id))
				{
					// A queued attack targets this tile: killing it now would make that order hit an empty tile.
					return int.MinValue;
				}
				value += kills ? 6 : 2;
			}
			if (mine && card.SpellHeal > 0)
			{
				value += Math.Min(card.SpellHeal, p.MaxHp - p.CurrentHp);
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
	/// Evaluates every commandable own piece without an order and queues the best order whose value is at
	/// least minValue. If AP is missing and allowVp is set, converts 1 VP into AP first (ShouldSpendVp).
	/// False if none qualifies.
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

		OrderCandidate? best = null;
		foreach (Piece piece in State.GetPiecesOf(PlayerIndex))
		{
			if (piece.Order != null || ctx.Planned.Contains(piece.Id) || !_controller.CanCommand(piece))
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
			if (!TryConvertVp(actions, $"for {CardName(p.Source)}'s order"))
			{
				return false;
			}
		}
		if (!_controller.SetOrder(p, pick.Move, attackTile))
		{
			return false;
		}

		ctx.Planned.Add(p.Id);
		if (pick.Move.HasValue)
		{
			ctx.SimOccupied.Remove(p.Position);
			ctx.SimOccupied.Add(pick.Move.Value);
		}
		if (pick.Attack.HasValue)
		{
			foreach ((int id, int dmg) in pick.Attack.Value.Hits)
			{
				ctx.PlannedDamage.TryGetValue(id, out int prev);
				ctx.PlannedDamage[id] = prev + dmg;
			}
			foreach (int id in pick.Attack.Value.Triggered)
			{
				ctx.ChainFired.Add(id);
			}
		}

		actions.Add(new AiAction
		{
			Kind = AiActionKind.SetOrder,
			PlayerIndex = PlayerIndex,
			Card = p.Source,
			PieceId = p.Id,
			MoveTarget = pick.Move,
			AttackTarget = attackTile,
			Target = attackTile ?? pick.Move,
			Description = DescribeOrder(p, pick.Move, pick.Attack) + $" ({State.Config.OrderApCost} AP)",
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
		AttackPlan? attack = ctx.ChainFired.Contains(piece.Id) ? null : ChooseAttack(piece, dest, ctx);
		GridPos? move = dest != piece.Position ? dest : null;

		if (move.HasValue && !_controller.GetValidMoveTargets(piece).Contains(move.Value))
		{
			move = null;
			attack = ctx.ChainFired.Contains(piece.Id) ? null : ChooseAttack(piece, piece.Position, ctx);
		}
		if (attack.HasValue && !Board.IsInAttackRange(move ?? piece.Position, attack.Value.Tile, piece.EffectiveRange))
		{
			attack = null;
		}
		if (!move.HasValue && !attack.HasValue)
		{
			return null;
		}

		int value = attack?.Value ?? 0;
		if (move.HasValue)
		{
			bool wasInZone = Board.IsInScoringZone(piece.Position);
			if (!wasInZone && Board.IsInScoringZone(move.Value))
			{
				value += 4;
			}
			else
			{
				int progress = DistanceToZoneRect(piece.Position) - DistanceToZoneRect(move.Value);
				if (progress > 0)
				{
					value += progress >= 2 ? 2 : 1;
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
			if (Board.GetTileEffectType(c) == TileEffectType.Lava)
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
	/// Attack from 'from': every occupied tile in range is evaluated with TurnController.PredictAttack (direct
	/// enemy hits as well as chains through unplanned friendlies) and scored by ScorePreview. Ties prefer direct
	/// hits. Null if nothing has a positive value.
	/// </summary>
	private AttackPlan? ChooseAttack(Piece piece, GridPos from, PlanContext ctx)
	{
		AttackPlan? best = null;
		bool bestDirect = false;
		foreach (GridPos tile in _controller.GetValidAttackTargets(piece, from))
		{
			Piece target = Board.GetPieceAt(tile);
			if (target == null || target == piece || !target.IsAlive)
			{
				continue;
			}
			bool friendly = target.OwnerIndex == PlayerIndex;
			if (friendly && (ctx.Planned.Contains(target.Id) || ctx.ChainFired.Contains(target.Id)))
			{
				continue;
			}
			if (!friendly && RemainingEhp(target, ctx.PlannedDamage) <= 0)
			{
				continue;
			}
			ChainPreview preview = _controller.PredictAttack(piece, from, tile);
			if (!preview.IsValid)
			{
				continue;
			}
			var plan = ScorePreview(preview, ctx, tile, friendly ? target.Id : -1);
			if (plan.Value <= 0)
			{
				continue;
			}
			bool direct = !friendly;
			if (!best.HasValue || plan.Value > best.Value.Value || (plan.Value == best.Value.Value && direct && !bestDirect))
			{
				best = plan;
				bestDirect = direct;
			}
		}
		return best;
	}

	/// <summary>Scores a preview: per enemy hit 3 (6 if it kills given planned damage), +1 per keyword effect, + heals.</summary>
	private AttackPlan ScorePreview(ChainPreview preview, PlanContext ctx, GridPos tile, int chainPieceId)
	{
		var hits = new List<(int, int)>();
		var local = new Dictionary<int, int>();
		int value = 0;
		foreach (PredictedHit hit in preview.Hits)
		{
			if (hit.TargetPieceId < 0 || hit.IsFriendly)
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
				hits.Add((enemy.Id, hit.Damage));
			}
			if ((hit.Effects & HitEffect.Frozen) != 0) value += 1;
			if ((hit.Effects & HitEffect.Lava) != 0) value += 1;
			if ((hit.Effects & HitEffect.Pushed) != 0)
			{
				value += Board.IsInScoringZone(enemy.Position) && hit.PushedTo.HasValue && !Board.IsInScoringZone(hit.PushedTo.Value) ? 3 : 1;
			}
		}
		value += preview.FriendlyHealed;
		return new AttackPlan
		{
			Tile = tile,
			ChainPieceId = chainPieceId,
			Value = value,
			Hits = hits,
			Triggered = new List<int>(preview.TriggeredPieceIds),
		};
	}

	/// <summary>Enemies the friendly's chain fire would hit directly (nearest piece per chain direction, walls stop).</summary>
	private List<int> ChainHits(Piece shooter)
	{
		var hits = new List<int>();
		int left = BoardState.LeftDirection(shooter.OwnerIndex);
		int fwd = BoardState.ForwardDirection(shooter.OwnerIndex);
		var dirs = new List<GridPos> { new GridPos(left, 0), new GridPos(-left, 0) };
		if (shooter.HasKeyword(Keyword.Conduit))
		{
			dirs.Add(new GridPos(0, fwd));
			dirs.Add(new GridPos(0, -fwd));
		}
		foreach (GridPos dir in dirs)
		{
			for (int d = 1; d <= shooter.EffectiveRange; d++)
			{
				var tile = new GridPos(shooter.Position.X + dir.X * d, shooter.Position.Y + dir.Y * d);
				if (!Board.IsPassable(tile))
				{
					break;
				}
				Piece p = Board.GetPieceAt(tile);
				if (p == null)
				{
					continue;
				}
				if (p.OwnerIndex != PlayerIndex)
				{
					hits.Add(p.Id);
				}
				break;
			}
		}
		return hits;
	}

	/// <summary>Tiles reachable with the v3 move rules where the piece may END (not sim-occupied). Own pieces are passable.</summary>
	private HashSet<GridPos> SimulatedReachable(GridPos from, int movement, HashSet<GridPos> occupied)
	{
		var dist = new Dictionary<GridPos, int> { [from] = 0 };
		var queue = new Queue<GridPos>();
		var result = new HashSet<GridPos>();
		queue.Enqueue(from);
		while (queue.Count > 0)
		{
			GridPos cur = queue.Dequeue();
			int d = dist[cur];
			if (d >= movement)
			{
				continue;
			}
			foreach (GridPos next in cur.Neighbors())
			{
				if (!Board.IsPassable(next) || dist.ContainsKey(next))
				{
					continue;
				}
				Piece occupant = Board.GetPieceAt(next);
				if (occupant != null && occupant.OwnerIndex != PlayerIndex)
				{
					continue;
				}
				dist[next] = d + 1;
				if (!occupied.Contains(next))
				{
					result.Add(next);
				}
				queue.Enqueue(next);
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

	private static int UnitStrength(CardData card) =>
		card.Attack + card.Hp + card.Shield + KeywordInfo.Split(card.Keywords).Count;

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
			text += attack.Value.ChainPieceId >= 0
				? $", triggers chain via {targetName} at {attack.Value.Tile}"
				: $", attacks {targetName} at {attack.Value.Tile}";
		}
		return text;
	}
}
