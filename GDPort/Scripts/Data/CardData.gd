class_name CardData
extends Resource
## Definition of a card. Unit cards use the stat block (movement..shield, ap_bonus);
## spell cards use the *_delta modifiers, which are applied to the target piece.
## ap_cost <= 0 means "use the default from GameConfig" (unit_ap_cost = 1, spell_ap_cost = 2).

@export_group("General")
@export var name: String = ""
@export_multiline var description: String = ""
@export_enum("Unit", "Spell", "Building") var card_type: int = CardType.UNIT
@export_enum("Attack", "Utility", "Resource") var role: int = UnitRole.ATTACK
## Clan of the card (None = basic). Decides the clan deathrattle and the aura effect.
@export_enum("None", "Fire", "Healing", "Frost", "Storm", "Stone") var clan: int = Clan.NONE
## Rarity (shop price, plate colour). Epic cards are mostly rewards of clan leaders.
@export_enum("Common", "Rare", "Epic", "Legendary") var rarity: int = CardRarity.COMMON
## Unit class (Swordsman, Archer...). The card's keywords are the effects layered on top of it.
## (C# "Class"; renamed because "class" is a GDScript keyword. A "class" key in .tres files is accepted via _set.)
@export_enum("None", "Swordsman", "Archer", "Guardian", "Scout", "Lancer", "Mage", "Cleric", "Brute", "Totem", "Worker") var class_: int = UnitClass.NONE
@export var ap_cost: int = 0

@export_group("Unit Stats")
@export var movement: int = 2
@export var attack: int = 1
@export var hp: int = 3
@export var range: int = 1
@export var shield: int = 0
@export var ap_bonus: int = 0

## Keyword flags of a unit (see Keyword / KeywordInfo).
@export_group("Keywords")
@export_flags("Burning", "Frost", "Push", "Pierce", "Mending", "Arc", "Echo", "Undying", "Builder", "Aura", "Planted", "Plunder", "Trapper") var keywords: int = Keyword.NONE
## Undying upgrade level (0 = original card; each Undying death returns a copy with level + 1).
@export var level: int = 0

## Unique effect of a Legendary unit (see LegendInfo).
@export_group("Legendary")
@export_enum("None", "Wildfire", "Dawnlight", "GlacialGrip", "ChainLightning", "Unbreakable") var legend: int = LegendEffect.NONE

## Effect when the unit dies (see TriggerInfo).
@export_group("Triggers")
@export_enum("None", "Explode", "Shockwave", "LavaPool", "HealAllies", "RaiseWalls", "DrawCard", "FrostNova", "Tribute") var deathrattle: int = DeathrattleType.NONE
@export var deathrattle_amount: int = 1
## Effect the first time the unit takes damage and survives.
@export_enum("None", "Thorns", "Repel", "Harden", "Enrage", "Shockwave") var on_first_hit: int = FirstHitType.NONE
@export var on_first_hit_amount: int = 1

@export_group("Spell Modifiers")
@export var attack_delta: int = 0
@export var hp_delta: int = 0
@export var shield_delta: int = 0
@export var movement_delta: int = 0
@export var range_delta: int = 0
## AP the caster gains when the spell resolves (e.g. Mana Surge).
@export var ap_gain: int = 0
## Status granted to the target piece (Piece spells), e.g. Overcharged.
@export_enum("None", "Frozen", "Overcharged") var grant_status: int = StatusEffectType.NONE

## Piece (classic), Tile (single tile) or Area (AreaShape around the clicked tile).
@export_group("Spell Targeting")
@export_enum("Piece", "Tile", "Area") var spell_target: int = SpellTargetType.PIECE
@export_enum("Single", "Plus", "Row3", "Column3", "Square2") var area_shape: int = AreaShape.SINGLE
## Tile effect placed on every tile of the area (None = no tile effect).
@export_enum("None", "Lava", "Wall", "Healing", "Rubble", "Ice", "Storm", "Mud") var tile_effect: int = TileEffectType.NONE
## Duration in global turns (2 = until the end of the caster's next turn, like piece spells).
@export var tile_effect_duration: int = 2
## Immediate damage to every ENEMY piece in the area.
@export var spell_damage: int = 0
## Immediate heal to every FRIENDLY piece in the area.
@export var spell_heal: int = 0
## Pushes every piece in the area 1 tile away from the anchor (the anchor's piece away from the caster).
@export var spell_push: bool = false

@export_group("Visuals")
@export var art: Texture2D
@export var tint: Color = Color.WHITE

## Building cards only (runtime, see BuildingInfo): which building this piece is.
var building: int = BuildingType.NONE


## Accepts the mechanically converted .tres key "class" (C# property Class) for class_.
func _set(property: StringName, value: Variant) -> bool:
	if property == &"class":
		class_ = int(value)
		return true
	return false


## True if the card has all given keyword flags.
func has_keyword(keyword: int) -> bool:
	return keyword != Keyword.NONE and (keywords & keyword) == keyword


## True for spells cast on a tile (Tile or Area) instead of a piece.
var targets_tile: bool:
	get:
		return card_type == CardType.SPELL and spell_target != SpellTargetType.PIECE

## Name without the Undying level suffix (e.g. "Bone Knight" for "Bone Knight +2").
var base_name: String:
	get:
		var suffix: String = " +%d" % level
		if level > 0 and name.ends_with(suffix):
			return name.substr(0, name.length() - suffix.length())
		return name


## Returns an upgraded copy for the Undying return: duplicate() with +1 attack, +1 hp, level + 1 and
## the name suffix " +level". The original resource is never modified.
func create_undying_upgrade() -> CardData:
	var p_base_name: String = base_name
	var copy: CardData = duplicate() as CardData
	if copy == null:
		copy = _copy_manually()
	copy.level = level + 1
	copy.attack = attack + 1
	copy.hp = hp + 1
	copy.name = "%s +%d" % [p_base_name, copy.level]
	return copy


func _copy_manually() -> CardData:
	var c := CardData.new()
	c.name = name
	c.description = description
	c.card_type = card_type
	c.role = role
	c.clan = clan
	c.rarity = rarity
	c.class_ = class_
	c.ap_cost = ap_cost
	c.movement = movement
	c.attack = attack
	c.hp = hp
	c.range = range
	c.shield = shield
	c.ap_bonus = ap_bonus
	c.keywords = keywords
	c.level = level
	c.legend = legend
	c.deathrattle = deathrattle
	c.deathrattle_amount = deathrattle_amount
	c.on_first_hit = on_first_hit
	c.on_first_hit_amount = on_first_hit_amount
	c.attack_delta = attack_delta
	c.hp_delta = hp_delta
	c.shield_delta = shield_delta
	c.movement_delta = movement_delta
	c.range_delta = range_delta
	c.ap_gain = ap_gain
	c.grant_status = grant_status
	c.spell_target = spell_target
	c.area_shape = area_shape
	c.tile_effect = tile_effect
	c.tile_effect_duration = tile_effect_duration
	c.spell_damage = spell_damage
	c.spell_heal = spell_heal
	c.spell_push = spell_push
	c.art = art
	c.tint = tint
	return c
