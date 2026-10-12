using Godot;

namespace Realmshatter;

/// <summary>Names, rule texts, emblem glyphs and colours of the Legendary effects.</summary>
public static class LegendInfo
{
	/// <summary>Radius of Dawnlight's heal.</summary>
	public const int DawnlightRadius = 3;
	/// <summary>Radius of Glacial Grip's freeze.</summary>
	public const int GlacialGripRadius = 2;
	/// <summary>How far Chain Lightning reaches and how many enemies it strikes.</summary>
	public const int ChainLightningRadius = 5;
	public const int ChainLightningTargets = 3;
	/// <summary>Damage of Wildfire to each enemy on Lava.</summary>
	public const int WildfireDamage = 2;

	public static string GetName(LegendEffect effect) => effect switch
	{
		LegendEffect.Wildfire => "Wildfire",
		LegendEffect.Dawnlight => "Dawnlight",
		LegendEffect.GlacialGrip => "Glacial Grip",
		LegendEffect.ChainLightning => "Chain Lightning",
		LegendEffect.Unbreakable => "Unbreakable",
		_ => "",
	};

	public static string Describe(LegendEffect effect) => effect switch
	{
		LegendEffect.Wildfire => $"At the start of your turn, every enemy standing on Lava takes {WildfireDamage} damage.",
		LegendEffect.Dawnlight => $"At the start of your turn, your units within {DawnlightRadius} tiles are healed to full HP.",
		LegendEffect.GlacialGrip => $"At the start of your turn, every enemy within {GlacialGripRadius} tiles is Frozen.",
		LegendEffect.ChainLightning => $"At the start of your turn, lightning strikes the {ChainLightningTargets} nearest enemies (within {ChainLightningRadius} tiles) for 1 damage each.",
		LegendEffect.Unbreakable => "It takes at most 1 damage from any single hit.",
		_ => "",
	};

	/// <summary>Emblem glyph of the effect.</summary>
	public static FxIconShape GetShape(LegendEffect effect) => effect switch
	{
		LegendEffect.Wildfire => FxIconShape.Flame,
		LegendEffect.Dawnlight => FxIconShape.Sun,
		LegendEffect.GlacialGrip => FxIconShape.Snowflake,
		LegendEffect.ChainLightning => FxIconShape.Bolt,
		LegendEffect.Unbreakable => FxIconShape.Bricks,
		_ => FxIconShape.Sun,
	};

	/// <summary>Glyph colour of the effect's emblem (shown on a gold coin).</summary>
	public static Color GetColor(LegendEffect effect) => effect switch
	{
		LegendEffect.Wildfire => new Color(1f, 0.5f, 0.12f),
		LegendEffect.Dawnlight => new Color(1f, 0.93f, 0.6f),
		LegendEffect.GlacialGrip => new Color(0.8f, 0.95f, 1f),
		LegendEffect.ChainLightning => new Color(0.85f, 0.75f, 1f),
		LegendEffect.Unbreakable => new Color(0.9f, 0.85f, 0.75f),
		_ => Colors.White,
	};

	/// <summary>Coin colour behind every Legendary emblem.</summary>
	public static readonly Color EmblemBackground = new Color(0.45f, 0.28f, 0.04f, 0.97f);
}
