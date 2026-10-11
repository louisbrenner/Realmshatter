class_name GridPos
extends RefCounted
## Board coordinate helpers. GridPos itself is replaced by Vector2i everywhere (x = column, left to right;
## y = row, row 0 = top, the side of player 1; row height-1 = bottom, the side of player 0).

## The four orthogonal unit offsets: right, left, down (+y), up (-y).
const ORTHOGONAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]


## Manhattan (taxicab) distance between two positions.
static func manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## The four orthogonal neighbors (may lie outside the board).
static func neighbors(p: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for d: Vector2i in ORTHOGONAL_DIRECTIONS:
		result.append(p + d)
	return result
