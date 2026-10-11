class_name CardData
extends Resource
## Definition of a card. Unit cards use the stat block (movement..shield, ap_bonus);
## spell cards use the *_delta modifiers, which are applied to the target piece.
## ap_cost <= 0 means "use the default from GameConfig" (unit_ap_cost = 1, spell_ap_cost = 2).

@export_group("General")
@export var name: String = ""
@export_multiline var description: String = ""
@export_enum("Unit", "Spell") var card_type: int = CardType.UNIT
@export_enum("Attack", "Utility", "Resource") var role: int = UnitRole.ATTACK
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
@export_flags("Burning", "Frost", "Push", "Pierce", "Mending", "Conduit", "Echo", "Undying") var keywords: int = Keyword.NONE
## Undying upgrade level (0 = original card; each Undying death returns a copy with level + 1).
@export var level: int = 0

@export_group("Spell Modifiers")
@export var attack_delta: int = 0
@export var hp_delta: int = 0
@export var shield_delta: int = 0
@export var movement_delta: int = 0
@export var range_delta: int = 0
## Status granted to the target piece (Piece spells), e.g. Overcharged.
@export_enum("None", "Frozen", "Overcharged") var grant_status: int = StatusEffectType.NONE

## Piece (classic), Tile (single tile) or Area (AreaShape around the clicked tile).
@export_group("Spell Targeting")
@export_enum("Piece", "Tile", "Area") var spell_target: int = SpellTargetType.PIECE
@export_enum("Single", "Plus", "Row3", "Column3", "Square2") var area_shape: int = AreaShape.SINGLE
## Tile effect placed on every tile of the area (None = no tile effect).
@export_enum("None", "Lava", "Wall", "Healing") var tile_effect: int = TileEffectType.NONE
## Duration in global turns (2 = until the end of the caster's next turn, like piece spells).
@export var tile_effect_duration: int = 2
## Immediate damage to every ENEMY piece in the area.
@export var spell_damage: int = 0
## Immediate heal to every FRIENDLY piece in the area.
@export var spell_heal: int = 0

@export_group("Visuals")
@export var art: Texture2D
@export var tint: Color = Color.WHITE

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


## True if the card has all given keyword flags.
func has_keyword(keyword: int) -> bool:
	return keyword != Keyword.NONE and (keywords & keyword) == keyword


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
	c.ap_cost = ap_cost
	c.movement = movement
	c.attack = attack
	c.hp = hp
	c.range = range
	c.shield = shield
	c.ap_bonus = ap_bonus
	c.keywords = keywords
	c.level = level
	c.attack_delta = attack_delta
	c.hp_delta = hp_delta
	c.shield_delta = shield_delta
	c.movement_delta = movement_delta
	c.range_delta = range_delta
	c.grant_status = grant_status
	c.spell_target = spell_target
	c.area_shape = area_shape
	c.tile_effect = tile_effect
	c.tile_effect_duration = tile_effect_duration
	c.spell_damage = spell_damage
	c.spell_heal = spell_heal
	c.art = art
	c.tint = tint
	return c
