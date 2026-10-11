namespace Realmshatter;

/// <summary>Temporary status on a piece (see Piece.StatusEffects).</summary>
public enum StatusEffectType
{
	None,
	/// <summary>Effective movement is 0 (applied by Frost, lasts through the owner's next turn).</summary>
	Frozen,
	/// <summary>The next time the piece is chain-triggered, its chain shots deal double damage (consumed).</summary>
	Overcharged,
}
