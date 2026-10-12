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
	/// <summary>Hitting a piece leaves Lava on the target tile (GameConfig.BurningLavaDuration turns).</summary>
	Burning = 1 << 0,
	/// <summary>Hitting a piece freezes it: it cannot move during its owner's next turn.</summary>
	Frost = 1 << 1,
	/// <summary>Hitting a piece (that survives) knocks it 1 tile away from the attacker, if that tile is free.</summary>
	Push = 1 << 2,
	/// <summary>The attack also hits the piece directly behind the target (friend or foe).</summary>
	Pierce = 1 << 3,
	/// <summary>Hitting a friendly heals it (GameConfig.MendingHeal) instead of damaging it.</summary>
	Mending = 1 << 4,
	/// <summary>Its attack also zaps every piece next to the target (friend or foe) for GameConfig.ArcDamage.</summary>
	Arc = 1 << 5,
	/// <summary>After attacking, it strikes the same tile again for GameConfig.EchoBonusDamage.</summary>
	Echo = 1 << 6,
	/// <summary>When it dies, its card returns to the deck upgraded (+1 Attack, +1 HP, Level +1).</summary>
	Undying = 1 << 7,
	/// <summary>Can construct its class's building (BuildingInfo.ForClass) on an adjacent tile.</summary>
	Builder = 1 << 8,
	/// <summary>At its owner's turn start it pulses its clan effect on the 8 surrounding tiles (TriggerInfo.AuraText).</summary>
	Aura = 1 << 9,
	/// <summary>
	/// Totem-like unit: it never moves and never scores victory points, but it may be deployed on any free tile within
	/// GameConfig.PlantRadius of one of its owner's units (except the crown field), not only in the back rows.
	/// </summary>
	Planted = 1 << 10,
	/// <summary>Whenever it destroys an enemy piece, its owner gains 1 AP (right away on its own turn, else next turn).</summary>
	Plunder = 1 << 11,
	/// <summary>Instead of attacking (also after moving) it can hide a trap next to it; the trap depends on its clan (TrapInfo).</summary>
	Trapper = 1 << 12,
}
