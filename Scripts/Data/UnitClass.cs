namespace Realmshatter;

/// <summary>
/// Class of a unit (its basic fighting style). A unit card = a class plus effects (keywords such as Burning or
/// Mending), e.g. Flame Archer = Archer + Burning. See ClassInfo for names, descriptions and base stats.
/// </summary>
public enum UnitClass
{
	None,
	Swordsman,
	Archer,
	Guardian,
	Scout,
	Lancer,
	Mage,
	Cleric,
	Brute,
	Totem,
	Worker,
}
