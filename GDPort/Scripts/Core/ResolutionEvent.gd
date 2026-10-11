class_name ResolutionEvent
extends RefCounted
## One step of turn resolution, in chronological order, for views to animate.
## C# object initializers map to: var e := ResolutionEvent.new(); e.type = ...; e.piece_id = ...

## ResolutionEventType value.
var type: int = ResolutionEventType.MOVED
## The acting or affected piece (see ResolutionEventType for meaning).
var piece_id: int = -1
## The other involved piece, or -1.
var other_piece_id: int = -1
var from: Vector2i = Vector2i.ZERO
var to: Vector2i = Vector2i.ZERO
var is_chain: bool = false
## Attacked: this shot is the extra hit of a Pierce attack.
var is_pierce: bool = false
var amount: int = 0
var shield_absorbed: int = 0
var hp_lost: int = 0
var remaining_hp: int = 0
var remaining_shield: int = 0
var spell_name: String = ""
## Card name (ReturnedToDeck, TileEffectApplied source, SpellCast).
var card_name: String = ""
## Player concerned (ReturnedToDeck, SpellCast), or -1.
var player_index: int = -1
## TileEffectType value.
var tile_effect: int = TileEffectType.NONE
## StatusEffectType value.
var status: int = StatusEffectType.NONE
## TileEffectApplied / StatusApplied: last turn (inclusive) in which the effect is active.
var expiry_turn: int = 0
## Moved: walked tiles excluding from (ends with to), an Array of Vector2i. null for other events.
var path: Variant = null


func _to_string() -> String:
	match type:
		ResolutionEventType.MOVED:
			return "Moved #%d %s->%s" % [piece_id, str(from), str(to)]
		ResolutionEventType.MOVE_BLOCKED:
			return "MoveBlocked #%d %s->%s" % [piece_id, str(from), str(to)]
		ResolutionEventType.ATTACKED:
			return "Attacked #%d %s->%s target #%d%s%s" % [piece_id, str(from), str(to), other_piece_id,
				" (chain)" if is_chain else "", " (pierce)" if is_pierce else ""]
		ResolutionEventType.ATTACK_CANCELLED:
			return "AttackCancelled #%d ->%s" % [piece_id, str(to)]
		ResolutionEventType.DAMAGED:
			return "Damaged #%d by #%d: %d (shield %d, hp %d) -> HP %d SHD %d" % [piece_id, other_piece_id, amount,
				shield_absorbed, hp_lost, remaining_hp, remaining_shield]
		ResolutionEventType.DIED:
			return "Died #%d at %s" % [piece_id, str(from)]
		ResolutionEventType.CHAIN_TRIGGERED:
			return "ChainTriggered #%d -> #%d" % [other_piece_id, piece_id]
		ResolutionEventType.SPELL_EXPIRED:
			return "SpellExpired '%s' on #%d" % [spell_name, piece_id]
		ResolutionEventType.PUSHED:
			return "Pushed #%d %s->%s by #%d" % [piece_id, str(from), str(to), other_piece_id]
		ResolutionEventType.PUSH_BLOCKED:
			return "PushBlocked #%d %s->%s by #%d" % [piece_id, str(from), str(to), other_piece_id]
		ResolutionEventType.HEALED:
			return "Healed #%d by #%d: +%d -> HP %d" % [piece_id, other_piece_id, amount, remaining_hp]
		ResolutionEventType.RETURNED_TO_DECK:
			return "ReturnedToDeck #%d '%s' -> P%d deck (level %d)" % [piece_id, card_name, player_index, amount]
		ResolutionEventType.TILE_EFFECT_APPLIED:
			return "TileEffectApplied %s at %s for %d turns" % [TileEffectType.name_of(tile_effect), str(to), amount]
		ResolutionEventType.TILE_EFFECT_EXPIRED:
			return "TileEffectExpired %s at %s" % [TileEffectType.name_of(tile_effect), str(to)]
		ResolutionEventType.TILE_DAMAGE:
			return "TileDamage %s at %s -> #%d %d" % [TileEffectType.name_of(tile_effect), str(to), piece_id, amount]
		ResolutionEventType.TILE_HEAL:
			return "TileHeal at %s -> #%d +%d (HP %d)" % [str(to), piece_id, amount, remaining_hp]
		ResolutionEventType.STATUS_APPLIED:
			return "StatusApplied %s on #%d" % [StatusEffectType.name_of(status), piece_id]
		ResolutionEventType.STATUS_EXPIRED:
			return "StatusExpired %s on #%d%s" % [StatusEffectType.name_of(status), piece_id, " (consumed)" if is_chain else ""]
		ResolutionEventType.SPELL_CAST:
			return "SpellCast '%s' by P%d at %s" % [card_name, player_index, str(to)]
	return ResolutionEventType.name_of(type)
