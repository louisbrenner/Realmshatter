class_name InputMode
extends RefCounted
## State of the human player's input state machine in GameManager.

enum {
	## Nothing selected; waiting for a card or piece selection.
	IDLE = 0,
	## A hand card is selected; waiting for a deploy tile or spell target.
	CARD_SELECTED = 1,
	## An own piece is selected; waiting for its move destination (or its own tile = stay).
	CHOOSING_MOVE = 2,
	## The move step is done; waiting for the attack tile (or any other tile = move only).
	CHOOSING_ATTACK = 3,
	## A Builder is selected and the player picks the tile for its building.
	CHOOSING_BUILD = 4,
	## A Trapper is selected and the player picks the tile for its trap.
	CHOOSING_TRAP = 5,
	## Animations or the AI turn are running; human input is ignored.
	BUSY = 6,
}

const NAMES := { IDLE: "Idle", CARD_SELECTED: "CardSelected", CHOOSING_MOVE: "ChoosingMove", CHOOSING_ATTACK: "ChoosingAttack", CHOOSING_BUILD: "ChoosingBuild", CHOOSING_TRAP: "ChoosingTrap", BUSY: "Busy" }

## Equivalent of C# enum ToString().
static func name_of(value: int) -> String:
	return NAMES.get(value, str(value))
