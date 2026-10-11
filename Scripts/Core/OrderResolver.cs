using System;
using System.Collections.Generic;

namespace Realmshatter;

/// <summary>
/// Resolves the queued orders of one player, plus the shared damage / heal / tile / status helpers.
///
/// Rules (v3):
/// - Orders resolve in ascending PieceOrder.OrderIndex. Per piece: move first, then attack.
/// - Move: the shortest path is recomputed at resolution (BoardState.FindPath with the mover's owner):
///   friendlies can be passed, enemies and walls block, Frozen pieces cannot move. Unreachable -> MoveBlocked
///   (the piece stays). If the destination holds a friendly, that friendly is PUSHED one tile further in the
///   direction of the last step; a push may chain into further friendlies (up to GameConfig.MaxPushChain
///   pieces). If the push is impossible (edge, wall, enemy, chain too long) a PushBlocked event is emitted
///   and the mover stops on the last free tile of its path (MoveBlocked if there is none).
///   The attack is then re-checked for range from the actual position (AttackCancelled if out of range).
/// - Attack hits whatever piece stands on the target tile at that moment (empty tile = miss).
///   Enemy: takes the shot damage. Spell shields absorb first, then base shield, then HP.
///   Keywords on enemy hits: Burning (Lava on the tile), Frost (Frozen), Push (knock back 1 tile).
/// - Friendly target: takes NO damage (Mending: heals it), but is triggered (ChainTriggered) and fires
///   once: sideways along its row (owner's LEFT first, then RIGHT; Conduit: then also forward and back)
///   up to its EffectiveRange, hitting the NEAREST piece per direction (pieces and walls stop the shot).
///   Chain shot damage = EffectiveAttack (+ EchoBonusDamage with Echo) (x OverchargeMultiplier when
///   Overcharged; the status is consumed). Enemies take damage; friendlies chain further.
/// - Pierce: every shot of a Pierce piece also hits the piece directly behind the target (same rules,
///   one extra tile in the shot direction, no further pierce).
/// - Each piece fires at most once per resolution: a piece already fired (via its own order or a
///   chain) cannot be chain-triggered again, and a piece fired by a chain skips its own queued attack.
/// - Pieces reaching 0 HP die immediately (removed from the board, orders skipped) and their card
///   returns to the owner's deck (Undying: an upgraded copy with +1 Attack / +1 Hp / Level + 1).
/// </summary>
public static class OrderResolver
{
	private sealed class Context
	{
		public GameState State;
		public List<ResolutionEvent> Events;
		public readonly HashSet<int> Fired = new HashSet<int>();
		public BoardState Board => State.Board;
		public GameConfig Config => State.Config;
	}

	/// <summary>Resolves all orders of the given player's pieces and returns the chronological events.</summary>
	public static List<ResolutionEvent> Resolve(GameState state, int playerIndex)
	{
		var ctx = new Context { State = state, Events = new List<ResolutionEvent>() };

		var ordered = new List<Piece>();
		foreach (Piece p in state.GetPiecesOf(playerIndex))
		{
			if (p.Order != null)
			{
				ordered.Add(p);
			}
		}
		ordered.Sort((a, b) => a.Order.OrderIndex.CompareTo(b.Order.OrderIndex));

		foreach (Piece piece in ordered)
		{
			if (!piece.IsAlive || state.GetPiece(piece.Id) == null)
			{
				continue;
			}
			PieceOrder order = piece.Order;

			if (order.MoveTarget.HasValue && order.MoveTarget.Value != piece.Position)
			{
				ResolveMove(ctx, piece, order.MoveTarget.Value);
			}

			if (order.AttackTarget.HasValue && !ctx.Fired.Contains(piece.Id))
			{
				GridPos target = order.AttackTarget.Value;
				if (!state.Board.IsInAttackRange(piece.Position, target, piece.EffectiveRange))
				{
					ctx.Events.Add(new ResolutionEvent { Type = ResolutionEventType.AttackCancelled, PieceId = piece.Id, From = piece.Position, To = target });
					continue;
				}
				ctx.Fired.Add(piece.Id);
				HitTile(ctx, piece, target, false, false, piece.EffectiveAttack, true);
			}
		}

		return ctx.Events;
	}

	/// <summary>
	/// Resolves a single attack of 'attacker' on 'target' exactly like an order would (including chains and
	/// keywords) and MUTATES the given state. Intended for cloned states (previews / AI simulation).
	/// </summary>
	public static List<ResolutionEvent> SimulateAttack(GameState state, Piece attacker, GridPos target)
	{
		var ctx = new Context { State = state, Events = new List<ResolutionEvent>() };
		if (attacker == null || !attacker.IsAlive)
		{
			return ctx.Events;
		}
		ctx.Fired.Add(attacker.Id);
		HitTile(ctx, attacker, target, false, false, attacker.EffectiveAttack, true);
		return ctx.Events;
	}

	/// <summary>Resolves a single move with the v3 rules (pass-through, push) and MUTATES the state. For clones.</summary>
	public static List<ResolutionEvent> SimulateMove(GameState state, Piece piece, GridPos target)
	{
		var ctx = new Context { State = state, Events = new List<ResolutionEvent>() };
		if (piece != null && piece.IsAlive && piece.Position != target)
		{
			ResolveMove(ctx, piece, target);
		}
		return ctx.Events;
	}

	/// <summary>
	/// Turn-start tile ticks for the given player's pieces: Lava damages (GameConfig.LavaDamage, may kill),
	/// Healing heals (GameConfig.HealingTileAmount). Returns the events (TileDamage + Damaged/Died/
	/// ReturnedToDeck, TileHeal).
	/// </summary>
	public static List<ResolutionEvent> ResolveTurnStart(GameState state, int playerIndex)
	{
		var events = new List<ResolutionEvent>();
		foreach (Piece piece in state.GetPiecesOf(playerIndex))
		{
			if (!piece.IsAlive)
			{
				continue;
			}
			GridPos pos = piece.Position;
			switch (state.Board.GetTileEffectType(pos))
			{
				case TileEffectType.Lava:
					int dmg = Math.Max(0, state.Config.LavaDamage);
					events.Add(new ResolutionEvent
					{
						Type = ResolutionEventType.TileDamage,
						PieceId = piece.Id,
						From = pos,
						To = pos,
						Amount = dmg,
						TileEffect = TileEffectType.Lava,
					});
					ApplyDamage(state, piece, dmg, -1, events);
					break;
				case TileEffectType.Healing:
					int healed = Math.Min(Math.Max(0, state.Config.HealingTileAmount), piece.MaxHp - piece.CurrentHp);
					if (healed > 0)
					{
						piece.CurrentHp += healed;
						events.Add(new ResolutionEvent
						{
							Type = ResolutionEventType.TileHeal,
							PieceId = piece.Id,
							From = pos,
							To = pos,
							Amount = healed,
							RemainingHp = piece.CurrentHp,
							TileEffect = TileEffectType.Healing,
						});
					}
					break;
			}
		}
		return events;
	}

	/// <summary>
	/// Applies damage to a piece: spell shields first, then base shield, then HP. If it dies, the piece is
	/// removed and its card returns to the owner's deck (Undying: upgraded copy). Appends Damaged (and
	/// Died + ReturnedToDeck) events. Returns HP lost.
	/// </summary>
	public static int ApplyDamage(GameState state, Piece target, int amount, int sourcePieceId, List<ResolutionEvent> events)
	{
		if (amount <= 0 || !target.IsAlive)
		{
			return 0;
		}
		int remaining = amount;
		int absorbed = 0;
		foreach (ActiveSpell spell in target.ActiveSpells)
		{
			int take = Math.Min(spell.RemainingShield, remaining);
			spell.RemainingShield -= take;
			absorbed += take;
			remaining -= take;
		}
		int baseTake = Math.Min(target.CurrentShield, remaining);
		target.CurrentShield -= baseTake;
		absorbed += baseTake;
		remaining -= baseTake;

		int hpLost = Math.Min(target.CurrentHp, remaining);
		target.CurrentHp -= hpLost;

		events?.Add(new ResolutionEvent
		{
			Type = ResolutionEventType.Damaged,
			PieceId = target.Id,
			OtherPieceId = sourcePieceId,
			From = target.Position,
			To = target.Position,
			Amount = amount,
			ShieldAbsorbed = absorbed,
			HpLost = hpLost,
			RemainingHp = target.CurrentHp,
			RemainingShield = target.TotalShield,
		});

		if (target.CurrentHp <= 0)
		{
			GridPos pos = target.Position;
			state.RemovePiece(target);
			events?.Add(new ResolutionEvent { Type = ResolutionEventType.Died, PieceId = target.Id, From = pos, To = pos });
			ReturnToDeck(state, target, events);
		}
		return hpLost;
	}

	/// <summary>Heals a piece up to its MaxHp. Appends a Healed event if anything was healed. Returns HP healed.</summary>
	public static int ApplyHeal(GameState state, Piece target, int amount, int sourcePieceId, List<ResolutionEvent> events)
	{
		if (amount <= 0 || target == null || !target.IsAlive)
		{
			return 0;
		}
		int healed = Math.Min(amount, target.MaxHp - target.CurrentHp);
		if (healed <= 0)
		{
			return 0;
		}
		target.CurrentHp += healed;
		events?.Add(new ResolutionEvent
		{
			Type = ResolutionEventType.Healed,
			PieceId = target.Id,
			OtherPieceId = sourcePieceId,
			From = target.Position,
			To = target.Position,
			Amount = healed,
			RemainingHp = target.CurrentHp,
		});
		return healed;
	}

	/// <summary>
	/// Places a tile effect (no rule checks besides: on the board, and a Wall only on an empty tile).
	/// Replaces an existing effect on that tile. ExpiryTurn = TurnNumber + max(1, durationTurns).
	/// </summary>
	public static bool ApplyTileEffect(GameState state, TileEffectType type, GridPos pos, int durationTurns,
		int creatorIndex, string sourceName, int sourcePieceId, List<ResolutionEvent> events)
	{
		if (type == TileEffectType.None || !state.Board.IsInside(pos))
		{
			return false;
		}
		if (type == TileEffectType.Wall && state.Board.IsOccupied(pos))
		{
			return false;
		}
		int duration = Math.Max(1, durationTurns);
		int expiry = state.TurnNumber + duration;
		state.Board.SetTileEffect(new TileEffect(type, pos, creatorIndex, state.TurnNumber, expiry, sourceName));
		events?.Add(new ResolutionEvent
		{
			Type = ResolutionEventType.TileEffectApplied,
			OtherPieceId = sourcePieceId,
			PlayerIndex = creatorIndex,
			From = pos,
			To = pos,
			TileEffect = type,
			Amount = duration,
			ExpiryTurn = expiry,
			CardName = sourceName ?? "",
		});
		return true;
	}

	/// <summary>Adds (or refreshes) a status on a piece. ExpiryTurn = TurnNumber + max(1, durationTurns).</summary>
	public static void ApplyStatus(GameState state, Piece target, StatusEffectType type, int durationTurns,
		string sourceName, int sourcePieceId, List<ResolutionEvent> events)
	{
		if (type == StatusEffectType.None || target == null || !target.IsAlive)
		{
			return;
		}
		int expiry = state.TurnNumber + Math.Max(1, durationTurns);
		for (int i = target.StatusEffects.Count - 1; i >= 0; i--)
		{
			if (target.StatusEffects[i].Type == type)
			{
				expiry = Math.Max(expiry, target.StatusEffects[i].ExpiryTurn);
				target.StatusEffects.RemoveAt(i);
			}
		}
		target.StatusEffects.Add(new StatusEffect(type, state.TurnNumber, expiry, sourceName));
		events?.Add(new ResolutionEvent
		{
			Type = ResolutionEventType.StatusApplied,
			PieceId = target.Id,
			OtherPieceId = sourcePieceId,
			From = target.Position,
			To = target.Position,
			Status = type,
			ExpiryTurn = expiry,
		});
	}

	/// <summary>
	/// Main axis direction of a shot from 'from' to 'to' (unit vector; X wins ties). Used for Push and Pierce.
	/// </summary>
	public static GridPos AttackDirection(GridPos from, GridPos to)
	{
		int dx = to.X - from.X;
		int dy = to.Y - from.Y;
		if (dx == 0 && dy == 0)
		{
			return new GridPos(0, 0);
		}
		return Math.Abs(dx) >= Math.Abs(dy) ? new GridPos(Math.Sign(dx), 0) : new GridPos(0, Math.Sign(dy));
	}

	// ------------------------------------------------------------------ internals

	private static void ReturnToDeck(GameState state, Piece piece, List<ResolutionEvent> events)
	{
		CardData card = piece.Source;
		if (card == null || piece.OwnerIndex < 0 || piece.OwnerIndex >= state.Players.Length)
		{
			return;
		}
		bool undying = piece.HasKeyword(Keyword.Undying);
		CardData returned = undying ? card.CreateUndyingUpgrade() : card;
		state.Players[piece.OwnerIndex].Deck.Add(returned);
		events?.Add(new ResolutionEvent
		{
			Type = ResolutionEventType.ReturnedToDeck,
			PieceId = piece.Id,
			PlayerIndex = piece.OwnerIndex,
			From = piece.Position,
			To = piece.Position,
			CardName = returned.Name,
			Amount = undying ? returned.Level : 0,
		});
	}

	private static void ResolveMove(Context ctx, Piece piece, GridPos target)
	{
		GridPos from = piece.Position;
		List<GridPos> path = ctx.Board.FindPath(from, target, piece.EffectiveMovement, piece.OwnerIndex);
		if (path == null || path.Count == 0)
		{
			ctx.Events.Add(new ResolutionEvent { Type = ResolutionEventType.MoveBlocked, PieceId = piece.Id, From = from, To = target });
			return;
		}

		GridPos dest = path[^1];
		Piece occupant = ctx.Board.GetPieceAt(dest);
		if (occupant == null)
		{
			ctx.Board.MovePiece(piece, dest);
			ctx.Events.Add(MovedEvent(piece, from, path));
			return;
		}

		GridPos prev = path.Count >= 2 ? path[^2] : from;
		var pushEvents = new List<ResolutionEvent>();
		if (TryPushLine(ctx, occupant, dest - prev, true, piece.OwnerIndex, ctx.Config.MaxPushChain, piece.Id, pushEvents))
		{
			ctx.Board.MovePiece(piece, dest);
			ctx.Events.Add(MovedEvent(piece, from, path));
			ctx.Events.AddRange(pushEvents);
			return;
		}

		ctx.Events.AddRange(pushEvents);
		int stop = -1;
		for (int i = path.Count - 2; i >= 0; i--)
		{
			if (!ctx.Board.IsOccupied(path[i]))
			{
				stop = i;
				break;
			}
		}
		if (stop < 0)
		{
			ctx.Events.Add(new ResolutionEvent { Type = ResolutionEventType.MoveBlocked, PieceId = piece.Id, From = from, To = target });
			return;
		}
		List<GridPos> walked = path.GetRange(0, stop + 1);
		ctx.Board.MovePiece(piece, walked[^1]);
		ctx.Events.Add(MovedEvent(piece, from, walked));
	}

	private static ResolutionEvent MovedEvent(Piece piece, GridPos from, List<GridPos> path) => new ResolutionEvent
	{
		Type = ResolutionEventType.Moved,
		PieceId = piece.Id,
		From = from,
		To = path[^1],
		Path = path.ToArray(),
	};

	/// <summary>
	/// Pushes 'first' one tile in 'dir'. With allowChain, further pieces of chainOwner in the way are pushed
	/// too (line of at most maxChain pieces). Pushed events (farthest piece first) or one PushBlocked event
	/// are appended to 'events'. Returns true if the push happened.
	/// </summary>
	private static bool TryPushLine(Context ctx, Piece first, GridPos dir, bool allowChain, int chainOwner, int maxChain,
		int pusherId, List<ResolutionEvent> events)
	{
		var line = new List<Piece> { first };
		GridPos next = first.Position + dir;
		bool ok = dir != new GridPos(0, 0);
		while (ok)
		{
			if (!ctx.Board.IsPassable(next))
			{
				ok = false;
				break;
			}
			Piece p = ctx.Board.GetPieceAt(next);
			if (p == null)
			{
				break;
			}
			if (allowChain && p.OwnerIndex == chainOwner && line.Count < Math.Max(1, maxChain))
			{
				line.Add(p);
				next += dir;
				continue;
			}
			ok = false;
		}

		if (!ok)
		{
			events.Add(new ResolutionEvent
			{
				Type = ResolutionEventType.PushBlocked,
				PieceId = first.Id,
				OtherPieceId = pusherId,
				From = first.Position,
				To = first.Position + dir,
			});
			return false;
		}

		for (int i = line.Count - 1; i >= 0; i--)
		{
			Piece p = line[i];
			GridPos from = p.Position;
			GridPos to = from + dir;
			ctx.Board.MovePiece(p, to);
			events.Add(new ResolutionEvent { Type = ResolutionEventType.Pushed, PieceId = p.Id, OtherPieceId = pusherId, From = from, To = to });
		}
		return true;
	}

	private static void HitTile(Context ctx, Piece attacker, GridPos tile, bool isChain, bool isPierce, int damage, bool allowPierce)
	{
		Piece target = ctx.Board.GetPieceAt(tile);
		ctx.Events.Add(new ResolutionEvent
		{
			Type = ResolutionEventType.Attacked,
			PieceId = attacker.Id,
			OtherPieceId = target?.Id ?? -1,
			From = attacker.Position,
			To = tile,
			IsChain = isChain,
			IsPierce = isPierce,
		});

		GridPos dir = AttackDirection(attacker.Position, tile);
		Piece behind = null;
		GridPos behindTile = tile + dir;
		if (allowPierce && attacker.HasKeyword(Keyword.Pierce) && ctx.Board.IsPassable(behindTile))
		{
			behind = ctx.Board.GetPieceAt(behindTile);
		}

		if (target != null)
		{
			if (target.OwnerIndex != attacker.OwnerIndex)
			{
				HitEnemy(ctx, attacker, target, tile, dir, damage);
			}
			else
			{
				if (attacker.HasKeyword(Keyword.Mending))
				{
					ApplyHeal(ctx.State, target, ctx.Config.MendingHeal, attacker.Id, ctx.Events);
				}
				if (!ctx.Fired.Contains(target.Id))
				{
					ctx.Fired.Add(target.Id);
					ctx.Events.Add(new ResolutionEvent
					{
						Type = ResolutionEventType.ChainTriggered,
						PieceId = target.Id,
						OtherPieceId = attacker.Id,
						From = attacker.Position,
						To = target.Position,
					});
					FireChain(ctx, target);
				}
			}
		}

		if (behind != null && behind.IsAlive && attacker.IsAlive && ctx.Board.GetPieceAt(behindTile) == behind)
		{
			HitTile(ctx, attacker, behindTile, isChain, true, damage, false);
		}
	}

	private static void HitEnemy(Context ctx, Piece attacker, Piece target, GridPos tile, GridPos dir, int damage)
	{
		ApplyDamage(ctx.State, target, damage, attacker.Id, ctx.Events);
		if (attacker.HasKeyword(Keyword.Burning))
		{
			ApplyTileEffect(ctx.State, TileEffectType.Lava, tile, ctx.Config.BurningLavaDuration,
				attacker.OwnerIndex, attacker.Source?.Name ?? "Burning", attacker.Id, ctx.Events);
		}
		if (!target.IsAlive)
		{
			return;
		}
		if (attacker.HasKeyword(Keyword.Frost))
		{
			ApplyStatus(ctx.State, target, StatusEffectType.Frozen, ctx.Config.FrostDuration,
				attacker.Source?.Name ?? "Frost", attacker.Id, ctx.Events);
		}
		if (attacker.HasKeyword(Keyword.Push))
		{
			TryPushLine(ctx, target, dir, false, -1, 1, attacker.Id, ctx.Events);
		}
	}

	private static void FireChain(Context ctx, Piece shooter)
	{
		int damage = shooter.EffectiveAttack;
		if (shooter.HasKeyword(Keyword.Echo))
		{
			damage += ctx.Config.EchoBonusDamage;
		}
		for (int i = shooter.StatusEffects.Count - 1; i >= 0; i--)
		{
			if (shooter.StatusEffects[i].Type != StatusEffectType.Overcharged)
			{
				continue;
			}
			shooter.StatusEffects.RemoveAt(i);
			damage *= Math.Max(1, ctx.Config.OverchargeMultiplier);
			ctx.Events.Add(new ResolutionEvent
			{
				Type = ResolutionEventType.StatusExpired,
				PieceId = shooter.Id,
				From = shooter.Position,
				To = shooter.Position,
				Status = StatusEffectType.Overcharged,
				IsChain = true,
			});
			break;
		}

		int left = BoardState.LeftDirection(shooter.OwnerIndex);
		int forward = BoardState.ForwardDirection(shooter.OwnerIndex);
		var dirs = new List<GridPos> { new GridPos(left, 0), new GridPos(-left, 0) };
		if (shooter.HasKeyword(Keyword.Conduit))
		{
			dirs.Add(new GridPos(0, forward));
			dirs.Add(new GridPos(0, -forward));
		}

		int range = shooter.EffectiveRange;
		foreach (GridPos dir in dirs)
		{
			if (!shooter.IsAlive)
			{
				return;
			}
			for (int d = 1; d <= range; d++)
			{
				var tile = new GridPos(shooter.Position.X + dir.X * d, shooter.Position.Y + dir.Y * d);
				if (!ctx.Board.IsPassable(tile))
				{
					break;
				}
				if (ctx.Board.IsOccupied(tile))
				{
					HitTile(ctx, shooter, tile, true, false, damage, true);
					break;
				}
			}
		}
	}
}
