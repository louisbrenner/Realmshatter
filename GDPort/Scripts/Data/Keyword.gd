class_name Keyword
extends RefCounted
## Keywords of a unit card (combinable flags). They modify how the piece's attacks resolve. See KeywordInfo, OrderResolver.

enum {
	NONE = 0,
	## Hitting a piece leaves Lava on the target tile (GameConfig.BurningLavaDuration turns).
	BURNING = 1,
	## Hitting a piece freezes it: it cannot move during its owner's next turn.
	FROST = 2,
	## Hitting a piece (that survives) knocks it 1 tile away from the attacker, if that tile is free.
	PUSH = 4,
	## The attack also hits the piece directly behind the target (friend or foe).
	PIERCE = 8,
	## Hitting a friendly heals it (GameConfig.MendingHeal) instead of damaging it.
	MENDING = 16,
	## Its attack also zaps every piece next to the target (friend or foe) for GameConfig.ArcDamage.
	ARC = 32,
	## After attacking, it strikes the same tile again for GameConfig.EchoBonusDamage.
	ECHO = 64,
	## When it dies, its card returns to the deck upgraded (+1 Attack, +1 HP, Level +1).
	UNDYING = 128,
	## Can construct its class's building (BuildingInfo.ForClass) on an adjacent tile.
	BUILDER = 256,
	## At its owner's turn start it pulses its clan effect on the 8 surrounding tiles (TriggerInfo.AuraText).
	AURA = 512,
	## Totem-like unit: it never moves and never scores victory points, but it may be deployed on any free tile within GameConfig.PlantRadius of one of its owner's units (except the crown field), not only in the back rows.
	PLANTED = 1024,
	## Whenever it destroys an enemy piece, its owner gains 1 AP (right away on its own turn, else next turn).
	PLUNDER = 2048,
	## Instead of attacking (also after moving) it can hide a trap next to it; the trap depends on its clan (TrapInfo).
	TRAPPER = 4096,
}

const NAMES := { NONE: "None", BURNING: "Burning", FROST: "Frost", PUSH: "Push", PIERCE: "Pierce", MENDING: "Mending", ARC: "Arc", ECHO: "Echo", UNDYING: "Undying", BUILDER: "Builder", AURA: "Aura", PLANTED: "Planted", PLUNDER: "Plunder", TRAPPER: "Trapper" }

## Equivalent of C# [Flags] enum ToString(): ", "-joined names, "None" for 0.
static func name_of(value: int) -> String:
	if value == 0:
		return NAMES[0]
	var parts: Array[String] = []
	var rest: int = value
	for v: int in NAMES:
		if v != 0 and (value & v) == v:
			parts.append(NAMES[v])
			rest &= ~v
	if rest != 0:
		return str(value)
	return ", ".join(parts)
