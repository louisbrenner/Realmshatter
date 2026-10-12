class_name Clan
extends RefCounted
## The clans of the town; every NPC belongs to one and fights with its style.

enum {
	NONE = 0,
	FIRE = 1,
	HEALING = 2,
	FROST = 3,
	STORM = 4,
	STONE = 5,
}

const NAMES := { NONE: "None", FIRE: "Fire", HEALING: "Healing", FROST: "Frost", STORM: "Storm", STONE: "Stone" }

## Equivalent of C# enum ToString().
static func name_of(value: int) -> String:
	return NAMES.get(value, str(value))
