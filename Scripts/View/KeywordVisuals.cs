using Godot;

namespace Realmshatter;

/// <summary>
/// Emblem glyph and colors per keyword, shared by the piece tokens (PieceView) and the cards (CardView):
/// flame = Burning, snowflake = Frost, fist = Push, spear = Pierce, cross = Mending, bolt = Conduit,
/// bell = Echo, skull = Undying.
/// </summary>
public static class KeywordVisuals
{
	/// <summary>Glyph of the keyword emblem.</summary>
	public static FxIconShape GetShape(Keyword keyword) => keyword switch
	{
		Keyword.Burning => FxIconShape.Flame,
		Keyword.Frost => FxIconShape.Snowflake,
		Keyword.Push => FxIconShape.Fist,
		Keyword.Pierce => FxIconShape.Spear,
		Keyword.Mending => FxIconShape.Plus,
		Keyword.Conduit => FxIconShape.Bolt,
		Keyword.Echo => FxIconShape.Bell,
		Keyword.Undying => FxIconShape.Skull,
		_ => FxIconShape.Plus,
	};

	/// <summary>Glyph color of the keyword emblem.</summary>
	public static Color GetForeground(Keyword keyword) => keyword switch
	{
		Keyword.Burning => new Color(1f, 0.45f, 0.08f),
		Keyword.Frost => new Color(0.88f, 0.97f, 1f),
		Keyword.Push => new Color(1f, 0.86f, 0.66f),
		Keyword.Pierce => new Color(0.92f, 0.95f, 1f),
		Keyword.Mending => new Color(0.55f, 1f, 0.55f),
		Keyword.Conduit => new Color(1f, 0.93f, 0.4f),
		Keyword.Echo => new Color(1f, 0.83f, 0.42f),
		Keyword.Undying => new Color(0.86f, 1f, 0.94f),
		_ => Colors.White,
	};

	/// <summary>Coin (background) color of the keyword emblem.</summary>
	public static Color GetBackground(Keyword keyword) => keyword switch
	{
		Keyword.Burning => new Color(0.42f, 0.08f, 0.03f, 0.97f),
		Keyword.Frost => new Color(0.14f, 0.38f, 0.72f, 0.97f),
		Keyword.Push => new Color(0.45f, 0.26f, 0.12f, 0.97f),
		Keyword.Pierce => new Color(0.28f, 0.33f, 0.42f, 0.97f),
		Keyword.Mending => new Color(0.1f, 0.38f, 0.14f, 0.97f),
		Keyword.Conduit => new Color(0.42f, 0.3f, 0.04f, 0.97f),
		Keyword.Echo => new Color(0.46f, 0.22f, 0.08f, 0.97f),
		Keyword.Undying => new Color(0.16f, 0.3f, 0.3f, 0.97f),
		_ => new Color(0.2f, 0.2f, 0.2f, 0.97f),
	};
}
