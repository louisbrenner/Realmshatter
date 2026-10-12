class_name CardRarity
extends RefCounted
## Rarity of a card: drives its shop price and the colour of its type plate.

enum {
	COMMON = 0,
	RARE = 1,
	EPIC = 2,
	## One unique unit per clan with a one-of-a-kind effect (LegendEffect); max 1 copy per deck, very expensive.
	LEGENDARY = 3,
}

const NAMES := { COMMON: "Common", RARE: "Rare", EPIC: "Epic", LEGENDARY: "Legendary" }

## Equivalent of C# enum ToString().
static func name_of(value: int) -> String:
	return NAMES.get(value, str(value))
