class_name PredictedHit
extends RefCounted
## One hit inside a ChainPreview (main attack, pierce hit, Arc zap or Echo strike).
## C# object initializers map to: var h := PredictedHit.new(); h.attacker_id = ...

## Piece that fired this shot.
var attacker_id: int = -1
var from: Vector2i = Vector2i.ZERO
## Tile that was hit.
var tile: Vector2i = Vector2i.ZERO
## Piece on the tile at hit time, or -1 (miss).
var target_piece_id: int = -1
## True if the target belongs to the attacker's owner.
var is_friendly: bool = false
## Arc zap or Echo strike.
var is_secondary: bool = false
var is_pierce: bool = false

## Incoming damage (before shields). 0 for Mending heals.
var damage: int = 0
var shield_absorbed: int = 0
var hp_lost: int = 0
var healed: int = 0
var kills: bool = false
## Destination of a knockback (Push), if any: Vector2i or null.
var pushed_to: Variant = null
## HitEffect flags.
var effects: int = HitEffect.NONE


func _to_string() -> String:
	return "#%d -> %s (#%d%s%s%s): " % [attacker_id, str(tile), target_piece_id,
		" friendly" if is_friendly else "", ", secondary" if is_secondary else "", ", pierce" if is_pierce else ""] \
		+ "dmg %d, hp -%d%s%s, %s" % [damage, hp_lost, ", kill" if kills else "",
		(", heal %d" % healed) if healed > 0 else "", HitEffect.name_of(effects)]
