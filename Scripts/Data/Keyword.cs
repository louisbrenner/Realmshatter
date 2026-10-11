using System;

namespace Realmshatter;

/// <summary>
/// Keywords of a unit card (combinable flags). They modify how the piece's attacks resolve.
/// See KeywordInfo for display names and descriptions, OrderResolver for the exact rules.
/// </summary>
[Flags]
public enum Keyword
{
	None = 0,
	/// <summary>Hitting an enemy leaves Lava on the target tile (GameConfig.BurningLavaDuration turns).</summary>
	Burning = 1 << 0,
	/// <summary>Hitting an enemy freezes it: it cannot move during its owner's next turn.</summary>
	Frost = 1 << 1,
	/// <summary>Hitting an enemy (that survives) knocks it 1 tile away from the attacker, if that tile is free.</summary>
	Push = 1 << 2,
	/// <summary>The attack also hits the piece directly behind the target (same rules: enemy = damage, friendly = chain).</summary>
	Pierce = 1 << 3,
	/// <summary>Hitting a friendly heals it (GameConfig.MendingHeal) and still triggers its chain.</summary>
	Mending = 1 << 4,
	/// <summary>When chain-triggered, fires in all 4 directions instead of only sideways.</summary>
	Conduit = 1 << 5,
	/// <summary>When chain-triggered, its shots deal +GameConfig.EchoBonusDamage damage.</summary>
	Echo = 1 << 6,
	/// <summary>When it dies, its card returns to the deck upgraded (+1 Attack, +1 HP, Level +1).</summary>
	Undying = 1 << 7,
}
