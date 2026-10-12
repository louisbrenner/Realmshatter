class_name Trap
extends RefCounted
## A hidden trap on one tile. Only its owner sees it; an enemy piece that steps onto the tile is stopped there and
## the trap springs (OrderResolver.trigger_trap), then it is gone.

var position: Vector2i = Vector2i.ZERO
var owner_index: int = 0
## TrapType value.
var type: int = TrapType.SPIKE
## The Trapper that set it (-1 if unknown); a trap kill counts as its kill (e.g. for Plunder).
var source_piece_id: int = -1
## Order of placement (older traps are replaced first when a Trapper sets one too many).
var serial: int = 0


func _init(p_position: Vector2i = Vector2i.ZERO, p_owner_index: int = 0, p_type: int = TrapType.SPIKE,
		p_source_piece_id: int = -1, p_serial: int = 0) -> void:
	position = p_position
	owner_index = p_owner_index
	type = p_type
	source_piece_id = p_source_piece_id
	serial = p_serial


func _to_string() -> String:
	return "%s of P%d at %s" % [TrapInfo.display_name(type), owner_index, str(position)]
