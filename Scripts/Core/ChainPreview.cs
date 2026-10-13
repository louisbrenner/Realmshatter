using System.Collections.Generic;

namespace Realmshatter;

/// <summary>
/// Result of TurnController.PredictAttack: what ONE attack would cause on the CURRENT board (friendly fire,
/// keywords, kills). Computed on a cloned state; the real state is never modified.
/// Piece ids refer to the real pieces.
/// </summary>
public sealed class ChainPreview
{
	public int AttackerId { get; init; } = -1;
	public GridPos From { get; init; }
	public GridPos Target { get; init; }
	/// <summary>False if the attack is not possible (invalid piece, out of range...). Lists are then empty.</summary>
	public bool IsValid { get; init; }

	/// <summary>The raw events the attack would produce (same format as resolution events).</summary>
	public List<ResolutionEvent> Events { get; } = new List<ResolutionEvent>();
	/// <summary>Every hit in chronological order.</summary>
	public List<PredictedHit> Hits { get; } = new List<PredictedHit>();
	/// <summary>Pieces that would die.</summary>
	public List<int> KilledPieceIds { get; } = new List<int>();
	/// <summary>Tile effects the attack would create (e.g. Lava from Burning).</summary>
	public List<TileEffect> NewTileEffects { get; } = new List<TileEffect>();

	/// <summary>Total HP lost by enemy pieces.</summary>
	public int EnemyHpLost { get; internal set; }
	/// <summary>Total incoming damage to enemy pieces (including shield-absorbed).</summary>
	public int EnemyDamage { get; internal set; }
	public int EnemyKills { get; internal set; }
	public int FriendlyHealed { get; internal set; }
	/// <summary>Total HP the attacker's own pieces would lose (friendly fire).</summary>
	public int FriendlyHpLost { get; internal set; }
	public int FriendlyKills { get; internal set; }

	/// <summary>Builds the summary lists from the events of a simulated attack.</summary>
	internal static ChainPreview FromEvents(int attackerId, GridPos from, GridPos target, int attackerOwner,
		IReadOnlyDictionary<int, int> owners, List<ResolutionEvent> events)
	{
		var preview = new ChainPreview { AttackerId = attackerId, From = from, Target = target, IsValid = true };
		preview.Events.AddRange(events);
		PredictedHit current = null;
		foreach (ResolutionEvent e in events)
		{
			switch (e.Type)
			{
				case ResolutionEventType.Attacked:
					bool friendly = e.OtherPieceId >= 0 && owners.TryGetValue(e.OtherPieceId, out int o) && o == attackerOwner;
					current = new PredictedHit
					{
						AttackerId = e.PieceId,
						From = e.From,
						Tile = e.To,
						TargetPieceId = e.OtherPieceId,
						IsFriendly = friendly,
						IsSecondary = e.IsSecondary,
						IsPierce = e.IsPierce,
					};
					preview.Hits.Add(current);
					break;
				case ResolutionEventType.Damaged:
					if (current != null && e.PieceId == current.TargetPieceId)
					{
						current.Damage += e.Amount;
						current.ShieldAbsorbed += e.ShieldAbsorbed;
						current.HpLost += e.HpLost;
					}
					if (!IsOwnedBy(owners, e.PieceId, attackerOwner))
					{
						preview.EnemyDamage += e.Amount;
						preview.EnemyHpLost += e.HpLost;
					}
					else
					{
						preview.FriendlyHpLost += e.HpLost;
					}
					break;
				case ResolutionEventType.Died:
					preview.KilledPieceIds.Add(e.PieceId);
					if (!IsOwnedBy(owners, e.PieceId, attackerOwner))
					{
						preview.EnemyKills++;
					}
					else
					{
						preview.FriendlyKills++;
					}
					if (current != null && e.PieceId == current.TargetPieceId)
					{
						current.Kills = true;
						current.Effects |= HitEffect.Killed;
					}
					break;
				case ResolutionEventType.Healed:
					preview.FriendlyHealed += e.Amount;
					if (current != null)
					{
						current.Healed += e.Amount;
						current.Effects |= HitEffect.Healed;
					}
					break;
				case ResolutionEventType.TileEffectApplied:
					preview.NewTileEffects.Add(new TileEffect(e.TileEffect, e.To, attackerOwner, e.ExpiryTurn - e.Amount + 1, e.ExpiryTurn, e.CardName));
					if (current != null && e.TileEffect == TileEffectType.Lava)
					{
						current.Effects |= HitEffect.Lava;
					}
					break;
				case ResolutionEventType.StatusApplied:
					if (current != null && e.Status == StatusEffectType.Frozen)
					{
						current.Effects |= HitEffect.Frozen;
					}
					break;
				case ResolutionEventType.Pushed:
					if (current != null && e.PieceId == current.TargetPieceId)
					{
						current.PushedTo = e.To;
						current.Effects |= HitEffect.Pushed;
					}
					break;
				case ResolutionEventType.PushBlocked:
					if (current != null && e.PieceId == current.TargetPieceId)
					{
						current.Effects |= HitEffect.PushBlocked;
					}
					break;
			}
		}
		return preview;
	}

	private static bool IsOwnedBy(IReadOnlyDictionary<int, int> owners, int pieceId, int player) =>
		owners.TryGetValue(pieceId, out int owner) && owner == player;
}
