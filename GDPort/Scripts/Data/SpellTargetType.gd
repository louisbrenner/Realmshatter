class_name SpellTargetType
extends RefCounted
## What a spell card is cast on.

enum {
	## A living piece (stat modifiers / status). Classic spells.
	PIECE = 0,
	## A single board tile (the AreaShape is ignored and treated as Single).
	TILE = 1,
	## A board tile as the anchor of CardData.AreaShape.
	AREA = 2,
}

const NAMES := { PIECE: "Piece", TILE: "Tile", AREA: "Area" }

## Equivalent of C# enum ToString().
static func name_of(value: int) -> String:
	return NAMES.get(value, str(value))
