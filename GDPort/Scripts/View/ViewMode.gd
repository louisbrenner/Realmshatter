class_name ViewMode
extends RefCounted
## Camera presentation mode of the board.
## TWO_D = orthographic, straight top-down. TWO_POINT_FIVE_D = orthographic, angled (isometric-like).
## THREE_D = perspective, angled from player 0's side.

enum { TWO_D = 0, TWO_POINT_FIVE_D = 1, THREE_D = 2 }

const NAMES := {
	TWO_D: "TwoD",
	TWO_POINT_FIVE_D: "TwoPointFiveD",
	THREE_D: "ThreeD",
}


## Equivalent of C# enum ToString().
static func name_of(value: int) -> String:
	return NAMES.get(value, str(value))
