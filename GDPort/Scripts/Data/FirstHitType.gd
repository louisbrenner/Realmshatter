class_name FirstHitType
extends RefCounted
## Effect a unit triggers the first time it takes damage and survives (CardData.OnFirstHit).

enum {
	NONE = 0,
	## The attacker takes Amount damage.
	THORNS = 1,
	## The attacker is pushed 1 tile away.
	REPEL = 2,
	## Gains Amount Shield.
	HARDEN = 3,
	## Gains +Amount Attack for the rest of the game.
	ENRAGE = 4,
	## Pushes every piece next to it 1 tile away.
	SHOCKWAVE = 5,
}

const NAMES := { NONE: "None", THORNS: "Thorns", REPEL: "Repel", HARDEN: "Harden", ENRAGE: "Enrage", SHOCKWAVE: "Shockwave" }

## Equivalent of C# enum ToString().
static func name_of(value: int) -> String:
	return NAMES.get(value, str(value))
