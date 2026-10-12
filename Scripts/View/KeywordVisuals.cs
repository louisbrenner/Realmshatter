using System.Collections.Generic;
using Godot;

namespace Realmshatter;

/// <summary>
/// Emblem glyph and colors per keyword, shared by the piece tokens (PieceView) and the cards (CardView):
/// flame = Burning, snowflake = Frost, fist = Push, spear = Pierce, cross = Mending, bolt = Arc,
/// bell = Echo, skull = Undying, hammer = Builder, sun = Aura, stake = Planted, gem = Plunder, jaws = Trapper.
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
		Keyword.Arc => FxIconShape.Bolt,
		Keyword.Echo => FxIconShape.Bell,
		Keyword.Undying => FxIconShape.Skull,
		Keyword.Builder => FxIconShape.Hammer,
		Keyword.Aura => FxIconShape.Sun,
		Keyword.Planted => FxIconShape.Stake,
		Keyword.Plunder => FxIconShape.Gem,
		Keyword.Trapper => FxIconShape.Trap,
		_ => FxIconShape.Plus,
	};

	/// <summary>
	/// Every emblem a card shows, in order: its keywords, then the first-hit burst and the deathrattle tombstone.
	/// (shape, glyph colour, coin colour) - shared by the cards and the piece tokens. firstHitUsed drops the
	/// first-hit burst (a piece token whose first-hit effect already fired).
	/// </summary>
	public static List<(FxIconShape Shape, Color Fg, Color Bg)> IconsFor(CardData card, bool firstHitUsed = false)
	{
		var list = new List<(FxIconShape, Color, Color)>();
		if (card == null)
		{
			return list;
		}
		foreach (Keyword k in KeywordInfo.Split(card.Keywords))
		{
			Color fg = GetForeground(k);
			Color bg = GetBackground(k);
			if (k == Keyword.Aura)
			{
				fg = ClanInfo.GetColor(card.Clan).Lightened(0.35f);
				bg = ClanInfo.GetColor(card.Clan).Darkened(0.65f);
			}
			list.Add((GetShape(k), fg, bg));
		}
		if (card.OnFirstHit != FirstHitType.None && !firstHitUsed)
		{
			list.Add((FxIconShape.Burst, new Color(1f, 0.82f, 0.45f), new Color(0.45f, 0.16f, 0.08f, 0.97f)));
		}
		if (card.Legend != LegendEffect.None)
		{
			list.Add((LegendInfo.GetShape(card.Legend), LegendInfo.GetColor(card.Legend), LegendInfo.EmblemBackground));
		}
		if (card.Deathrattle != DeathrattleType.None)
		{
			list.Add((FxIconShape.Tomb, new Color(0.85f, 0.85f, 0.95f), new Color(0.18f, 0.16f, 0.26f, 0.97f)));
		}
		return list;
	}

	/// <summary>Glyph color of the keyword emblem.</summary>
	public static Color GetForeground(Keyword keyword) => keyword switch
	{
		Keyword.Burning => new Color(1f, 0.45f, 0.08f),
		Keyword.Frost => new Color(0.88f, 0.97f, 1f),
		Keyword.Push => new Color(1f, 0.86f, 0.66f),
		Keyword.Pierce => new Color(0.92f, 0.95f, 1f),
		Keyword.Mending => new Color(0.55f, 1f, 0.55f),
		Keyword.Arc => new Color(1f, 0.93f, 0.4f),
		Keyword.Echo => new Color(1f, 0.83f, 0.42f),
		Keyword.Undying => new Color(0.86f, 1f, 0.94f),
		Keyword.Builder => new Color(0.95f, 0.85f, 0.65f),
		Keyword.Aura => new Color(1f, 0.92f, 0.55f),
		Keyword.Planted => new Color(0.78f, 1f, 0.62f),
		Keyword.Plunder => new Color(0.6f, 0.88f, 1f),
		Keyword.Trapper => new Color(0.9f, 0.86f, 0.78f),
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
		Keyword.Arc => new Color(0.42f, 0.3f, 0.04f, 0.97f),
		Keyword.Echo => new Color(0.46f, 0.22f, 0.08f, 0.97f),
		Keyword.Undying => new Color(0.16f, 0.3f, 0.3f, 0.97f),
		Keyword.Builder => new Color(0.36f, 0.24f, 0.14f, 0.97f),
		Keyword.Aura => new Color(0.4f, 0.32f, 0.08f, 0.97f),
		Keyword.Planted => new Color(0.2f, 0.32f, 0.12f, 0.97f),
		Keyword.Plunder => new Color(0.08f, 0.22f, 0.5f, 0.97f),
		Keyword.Trapper => new Color(0.26f, 0.22f, 0.18f, 0.97f),
		_ => new Color(0.2f, 0.2f, 0.2f, 0.97f),
	};
}
