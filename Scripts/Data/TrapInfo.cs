using Godot;

namespace Realmshatter;

/// <summary>Which trap a clan's Trapper sets, plus names, rule texts and colours of the traps.</summary>
public static class TrapInfo
{
	/// <summary>Trap set by a Trapper of the given clan.</summary>
	public static TrapType ForClan(Clan clan) => clan switch
	{
		Clan.Fire => TrapType.Fire,
		Clan.Frost => TrapType.Frost,
		Clan.Storm => TrapType.Shock,
		Clan.Stone => TrapType.Pitfall,
		Clan.Healing => TrapType.Sanctum,
		_ => TrapType.Spike,
	};

	/// <summary>Display name, e.g. "Fire Trap".</summary>
	public static string GetName(TrapType type) => type switch
	{
		TrapType.Fire => "Fire Trap",
		TrapType.Frost => "Frost Trap",
		TrapType.Shock => "Shock Trap",
		TrapType.Pitfall => "Pitfall",
		TrapType.Sanctum => "Sanctum Ward",
		_ => "Spike Trap",
	};

	/// <summary>What happens to an enemy that steps on it (after its move is stopped there).</summary>
	public static string Describe(TrapType type) => type switch
	{
		TrapType.Fire => "1 damage and its tile turns into Lava.",
		TrapType.Frost => "1 damage and it is Frozen through its next turn.",
		TrapType.Shock => "1 damage to it and to every enemy next to it.",
		TrapType.Pitfall => "3 damage.",
		TrapType.Sanctum => "1 damage, and your pieces within 2 tiles heal 1 HP.",
		_ => "2 damage.",
	};

	/// <summary>Glyph colour of the trap's emblem / board marker.</summary>
	public static Color GetColor(TrapType type) => type switch
	{
		TrapType.Fire => new Color(1f, 0.5f, 0.15f),
		TrapType.Frost => new Color(0.6f, 0.88f, 1f),
		TrapType.Shock => new Color(0.82f, 0.68f, 1f),
		TrapType.Pitfall => new Color(0.82f, 0.74f, 0.6f),
		TrapType.Sanctum => new Color(1f, 0.9f, 0.5f),
		_ => new Color(0.9f, 0.9f, 0.92f),
	};
}
