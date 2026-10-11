class_name AreaShape
extends RefCounted
## Shape of an area spell around its anchor tile (clipped to the board).

enum { SINGLE = 0, PLUS = 1, ROW3 = 2, COLUMN3 = 3, SQUARE2 = 4 }

const NAMES := { SINGLE: "Single", PLUS: "Plus", ROW3: "Row3", COLUMN3: "Column3", SQUARE2: "Square2" }

## Equivalent of C# enum ToString().
static func name_of(value: int) -> String:
	return NAMES.get(value, str(value))
