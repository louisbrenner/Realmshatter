class_name PieceStats
extends RefCounted
## Plain stat block of a piece (base or effective values). Value type in C#: use copy() where needed.

var movement: int
var attack: int
var hp: int
var range: int
var shield: int


func _init(p_movement: int = 0, p_attack: int = 0, p_hp: int = 0, p_range: int = 0, p_shield: int = 0) -> void:
	movement = p_movement
	attack = p_attack
	hp = p_hp
	range = p_range
	shield = p_shield


## Reads the unit stat block of a card.
static func from_card(card: CardData) -> PieceStats:
	return PieceStats.new(card.movement, card.attack, card.hp, card.range, card.shield)


## Value copy (C# struct semantics).
func copy() -> PieceStats:
	return PieceStats.new(movement, attack, hp, range, shield)


func _to_string() -> String:
	return "MOV %d ATK %d HP %d RNG %d SHD %d" % [movement, attack, hp, range, shield]
