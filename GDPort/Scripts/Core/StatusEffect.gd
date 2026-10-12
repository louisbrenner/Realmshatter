class_name StatusEffect
extends RefCounted
## A temporary status on a piece. Expires at the END of turn expiry_turn (or earlier when consumed).

## StatusEffectType value.
var type: int = StatusEffectType.NONE
var applied_turn: int = 0
var expiry_turn: int = 0
## Name of the card that caused the status, for tooltips.
var source_name: String = ""


func _init(p_type: int = StatusEffectType.NONE, p_applied_turn: int = 0, p_expiry_turn: int = 0,
		p_source_name: String = "") -> void:
	type = p_type
	applied_turn = p_applied_turn
	expiry_turn = p_expiry_turn
	source_name = p_source_name


func _to_string() -> String:
	return "%s (until end of turn %d)" % [StatusEffectType.name_of(type), expiry_turn]
