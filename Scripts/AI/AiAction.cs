namespace Realmshatter;

/// <summary>
/// One step the AI already executed through the TurnController (for logging / animation).
/// Field usage per kind:
/// Draft: Card = chosen card.
/// PlayUnit: Card, PieceId = new piece, Target = deploy tile.
/// PlaySpell: Card, PieceId = target piece (-1 for tile/area spells), Target = target piece position / anchor tile.
/// ConvertVp: no extra fields (1 VP became 1 AP).
/// Command: PieceId = commanded piece, MoveTarget / AttackTarget as executed, Target = AttackTarget ?? MoveTarget.
/// </summary>
public sealed class AiAction
{
	public AiActionKind Kind { get; init; }
	public int PlayerIndex { get; init; }
	public CardData Card { get; init; }
	public int PieceId { get; init; } = -1;
	public GridPos? Target { get; init; }
	public GridPos? MoveTarget { get; init; }
	public GridPos? AttackTarget { get; init; }
	public string Description { get; init; } = "";

	public override string ToString() => $"[P{PlayerIndex} {Kind}] {Description}";
}
