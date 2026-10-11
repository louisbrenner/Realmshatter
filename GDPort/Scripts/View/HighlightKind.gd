class_name HighlightKind
extends RefCounted
## Kind of a tile highlight drawn by BoardView. Later values are drawn on top.

enum { MOVE = 0, ATTACK = 1, DEPLOY = 2, SPELL = 3, SELECTED = 4, HOVER = 5 }

const NAMES := {
	MOVE: "Move",
	ATTACK: "Attack",
	DEPLOY: "Deploy",
	SPELL: "Spell",
	SELECTED: "Selected",
	HOVER: "Hover",
}


## Equivalent of C# enum ToString().
static func name_of(value: int) -> String:
	return NAMES.get(value, str(value))
