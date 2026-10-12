class_name LegendEffect
extends RefCounted
## Unique effect of a Legendary unit (one per clan, see LegendInfo).

enum {
	NONE = 0,
	## Ember Legion: at the start of your turn every enemy standing on Lava takes 2 damage.
	WILDFIRE = 1,
	## Dawn Covenant: at the start of your turn your units within 3 tiles are healed to full HP.
	DAWNLIGHT = 2,
	## Frostbound: at the start of your turn every enemy within 2 tiles is Frozen.
	GLACIAL_GRIP = 3,
	## Storm Circuit: at the start of your turn lightning strikes the 3 nearest enemies (within 5 tiles) for 1 damage.
	CHAIN_LIGHTNING = 4,
	## Stone Bastion: it takes at most 1 damage from any single hit.
	UNBREAKABLE = 5,
}

const NAMES := { NONE: "None", WILDFIRE: "Wildfire", DAWNLIGHT: "Dawnlight", GLACIAL_GRIP: "GlacialGrip", CHAIN_LIGHTNING: "ChainLightning", UNBREAKABLE: "Unbreakable" }

## Equivalent of C# enum ToString().
static func name_of(value: int) -> String:
	return NAMES.get(value, str(value))
