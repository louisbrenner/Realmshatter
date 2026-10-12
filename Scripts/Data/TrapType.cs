namespace Realmshatter;

/// <summary>Kind of a hidden trap; a Trapper's clan decides which one it sets (see TrapInfo).</summary>
public enum TrapType
{
	/// <summary>Basic: spikes for 2 damage.</summary>
	Spike,
	/// <summary>Ember Legion: 1 damage and the tile turns into Lava.</summary>
	Fire,
	/// <summary>Frostbound: 1 damage and the victim is Frozen through its next turn.</summary>
	Frost,
	/// <summary>Storm Circuit: 1 damage to the victim and to every enemy next to it.</summary>
	Shock,
	/// <summary>Stone Bastion: a pitfall for 3 damage.</summary>
	Pitfall,
	/// <summary>Dawn Covenant: 1 damage and the trap owner's pieces within 2 tiles heal 1.</summary>
	Sanctum,
}
