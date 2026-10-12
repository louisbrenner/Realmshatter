class_name TrapInfo
extends RefCounted
## Which trap a clan's Trapper sets, plus names, rule texts and colours of the traps.


## Trap set by a Trapper of the given clan.
static func for_clan(clan: int) -> int:
	match clan:
		Clan.FIRE: return TrapType.FIRE
		Clan.FROST: return TrapType.FROST
		Clan.STORM: return TrapType.SHOCK
		Clan.STONE: return TrapType.PITFALL
		Clan.HEALING: return TrapType.SANCTUM
	return TrapType.SPIKE


## Display name, e.g. "Fire Trap".
static func display_name(type: int) -> String:
	match type:
		TrapType.FIRE: return "Fire Trap"
		TrapType.FROST: return "Frost Trap"
		TrapType.SHOCK: return "Shock Trap"
		TrapType.PITFALL: return "Pitfall"
		TrapType.SANCTUM: return "Sanctum Ward"
	return "Spike Trap"


## What happens to an enemy that steps on it (after its move is stopped there).
static func describe(type: int) -> String:
	match type:
		TrapType.FIRE: return "1 damage and its tile turns into Lava."
		TrapType.FROST: return "1 damage and it is Frozen through its next turn."
		TrapType.SHOCK: return "1 damage to it and to every enemy next to it."
		TrapType.PITFALL: return "3 damage."
		TrapType.SANCTUM: return "1 damage, and your pieces within 2 tiles heal 1 HP."
	return "2 damage."


## Glyph colour of the trap's emblem / board marker.
static func get_color(type: int) -> Color:
	match type:
		TrapType.FIRE: return Color(1.0, 0.5, 0.15)
		TrapType.FROST: return Color(0.6, 0.88, 1.0)
		TrapType.SHOCK: return Color(0.82, 0.68, 1.0)
		TrapType.PITFALL: return Color(0.82, 0.74, 0.6)
		TrapType.SANCTUM: return Color(1.0, 0.9, 0.5)
	return Color(0.9, 0.9, 0.92)
