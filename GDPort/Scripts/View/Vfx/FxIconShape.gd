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
}


## Equivalent of C# enum ToString().
static func name_of(value: int) -> String:
	return NAMES.get(value, str(value))
