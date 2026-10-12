class_name CardType
extends RefCounted
## Kind of card: a unit that is deployed as a piece, or a spell that targets a piece.

enum {
	UNIT = 0,
	SPELL = 1,
	## A building piece created by a Builder (never part of a deck, see BuildingInfo).
	BUILDING = 2,
}

const NAMES := { UNIT: "Unit", SPELL: "Spell", BUILDING: "Building" }

## Equivalent of C# enum ToString().
static func name_of(value: int) -> String:
	return NAMES.get(value, str(value))
