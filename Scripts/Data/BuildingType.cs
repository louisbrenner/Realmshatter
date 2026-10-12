namespace Realmshatter;

/// <summary>Buildings a Builder unit can construct; which one depends on the unit's class (see BuildingInfo).</summary>
public enum BuildingType
{
	None,
	/// <summary>Archer: once per enemy turn, shoots an enemy that moves into its range.</summary>
	Turret,
	/// <summary>Worker: +1 AP for its owner at every turn start.</summary>
	ManaWell,
	/// <summary>Cleric: heals the owner's pieces on the 8 surrounding tiles at every turn start.</summary>
	Shrine,
	/// <summary>Guardian / Swordsman: a tough blocker.</summary>
	Barricade,
	/// <summary>Mage: the owner may cast spells within a larger radius around it.</summary>
	Obelisk,
}
