class_name AiAction
extends RefCounted
## One step the AI already executed through the TurnController (for logging / animation).
## Field usage per kind:
## Draft: card = chosen card.
## PlayUnit: card, piece_id = new piece, target = deploy tile.
## PlaySpell: card, piece_id = target piece (-1 for tile/area spells), target = target piece position / anchor tile.
## ConvertVp: no extra fields (1 VP became 1 AP).
## Command: piece_id = commanded piece, move_target / attack_target as executed, target = attack_target ?? move_target.

var kind: int = AiActionKind.DRAFT
var player_index: int = 0
var card: CardData = null
var piece_id: int = -1
## Vector2i or null.
var target: Variant = null
## Vector2i or null.
var move_target: Variant = null
## Vector2i or null.
var attack_target: Variant = null
var description: String = ""


func _to_string() -> String:
	return "[P%d %s] %s" % [player_index, AiActionKind.name_of(kind), description]
