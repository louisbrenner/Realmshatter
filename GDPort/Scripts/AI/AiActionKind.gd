class_name AiActionKind
extends RefCounted
## Kind of step the AI executed during its turn.

enum {
	DRAFT = 0,
	PLAY_UNIT = 1,
	PLAY_SPELL = 2,
	SET_ORDER = 3,
	## Converted 1 VP into 1 AP (TurnController.convert_vp_to_ap).
	CONVERT_VP = 4,
}

const NAMES := {
	DRAFT: "Draft",
	PLAY_UNIT: "PlayUnit",
	PLAY_SPELL: "PlaySpell",
	SET_ORDER: "SetOrder",
	CONVERT_VP: "ConvertVp",
}


## Equivalent of C# enum ToString().
static func name_of(value: int) -> String:
	return NAMES.get(value, str(value))
