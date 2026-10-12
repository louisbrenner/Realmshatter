using System.Collections.Generic;

namespace Realmshatter;

/// <summary>Display names and short rule texts of keywords (for card texts and tooltips).</summary>
public static class KeywordInfo
{
	/// <summary>All single keywords in display order.</summary>
	public static readonly Keyword[] All =
	{
		Keyword.Burning, Keyword.Frost, Keyword.Push, Keyword.Pierce,
		Keyword.Mending, Keyword.Arc, Keyword.Echo, Keyword.Undying, Keyword.Builder, Keyword.Aura, Keyword.Planted, Keyword.Plunder, Keyword.Trapper,
	};

	/// <summary>Display name of a single keyword.</summary>
	public static string GetName(Keyword keyword) => keyword switch
	{
		Keyword.Burning => "Burning",
		Keyword.Frost => "Frost",
		Keyword.Push => "Push",
		Keyword.Pierce => "Pierce",
		Keyword.Mending => "Mending",
		Keyword.Arc => "Arc",
		Keyword.Echo => "Echo",
		Keyword.Undying => "Undying",
		Keyword.Builder => "Builder",
		Keyword.Aura => "Aura",
		Keyword.Planted => "Planted",
		Keyword.Plunder => "Plunder",
		Keyword.Trapper => "Trapper",
		_ => keyword.ToString(),
	};

	/// <summary>Short rule text of a single keyword.</summary>
	public static string GetDescription(Keyword keyword) => keyword switch
	{
		Keyword.Burning => "Its attacks set the target tile on fire - even an empty one (Lava: 1 damage at the start of the occupant's turn).",
		Keyword.Frost => "Hitting a piece freezes it (it cannot move on its next turn); the target tile turns to Ice (stops any move onto it).",
		Keyword.Push => "Hitting a piece knocks it 1 tile away; if another piece, a building, a wall or a rock is in the way, it is slammed into it and takes 1 damage instead. The target tile turns to Mud (costs 2 movement).",
		Keyword.Pierce => "The attack also hits the piece directly behind the target - friend or foe.",
		Keyword.Mending => "Hitting a friendly heals it 1 HP instead of damaging it; the target tile becomes a Healing spring (for anyone).",
		Keyword.Arc => "Its attack also zaps every piece next to the target for 1 damage - friend or foe; the target tile becomes a Storm cell.",
		Keyword.Echo => "After attacking, it strikes the same tile again for 1 damage.",
		Keyword.Undying => "When it dies, it returns to your deck with +1 Attack and +1 HP.",
		Keyword.Builder => "Instead of acting it can build its class's building on an adjacent tile. It cannot move or score VP while building; if it dies, the unfinished building collapses.",
		Keyword.Aura => "At the start of your turn it pulses its clan's effect onto the 8 surrounding tiles.",
		Keyword.Plunder => "Whenever it destroys an enemy piece, you gain 1 AP.",
		Keyword.Trapper => "Instead of attacking (also after moving) it can hide a trap on a free tile next to it (1 AP). An enemy stepping on it is stopped and hit. Up to 2 traps per Trapper.",
		Keyword.Planted => "Cannot move and never scores VP. Deploy it on any free tile within 2 of one of your units (not on the crown).",
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
		StatusEffectType.Overcharged => "Its next attack deals double damage.",
		_ => "",
	};

	/// <summary>Display name of a tile effect.</summary>
	public static string GetTileEffectName(TileEffectType type) => type switch
	{
		TileEffectType.Lava => "Lava",
		TileEffectType.Wall => "Wall",
		TileEffectType.Healing => "Healing",
		TileEffectType.Rubble => "Rubble",
		TileEffectType.Ice => "Ice",
		TileEffectType.Storm => "Storm Cell",
		TileEffectType.Mud => "Mud",
		_ => type.ToString(),
	};

	/// <summary>Short rule text of a tile effect.</summary>
	public static string GetTileEffectDescription(TileEffectType type) => type switch
	{
		TileEffectType.Lava => "Deals 1 damage to the piece on it at the start of that piece's owner's turn.",
		TileEffectType.Wall => "Impassable: blocks movement, pushes and pierce shots.",
		TileEffectType.Healing => "Heals the piece on it 1 HP at the start of that piece's owner's turn.",
		TileEffectType.Rubble => "Ruins of a destroyed building: impassable until it is cleared.",
		TileEffectType.Ice => "Slippery: any piece moving onto it slides to a halt there.",
		TileEffectType.Storm => "Crackles at the start of the occupant's turn: 1 damage to it and to every piece next to it.",
		TileEffectType.Mud => "Sticky: entering costs 2 movement.",
		_ => "",
	};
}
