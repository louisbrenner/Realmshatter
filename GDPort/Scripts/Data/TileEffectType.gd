class_name TileEffectType
extends RefCounted
## Map-altering effect on a board tile (one effect per tile, a newer one replaces the older).

enum { NONE = 0, LAVA = 1, WALL = 2, HEALING = 3 }

const NAMES := { NONE: "None", LAVA: "Lava", WALL: "Wall", HEALING: "Healing" }

## Equivalent of C# enum ToString().
static func name_of(value: int) -> String:
	return NAMES.get(value, str(value))
