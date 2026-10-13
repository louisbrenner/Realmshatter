class_name ChainPreview
extends RefCounted
## Result of TurnController.predict_attack: what ONE attack would cause on the CURRENT board (friendly fire,
## keywords, kills). Computed on a cloned state; the real state is never modified.
## Piece ids refer to the real pieces.

var attacker_id: int = -1
var from: Vector2i = Vector2i.ZERO
var target: Vector2i = Vector2i.ZERO
## False if the attack is not possible (invalid piece, out of range...). Lists are then empty.
var is_valid: bool = false

## The raw events the attack would produce (same format as resolution events).
var events: Array[ResolutionEvent] = []
## Every hit in chronological order.
var hits: Array[PredictedHit] = []
## Pieces that would die.
var killed_piece_ids: Array[int] = []
## Tile effects the attack would create (e.g. Lava from Burning).
var new_tile_effects: Array[TileEffect] = []

## Total HP lost by enemy pieces.
var enemy_hp_lost: int = 0
## Total incoming damage to enemy pieces (including shield-absorbed).
var enemy_damage: int = 0
var enemy_kills: int = 0
var friendly_healed: int = 0
## Total HP the attacker's own pieces would lose (friendly fire).
var friendly_hp_lost: int = 0
var friendly_kills: int = 0


## Builds the summary lists from the events of a simulated attack. 'owners' maps piece id -> owner index.
static func from_events(p_attacker_id: int, p_from: Vector2i, p_target: Vector2i, attacker_owner: int,
		owners: Dictionary, p_events: Array) -> ChainPreview:
	var preview := ChainPreview.new()
	preview.attacker_id = p_attacker_id
	preview.from = p_from
	preview.target = p_target
	preview.is_valid = true
	for e: ResolutionEvent in p_events:
		preview.events.append(e)
	var current: PredictedHit = null
	for e: ResolutionEvent in p_events:
		match e.type:
			ResolutionEventType.ATTACKED:
				var friendly: bool = e.other_piece_id >= 0 and owners.has(e.other_piece_id) \
					and int(owners[e.other_piece_id]) == attacker_owner
				current = PredictedHit.new()
				current.attacker_id = e.piece_id
				current.from = e.from
				current.tile = e.to
				current.target_piece_id = e.other_piece_id
				current.is_friendly = friendly
				current.is_secondary = e.is_secondary
				current.is_pierce = e.is_pierce
				preview.hits.append(current)
			ResolutionEventType.DAMAGED:
				if current != null and e.piece_id == current.target_piece_id:
					current.damage += e.amount
					current.shield_absorbed += e.shield_absorbed
					current.hp_lost += e.hp_lost
				if not _is_owned_by(owners, e.piece_id, attacker_owner):
					preview.enemy_damage += e.amount
					preview.enemy_hp_lost += e.hp_lost
				else:
					preview.friendly_hp_lost += e.hp_lost
			ResolutionEventType.DIED:
				preview.killed_piece_ids.append(e.piece_id)
				if not _is_owned_by(owners, e.piece_id, attacker_owner):
					preview.enemy_kills += 1
				else:
					preview.friendly_kills += 1
				if current != null and e.piece_id == current.target_piece_id:
					current.kills = true
					current.effects |= HitEffect.KILLED
			ResolutionEventType.HEALED:
				preview.friendly_healed += e.amount
				if current != null:
					current.healed += e.amount
					current.effects |= HitEffect.HEALED
			ResolutionEventType.TILE_EFFECT_APPLIED:
				preview.new_tile_effects.append(TileEffect.new(e.tile_effect, e.to, attacker_owner,
					e.expiry_turn - e.amount + 1, e.expiry_turn, e.card_name))
				if current != null and e.tile_effect == TileEffectType.LAVA:
					current.effects |= HitEffect.LAVA
			ResolutionEventType.STATUS_APPLIED:
				if current != null and e.status == StatusEffectType.FROZEN:
					current.effects |= HitEffect.FROZEN
			ResolutionEventType.PUSHED:
				if current != null and e.piece_id == current.target_piece_id:
					current.pushed_to = e.to
					current.effects |= HitEffect.PUSHED
			ResolutionEventType.PUSH_BLOCKED:
				if current != null and e.piece_id == current.target_piece_id:
					current.effects |= HitEffect.PUSH_BLOCKED
	return preview


static func _is_owned_by(owners: Dictionary, piece_id: int, player: int) -> bool:
	return owners.has(piece_id) and int(owners[piece_id]) == player
