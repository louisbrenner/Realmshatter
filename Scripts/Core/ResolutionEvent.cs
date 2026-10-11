using System.Collections.Generic;

namespace Realmshatter;

/// <summary>One step of turn resolution, in chronological order, for views to animate.</summary>
public sealed class ResolutionEvent
{
	public ResolutionEventType Type { get; init; }
	/// <summary>The acting or affected piece (see ResolutionEventType for meaning).</summary>
	public int PieceId { get; init; } = -1;
	/// <summary>The other involved piece, or -1.</summary>
	public int OtherPieceId { get; init; } = -1;
	public GridPos From { get; init; }
	public GridPos To { get; init; }
	public bool IsChain { get; init; }
	/// <summary>Attacked: this shot is the extra hit of a Pierce attack.</summary>
	public bool IsPierce { get; init; }
	public int Amount { get; init; }
	public int ShieldAbsorbed { get; init; }
	public int HpLost { get; init; }
	public int RemainingHp { get; init; }
	public int RemainingShield { get; init; }
	public string SpellName { get; init; } = "";
	/// <summary>Card name (ReturnedToDeck, TileEffectApplied source, SpellCast).</summary>
	public string CardName { get; init; } = "";
	/// <summary>Player concerned (ReturnedToDeck, SpellCast), or -1.</summary>
	public int PlayerIndex { get; init; } = -1;
	public TileEffectType TileEffect { get; init; }
	public StatusEffectType Status { get; init; }
	/// <summary>TileEffectApplied / StatusApplied: last turn (inclusive) in which the effect is active.</summary>
	public int ExpiryTurn { get; init; }
	/// <summary>Moved: walked tiles excluding From (ends with To). Null for other events.</summary>
	public IReadOnlyList<GridPos> Path { get; init; }

	public override string ToString() => Type switch
	{
		ResolutionEventType.Moved => $"Moved #{PieceId} {From}->{To}",
		ResolutionEventType.MoveBlocked => $"MoveBlocked #{PieceId} {From}->{To}",
		ResolutionEventType.Attacked => $"Attacked #{PieceId} {From}->{To} target #{OtherPieceId}{(IsChain ? " (chain)" : "")}{(IsPierce ? " (pierce)" : "")}",
		ResolutionEventType.AttackCancelled => $"AttackCancelled #{PieceId} ->{To}",
		ResolutionEventType.Damaged => $"Damaged #{PieceId} by #{OtherPieceId}: {Amount} (shield {ShieldAbsorbed}, hp {HpLost}) -> HP {RemainingHp} SHD {RemainingShield}",
		ResolutionEventType.Died => $"Died #{PieceId} at {From}",
		ResolutionEventType.ChainTriggered => $"ChainTriggered #{OtherPieceId} -> #{PieceId}",
		ResolutionEventType.SpellExpired => $"SpellExpired '{SpellName}' on #{PieceId}",
		ResolutionEventType.Pushed => $"Pushed #{PieceId} {From}->{To} by #{OtherPieceId}",
		ResolutionEventType.PushBlocked => $"PushBlocked #{PieceId} {From}->{To} by #{OtherPieceId}",
		ResolutionEventType.Healed => $"Healed #{PieceId} by #{OtherPieceId}: +{Amount} -> HP {RemainingHp}",
		ResolutionEventType.ReturnedToDeck => $"ReturnedToDeck #{PieceId} '{CardName}' -> P{PlayerIndex} deck (level {Amount})",
		ResolutionEventType.TileEffectApplied => $"TileEffectApplied {TileEffect} at {To} for {Amount} turns",
		ResolutionEventType.TileEffectExpired => $"TileEffectExpired {TileEffect} at {To}",
		ResolutionEventType.TileDamage => $"TileDamage {TileEffect} at {To} -> #{PieceId} {Amount}",
		ResolutionEventType.TileHeal => $"TileHeal at {To} -> #{PieceId} +{Amount} (HP {RemainingHp})",
		ResolutionEventType.StatusApplied => $"StatusApplied {Status} on #{PieceId}",
		ResolutionEventType.StatusExpired => $"StatusExpired {Status} on #{PieceId}{(IsChain ? " (consumed)" : "")}",
		ResolutionEventType.SpellCast => $"SpellCast '{CardName}' by P{PlayerIndex} at {To}",
		_ => Type.ToString(),
	};
}
