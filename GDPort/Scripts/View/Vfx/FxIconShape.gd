class_name FxIconShape
extends RefCounted
## Glyphs of fx_icon.gdshader / keyword_icon.gdshader (VfxAssets.create_icon, KeywordVisuals).

enum {
	SNOWFLAKE = 0,
	BOLT = 1,
	SKULL = 2,
	FLAME = 3,
	PLUS = 4,
	CROSS = 5,
	FROST_RING = 6,
	FIST = 7,
	SPEAR = 8,
	BELL = 9,
	TOMB = 10,
	BURST = 11,
	HAMMER = 12,
	SUN = 13,
	## Stake driven into the ground (Planted).
	STAKE = 14,
	## Two upward chevrons (movement).
	CHEVRONS = 15,
	## Ring with ticks (range).
	CROSSHAIR = 16,
	## Brick wall.
	BRICKS = 17,
	## Faceted mana gem (AP).
	GEM = 18,
	## Toothed trap jaws (Trapper, traps).
	TRAP = 19,
	## Bow and arrow (archers).
	BOW = 20,
}

const NAMES := {
	SNOWFLAKE: "Snowflake",
	BOLT: "Bolt",
	SKULL: "Skull",
	FLAME: "Flame",
	PLUS: "Plus",
	CROSS: "Cross",
	FROST_RING: "FrostRing",
	FIST: "Fist",
	SPEAR: "Spear",
	BELL: "Bell",
	TOMB: "Tomb",
	BURST: "Burst",
	HAMMER: "Hammer",
	SUN: "Sun",
	STAKE: "Stake",
	CHEVRONS: "Chevrons",
	CROSSHAIR: "Crosshair",
	BRICKS: "Bricks",
	GEM: "Gem",
	TRAP: "Trap",
	BOW: "Bow",
}


## Equivalent of C# enum ToString().
static func name_of(value: int) -> String:
	return NAMES.get(value, str(value))
