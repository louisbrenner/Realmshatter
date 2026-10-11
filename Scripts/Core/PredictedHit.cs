namespace Realmshatter;

/// <summary>One shot inside a ChainPreview (direct attack, chain shot or pierce hit).</summary>
public sealed class PredictedHit
{
	/// <summary>Piece that fired this shot.</summary>
	public int AttackerId { get; init; } = -1;
	public GridPos From { get; init; }
	/// <summary>Tile that was hit.</summary>
	public GridPos Tile { get; init; }
	/// <summary>Piece on the tile at hit time, or -1 (miss).</summary>
	public int TargetPieceId { get; init; } = -1;
	/// <summary>True if the target belongs to the attacker's owner.</summary>
	public bool IsFriendly { get; init; }
	public bool IsChain { get; init; }
	public bool IsPierce { get; init; }

	/// <summary>Incoming damage (before shields). 0 for friendly hits.</summary>
	public int Damage { get; internal set; }
	public int ShieldAbsorbed { get; internal set; }
	public int HpLost { get; internal set; }
	public int Healed { get; internal set; }
	public bool Kills { get; internal set; }
	/// <summary>Destination of a knockback (Push), if any.</summary>
	public GridPos? PushedTo { get; internal set; }
	public HitEffect Effects { get; internal set; }

	public override string ToString() =>
		$"#{AttackerId} -> {Tile} (#{TargetPieceId}{(IsFriendly ? " friendly" : "")}{(IsChain ? ", chain" : "")}{(IsPierce ? ", pierce" : "")}): " +
		$"dmg {Damage}, hp -{HpLost}{(Kills ? ", kill" : "")}{(Healed > 0 ? $", heal {Healed}" : "")}, {Effects}";
}
