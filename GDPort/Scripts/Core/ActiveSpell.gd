class_name ActiveSpell
extends RefCounted
## A spell currently affecting a piece. It expires at the END of turn expiry_turn
## (= cast turn + 2, i.e. the end of the caster's next turn).
## remaining_shield is a temporary shield granted by the spell; it absorbs damage
## before the piece's own shield and vanishes on expiry.

var source: CardData
var effect: SpellEffect
var caster_index: int
var cast_turn: int
var expiry_turn: int
var remaining_shield: int


func _init(p_source: CardData = null, p_effect: SpellEffect = null, p_caster_index: int = 0, p_cast_turn: int = 0, p_expiry_turn: int = 0) -> void:
	source = p_source
	effect = p_effect if p_effect != null else SpellEffect.new()
	caster_index = p_caster_index
	cast_turn = p_cast_turn
	expiry_turn = p_expiry_turn
	remaining_shield = effect.shield_delta if effect.shield_delta > 0 else 0
