class_name DeathrattleType
extends RefCounted
## Effect a unit triggers when it dies (CardData.Deathrattle, strength CardData.DeathrattleAmount).

enum {
	NONE = 0,
	## Deals Amount damage to every piece next to it - friend or foe.
	EXPLODE = 1,
	## Pushes every piece next to it 1 tile away.
	SHOCKWAVE = 2,
	## Its tile and the tiles next to it turn into Lava.
	LAVA_POOL = 3,
	## Heals the owner's pieces within 2 tiles by Amount.
	HEAL_ALLIES = 4,
	## Raises Walls on the free tiles next to it.
	RAISE_WALLS = 5,
	## The owner draws Amount cards from its deck.
	DRAW_CARD = 6,
	## Freezes every enemy next to it.
	FROST_NOVA = 7,
	## The owner gains Amount AP at the start of its next turn.
	TRIBUTE = 8,
}

const NAMES := { NONE: "None", EXPLODE: "Explode", SHOCKWAVE: "Shockwave", LAVA_POOL: "LavaPool", HEAL_ALLIES: "HealAllies", RAISE_WALLS: "RaiseWalls", DRAW_CARD: "DrawCard", FROST_NOVA: "FrostNova", TRIBUTE: "Tribute" }

## Equivalent of C# enum ToString().
static func name_of(value: int) -> String:
	return NAMES.get(value, str(value))
