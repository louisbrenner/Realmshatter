namespace ProjectClaude;

/// <summary>Shape of an area spell around its anchor tile (clipped to the board).</summary>
public enum AreaShape
{
	/// <summary>Only the anchor tile.</summary>
	Single,
	/// <summary>Anchor plus its 4 orthogonal neighbors.</summary>
	Plus,
	/// <summary>Anchor plus the tiles left and right of it (horizontal line of 3).</summary>
	Row3,
	/// <summary>Anchor plus the tiles above and below it (vertical line of 3).</summary>
	Column3,
	/// <summary>2x2 square with the anchor as its top-left tile (anchor, +X, +Y, +X+Y).</summary>
	Square2,
}
