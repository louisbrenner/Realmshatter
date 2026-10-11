namespace ProjectClaude;

/// <summary>What a spell card is cast on.</summary>
public enum SpellTargetType
{
	/// <summary>A living piece (stat modifiers / status). Classic spells.</summary>
	Piece,
	/// <summary>A single board tile (the AreaShape is ignored and treated as Single).</summary>
	Tile,
	/// <summary>A board tile as the anchor of CardData.AreaShape.</summary>
	Area,
}
