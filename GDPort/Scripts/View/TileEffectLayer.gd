class_name TileEffectLayer
extends Node3D
## Shows BoardState.tile_effects (lava, walls, healing runes) with duration badges. Created by BoardView
## as its child "TileEffects". sync diffs the shown visuals against a board and animates appear/expire;
## play_applied / play_expired animate single tiles while resolution events are played.

## Vector2i -> TileEffectVisual
var _visuals: Dictionary = {}
## Vector2i -> int
var _totals: Dictionary = {}
var _board: BoardView

## Global turn number used for the remaining-duration badges (TileEffect.remaining_turns).
var current_turn: int = 1

## Number of tiles currently showing an effect.
var count: int:
	get:
		return _visuals.size()


## Connects the layer to its board (for grid -> world conversion and tile size).
func setup(board: BoardView) -> void:
	_board = board


## The effect type currently shown on a tile (NONE if nothing).
func get_shown_type(pos: Vector2i) -> int:
	if _visuals.has(pos) and is_instance_valid(_visuals[pos]):
		return (_visuals[pos] as TileEffectVisual).type
	return TileEffectType.NONE


## Makes the shown effects match the board: new effects appear (animated if requested), effects that
## are gone vanish, replaced types swap, and duration badges are refreshed. current_turn_value < 0 keeps current_turn.
func sync(board: BoardState, current_turn_value: int = -1, animate: bool = true) -> void:
	if board == null:
		return
	if current_turn_value >= 0:
		current_turn = current_turn_value
	var seen: Dictionary = {}
	var effects: Dictionary = board.tile_effects
	for key: Vector2i in effects.keys():
		var effect: TileEffect = effects[key]
		if effect == null or effect.type == TileEffectType.NONE:
			continue
		seen[key] = true
		if _visuals.has(key) and is_instance_valid(_visuals[key]) and (_visuals[key] as TileEffectVisual).type == effect.type:
			var existing: TileEffectVisual = _visuals[key]
			if existing.expiry_turn != effect.expiry_turn:
				_totals[key] = effect.remaining_turns(current_turn)
				existing.pulse()
			existing.expiry_turn = effect.expiry_turn
			_update_badge(key, existing)
			continue
		_show_effect(key, effect.type, effect.expiry_turn, animate)
	var stale: Array[Vector2i] = []
	for pos: Vector2i in _visuals.keys():
		if not seen.has(pos):
			stale.append(pos)
	for pos in stale:
		_hide_effect(pos, animate)


## Animates an effect appearing on a tile (replacing any other shown there). Completes when formed.
func play_applied(pos: Vector2i, type: int, expiry_turn: int) -> void:
	await _show_effect(pos, type, expiry_turn, true)


## Animates the effect on a tile disappearing. Completes when it is gone.
func play_expired(pos: Vector2i) -> void:
	await _hide_effect(pos, true)


## "Rewinds" the shown effects to the state before a list of events (in case the view was synced to the
## final state already): tiles whose first event is TILE_EFFECT_APPLIED are hidden, tiles whose first event
## is TILE_EFFECT_EXPIRED are shown, so that playing the events animates them correctly.
func prepare_for_events(events: Array) -> void:
	if events == null:
		return
	var handled: Dictionary = {}
	for e: ResolutionEvent in events:
		if e.type != ResolutionEventType.TILE_EFFECT_APPLIED and e.type != ResolutionEventType.TILE_EFFECT_EXPIRED:
			continue
		if handled.has(e.to):
			continue
		handled[e.to] = true
		if e.type == ResolutionEventType.TILE_EFFECT_APPLIED:
			if _visuals.has(e.to) and is_instance_valid(_visuals[e.to]):
				var v: TileEffectVisual = _visuals[e.to]
				if v.type == e.tile_effect and v.expiry_turn == e.expiry_turn:
					_visuals.erase(e.to)
					v.queue_free()
		elif get_shown_type(e.to) == TileEffectType.NONE and e.tile_effect != TileEffectType.NONE:
			_show_effect(e.to, e.tile_effect, -1, false)


## Removes all visuals immediately.
func clear_all() -> void:
	for v in _visuals.values():
		if is_instance_valid(v):
			(v as TileEffectVisual).queue_free()
	_visuals.clear()
	_totals.clear()


func _show_effect(pos: Vector2i, type: int, expiry_turn: int, animate: bool) -> void:
	if type == TileEffectType.NONE:
		await _hide_effect(pos, animate)
		return
	if _visuals.has(pos) and is_instance_valid(_visuals[pos]):
		var old: TileEffectVisual = _visuals[pos]
		if old.type == type:
			old.expiry_turn = expiry_turn
			_totals[pos] = _remaining(expiry_turn)
			_update_badge(pos, old)
			old.pulse()
			return
		_visuals.erase(pos)
		old.play_vanish()
	var visual := TileEffectVisual.new()
	visual.setup(type, _board.tile_size if _board != null else 1.0, false, pos.x * 1.37 + pos.y * 2.11)
	visual.expiry_turn = expiry_turn
	add_child(visual)
	visual.global_position = _board.grid_to_world(pos) if _board != null else Vector3(pos.x, 0.0, pos.y)
	_visuals[pos] = visual
	_totals[pos] = _remaining(expiry_turn)
	_update_badge(pos, visual)
	if animate:
		await visual.play_appear()
	else:
		visual.show_instant()


func _hide_effect(pos: Vector2i, animate: bool) -> void:
	if not _visuals.has(pos):
		return
	var v: Variant = _visuals[pos]
	_visuals.erase(pos)
	_totals.erase(pos)
	if not is_instance_valid(v):
		return
	if animate:
		await (v as TileEffectVisual).play_vanish()
	else:
		(v as TileEffectVisual).queue_free()


func _remaining(expiry_turn: int) -> int:
	if expiry_turn < 0 or expiry_turn >= TileEffect.PERMANENT:
		return 0
	return maxi(0, expiry_turn - current_turn + 1)


func _update_badge(pos: Vector2i, v: TileEffectVisual) -> void:
	var remaining: int = _remaining(v.expiry_turn)
	var total: int = _totals.get(pos, 0)
	v.set_remaining(remaining, maxi(total, remaining))
