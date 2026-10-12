class_name AiActionKind
extends RefCounted
## Kind of step the AI executed during its turn.

enum {
	DRAFT = 0,
	PLAY_UNIT = 1,
	PLAY_SPELL = 2,
	## Commanded a piece (move + attack resolved immediately).
	COMMAND = 3,
	## A Builder started a building (TurnController.build).
	BUILD = 4,
	## A Trapper hid a trap (TurnController.set_trap); the target tile stays secret in the description.
	TRAP = 5,
	## Converted 1 VP into 1 AP (TurnController.convert_vp_to_ap).
	CONVERT_VP = 6,
}

const NAMES := {
	DRAFT: "Draft",
	PLAY_UNIT: "PlayUnit",
	PLAY_SPELL: "PlaySpell",
	COMMAND: "Command",
	BUILD: "Build",
	TRAP: "Trap",
	CONVERT_VP: "ConvertVp",
}


## Equivalent of C# enum ToString().
static func name_of(value: int) -> String:
	return NAMES.get(value, str(value))
