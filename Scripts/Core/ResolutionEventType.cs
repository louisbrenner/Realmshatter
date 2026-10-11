namespace ProjectClaude;

/// <summary>
/// Kind of a resolution event emitted by OrderResolver / TurnController (EndTurn, turn-start ticks, tile spells).
/// Views must ignore types they do not know.
/// </summary>
public enum ResolutionEventType
{
	/// <summary>PieceId moved From -> To. Path = the tiles walked (excluding From).</summary>
	Moved,
	/// <summary>PieceId could not move From -> To (enemy / wall blocks at resolution time, or it is Frozen).</summary>
	MoveBlocked,
	/// <summary>PieceId attacked tile To from From. OtherPieceId = piece on that tile or -1. IsChain = chain shot, IsPierce = pierce hit.</summary>
	Attacked,
	/// <summary>Attack of PieceId at tile To was cancelled (out of range after a blocked/shortened move).</summary>
	AttackCancelled,
	/// <summary>PieceId took damage from OtherPieceId (-1 = tile/spell): Amount incoming, ShieldAbsorbed, HpLost, RemainingHp, RemainingShield.</summary>
	Damaged,
	/// <summary>PieceId died at From. Already removed from the board (a ReturnedToDeck event follows).</summary>
	Died,
	/// <summary>Friendly OtherPieceId hit PieceId, which now fires (sideways, or in 4 directions with Conduit).</summary>
	ChainTriggered,
	/// <summary>A spell (SpellName) on PieceId expired.</summary>
	SpellExpired,

	/// <summary>PieceId was pushed From -> To by OtherPieceId (a moving friendly or a Push attacker).</summary>
	Pushed,
	/// <summary>PieceId (at From) could not be pushed to To by OtherPieceId (edge, wall, enemy or chain too long).</summary>
	PushBlocked,
	/// <summary>PieceId was healed by OtherPieceId (-1 = spell): Amount healed, RemainingHp.</summary>
	Healed,
	/// <summary>The card of dead PieceId returned to PlayerIndex's deck: CardName, Amount = Undying level (0 = unchanged card).</summary>
	ReturnedToDeck,
	/// <summary>TileEffect placed on tile To: Amount = duration, ExpiryTurn, CardName = source, OtherPieceId = source piece or -1.</summary>
	TileEffectApplied,
	/// <summary>TileEffect on tile To expired.</summary>
	TileEffectExpired,
	/// <summary>Turn-start tick: TileEffect (Lava) on tile To damages PieceId by Amount (a Damaged event follows).</summary>
	TileDamage,
	/// <summary>Turn-start tick: Healing tile To heals PieceId by Amount, RemainingHp.</summary>
	TileHeal,
	/// <summary>Status was applied to PieceId by OtherPieceId (-1 = spell). ExpiryTurn.</summary>
	StatusApplied,
	/// <summary>Status on PieceId expired or was consumed (IsChain = consumed by a chain trigger).</summary>
	StatusExpired,
	/// <summary>PlayerIndex cast tile/area spell CardName on anchor tile To (first event of LastSpellEvents).</summary>
	SpellCast,
}
