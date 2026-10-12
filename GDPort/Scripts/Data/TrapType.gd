class_name TrapType
extends RefCounted
## Kind of a hidden trap; a Trapper's clan decides which one it sets (see TrapInfo).

enum {
	## Basic: spikes for 2 damage.
	SPIKE = 0,
	## Ember Legion: 1 damage and the tile turns into Lava.
	FIRE = 1,
	## Frostbound: 1 damage and the victim is Frozen through its next turn.
	FROST = 2,
	## Storm Circuit: 1 damage to the victim and to every enemy next to it.
	SHOCK = 3,
	## Stone Bastion: a pitfall for 3 damage.
	PITFALL = 4,
	## Dawn Covenant: 1 damage and the trap owner's pieces within 2 tiles heal 1.
	SANCTUM = 5,
}

const NAMES := { SPIKE: "Spike", FIRE: "Fire", FROST: "Frost", SHOCK: "Shock", PITFALL: "Pitfall", SANCTUM: "Sanctum" }

## Equivalent of C# enum ToString().
static func name_of(value: int) -> String:
	return NAMES.get(value, str(value))
