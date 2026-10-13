class_name TileEffect
extends RefCounted
## A map effect on one tile. It expires at the END of turn expiry_turn (like spells): an effect created in
## turn T with duration D has expiry_turn = T + D - 1, so it lasts D turns counting its creation turn (an even D
## gives both players the same number of turns with it; D = 4 ends after the opponent's second turn).

## expiry_turn of map effects that never expire (lava fields and springs of the map generator).
## C# int.MaxValue / 4.
const PERMANENT: int = 2147483647 / 4

## True for map effects that never expire.
var is_permanent: bool:
	get:
		return expiry_turn >= PERMANENT

## TileEffectType value.
var type: int = TileEffectType.NONE
var position: Vector2i = Vector2i.ZERO
## Player who created the effect (-1 = neutral).
var creator_index: int = -1
var created_turn: int = 0
var expiry_turn: int = 0
## Name of the card that created the effect (spell or Burning unit), for tooltips.
var source_name: String = ""


func _init(p_type: int = TileEffectType.NONE, p_position: Vector2i = Vector2i.ZERO, p_creator_index: int = -1,
		p_created_turn: int = 0, p_expiry_turn: int = 0, p_source_name: String = "") -> void:
	type = p_type
	position = p_position
	creator_index = p_creator_index
	created_turn = p_created_turn
	expiry_turn = p_expiry_turn
	source_name = p_source_name


## Number of turn ends (including the current turn's end) until the effect is gone.
func remaining_turns(current_turn: int) -> int:
	return maxi(0, expiry_turn - current_turn + 1)


func _to_string() -> String:
	return "%s at %s (until end of turn %d)" % [TileEffectType.name_of(type), str(position), expiry_turn]
