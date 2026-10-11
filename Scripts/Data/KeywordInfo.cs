using System.Collections.Generic;

namespace Realmshatter;

/// <summary>Display names and short rule texts of keywords (for card texts and tooltips).</summary>
public static class KeywordInfo
{
	/// <summary>All single keywords in display order.</summary>
	public static readonly Keyword[] All =
	{
		Keyword.Burning, Keyword.Frost, Keyword.Push, Keyword.Pierce,
		Keyword.Mending, Keyword.Conduit, Keyword.Echo, Keyword.Undying,
	};

	/// <summary>Display name of a single keyword.</summary>
	public static string GetName(Keyword keyword) => keyword switch
	{
		Keyword.Burning => "Burning",
		Keyword.Frost => "Frost",
		Keyword.Push => "Push",
		Keyword.Pierce => "Pierce",
		Keyword.Mending => "Mending",
		Keyword.Conduit => "Conduit",
		Keyword.Echo => "Echo",
		Keyword.Undying => "Undying",
		_ => keyword.ToString(),
	};

	/// <summary>Short rule text of a single keyword.</summary>
	public static string GetDescription(Keyword keyword) => keyword switch
	{
		Keyword.Burning => "Hitting an enemy sets its tile on fire (Lava: 1 damage at the start of the occupant's turn).",
		Keyword.Frost => "Hitting an enemy freezes it: it cannot move on its next turn.",
		Keyword.Push => "Hitting an enemy knocks it 1 tile away, if that tile is free.",
		Keyword.Pierce => "The attack also hits the piece directly behind the target.",
		Keyword.Mending => "Hitting a friendly heals it 1 HP (it still chain-fires).",
		Keyword.Conduit => "When chain-triggered, fires in all 4 directions instead of only sideways.",
		Keyword.Echo => "When chain-triggered, its shots deal +1 damage.",
		Keyword.Undying => "When it dies, it returns to your deck with +1 Attack and +1 HP.",
		_ => "",
	};

	/// <summary>The single keywords contained in a combined flag value, in display order.</summary>
	public static List<Keyword> Split(Keyword keywords)
	{
		var list = new List<Keyword>();
		foreach (Keyword k in All)
		{
			if ((keywords & k) != 0)
			{
				list.Add(k);
			}
		}
		return list;
	}

	/// <summary>Comma-separated display names, e.g. "Burning, Pierce" ("" for none).</summary>
	public static string Format(Keyword keywords)
	{
		var names = new List<string>();
		foreach (Keyword k in Split(keywords))
		{
			names.Add(GetName(k));
		}
		return string.Join(", ", names);
	}

	/// <summary>Display name of a status effect.</summary>
	public static string GetStatusName(StatusEffectType status) => status switch
	{
		StatusEffectType.Frozen => "Frozen",
		StatusEffectType.Overcharged => "Overcharged",
		_ => status.ToString(),
	};

	/// <summary>Short rule text of a status effect.</summary>
	public static string GetStatusDescription(StatusEffectType status) => status switch
	{
		StatusEffectType.Frozen => "Cannot move this turn.",
		StatusEffectType.Overcharged => "Its next chain trigger deals double damage.",
		_ => "",
	};

	/// <summary>Display name of a tile effect.</summary>
	public static string GetTileEffectName(TileEffectType type) => type switch
	{
		TileEffectType.Lava => "Lava",
		TileEffectType.Wall => "Wall",
		TileEffectType.Healing => "Healing",
		_ => type.ToString(),
	};

	/// <summary>Short rule text of a tile effect.</summary>
	public static string GetTileEffectDescription(TileEffectType type) => type switch
	{
		TileEffectType.Lava => "Deals 1 damage to the piece on it at the start of that piece's owner's turn.",
		TileEffectType.Wall => "Impassable: blocks movement, pushes and sideways chain shots.",
		TileEffectType.Healing => "Heals the piece on it 1 HP at the start of that piece's owner's turn.",
		_ => "",
	};
}
