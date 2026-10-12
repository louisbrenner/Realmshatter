namespace Realmshatter;

/// <summary>
/// Kind of a resolution event emitted by OrderResolver / TurnController (actions, EndTurn expiries, turn-start ticks, spells).
/// Views must ignore types they do not know.
/// </summary>
public enum ResolutionEventType
{
	/// <summary>PieceId moved From -> To. Path = the tiles walked (excluding From).</summary>
	Moved,
	/// <summary>PieceId could not move From -> To (enemy / wall blocks at resolution time, or it is Frozen).</summary>
	MoveBlocked,
	/// <summary>PieceId attacked tile To from From. OtherPieceId = piece on that tile or -1. IsSecondary = Arc zap / Echo strike, IsPierce = pierce hit.</summary>
	Attacked,
	/// <summary>Attack of PieceId at tile To was cancelled (out of range after a blocked/shortened move).</summary>
	AttackCancelled,
	/// <summary>PieceId took damage from OtherPieceId (-1 = tile/spell): Amount incoming, ShieldAbsorbed, HpLost, RemainingHp, RemainingShield.</summary>
	Damaged,
	/// <summary>PieceId died at From. Already removed from the board (Undying: a ReturnedToDeck event follows).</summary>
	Died,
	/// <summary>A spell (SpellName) on PieceId expired.</summary>
	SpellExpired,

	/// <summary>PieceId was pushed From -> To by OtherPieceId (a moving friendly or a Push attacker).</summary>
	Pushed,
	/// <summary>PieceId (at From) could not be pushed to To by OtherPieceId (edge, wall, enemy or chain too long).</summary>
	PushBlocked,
	/// <summary>PieceId was healed by OtherPieceId (-1 = spell): Amount healed, RemainingHp.</summary>
	Healed,
	/// <summary>The card of dead Undying PieceId returned to PlayerIndex's deck: CardName, Amount = new Undying level.</summary>
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
	/// <summary>Status on PieceId expired or was consumed (IsSecondary = consumed by an attack).</summary>
	StatusExpired,
	/// <summary>PlayerIndex cast tile/area spell CardName on anchor tile To (first event of LastSpellEvents).</summary>
	SpellCast,
	/// <summary>Dead PieceId (owner PlayerIndex) triggers its deathrattle at From: SpellName = effect, Amount, CardName.</summary>
	Deathrattle,
	/// <summary>PieceId was hit for the first time by OtherPieceId (-1 = spell/tile): SpellName = effect, Amount, RemainingShield.</summary>
	FirstHitTriggered,
	/// <summary>Builder PieceId started building OtherPieceId (SpellName = building) on tile To.</summary>
	BuildingStarted,
	/// <summary>Building PieceId at To is finished (SpellName = building).</summary>
	BuildingCompleted,
	/// <summary>Aura of PieceId pulses at its turn start (SpellName = aura name, PlayerIndex = owner).</summary>
	AuraPulse,
	/// <summary>
	/// PlayerIndex gained Amount AP from a card (PieceId = source piece or -1, CardName = source, From = where).
	/// IsSecondary = the AP arrives at the start of that player's next turn.
	/// </summary>
	ApGained,
	/// <summary>The Rock on tile To took Amount damage; RemainingHp 0 = it crumbled to plain ground.</summary>
	TerrainDamaged,
	/// <summary>Piece PieceId (owner PlayerIndex) hid a trap on tile To: CardName = trap name, SpellName = TrapType.</summary>
	TrapSet,
	/// <summary>Enemy PieceId stepped on a trap of PlayerIndex at To and was stopped: CardName = trap name, SpellName = TrapType.</summary>
	TrapTriggered,
}
