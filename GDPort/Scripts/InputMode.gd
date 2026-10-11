class_name InputMode
extends RefCounted
## State of the human player's input state machine in GameManager.

enum { IDLE = 0, CARD_SELECTED = 1, CHOOSING_MOVE = 2, CHOOSING_ATTACK = 3, BUSY = 4 }

const NAMES := { IDLE: "Idle", CARD_SELECTED: "CardSelected", CHOOSING_MOVE: "ChoosingMove", CHOOSING_ATTACK: "ChoosingAttack", BUSY: "Busy" }

## Equivalent of C# enum ToString().
static func name_of(value: int) -> String:
	return NAMES.get(value, str(value))
