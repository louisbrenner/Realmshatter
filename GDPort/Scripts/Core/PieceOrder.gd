class_name PieceOrder
extends RefCounted
## Planned action of a piece for this turn. move_target is a destination tile (null = stay).
## attack_target is a TILE (null = no attack): whatever stands there at resolution time is hit.
## order_index is the global sequence number; orders resolve in ascending order_index.

## Vector2i or null.
var move_target: Variant = null
## Vector2i or null.
var attack_target: Variant = null
var order_index: int = 0
## AP paid when this order was created (refunded if the order is cleared during the turn).
var ap_paid: int = 0


func _init(p_move_target: Variant = null, p_attack_target: Variant = null, p_order_index: int = 0) -> void:
	move_target = p_move_target
	attack_target = p_attack_target
	order_index = p_order_index
