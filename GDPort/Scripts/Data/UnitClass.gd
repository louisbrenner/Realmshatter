class_name UnitClass
extends RefCounted
## Class of a unit (its basic fighting style). A unit card = a class plus effects (keywords such as Burning or Mending), e.g. Flame Archer = Archer + Burning. See ClassInfo for names, descriptions and base stats.

enum {
	NONE = 0,
	SWORDSMAN = 1,
	ARCHER = 2,
	GUARDIAN = 3,
	SCOUT = 4,
	LANCER = 5,
	MAGE = 6,
	CLERIC = 7,
	BRUTE = 8,
	TOTEM = 9,
	WORKER = 10,
}

const NAMES := { NONE: "None", SWORDSMAN: "Swordsman", ARCHER: "Archer", GUARDIAN: "Guardian", SCOUT: "Scout", LANCER: "Lancer", MAGE: "Mage", CLERIC: "Cleric", BRUTE: "Brute", TOTEM: "Totem", WORKER: "Worker" }

## Equivalent of C# enum ToString().
static func name_of(value: int) -> String:
	return NAMES.get(value, str(value))
