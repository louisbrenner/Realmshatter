class_name TerrainType
extends RefCounted
## Permanent ground of a tile, placed by the MapGenerator at game start (separate from the temporary tile effects, so spells never wash a river away).

enum {
	NONE = 0,
	## River / pond: passable, but entering costs GameConfig.WaterMoveCost movement.
	WATER = 1,
	## Bridge over a river: normal ground.
	BRIDGE = 2,
	## Breakable rock wall: impassable until attacks reduce its HP (GameConfig.RockHp) to 0.
	ROCK = 3,
}

const NAMES := { NONE: "None", WATER: "Water", BRIDGE: "Bridge", ROCK: "Rock" }

## Equivalent of C# enum ToString().
static func name_of(value: int) -> String:
	return NAMES.get(value, str(value))
