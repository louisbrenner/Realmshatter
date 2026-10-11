namespace ProjectClaude;

/// <summary>
/// Planned action of a piece for this turn. MoveTarget is a destination tile (null = stay).
/// AttackTarget is a TILE (null = no attack): whatever stands there at resolution time is hit.
/// OrderIndex is the global sequence number; orders resolve in ascending OrderIndex.
/// </summary>
public sealed class PieceOrder
{
	public GridPos? MoveTarget { get; set; }
	public GridPos? AttackTarget { get; set; }
	public int OrderIndex { get; set; }
	/// <summary>AP paid when this order was created (refunded if the order is cleared during the turn).</summary>
	public int ApPaid { get; internal set; }

	public PieceOrder(GridPos? moveTarget, GridPos? attackTarget, int orderIndex)
	{
		MoveTarget = moveTarget;
		AttackTarget = attackTarget;
		OrderIndex = orderIndex;
	}
}
