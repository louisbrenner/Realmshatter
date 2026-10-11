class_name KeywordInfo
extends RefCounted
## Display names and short rule texts of keywords (for card texts and tooltips).

## All single keywords in display order.
const ALL: Array[int] = [
	Keyword.BURNING, Keyword.FROST, Keyword.PUSH, Keyword.PIERCE,
	Keyword.MENDING, Keyword.CONDUIT, Keyword.ECHO, Keyword.UNDYING,
]


## Display name of a single keyword.
static func get_keyword_name(keyword: int) -> String:
	match keyword:
		Keyword.BURNING: return "Burning"
		Keyword.FROST: return "Frost"
		Keyword.PUSH: return "Push"
		Keyword.PIERCE: return "Pierce"
		Keyword.MENDING: return "Mending"
		Keyword.CONDUIT: return "Conduit"
		Keyword.ECHO: return "Echo"
		Keyword.UNDYING: return "Undying"
	return Keyword.name_of(keyword)


## Short rule text of a single keyword.
static func get_description(keyword: int) -> String:
	match keyword:
		Keyword.BURNING: return "Hitting an enemy sets its tile on fire (Lava: 1 damage at the start of the occupant's turn)."
		Keyword.FROST: return "Hitting an enemy freezes it: it cannot move on its next turn."
		Keyword.PUSH: return "Hitting an enemy knocks it 1 tile away, if that tile is free."
		Keyword.PIERCE: return "The attack also hits the piece directly behind the target."
		Keyword.MENDING: return "Hitting a friendly heals it 1 HP (it still chain-fires)."
		Keyword.CONDUIT: return "When chain-triggered, fires in all 4 directions instead of only sideways."
		Keyword.ECHO: return "When chain-triggered, its shots deal +1 damage."
		Keyword.UNDYING: return "When it dies, it returns to your deck with +1 Attack and +1 HP."
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
	var names: Array[String] = []
	for k: int in split(keywords):
		names.append(get_keyword_name(k))
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
		StatusEffectType.OVERCHARGED: return "Its next chain trigger deals double damage."
	return ""


## Display name of a tile effect.
static func get_tile_effect_name(type: int) -> String:
	match type:
		TileEffectType.LAVA: return "Lava"
		TileEffectType.WALL: return "Wall"
		TileEffectType.HEALING: return "Healing"
	return TileEffectType.name_of(type)


## Short rule text of a tile effect.
static func get_tile_effect_description(type: int) -> String:
	match type:
		TileEffectType.LAVA: return "Deals 1 damage to the piece on it at the start of that piece's owner's turn."
		TileEffectType.WALL: return "Impassable: blocks movement, pushes and sideways chain shots."
		TileEffectType.HEALING: return "Heals the piece on it 1 HP at the start of that piece's owner's turn."
	return ""
