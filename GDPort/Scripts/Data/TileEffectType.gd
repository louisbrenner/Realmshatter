class_name TileEffectType
extends RefCounted
## Map-altering effect on a board tile (one effect per tile, a newer one replaces the older).

enum {
	NONE = 0,
	## Damages the occupant at the start of its owner's turn (GameConfig.LavaDamage). Passable.
	LAVA = 1,
	## Impassable and unoccupiable; blocks movement, pushes, deploys and sideways chain shots.
	WALL = 2,
	## Heals the occupant at the start of its owner's turn (GameConfig.HealingTileAmount). Passable.
	HEALING = 3,
	## Ruins of a destroyed building: impassable like a Wall until it expires.
	RUBBLE = 4,
	## Frozen ground (Frost attacks): a piece moving onto it slides to a halt there. Passable.
	ICE = 5,
	## Storm cell (Arc attacks): at the start of the occupant owner's turn, 1 damage to it and to every piece next to it.
	STORM = 6,
	## Mud (Push attacks): entering costs 2 movement. Passable.
	MUD = 7,
}

const NAMES := { NONE: "None", LAVA: "Lava", WALL: "Wall", HEALING: "Healing", RUBBLE: "Rubble", ICE: "Ice", STORM: "Storm", MUD: "Mud" }

## Equivalent of C# enum ToString().
static func name_of(value: int) -> String:
	return NAMES.get(value, str(value))
