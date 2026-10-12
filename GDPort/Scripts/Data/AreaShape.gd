class_name AreaShape
extends RefCounted
## Shape of an area spell around its anchor tile (clipped to the board).

enum {
	## Only the anchor tile.
	SINGLE = 0,
	## Anchor plus its 4 orthogonal neighbors.
	PLUS = 1,
	## Anchor plus the tiles left and right of it (horizontal line of 3).
	ROW3 = 2,
	## Anchor plus the tiles above and below it (vertical line of 3).
	COLUMN3 = 3,
	## 2x2 square with the anchor as its top-left tile (anchor, +X, +Y, +X+Y).
	SQUARE2 = 4,
}

const NAMES := { SINGLE: "Single", PLUS: "Plus", ROW3: "Row3", COLUMN3: "Column3", SQUARE2: "Square2" }

## Equivalent of C# enum ToString().
static func name_of(value: int) -> String:
	return NAMES.get(value, str(value))
