class_name BuildingType
extends RefCounted
## Buildings a Builder unit can construct; which one depends on the unit's class (see BuildingInfo).

enum {
	NONE = 0,
	## Archer: once per enemy turn, shoots an enemy that moves into its range.
	TURRET = 1,
	## Worker: +1 AP for its owner at every turn start.
	MANA_WELL = 2,
	## Cleric: heals the owner's pieces on the 8 surrounding tiles at every turn start.
	SHRINE = 3,
	## Guardian / Swordsman: a tough blocker.
	BARRICADE = 4,
	## Mage: the owner may cast spells within a larger radius around it.
	OBELISK = 5,
}

const NAMES := { NONE: "None", TURRET: "Turret", MANA_WELL: "ManaWell", SHRINE: "Shrine", BARRICADE: "Barricade", OBELISK: "Obelisk" }

## Equivalent of C# enum ToString().
static func name_of(value: int) -> String:
	return NAMES.get(value, str(value))
