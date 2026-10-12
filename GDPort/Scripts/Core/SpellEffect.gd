class_name SpellEffect
extends RefCounted
## Stat modifiers applied by a spell. Values may be negative (debuffs). Value type in C#: use copy() where needed.

var attack_delta: int = 0
var hp_delta: int = 0
var shield_delta: int = 0
var movement_delta: int = 0
var range_delta: int = 0


func _init(p_attack_delta: int = 0, p_hp_delta: int = 0, p_shield_delta: int = 0, p_movement_delta: int = 0,
		p_range_delta: int = 0) -> void:
	attack_delta = p_attack_delta
	hp_delta = p_hp_delta
	shield_delta = p_shield_delta
	movement_delta = p_movement_delta
	range_delta = p_range_delta


## Reads the spell modifiers of a card. With power != 0 each is pushed 'power' further in its direction
## (Obelisk: +2 Attack -> +3, -1 -> -2). Merges both C# FromCard overloads (power 0 = plain read).
static func from_card(card: CardData, power: int = 0) -> SpellEffect:
	if power == 0:
		return SpellEffect.new(card.attack_delta, card.hp_delta, card.shield_delta, card.movement_delta, card.range_delta)
	return SpellEffect.new(boost(card.attack_delta, power), boost(card.hp_delta, power), boost(card.shield_delta, power),
		boost(card.movement_delta, power), boost(card.range_delta, power))


## Moves a non-zero value 'power' further away from zero (zero stays zero).
static func boost(value: int, power: int) -> int:
	return value + power if value > 0 else (value - power if value < 0 else 0)


## Value copy (C# struct semantics).
func copy() -> SpellEffect:
	return SpellEffect.new(attack_delta, hp_delta, shield_delta, movement_delta, range_delta)
