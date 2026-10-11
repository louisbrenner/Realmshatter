class_name StatusMarkerLayer
extends Node3D
## Floating status icons above pieces (Frozen = snowflake on an ice coin plus a frost ring on the ground,
## Overcharged = crackling bolt on a violet coin). Independent of PieceView: markers follow the piece views
## returned by view_resolver every frame (so they ride along with move animations) and fall back to the
## piece's tile. BoardAnimator creates one automatically (BoardAnimator.status_markers) and syncs it in sync_all.

class Marker:
	var root: Node3D
	var icon_row: Node3D
	var frost_ring: MeshInstance3D
	## StatusEffectType (int) -> Node3D (untyped values so freed icons can be checked safely).
	var icons: Dictionary = {}
	var fallback: Vector3 = Vector3.ZERO
	var phase: float = 0.0

const FROZEN_FG := Color(0.9, 0.97, 1.0)
const FROZEN_BG := Color(0.2, 0.5, 0.85, 0.95)
const CHARGE_FG := Color(1.0, 0.95, 0.55)
const CHARGE_BG := Color(0.42, 0.22, 0.75, 0.95)

## piece id (int) -> Marker
var _markers: Dictionary = {}
var _time: float = 0.0

## Returns the node (usually the PieceView) a piece's marker follows, or null. Signature: func(piece_id: int) -> Node3D.
var view_resolver: Callable = Callable()

## Height of the icon row above the piece origin.
@export var icon_height: float = 0.5

## Offset of the icon row toward the far (-Z) edge of the tile, so it does not cover the portrait in 2D.
@export var icon_back_offset: float = 0.44

@export var icon_size: float = 0.3


## Shows exactly the statuses of the living pieces in the state (pops new icons in, fades removed ones).
func sync(state: GameState, board: BoardView) -> void:
	if state == null:
		return
	var alive: Dictionary = {}
	for piece: Piece in state.pieces:
		alive[piece.id] = true
		var fallback: Vector3 = board.grid_to_world(piece.position) if board != null else Vector3(piece.position.x, 0.0, piece.position.y)
		for type: int in [StatusEffectType.FROZEN, StatusEffectType.OVERCHARGED]:
			set_status(piece.id, type, piece.has_status(type), fallback, true)
		if _markers.has(piece.id):
			var m: Marker = _markers[piece.id]
			m.fallback = fallback
	var stale: Array[int] = []
	for id: int in _markers.keys():
		if not alive.has(id):
			stale.append(id)
	for id in stale:
		remove_piece(id)


## Adds or removes one status icon for a piece (used while events are played).
## fallback_world: Vector3 or null.
func set_status(piece_id: int, type: int, active: bool, fallback_world: Variant = null, animate: bool = true) -> void:
	if type == StatusEffectType.NONE:
		return
	var marker: Marker = _markers.get(piece_id) as Marker
	if active:
		if marker == null:
			marker = _create_marker(piece_id, fallback_world if fallback_world != null else Vector3.ZERO)
		if fallback_world != null:
			marker.fallback = fallback_world
		if marker.icons.has(type):
			return
		var icon: Node3D = _create_icon(type)
		marker.icon_row.add_child(icon)
		marker.icons[type] = icon
		if type == StatusEffectType.FROZEN:
			marker.frost_ring.visible = true
			if animate:
				marker.frost_ring.scale = Vector3.ONE * 0.2
				marker.frost_ring.create_tween().tween_property(marker.frost_ring, "scale", Vector3.ONE, 0.3) \
					.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if animate:
			icon.scale = Vector3.ONE * 0.1
			var t: Tween = icon.create_tween()
			t.tween_property(icon, "scale", Vector3.ONE * 1.3, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			t.tween_property(icon, "scale", Vector3.ONE, 0.12)
		_layout(marker)
	elif marker != null and marker.icons.has(type):
		var icon = marker.icons[type]
		marker.icons.erase(type)
		if type == StatusEffectType.FROZEN:
			marker.frost_ring.visible = false
		if animate and is_instance_valid(icon):
			var t: Tween = icon.create_tween()
			t.tween_property(icon, "scale", Vector3.ONE * 1.4, 0.08)
			t.tween_property(icon, "scale", Vector3.ONE * 0.01, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			t.tween_callback(icon.queue_free)
		elif is_instance_valid(icon):
			icon.queue_free()
		_layout(marker)


## True if the piece currently shows the status icon.
func has_status(piece_id: int, type: int) -> bool:
	if not _markers.has(piece_id):
		return false
	var m: Marker = _markers[piece_id]
	return m.icons.has(type)


## "Rewinds" icons to the state before a list of events: pieces whose first event for a status is
## STATUS_APPLIED lose that icon, STATUS_EXPIRED gets it back, so playing the events animates them.
func prepare_for_events(events: Array) -> void:
	if events == null:
		return
	var handled: Dictionary = {}
	for e: ResolutionEvent in events:
		if e.type != ResolutionEventType.STATUS_APPLIED and e.type != ResolutionEventType.STATUS_EXPIRED:
			continue
		var key := Vector2i(e.piece_id, e.status)
		if handled.has(key):
			continue
		handled[key] = true
		set_status(e.piece_id, e.status, e.type == ResolutionEventType.STATUS_EXPIRED, null, false)


## Removes all icons of a piece immediately.
func remove_piece(piece_id: int) -> void:
	if _markers.has(piece_id):
		var m: Marker = _markers[piece_id]
		_markers.erase(piece_id)
		if is_instance_valid(m.root):
			m.root.queue_free()


## Removes every marker.
func clear_all() -> void:
	for m: Marker in _markers.values():
		if is_instance_valid(m.root):
			m.root.queue_free()
	_markers.clear()


func _process(delta: float) -> void:
	_time += delta
	for id: int in _markers:
		var m: Marker = _markers[id]
		if not is_instance_valid(m.root):
			continue
		var view = null
		if view_resolver.is_valid():
			view = view_resolver.call(id)
		var base_pos: Vector3 = view.global_position if (view != null and is_instance_valid(view)) else m.fallback
		m.root.global_position = base_pos
		var any: bool = m.icons.size() > 0
		m.root.visible = any
		var bob: float = sin(_time * 2.4 + m.phase) * 0.03
		m.icon_row.position = Vector3(0.0, icon_height + bob, -icon_back_offset)
		if m.frost_ring.visible:
			m.frost_ring.rotation = Vector3(0.0, _time * 0.25 + m.phase, 0.0)


func _create_marker(piece_id: int, fallback: Vector3) -> Marker:
	var root := Node3D.new()
	root.name = "Status_%d" % piece_id
	add_child(root)
	root.global_position = fallback
	var row := Node3D.new()
	row.name = "Icons"
	row.position = Vector3(0.0, icon_height, -icon_back_offset)
	root.add_child(row)
	var ring: MeshInstance3D = VfxAssets.create_icon(FxIconShape.FROST_RING, 1.0, Color(0.6, 0.88, 1.0, 0.55), Color(0, 0, 0, 0), false, 3)
	var ring_mat := ring.material_override as ShaderMaterial
	ring_mat.set_shader_parameter("billboard", false)
	ring_mat.set_shader_parameter("energy", 1.1)
	var ring_mesh := PlaneMesh.new()
	ring_mesh.size = Vector2(1.18, 1.18)
	ring.mesh = ring_mesh
	ring.position = Vector3(0.0, 0.025, -0.03)
	ring.visible = false
	root.add_child(ring)
	var marker := Marker.new()
	marker.root = root
	marker.icon_row = row
	marker.frost_ring = ring
	marker.fallback = fallback
	marker.phase = piece_id * 1.7
	_markers[piece_id] = marker
	return marker


func _create_icon(type: int) -> Node3D:
	var holder := Node3D.new()
	holder.name = StatusEffectType.name_of(type)
	var frozen: bool = type == StatusEffectType.FROZEN
	var icon: MeshInstance3D = VfxAssets.create_icon(FxIconShape.SNOWFLAKE if frozen else FxIconShape.BOLT, icon_size,
		FROZEN_FG if frozen else CHARGE_FG, FROZEN_BG if frozen else CHARGE_BG, true, 31)
	var mat := icon.material_override as ShaderMaterial
	mat.set_shader_parameter("energy", 1.2 if frozen else 1.6)
	if frozen:
		mat.set_shader_parameter("spin", 0.4)
	holder.add_child(icon)
	var glow := MeshInstance3D.new()
	glow.mesh = VfxAssets.glow_quad
	glow.scale = Vector3.ONE * icon_size * 1.7
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.set_instance_shader_parameter("tint", Color(0.4, 0.75, 1.0, 0.55) if frozen else Color(0.75, 0.55, 1.0, 0.6))
	holder.add_child(glow)
	return holder


func _layout(m: Marker) -> void:
	var n: int = m.icons.size()
	var i: int = 0
	for type: int in [StatusEffectType.FROZEN, StatusEffectType.OVERCHARGED]:
		if not m.icons.has(type):
			continue
		var icon = m.icons[type]
		var x: float = (i - (n - 1) * 0.5) * icon_size * 1.05
		icon.position = Vector3(x, 0.0, 0.0)
		i += 1
