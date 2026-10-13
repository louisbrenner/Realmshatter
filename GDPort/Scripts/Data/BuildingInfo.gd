class_name BuildingInfo
extends RefCounted
## Stats and texts of the buildings, which class builds what, and the runtime CardData each building piece uses
## (CardType.BUILDING, never in a deck). Construction time is counted in the owner's turns.
## Clan versions: a building raised by a clan unit carries that clan ("Ember Turret", "Rime Barricade", ...). It works
## like the plain building and additionally pulses its clan's aura onto the 8 surrounding tiles at the start of every
## owner turn (OrderResolver.resolve_buildings_turn_start).

## Key: type * 16 + clan.
static var _cards: Dictionary[int, CardData] = {}


## Building a Builder of this class constructs (None = this class cannot build).
static func for_class(unit_class: int) -> int:
	match unit_class:
		UnitClass.ARCHER: return BuildingType.TURRET
		UnitClass.WORKER: return BuildingType.MANA_WELL
		UnitClass.CLERIC: return BuildingType.SHRINE
		UnitClass.GUARDIAN: return BuildingType.BARRICADE
		UnitClass.SWORDSMAN: return BuildingType.BARRICADE
		UnitClass.MAGE: return BuildingType.OBELISK
	return BuildingType.NONE


## Name prefix of a clan's buildings ("" for neutral ones).
static func clan_prefix(clan: int) -> String:
	match clan:
		Clan.FIRE: return "Ember"
		Clan.FROST: return "Rime"
		Clan.STORM: return "Storm"
		Clan.STONE: return "Granite"
		Clan.HEALING: return "Dawn"
	return ""


## Name of a building, raised by a unit of 'clan' (e.g. "Ember Turret"; neutral = plain name).
static func display_name(type: int, clan: int = Clan.NONE) -> String:
	var plain: String = ""
	match type:
		BuildingType.TURRET: plain = "Turret"
		BuildingType.MANA_WELL: plain = "Mana Well"
		BuildingType.SHRINE: plain = "Shrine"
		BuildingType.BARRICADE: plain = "Barricade"
		BuildingType.OBELISK: plain = "Obelisk"
	if clan == Clan.NONE or type == BuildingType.NONE:
		return plain
	return "%s %s" % [clan_prefix(clan), plain]


## Rule text of a building; clan versions add their turn-start aura pulse.
static func get_description(type: int, clan: int = Clan.NONE) -> String:
	var text: String = _plain_description(type)
	if clan == Clan.NONE or type == BuildingType.NONE:
		return text
	return "%s At the start of your turn it also %s" % [text, TriggerInfo.aura_text(clan)]


static func _plain_description(type: int) -> String:
	match type:
		BuildingType.TURRET: return "Once per enemy turn it shoots an enemy that moves into range (3 tiles) for 1 damage."
		BuildingType.MANA_WELL: return "+1 AP for its owner at the start of every turn."
		BuildingType.SHRINE: return "Heals your pieces on the 8 surrounding tiles by 1 at the start of your turn."
		BuildingType.BARRICADE: return "Two sturdy blockers that hold a lane (one build places two)."
		BuildingType.OBELISK: return "Empowers your spells aimed within 4 tiles of it: +1 damage, healing, stat change and duration."
	return ""


## AP the build action costs.
static func get_cost(type: int) -> int:
	match type:
		BuildingType.MANA_WELL: return 2
		BuildingType.NONE: return 0
	return 1


## How many buildings one build action places (Barricades come in pairs).
static func get_build_count(type: int) -> int:
	return 2 if type == BuildingType.BARRICADE else 1


## Own turns until the building is finished.
static func get_build_turns(type: int) -> int:
	return 2 if type == BuildingType.MANA_WELL else 1


## The (shared, runtime) card describing a building piece raised by a unit of 'clan' (neutral by default).
static func get_card(type: int, clan: int = Clan.NONE) -> CardData:
	var key: int = type * 16 + clan
	if _cards.has(key):
		return _cards[key]
	var hp: int = 1
	var atk: int = 0
	var rng: int = 1
	var shield: int = 0
	var tint: Color = Color.GRAY
	match type:
		BuildingType.TURRET:
			hp = 4; atk = 1; rng = 3; shield = 0; tint = Color(0.7, 0.55, 0.4)
		BuildingType.MANA_WELL:
			hp = 3; atk = 0; rng = 1; shield = 0; tint = Color(0.35, 0.6, 1.0)
		BuildingType.SHRINE:
			hp = 3; atk = 0; rng = 1; shield = 0; tint = Color(1.0, 0.9, 0.55)
		BuildingType.BARRICADE:
			hp = 3; atk = 0; rng = 1; shield = 1; tint = Color(0.6, 0.5, 0.38)
		BuildingType.OBELISK:
			hp = 3; atk = 0; rng = 1; shield = 0; tint = Color(0.65, 0.45, 1.0)
	if clan != Clan.NONE:
		# Clan buildings are a little sturdier than plain ones.
		tint = tint.lerp(ClanInfo.get_color(clan), 0.6)
		hp += 1
	var card := CardData.new()
	card.name = display_name(type, clan)
	card.description = get_description(type, clan)
	card.clan = clan
	card.card_type = CardType.BUILDING
	card.role = UnitRole.UTILITY
	card.movement = 0
	card.attack = atk
	card.hp = hp
	card.range = rng
	card.shield = shield
	card.tint = tint
	card.building = type
	_cards[key] = card
	return card
