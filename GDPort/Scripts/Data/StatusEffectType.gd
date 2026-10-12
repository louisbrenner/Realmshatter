class_name StatusEffectType
extends RefCounted
## Temporary status on a piece (see Piece.StatusEffects).

enum {
	NONE = 0,
	## Effective movement is 0 (applied by Frost, lasts through the owner's next turn).
	FROZEN = 1,
	## The next time the piece is chain-triggered, its chain shots deal double damage (consumed).
	OVERCHARGED = 2,
}

const NAMES := { NONE: "None", FROZEN: "Frozen", OVERCHARGED: "Overcharged" }

## Equivalent of C# enum ToString().
static func name_of(value: int) -> String:
	return NAMES.get(value, str(value))
