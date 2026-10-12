namespace Realmshatter;

/// <summary>
/// A hidden trap on one tile. Only its owner sees it; an enemy piece that steps onto the tile is stopped there and
/// the trap springs (OrderResolver.TriggerTrap), then it is gone.
/// </summary>
public sealed class Trap
{
	public GridPos Position { get; }
	public int OwnerIndex { get; }
	public TrapType Type { get; }
	/// <summary>The Trapper that set it (-1 if unknown); a trap kill counts as its kill (e.g. for Plunder).</summary>
	public int SourcePieceId { get; }
	/// <summary>Order of placement (older traps are replaced first when a Trapper sets one too many).</summary>
	public int Serial { get; }

	public Trap(GridPos position, int ownerIndex, TrapType type, int sourcePieceId, int serial)
	{
		Position = position;
		OwnerIndex = ownerIndex;
		Type = type;
		SourcePieceId = sourcePieceId;
		Serial = serial;
	}

	public override string ToString() => $"{TrapInfo.GetName(Type)} of P{OwnerIndex} at {Position}";
}
