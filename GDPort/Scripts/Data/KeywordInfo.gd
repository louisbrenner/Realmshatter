class_name KeywordInfo
extends RefCounted
## Display names and short rule texts of keywords (for card texts and tooltips).

## All single keywords in display order.
const ALL: Array[int] = [
	Keyword.BURNING, Keyword.FROST, Keyword.PUSH, Keyword.PIERCE,
	Keyword.MENDING, Keyword.ARC, Keyword.ECHO, Keyword.UNDYING, Keyword.BUILDER, Keyword.AURA, Keyword.PLANTED, Keyword.PLUNDER, Keyword.TRAPPER,
]


## Display name of a single keyword.
static func display_name(keyword: int) -> String:
	match keyword:
		Keyword.BURNING: return "Burning"
		Keyword.FROST: return "Frost"
		Keyword.PUSH: return "Push"
		Keyword.PIERCE: return "Pierce"
		Keyword.MENDING: return "Mending"
		Keyword.ARC: return "Arc"
		Keyword.ECHO: return "Echo"
		Keyword.UNDYING: return "Undying"
		Keyword.BUILDER: return "Builder"
		Keyword.AURA: return "Aura"
		Keyword.PLANTED: return "Planted"
		Keyword.PLUNDER: return "Plunder"
		Keyword.TRAPPER: return "Trapper"
	return Keyword.name_of(keyword)


## Short rule text of a single keyword.
static func get_description(keyword: int) -> String:
	match keyword:
		Keyword.BURNING: return "Its attacks set the target tile on fire - even an empty one (Lava: 1 damage at the start of the occupant's turn)."
		Keyword.FROST: return "Hitting a piece freezes it (it cannot move on its next turn); the target tile turns to Ice (stops any move onto it)."
		Keyword.PUSH: return "Hitting a piece knocks it 1 tile away; if another piece, a building, a wall or a rock is in the way, it is slammed into it and takes 1 damage instead. The target tile turns to Mud (costs 2 movement)."
		Keyword.PIERCE: return "The attack also hits the piece directly behind the target - friend or foe."
		Keyword.MENDING: return "Hitting a friendly heals it 1 HP instead of damaging it; the target tile becomes a Healing spring (for anyone)."
		Keyword.ARC: return "Its attack also zaps every piece next to the target for 1 damage - friend or foe; the target tile becomes a Storm cell."
		Keyword.ECHO: return "After attacking, it strikes the same tile again for 1 damage."
		Keyword.UNDYING: return "When it dies, it returns to your deck with +1 Attack and +1 HP."
		Keyword.BUILDER: return "Instead of acting it can build its class's building on an adjacent tile. It cannot move or score VP while building; if it dies, the unfinished building collapses."
		Keyword.AURA: return "At the start of your turn it pulses its clan's effect onto the 8 surrounding tiles."
		Keyword.PLUNDER: return "Whenever it destroys an enemy piece, you gain 1 AP."
		Keyword.TRAPPER: return "Instead of attacking (also after moving) it can hide a trap on a free tile next to it (1 AP). An enemy stepping on it is stopped and hit. Up to 2 traps per Trapper."
		Keyword.PLANTED: return "Cannot move and never scores VP. Deploy it on any free tile within 2 of one of your units (not on the crown)."
	return ""


## The single keywords contained in a combined flag value, in display order.
static func split(keywords: int) -> Array[int]:
	var list: Array[int] = []
	for k: int in ALL:
		if (keywords & k) != 0:
			list.append(k)
	return list


## Comma-separated display names, e.g. "Burning, Pierce" ("" for none).
static func format(keywords: int) -> String:
	var names: PackedStringArray = []
	for k: int in split(keywords):
		names.append(display_name(k))
	return ", ".join(names)


## Display name of a status effect.
static func get_status_name(status: int) -> String:
	match status:
		StatusEffectType.FROZEN: return "Frozen"
		StatusEffectType.OVERCHARGED: return "Overcharged"
	return StatusEffectType.name_of(status)


## Short rule text of a status effect.
static func get_status_description(status: int) -> String:
	match status:
		StatusEffectType.FROZEN: return "Cannot move this turn."
		StatusEffectType.OVERCHARGED: return "Its next attack deals double damage."
	return ""


## Display name of a tile effect.
static func get_tile_effect_name(type: int) -> String:
	match type:
		TileEffectType.LAVA: return "Lava"
		TileEffectType.WALL: return "Wall"
		TileEffectType.HEALING: return "Healing"
		TileEffectType.RUBBLE: return "Rubble"
		TileEffectType.ICE: return "Ice"
		TileEffectType.STORM: return "Storm Cell"
		TileEffectType.MUD: return "Mud"
	return TileEffectType.name_of(type)


## Short rule text of a tile effect.
static func get_tile_effect_description(type: int) -> String:
	match type:
		TileEffectType.LAVA: return "Deals 1 damage to the piece on it at the start of that piece's owner's turn."
		TileEffectType.WALL: return "Impassable: blocks movement, pushes and pierce shots."
		TileEffectType.HEALING: return "Heals the piece on it 1 HP at the start of that piece's owner's turn."
		TileEffectType.RUBBLE: return "Ruins of a destroyed building: impassable until it is cleared."
		TileEffectType.ICE: return "Slippery: any piece moving onto it slides to a halt there."
		TileEffectType.STORM: return "Crackles at the start of the occupant's turn: 1 damage to it and to every piece next to it."
		TileEffectType.MUD: return "Sticky: entering costs 2 movement."
	return ""
