class_name SpellTargetType
extends RefCounted
## What a spell card is cast on (Piece, single Tile, or Area around the anchor tile).

enum { PIECE = 0, TILE = 1, AREA = 2 }

const NAMES := { PIECE: "Piece", TILE: "Tile", AREA: "Area" }

## Equivalent of C# enum ToString().
static func name_of(value: int) -> String:
	return NAMES.get(value, str(value))
