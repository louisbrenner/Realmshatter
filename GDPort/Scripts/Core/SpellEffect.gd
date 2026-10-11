class_name SpellEffect
extends RefCounted
## Stat modifiers applied by a spell. Values may be negative (debuffs). Value type in C#: use copy() where needed.

var attack_delta: int = 0
var hp_delta: int = 0
var shield_delta: int = 0
var movement_delta: int = 0
var range_delta: int = 0


## Reads the spell modifiers of a card.
static func from_card(card: CardData) -> SpellEffect:
	var e := SpellEffect.new()
	e.attack_delta = card.attack_delta
	e.hp_delta = card.hp_delta
	e.shield_delta = card.shield_delta
	e.movement_delta = card.movement_delta
	e.range_delta = card.range_delta
	return e


## Value copy (C# struct semantics).
func copy() -> SpellEffect:
	var e := SpellEffect.new()
	e.attack_delta = attack_delta
	e.hp_delta = hp_delta
	e.shield_delta = shield_delta
	e.movement_delta = movement_delta
	e.range_delta = range_delta
	return e
