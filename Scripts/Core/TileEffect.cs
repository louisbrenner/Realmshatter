namespace Realmshatter;

/// <summary>
/// A map effect on one tile. It expires at the END of turn ExpiryTurn (like spells): an effect created in
/// turn T with duration D has ExpiryTurn = T + D (D = 2 lasts until the end of the creator's next turn).
/// </summary>
public sealed class TileEffect
{
	public TileEffectType Type { get; }
	public GridPos Position { get; }
	/// <summary>Player who created the effect (-1 = neutral).</summary>
	public int CreatorIndex { get; }
	public int CreatedTurn { get; }
	public int ExpiryTurn { get; }
	/// <summary>Name of the card that created the effect (spell or Burning unit), for tooltips.</summary>
	public string SourceName { get; }

	public TileEffect(TileEffectType type, GridPos position, int creatorIndex, int createdTurn, int expiryTurn, string sourceName)
	{
		Type = type;
		Position = position;
		CreatorIndex = creatorIndex;
		CreatedTurn = createdTurn;
		ExpiryTurn = expiryTurn;
		SourceName = sourceName ?? "";
	}

	/// <summary>Number of turn ends (including the current turn's end) until the effect is gone.</summary>
	public int RemainingTurns(int currentTurn) => System.Math.Max(0, ExpiryTurn - currentTurn + 1);

	public override string ToString() => $"{Type} at {Position} (until end of turn {ExpiryTurn})";
}
