class_name StatusEffectType
extends RefCounted
## Temporary status on a piece (see Piece.status_effects).

enum { NONE = 0, FROZEN = 1, OVERCHARGED = 2 }

const NAMES := { NONE: "None", FROZEN: "Frozen", OVERCHARGED: "Overcharged" }

## Equivalent of C# enum ToString().
static func name_of(value: int) -> String:
	return NAMES.get(value, str(value))
