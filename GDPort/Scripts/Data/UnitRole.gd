class_name UnitRole
extends RefCounted
## Role of a unit card. Resource units typically grant bonus AP.

enum {
	ATTACK = 0,
	UTILITY = 1,
	RESOURCE = 2,
}

const NAMES := { ATTACK: "Attack", UTILITY: "Utility", RESOURCE: "Resource" }

## Equivalent of C# enum ToString().
static func name_of(value: int) -> String:
	return NAMES.get(value, str(value))
