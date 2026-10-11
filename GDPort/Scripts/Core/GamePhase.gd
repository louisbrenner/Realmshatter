class_name GamePhase
extends RefCounted
## Phase of the current turn.

enum { NOT_STARTED = 0, DRAFT = 1, MAIN = 2, RESOLVING = 3, GAME_OVER = 4 }

const NAMES := { NOT_STARTED: "NotStarted", DRAFT: "Draft", MAIN: "Main", RESOLVING: "Resolving", GAME_OVER: "GameOver" }

## Equivalent of C# enum ToString().
static func name_of(value: int) -> String:
	return NAMES.get(value, str(value))
