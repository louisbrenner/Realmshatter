using System;
using System.Collections.Generic;

namespace Realmshatter;

/// <summary>
/// Resolves piece actions immediately (there is no end-of-turn resolution), plus the shared damage / heal /
/// tile / status helpers.
///
/// Rules (v4):
/// - A piece acts once per turn: it moves, then attacks; both resolve the moment the attack is declared.
/// - Move: shortest path (BoardState.FindPath with the mover's owner): friendlies can be passed, enemies and walls
///   block, Frozen pieces cannot move. If the destination holds a friendly, that friendly is PUSHED one tile further
///   in the direction of the last step (a line of up to GameConfig.MaxPushChain friendlies can be pushed). If the
///   push is impossible a PushBlocked event is emitted and the mover stops on the last free tile of its path.
///   The attack is then re-checked for range from the actual position (AttackCancelled if out of range).
/// - Attack hits whatever piece stands on the target tile (empty tile = miss). Friend or foe, the target takes the
///   damage (spell shields absorb first, then base shield, then HP): friendly fire is real. Only Mending turns a
///   hit on a friendly into a heal (GameConfig.MendingHeal) instead of damage.
///   On-hit keywords apply to every damaged piece: Burning (Lava on the tile), Frost (Frozen), Push (knock back).
/// - Overcharged: the attack deals GameConfig.OverchargeMultiplier x damage; the status is consumed.
/// - Pierce: also hits the piece directly behind the target (same damage, no further pierce).
/// - Arc: also zaps every piece orthogonally adjacent to the target tile (except the attacker) for
///   GameConfig.ArcDamage - friend or foe.
/// - Echo: after the attack it strikes the same tile a second time for GameConfig.EchoBonusDamage.
/// - Pieces reaching 0 HP die immediately; their card is gone, except Undying cards, which return to the owner's
///   deck as an upgraded copy.
/// </summary>
public static class OrderResolver
{
	private sealed class Context
	{
		public GameState State;
		public List<ResolutionEvent> Events;
		public BoardState Board => State.Board;
		public GameConfig Config => State.Config;
	}

	/// <summary>
	/// Resolves one piece action right away: optional move (move != null and != position), then optional attack on
	/// tile 'attack'. Mutates the state and returns the chronological events. No rule / AP checks.
	/// </summary>
	public static List<ResolutionEvent> ResolveAction(GameState state, Piece piece, GridPos? move, GridPos? attack)
	{
		var ctx = new Context { State = state, Events = new List<ResolutionEvent>() };
		if (piece == null || !piece.IsAlive || state.GetPiece(piece.Id) == null)
		{
			return ctx.Events;
		}
		if (move.HasValue && move.Value != piece.Position)
		{
			ResolveMove(ctx, piece, move.Value);
			TriggerTurrets(ctx, piece);
		}
		if (attack.HasValue && piece.IsAlive && state.GetPiece(piece.Id) != null)
		{
			GridPos target = attack.Value;
			if (!state.Board.IsInAttackRange(piece.Position, target, piece.EffectiveRange))
			{
				ctx.Events.Add(new ResolutionEvent { Type = ResolutionEventType.AttackCancelled, PieceId = piece.Id, From = piece.Position, To = target });
			}
			else
			{
				Strike(ctx, piece, target);
			}
		}
		return ctx.Events;
	}

	/// <summary>
	/// Resolves a single attack of 'attacker' on 'target' exactly like an action would (keywords, friendly fire)
	/// and MUTATES the given state. Intended for cloned states (previews / AI simulation).
	/// </summary>
	public static List<ResolutionEvent> SimulateAttack(GameState state, Piece attacker, GridPos target)
	{
		var ctx = new Context { State = state, Events = new List<ResolutionEvent>() };
		if (attacker != null && attacker.IsAlive)
		{
			Strike(ctx, attacker, target);
		}
		return ctx.Events;
	}

	/// <summary>Resolves a single move (pass-through, push) and MUTATES the state. For clones.</summary>
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
				case TileEffectType.Storm:
					events.Add(new ResolutionEvent
					{
						Type = ResolutionEventType.TileDamage,
						PieceId = piece.Id,
						From = pos,
						To = pos,
						Amount = 1,
						TileEffect = TileEffectType.Storm,
					});
					ApplyDamage(state, piece, 1, -1, events);
					foreach (GridPos n in pos.Neighbors())
					{
						Piece near = state.Board.GetPieceAt(n);
						if (near != null && near.IsAlive)
						{
							ApplyDamage(state, near, 1, -1, events);
						}
					}
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
	/// removed (Undying: an upgraded copy returns to the owner's deck). Appends Damaged (and
	/// Died + ReturnedToDeck) events. Returns HP lost.
	/// </summary>
	public static int ApplyDamage(GameState state, Piece target, int amount, int sourcePieceId, List<ResolutionEvent> events)
	{
		if (amount <= 0 || !target.IsAlive)
		{
			return 0;
		}
		if (target.Source?.Legend == LegendEffect.Unbreakable)
		{
			amount = 1; // Unbreakable: never more than 1 damage per hit
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
			Piece killer = sourcePieceId >= 0 ? state.GetPiece(sourcePieceId) : null;
			if (killer != null && killer.OwnerIndex != target.OwnerIndex && killer.HasKeyword(Keyword.Plunder))
			{
				GrantAp(state, killer.OwnerIndex, 1, killer.Id, killer.Source?.Name ?? "Plunder", pos, events);
			}
			if (target.IsBuilding)
			{
				OnBuildingDestroyed(state, target, pos, events ?? new List<ResolutionEvent>());
			}
			else
			{
				ReturnToDeck(state, target, events);
				TriggerDeathrattle(state, target, pos, events ?? new List<ResolutionEvent>());
				if (target.ConstructingId >= 0)
				{
					// The builder died: its unfinished buildings (a Barricade build places two) collapse.
					target.ConstructingId = -1;
					foreach (Piece site in new List<Piece>(state.Pieces))
					{
						if (site.IsBuilding && site.BuilderId == target.Id && site.UnderConstruction && state.GetPiece(site.Id) != null)
						{
							ApplyDamage(state, site, site.CurrentHp + site.TotalShield + 100, -1, events);
						}
					}
				}
			}
		}
		else if (!target.WasHit)
		{
			target.WasHit = true;
			TriggerFirstHit(state, target, sourcePieceId, events ?? new List<ResolutionEvent>());
		}
		return hpLost;
	}

	/// <summary>A destroyed building frees its builder and leaves impassable rubble for GameConfig.RubbleDuration turns.</summary>
	private static void OnBuildingDestroyed(GameState state, Piece building, GridPos pos, List<ResolutionEvent> events)
	{
		Piece builder = building.BuilderId >= 0 ? state.GetPiece(building.BuilderId) : null;
		if (builder != null && builder.ConstructingId == building.Id)
		{
			// Still pinned while another of its buildings (the second Barricade) is unfinished.
			Piece other = new List<Piece>(state.Pieces).Find(p => p.IsBuilding && p.BuilderId == builder.Id && p.UnderConstruction && p.Id != building.Id);
			builder.ConstructingId = other?.Id ?? -1;
		}
		ApplyTileEffect(state, TileEffectType.Rubble, pos, Math.Max(1, state.Config.RubbleDuration), -1,
			$"{building.Source?.Name ?? "Building"} ruins", building.Id, events);
	}

	/// <summary>
	/// Finished enemy turrets that have not fired this turn shoot at a piece that just moved into their range.
	/// </summary>
	private static void TriggerTurrets(Context ctx, Piece mover)
	{
		foreach (Piece turret in new List<Piece>(ctx.State.Pieces))
		{
			if (!mover.IsAlive || ctx.State.GetPiece(mover.Id) == null)
			{
				return;
			}
			if (turret.Building != BuildingType.Turret || turret.UnderConstruction || turret.OwnerIndex == mover.OwnerIndex
				|| turret.ReactedTurn == ctx.State.TurnNumber || turret.EffectiveAttack <= 0
				|| !ctx.Board.IsInAttackRange(turret.Position, mover.Position, turret.EffectiveRange))
			{
				continue;
			}
			turret.ReactedTurn = ctx.State.TurnNumber;
			HitTile(ctx, turret, mover.Position, turret.EffectiveAttack, false, false, false);
		}
	}

	/// <summary>
	/// Turn start of a player's buildings: unfinished buildings whose time has come are finished (builder freed),
	/// finished Shrines heal the owner's pieces on the 8 surrounding tiles.
	/// </summary>
	public static List<ResolutionEvent> ResolveBuildingsTurnStart(GameState state, int playerIndex)
	{
		var events = new List<ResolutionEvent>();
		foreach (Piece b in state.GetPiecesOf(playerIndex))
		{
			if (!b.IsBuilding)
			{
				continue;
			}
			if (b.UnderConstruction && state.TurnNumber >= b.CompleteTurn)
			{
				b.UnderConstruction = false;
				Piece builder = b.BuilderId >= 0 ? state.GetPiece(b.BuilderId) : null;
				if (builder != null && builder.ConstructingId == b.Id)
				{
					builder.ConstructingId = -1;
				}
				events.Add(new ResolutionEvent
				{
					Type = ResolutionEventType.BuildingCompleted,
					PieceId = b.Id,
					PlayerIndex = playerIndex,
					From = b.Position,
					To = b.Position,
					SpellName = BuildingInfo.GetName(b.Building),
				});
			}
			else if (!b.UnderConstruction && b.Building == BuildingType.Shrine)
			{
				foreach (Piece ally in Around(state, b.Position))
				{
					if (ally.OwnerIndex == playerIndex && !ally.IsBuilding)
					{
						ApplyHeal(state, ally, 1, b.Id, events);
					}
				}
			}
		}
		return events;
	}

	/// <summary>
	/// Turn start auras of a player's units: each Aura unit pulses its clan effect on the 8 surrounding tiles
	/// (Fire: 1 damage to enemies, Healing: heal allies 1, Frost: freeze enemies, Storm: allies +1 Attack this turn,
	/// Stone: allies +1 Shield up to 2).
	/// </summary>
	/// <summary>
	/// Turn start of a player's Legendary units: Wildfire (enemies on Lava take damage), Dawnlight (full heal nearby),
	/// Glacial Grip (freeze enemies nearby) and Chain Lightning (strike the nearest enemies). Each fires an AuraPulse
	/// event with the effect's name first. Unbreakable works in ApplyDamage instead.
	/// </summary>
	public static List<ResolutionEvent> ResolveLegends(GameState state, int playerIndex)
	{
		var events = new List<ResolutionEvent>();
		foreach (Piece source in new List<Piece>(state.GetPiecesOf(playerIndex)))
		{
			LegendEffect legend = source.Source?.Legend ?? LegendEffect.None;
			if (legend is LegendEffect.None or LegendEffect.Unbreakable || source.IsBuilding || !source.IsAlive || state.GetPiece(source.Id) == null)
			{
				continue;
			}
			events.Add(new ResolutionEvent
			{
				Type = ResolutionEventType.AuraPulse,
				PieceId = source.Id,
				PlayerIndex = playerIndex,
				From = source.Position,
				To = source.Position,
				SpellName = LegendInfo.GetName(legend),
				CardName = (source.Source?.Clan ?? Clan.None).ToString(),
			});
			var enemies = new List<Piece>();
			foreach (Piece p in state.Pieces)
			{
				if (p.OwnerIndex != playerIndex && p.IsAlive)
				{
					enemies.Add(p);
				}
			}
			switch (legend)
			{
				case LegendEffect.Wildfire:
					foreach (Piece e in enemies)
					{
						if (state.Board.GetTileEffectType(e.Position) == TileEffectType.Lava)
						{
							ApplyDamage(state, e, LegendInfo.WildfireDamage, source.Id, events);
						}
					}
					break;
				case LegendEffect.Dawnlight:
					foreach (Piece ally in new List<Piece>(state.GetPiecesOf(playerIndex)))
					{
						if (!ally.IsBuilding && ally.CurrentHp < ally.MaxHp && ally.Position.ManhattanDistance(source.Position) <= LegendInfo.DawnlightRadius)
						{
							ApplyHeal(state, ally, ally.MaxHp - ally.CurrentHp, source.Id, events);
						}
					}
					break;
				case LegendEffect.GlacialGrip:
					foreach (Piece e in enemies)
					{
						if (!e.IsBuilding && e.Position.ManhattanDistance(source.Position) <= LegendInfo.GlacialGripRadius)
						{
							ApplyStatus(state, e, StatusEffectType.Frozen, state.Config.FrostDuration, LegendInfo.GetName(legend), source.Id, events);
						}
					}
					break;
				case LegendEffect.ChainLightning:
					enemies.RemoveAll(e => e.Position.ManhattanDistance(source.Position) > LegendInfo.ChainLightningRadius);
					enemies.Sort((a, b) =>
					{
						int da = a.Position.ManhattanDistance(source.Position);
						int db = b.Position.ManhattanDistance(source.Position);
						return da != db ? da.CompareTo(db) : a.Id.CompareTo(b.Id);
					});
					for (int i = 0; i < enemies.Count && i < LegendInfo.ChainLightningTargets; i++)
					{
						ApplyDamage(state, enemies[i], 1, source.Id, events);
					}
					break;
			}
		}
		return events;
	}

	public static List<ResolutionEvent> ResolveAuras(GameState state, int playerIndex)
	{
		var events = new List<ResolutionEvent>();
		foreach (Piece source in state.GetPiecesOf(playerIndex))
		{
			if (source.IsBuilding || !source.HasKeyword(Keyword.Aura) || !source.IsAlive || state.GetPiece(source.Id) == null)
			{
				continue;
			}
			Clan clan = source.Source?.Clan ?? Clan.None;
			events.Add(new ResolutionEvent
			{
				Type = ResolutionEventType.AuraPulse,
				PieceId = source.Id,
				PlayerIndex = playerIndex,
				From = source.Position,
				To = source.Position,
				SpellName = TriggerInfo.AuraName(clan),
				CardName = clan.ToString(),
			});
			foreach (Piece p in Around(state, source.Position))
			{
				bool ally = p.OwnerIndex == playerIndex;
				switch (clan)
				{
					case Clan.Fire:
						if (!ally)
						{
							ApplyDamage(state, p, 1, source.Id, events);
						}
						break;
					case Clan.Healing:
						if (ally)
						{
							ApplyHeal(state, p, 1, source.Id, events);
						}
						break;
					case Clan.Frost:
						if (!ally && !p.IsBuilding)
						{
							ApplyStatus(state, p, StatusEffectType.Frozen, state.Config.FrostDuration, TriggerInfo.AuraName(clan), source.Id, events);
						}
						break;
					case Clan.Storm:
						if (ally && !p.IsBuilding)
						{
							p.ActiveSpells.Add(new ActiveSpell(source.Source, new SpellEffect { AttackDelta = 1 }, playerIndex, state.TurnNumber, state.TurnNumber));
						}
						break;
					case Clan.Stone:
						if (ally && p.CurrentShield < 2)
						{
							p.CurrentShield += 1;
						}
						break;
				}
			}
		}
		return events;
	}

	/// <summary>Living pieces on the 8 tiles around a position.</summary>
	private static List<Piece> Around(GameState state, GridPos center)
	{
		var list = new List<Piece>();
		for (int dy = -1; dy <= 1; dy++)
		{
			for (int dx = -1; dx <= 1; dx++)
			{
				if (dx == 0 && dy == 0)
				{
					continue;
				}
				Piece p = state.Board.GetPieceAt(new GridPos(center.X + dx, center.Y + dy));
				if (p != null && p.IsAlive)
				{
					list.Add(p);
				}
			}
		}
		return list;
	}

	/// <summary>Pushes a piece 1 tile in 'dir' if that tile is free (edge, wall or piece = PushBlocked). Appends events.</summary>
	public static bool PushPiece(GameState state, Piece piece, GridPos dir, int pusherId, List<ResolutionEvent> events)
	{
		if (piece == null || !piece.IsAlive || state.GetPiece(piece.Id) == null || dir == new GridPos(0, 0))
		{
			return false;
		}
		var ctx = new Context { State = state, Events = events ?? new List<ResolutionEvent>() };
		return TryPushLine(ctx, piece, dir, false, -1, 1, pusherId, ctx.Events);
	}

	/// <summary>Pushes every piece next to 'center' one tile away from it (shockwaves).</summary>
	public static void PushNeighborsAway(GameState state, GridPos center, int pusherId, List<ResolutionEvent> events)
	{
		var pieces = new List<Piece>();
		foreach (GridPos n in center.Neighbors())
		{
			Piece p = state.Board.GetPieceAt(n);
			if (p != null)
			{
				pieces.Add(p);
			}
		}
		foreach (Piece p in pieces)
		{
			PushPiece(state, p, p.Position - center, pusherId, events);
		}
	}

	private static void TriggerDeathrattle(GameState state, Piece dead, GridPos pos, List<ResolutionEvent> events)
	{
		CardData card = dead.Source;
		if (card == null || card.Deathrattle == DeathrattleType.None)
		{
			return;
		}
		int amount = Math.Max(1, card.DeathrattleAmount);
		events.Add(new ResolutionEvent
		{
			Type = ResolutionEventType.Deathrattle,
			PieceId = dead.Id,
			PlayerIndex = dead.OwnerIndex,
			From = pos,
			To = pos,
			SpellName = TriggerInfo.GetName(card.Deathrattle),
			CardName = card.Name,
			Amount = amount,
		});
		int duration = Math.Max(1, state.Config.TriggerEffectDuration);
		switch (card.Deathrattle)
		{
			case DeathrattleType.Explode:
			{
				var victims = new List<Piece>();
				foreach (GridPos n in pos.Neighbors())
				{
					Piece p = state.Board.GetPieceAt(n);
					if (p != null)
					{
						victims.Add(p);
					}
				}
				foreach (Piece p in victims)
				{
					if (p.IsAlive && state.GetPiece(p.Id) != null)
					{
						ApplyDamage(state, p, amount, dead.Id, events);
					}
				}
				break;
			}
			case DeathrattleType.Shockwave:
				PushNeighborsAway(state, pos, dead.Id, events);
				break;
			case DeathrattleType.LavaPool:
				ApplyTileEffect(state, TileEffectType.Lava, pos, duration, dead.OwnerIndex, card.Name, dead.Id, events);
				foreach (GridPos n in pos.Neighbors())
				{
					ApplyTileEffect(state, TileEffectType.Lava, n, duration, dead.OwnerIndex, card.Name, dead.Id, events);
				}
				break;
			case DeathrattleType.HealAllies:
				foreach (Piece p in new List<Piece>(state.GetPiecesOf(dead.OwnerIndex)))
				{
					if (p.Position.ManhattanDistance(pos) <= 2)
					{
						ApplyHeal(state, p, amount, dead.Id, events);
					}
				}
				break;
			case DeathrattleType.RaiseWalls:
				foreach (GridPos n in pos.Neighbors())
				{
					if (state.Board.IsPassable(n) && !state.Board.IsOccupied(n))
					{
						ApplyTileEffect(state, TileEffectType.Wall, n, duration, dead.OwnerIndex, card.Name, dead.Id, events);
					}
				}
				break;
			case DeathrattleType.FrostNova:
				foreach (GridPos n in pos.Neighbors())
				{
					Piece p = state.Board.GetPieceAt(n);
					if (p != null && p.OwnerIndex != dead.OwnerIndex && !p.IsBuilding)
					{
						ApplyStatus(state, p, StatusEffectType.Frozen, state.Config.FrostDuration, card.Name, dead.Id, events);
					}
				}
				break;
			case DeathrattleType.Tribute:
				state.Players[dead.OwnerIndex].PendingAp += amount;
				events.Add(new ResolutionEvent
				{
					Type = ResolutionEventType.ApGained,
					PieceId = dead.Id,
					PlayerIndex = dead.OwnerIndex,
					From = pos,
					To = pos,
					Amount = amount,
					CardName = card.Name,
					IsSecondary = true,
				});
				break;
			case DeathrattleType.DrawCard:
			{
				PlayerState owner = state.Players[dead.OwnerIndex];
				for (int i = 0; i < amount && owner.Deck.Count > 0; i++)
				{
					int index = state.Random.Next(owner.Deck.Count);
					owner.Hand.Add(owner.Deck[index]);
					owner.Deck.RemoveAt(index);
				}
				break;
			}
		}
	}

	private static void TriggerFirstHit(GameState state, Piece target, int sourcePieceId, List<ResolutionEvent> events)
	{
		CardData card = target.Source;
		if (card == null || card.OnFirstHit == FirstHitType.None)
		{
			return;
		}
		int amount = Math.Max(1, card.OnFirstHitAmount);
		Piece source = sourcePieceId >= 0 ? state.GetPiece(sourcePieceId) : null;
		if (source == target)
		{
			source = null;
		}
		if (card.OnFirstHit == FirstHitType.Harden)
		{
			target.CurrentShield += amount;
		}
		else if (card.OnFirstHit == FirstHitType.Enrage)
		{
			target.BonusAttack += amount;
		}
		events.Add(new ResolutionEvent
		{
			Type = ResolutionEventType.FirstHitTriggered,
			PieceId = target.Id,
			OtherPieceId = sourcePieceId,
			From = target.Position,
			To = target.Position,
			SpellName = TriggerInfo.GetName(card.OnFirstHit),
			CardName = card.Name,
			Amount = amount,
			RemainingHp = target.CurrentHp,
			RemainingShield = target.TotalShield,
		});
		switch (card.OnFirstHit)
		{
			case FirstHitType.Thorns:
				if (source != null && source.IsAlive)
				{
					ApplyDamage(state, source, amount, target.Id, events);
				}
				break;
			case FirstHitType.Repel:
				if (source != null && source.IsAlive)
				{
					PushPiece(state, source, AttackDirection(target.Position, source.Position), target.Id, events);
				}
				break;
			case FirstHitType.Shockwave:
				PushNeighborsAway(state, target.Position, target.Id, events);
				break;
		}
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
		// The crown field never carries tile effects (no lava, walls, healing or rubble on it).
		if (type == TileEffectType.None || !state.Board.IsInside(pos) || state.Board.IsInHotZone(pos))
		{
			return false;
		}
		if (type == TileEffectType.Wall && state.Board.IsOccupied(pos))
		{
			return false;
		}
		// Permanent map effects stay; nothing grows on walls or rocks.
		if (state.Board.GetTileEffect(pos)?.IsPermanent == true || (type != TileEffectType.Wall && state.Board.IsWall(pos)))
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

	/// <summary>
	/// Adds (or refreshes) a status on a piece. ExpiryTurn = TurnNumber + max(1, durationTurns); Frozen always lasts
	/// through the victim owner's next turn.
	/// </summary>
	public static void ApplyStatus(GameState state, Piece target, StatusEffectType type, int durationTurns,
		string sourceName, int sourcePieceId, List<ResolutionEvent> events)
	{
		if (type == StatusEffectType.None || target == null || !target.IsAlive)
		{
			return;
		}
		int expiry = state.TurnNumber + Math.Max(1, durationTurns);
		if (type == StatusEffectType.Frozen && target.OwnerIndex == state.CurrentPlayerIndex)
		{
			// Frozen during its owner's own turn (e.g. by a deathrattle its attack triggered): it must still sit out
			// the owner's NEXT turn, not thaw before it could move again.
			expiry = Math.Max(expiry, state.TurnNumber + 2);
		}
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

	/// <summary>
	/// Springs a trap on the piece standing on it: removes the trap, appends TrapTriggered and applies the trap's
	/// effect (see TrapInfo). The Trapper (if still alive) counts as the damage source.
	/// </summary>
	public static void TriggerTrap(GameState state, Piece victim, Trap trap, List<ResolutionEvent> events)
	{
		state.Board.RemoveTrap(trap.Position);
		GridPos pos = trap.Position;
		events.Add(new ResolutionEvent
		{
			Type = ResolutionEventType.TrapTriggered,
			PieceId = victim.Id,
			PlayerIndex = trap.OwnerIndex,
			From = pos,
			To = pos,
			CardName = TrapInfo.GetName(trap.Type),
			SpellName = trap.Type.ToString(),
		});
		int source = state.GetPiece(trap.SourcePieceId) != null ? trap.SourcePieceId : -1;
		string name = TrapInfo.GetName(trap.Type);
		switch (trap.Type)
		{
			case TrapType.Fire:
				ApplyDamage(state, victim, 1, source, events);
				ApplyTileEffect(state, TileEffectType.Lava, pos, state.Config.BurningLavaDuration, trap.OwnerIndex, name, source, events);
				break;
			case TrapType.Frost:
				ApplyDamage(state, victim, 1, source, events);
				if (victim.IsAlive)
				{
					// +1: it is the victim's own turn, so the freeze has to last through its next one.
					ApplyStatus(state, victim, StatusEffectType.Frozen, state.Config.FrostDuration + 1, name, source, events);
				}
				break;
			case TrapType.Shock:
				ApplyDamage(state, victim, 1, source, events);
				foreach (GridPos n in pos.Neighbors())
				{
					Piece p = state.Board.GetPieceAt(n);
					if (p != null && p.OwnerIndex != trap.OwnerIndex)
					{
						ApplyDamage(state, p, 1, source, events);
					}
				}
				break;
			case TrapType.Pitfall:
				ApplyDamage(state, victim, 3, source, events);
				break;
			case TrapType.Sanctum:
				ApplyDamage(state, victim, 1, source, events);
				foreach (Piece ally in new List<Piece>(state.GetPiecesOf(trap.OwnerIndex)))
				{
					if (!ally.IsBuilding && ally.Position.ManhattanDistance(pos) <= 2)
					{
						ApplyHeal(state, ally, 1, source, events);
					}
				}
				break;
			default:
				ApplyDamage(state, victim, 2, source, events);
				break;
		}
	}

	/// <summary>Damages a breakable Rock and appends a TerrainDamaged event (RemainingHp 0 = it crumbled).</summary>
	public static void DamageRock(GameState state, GridPos tile, int damage, List<ResolutionEvent> events)
	{
		int remaining = state.Board.DamageRock(tile, damage);
		if (remaining < 0)
		{
			return;
		}
		events?.Add(new ResolutionEvent
		{
			Type = ResolutionEventType.TerrainDamaged,
			From = tile,
			To = tile,
			Amount = damage,
			RemainingHp = remaining,
		});
	}

	/// <summary>
	/// Gives a player AP from a card effect: right away during its own turn, otherwise at the start of its next turn
	/// (PlayerState.PendingAp). Appends an ApGained event.
	/// </summary>
	public static void GrantAp(GameState state, int player, int amount, int sourcePieceId, string source, GridPos at, List<ResolutionEvent> events)
	{
		if (amount <= 0 || player < 0 || player >= state.Players.Length)
		{
			return;
		}
		bool now = state.CurrentPlayerIndex == player && state.Phase != GamePhase.GameOver;
		if (now)
		{
			state.Players[player].ActionPoints += amount;
		}
		else
		{
			state.Players[player].PendingAp += amount;
		}
		events?.Add(new ResolutionEvent
		{
			Type = ResolutionEventType.ApGained,
			PieceId = sourcePieceId,
			PlayerIndex = player,
			From = at,
			To = at,
			Amount = amount,
			CardName = source,
			IsSecondary = !now,
		});
	}

	// ------------------------------------------------------------------ internals

	private static void ReturnToDeck(GameState state, Piece piece, List<ResolutionEvent> events)
	{
		CardData card = piece.Source;
		if (card == null || piece.OwnerIndex < 0 || piece.OwnerIndex >= state.Players.Length)
		{
			return;
		}
		// Destroyed cards are lost; only Undying cards come back, stronger each time.
		if (!piece.HasKeyword(Keyword.Undying))
		{
			state.Players[piece.OwnerIndex].Graveyard.Add(card);
			return;
		}
		CardData returned = card.CreateUndyingUpgrade();
		state.Players[piece.OwnerIndex].Deck.Add(returned);
		events?.Add(new ResolutionEvent
		{
			Type = ResolutionEventType.ReturnedToDeck,
			PieceId = piece.Id,
			PlayerIndex = piece.OwnerIndex,
			From = piece.Position,
			To = piece.Position,
			CardName = returned.Name,
			Amount = returned.Level,
		});
	}

	/// <summary>
	/// Moves a piece along its path (pushing friendlies at the end). An enemy trap on the way stops the move on its
	/// tile and springs (TriggerTrap).
	/// </summary>
	private static void ResolveMove(Context ctx, Piece piece, GridPos target)
	{
		GridPos from = piece.Position;
		List<GridPos> path = ctx.Board.FindPath(from, target, piece.EffectiveMovement, piece.OwnerIndex);
		if (path == null || path.Count == 0)
		{
			ctx.Events.Add(new ResolutionEvent { Type = ResolutionEventType.MoveBlocked, PieceId = piece.Id, From = from, To = target });
			return;
		}
		Trap trap = null;
		for (int i = 0; i < path.Count; i++)
		{
			if (ctx.Board.IsOccupied(path[i]))
			{
				continue;
			}
			Trap t = ctx.Board.GetTrap(path[i]);
			if (t != null && t.OwnerIndex != piece.OwnerIndex)
			{
				trap = t;
				path = path.GetRange(0, i + 1);
				break;
			}
			if (ctx.Board.GetTileEffectType(path[i]) == TileEffectType.Ice && i < path.Count - 1)
			{
				// Slides to a halt on the ice.
				path = path.GetRange(0, i + 1);
				break;
			}
		}
		MoveAlong(ctx, piece, from, target, path);
		if (trap != null && piece.IsAlive && piece.Position == trap.Position)
		{
			TriggerTrap(ctx.State, piece, trap, ctx.Events);
		}
	}

	private static void MoveAlong(Context ctx, Piece piece, GridPos from, GridPos target, List<GridPos> path)
	{

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
	/// A real push (no chain: Push hits, shockwaves, push spells, Repel) that is stopped by an object - another
	/// piece, a building, a wall or a rock - slams the pushed piece into it: it takes GameConfig.PushCollisionDamage
	/// instead of moving. The board edge only blocks.
	/// </summary>
	private static bool TryPushLine(Context ctx, Piece first, GridPos dir, bool allowChain, int chainOwner, int maxChain,
		int pusherId, List<ResolutionEvent> events)
	{
		var line = new List<Piece> { first };
		GridPos next = first.Position + dir;
		bool ok = dir != new GridPos(0, 0) && !first.IsBuilding;
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
			if (allowChain && p.OwnerIndex == chainOwner && !p.IsBuilding && line.Count < Math.Max(1, maxChain))
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
			GridPos into = first.Position + dir;
			bool hitsObject = ctx.Board.IsInside(into) && (ctx.Board.IsOccupied(into) || ctx.Board.IsWall(into));
			if (!allowChain && hitsObject && dir != new GridPos(0, 0) && !first.IsBuilding)
			{
				ApplyDamage(ctx.State, first, Math.Max(0, ctx.Config.PushCollisionDamage), pusherId, events);
			}
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

	/// <summary>One declared attack: Overcharge multiplier, the main hit (with Pierce / Arc), then the Echo strike.</summary>
	private static void Strike(Context ctx, Piece attacker, GridPos tile)
	{
		int damage = attacker.EffectiveAttack;
		for (int i = attacker.StatusEffects.Count - 1; i >= 0; i--)
		{
			if (attacker.StatusEffects[i].Type != StatusEffectType.Overcharged)
			{
				continue;
			}
			attacker.StatusEffects.RemoveAt(i);
			damage *= Math.Max(1, ctx.Config.OverchargeMultiplier);
			ctx.Events.Add(new ResolutionEvent
			{
				Type = ResolutionEventType.StatusExpired,
				PieceId = attacker.Id,
				From = attacker.Position,
				To = attacker.Position,
				Status = StatusEffectType.Overcharged,
				IsSecondary = true,
			});
			break;
		}
		HitTile(ctx, attacker, tile, damage, false, false, true);
		if (attacker.IsAlive && attacker.HasKeyword(Keyword.Echo) && ctx.Config.EchoBonusDamage > 0)
		{
			HitTile(ctx, attacker, tile, ctx.Config.EchoBonusDamage, true, false, false);
		}
	}

	private static void HitTile(Context ctx, Piece attacker, GridPos tile, int damage, bool secondary, bool isPierce, bool primary)
	{
		Piece target = ctx.Board.GetPieceAt(tile);
		if (target == attacker)
		{
			target = null;
		}
		ctx.Events.Add(new ResolutionEvent
		{
			Type = ResolutionEventType.Attacked,
			PieceId = attacker.Id,
			OtherPieceId = target?.Id ?? -1,
			From = attacker.Position,
			To = tile,
			IsSecondary = secondary,
			IsPierce = isPierce,
		});

		GridPos dir = AttackDirection(attacker.Position, tile);
		Piece behind = null;
		GridPos behindTile = tile + dir;
		if (primary && attacker.HasKeyword(Keyword.Pierce) && ctx.Board.IsPassable(behindTile))
		{
			behind = ctx.Board.GetPieceAt(behindTile);
			if (behind == attacker)
			{
				behind = null;
			}
		}
		var arcTargets = new List<Piece>();
		if (primary && attacker.HasKeyword(Keyword.Arc) && ctx.Config.ArcDamage > 0)
		{
			foreach (GridPos n in tile.Neighbors())
			{
				Piece p = ctx.Board.GetPieceAt(n);
				if (p != null && p != attacker && p != behind)
				{
					arcTargets.Add(p);
				}
			}
		}

		if (target != null)
		{
			HitPiece(ctx, attacker, target, tile, dir, damage);
		}
		else if (ctx.Board.GetTerrain(tile) == TerrainType.Rock)
		{
			DamageRock(ctx.State, tile, damage, ctx.Events);
		}
		if (primary)
		{
			LeaveAttackGround(ctx, attacker, tile);
		}
		if (behind != null && behind.IsAlive && attacker.IsAlive && ctx.Board.GetPieceAt(behindTile) == behind)
		{
			HitTile(ctx, attacker, behindTile, damage, secondary, true, false);
		}
		foreach (Piece p in arcTargets)
		{
			if (p.IsAlive && attacker.IsAlive && ctx.State.GetPiece(p.Id) != null)
			{
				HitTile(ctx, attacker, p.Position, ctx.Config.ArcDamage, true, false, false);
			}
		}
	}

	/// <summary>
	/// Clan attacks mark the ground they hit - whether a piece stood there or not - with an effect that works for
	/// everyone: Burning = Lava, Frost = Ice, Arc = Storm cell, Mending = Healing spring, Push = Mud (first matching
	/// keyword wins).
	/// </summary>
	private static void LeaveAttackGround(Context ctx, Piece attacker, GridPos tile)
	{
		(TileEffectType type, int duration) = attacker.HasKeyword(Keyword.Burning) ? (TileEffectType.Lava, ctx.Config.BurningLavaDuration)
			: attacker.HasKeyword(Keyword.Frost) ? (TileEffectType.Ice, ctx.Config.AttackGroundDuration)
			: attacker.HasKeyword(Keyword.Arc) ? (TileEffectType.Storm, ctx.Config.AttackGroundDuration)
			: attacker.HasKeyword(Keyword.Mending) ? (TileEffectType.Healing, ctx.Config.AttackGroundDuration)
			: attacker.HasKeyword(Keyword.Push) ? (TileEffectType.Mud, ctx.Config.AttackGroundDuration)
			: (TileEffectType.None, 0);
		if (type != TileEffectType.None && ctx.Board.IsInside(tile))
		{
			ApplyTileEffect(ctx.State, type, tile, duration, attacker.OwnerIndex, attacker.Source?.Name ?? type.ToString(), attacker.Id, ctx.Events);
		}
	}

	/// <summary>Damages any hit piece (friend or foe) and applies the attacker's on-hit keywords. Mending heals friendlies instead.</summary>
	private static void HitPiece(Context ctx, Piece attacker, Piece target, GridPos tile, GridPos dir, int damage)
	{
		if (target.OwnerIndex == attacker.OwnerIndex && attacker.HasKeyword(Keyword.Mending))
		{
			ApplyHeal(ctx.State, target, ctx.Config.MendingHeal, attacker.Id, ctx.Events);
			return;
		}
		ApplyDamage(ctx.State, target, damage, attacker.Id, ctx.Events);
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
}
