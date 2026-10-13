class_name CameraRig
extends Node3D
## Camera rig for the three view modes. The rig sits at the board center; its child Camera3D
## is positioned around it. 2D = orthographic top-down, 2.5D = orthographic angled,
## 3D = perspective angled. Player 0 (board +Z side) is always at the bottom of the screen.
## Mode switches tween pitch, yaw, distance and ortho size / fov.

## Emitted when the view mode changes (value = ViewMode int).
signal view_mode_changed(mode: int)

@export_enum("TwoD", "TwoPointFiveD", "ThreeD") var initial_mode: int = ViewMode.THREE_D
## Board extent to fit in world units (X = width, Y = depth along Z).
@export var board_fit_size: Vector2 = Vector2(10, 8)
## Extra space around the board in world units.
@export var fit_margin: float = 0.55
## Height of pieces/labels to keep in view.
@export var content_height: float = 0.5
@export var tween_duration: float = 0.6

@export_group("Screen Insets")
## Resolution the HUD is designed for; insets are given in these pixels and scale like the HUD.
@export var inset_reference_size: Vector2 = Vector2(1152, 648)
## Screen space kept free for the HUD (reference pixels): left side panels.
@export var inset_left: float = 210.0
## Top bar + hint ribbon.
@export var inset_top: float = 74.0
## Right column (deck, End Turn).
@export var inset_right: float = 176.0
## Resting hand cards.
@export var inset_bottom: float = 104.0
## Lower bound of the HUD scale (must match Hud.min_scale).
@export var inset_min_scale: float = 0.7

@export_group("2D")
@export var ortho_distance: float = 30.0

@export_group("2.5D")
@export var iso_pitch_degrees: float = -50.0
@export var iso_yaw_degrees: float = 20.0

@export_group("3D")
@export var perspective_pitch_degrees: float = -66.0
@export var perspective_yaw_degrees: float = 0.0
@export var perspective_fov: float = 50.0


class CamPose:
	var pitch: float = 0.0
	var yaw: float = 0.0
	var distance: float = 0.0
	var size: float = 0.0
	var fov: float = 0.0
	var offset: Vector2 = Vector2.ZERO
	var orthogonal: bool = false

	func copy() -> CamPose:
		var p := CamPose.new()
		p.pitch = pitch
		p.yaw = yaw
		p.distance = distance
		p.size = size
		p.fov = fov
		p.offset = offset
		p.orthogonal = orthogonal
		return p


var _camera: Camera3D
var _tween: Tween
var _from: CamPose = CamPose.new()
var _to: CamPose = CamPose.new()
var _current: CamPose = CamPose.new()
var _switched_projection: bool = false
## Yaw change of the running tween (shortest way, except flips, which turn in a fixed direction).
var _yaw_delta: float = 0.0
## Direction of the next flip turn (+1 / -1), 0 = shortest way.
var _spin: int = 0
## True while the view is turned 180 degrees (the board seen from player 1's side, hotseat).
var flipped: bool = false
var _shake_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _shake_strength: float = 0.0
var _shake_duration: float = 0.0
var _shake_time: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO

## Currently active (or target, while tweening) view mode (ViewMode int).
var mode: int = ViewMode.TWO_D

## The rig's camera.
var camera: Camera3D:
	get:
		return _camera


func _ready() -> void:
	_camera = get_node("Camera3D") as Camera3D
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	set_mode(initial_mode, false)


func _exit_tree() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null and viewport.size_changed.is_connected(_on_viewport_size_changed):
		viewport.size_changed.disconnect(_on_viewport_size_changed)


## Switches to a view mode, optionally with a tween.
func set_mode(new_mode: int, animate: bool = true) -> void:
	if _camera == null:
		_camera = get_node("Camera3D") as Camera3D
	mode = new_mode
	var target: CamPose = _compute_pose(new_mode)

	if _tween != null and _tween.is_valid():
		_tween.kill()

	if not animate or tween_duration <= 0.0:
		_current = target
		_apply_pose(target)
	else:
		_from = _current.copy()
		_to = target
		_switched_projection = false
		_yaw_delta = angle_difference(_from.yaw, _to.yaw)
		if _spin != 0 and absf(_yaw_delta) > PI - 0.05:
			# Exactly opposite: turn the way PieceViews turn (BoardAnimator.set_flipped), not by rounding luck.
			_yaw_delta = _spin * absf(_yaw_delta)
		_tween = create_tween()
		_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_tween.tween_method(_blend, 0.0, 1.0, tween_duration)
	view_mode_changed.emit(new_mode)


## Shakes the camera for a moment (offset in world units along the screen axes, decaying).
## A stronger or longer running shake is not cut short by a weaker one.
func shake(strength: float, duration: float) -> void:
	if strength <= 0.0 or duration <= 0.0:
		return
	var remaining: float = _shake_strength * maxf(0.0, 1.0 - _shake_time / _shake_duration) if _shake_duration > 0.0 else 0.0
	_shake_strength = maxf(strength, remaining)
	_shake_duration = duration
	_shake_time = 0.0


func _process(delta: float) -> void:
	if _camera == null or _shake_duration <= 0.0:
		return
	_shake_time += delta
	if _shake_time >= _shake_duration:
		_shake_duration = 0.0
		_shake_offset = Vector2.ZERO
	else:
		var k: float = 1.0 - _shake_time / _shake_duration
		var s: float = _shake_strength * k * k
		_shake_offset = Vector2(_shake_rng.randf_range(-1.0, 1.0), _shake_rng.randf_range(-1.0, 1.0)) * s
	if _tween == null or not _tween.is_valid() or not _tween.is_running():
		_apply_pose(_current)


## Turns the view 180 degrees around the board (true = seen from player 1's side), keeping the mode.
func set_flipped(value: bool, animate: bool = true) -> void:
	if value == flipped:
		return
	flipped = value
	# Flipping turns counter-clockwise (+yaw), unflipping clockwise, like the piece tokens.
	_spin = 1 if value else -1
	set_mode(mode, animate)
	_spin = 0


## Advances 2D -> 2.5D -> 3D -> 2D and returns the new mode.
func cycle_mode() -> int:
	var next: int
	match mode:
		ViewMode.TWO_D:
			next = ViewMode.TWO_POINT_FIVE_D
		ViewMode.TWO_POINT_FIVE_D:
			next = ViewMode.THREE_D
		_:
			next = ViewMode.TWO_D
	set_mode(next, true)
	return next


func _on_viewport_size_changed() -> void:
	if _tween != null and _tween.is_valid() and _tween.is_running():
		_to = _compute_pose(mode)
		return
	_current = _compute_pose(mode)
	_apply_pose(_current)


func _blend(t: float) -> void:
	var pose := CamPose.new()
	pose.pitch = lerp_angle(_from.pitch, _to.pitch, t)
	pose.yaw = _from.yaw + _yaw_delta * t
	pose.distance = lerpf(_from.distance, _to.distance, t)
	pose.size = lerpf(_from.size, _to.size, t)
	pose.fov = lerpf(_from.fov, _to.fov, t)
	pose.offset = _from.offset.lerp(_to.offset, t)
	pose.orthogonal = _from.orthogonal
	if _from.orthogonal != _to.orthogonal and t >= 0.5:
		_switched_projection = true
	if _switched_projection or t >= 1.0:
		pose.orthogonal = _to.orthogonal
	_current = pose
	_apply_pose(pose)


func _apply_pose(pose: CamPose) -> void:
	var basis_value := Basis.from_euler(Vector3(pose.pitch, pose.yaw, 0.0))
	var forward: Vector3 = -basis_value.z
	var position_value: Vector3 = basis_value.x * (pose.offset.x + _shake_offset.x) \
			+ basis_value.y * (pose.offset.y + _shake_offset.y) - forward * pose.distance
	_camera.transform = Transform3D(basis_value, position_value)
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	if pose.orthogonal:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = maxf(0.1, pose.size)
	else:
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.fov = clampf(pose.fov, 1.0, 170.0)


func _compute_pose(view_mode: int) -> CamPose:
	var aspect: float = _get_aspect()
	var turn: float = PI if flipped else 0.0
	match view_mode:
		ViewMode.TWO_POINT_FIVE_D:
			return _compute_ortho_pose(deg_to_rad(iso_pitch_degrees), deg_to_rad(iso_yaw_degrees) + turn, aspect)
		ViewMode.THREE_D:
			return _compute_perspective_pose(deg_to_rad(perspective_pitch_degrees), deg_to_rad(perspective_yaw_degrees) + turn, aspect)
	return _compute_ortho_pose(deg_to_rad(-90.0), turn, aspect)


func _compute_ortho_pose(pitch: float, yaw: float, aspect: float) -> CamPose:
	var basis_value := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var max_y: float = -INF
	for corner in _get_fit_corners():
		var x: float = corner.dot(basis_value.x)
		var y: float = corner.dot(basis_value.y)
		min_x = minf(min_x, x)
		max_x = maxf(max_x, x)
		min_y = minf(min_y, y)
		max_y = maxf(max_y, y)
	var span_x: float = max_x - min_x
	var span_y: float = max_y - min_y
	var insets: Vector4 = _get_inset_fractions()
	var left: float = insets.x
	var top: float = insets.y
	var right: float = insets.z
	var bottom: float = insets.w
	var avail_x: float = maxf(0.2, 1.0 - left - right)
	var avail_y: float = maxf(0.2, 1.0 - top - bottom)
	var size_value: float = maxf(span_y / avail_y, span_x / (maxf(0.1, aspect) * avail_x))
	# Shift so the board is centered in the screen area left free by the HUD.
	var shift_x: float = (left - right) * 0.5 * size_value * aspect
	var shift_y: float = (bottom - top) * 0.5 * size_value
	var pose := CamPose.new()
	pose.pitch = pitch
	pose.yaw = yaw
	pose.distance = ortho_distance
	pose.size = size_value
	pose.fov = perspective_fov
	pose.offset = Vector2((min_x + max_x) * 0.5 - shift_x, (min_y + max_y) * 0.5 - shift_y)
	pose.orthogonal = true
	return pose


func _compute_perspective_pose(pitch: float, yaw: float, aspect: float) -> CamPose:
	var basis_value := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var forward: Vector3 = -basis_value.z
	var tan_v: float = tan(deg_to_rad(perspective_fov) * 0.5)
	var tan_h: float = tan_v * maxf(0.1, aspect)
	var insets: Vector4 = _get_inset_fractions()
	var left: float = insets.x
	var top: float = insets.y
	var right: float = insets.z
	var bottom: float = insets.w
	var fit_v: float = tan_v * maxf(0.2, 1.0 - top - bottom)
	var fit_h: float = tan_h * maxf(0.2, 1.0 - left - right)
	var distance: float = 1.0
	for corner in _get_fit_corners():
		var x: float = absf(corner.dot(basis_value.x))
		var y: float = absf(corner.dot(basis_value.y))
		var depth_offset: float = corner.dot(forward)
		distance = maxf(distance, y / fit_v - depth_offset)
		distance = maxf(distance, x / fit_h - depth_offset)
	# Slide the camera sideways so the board center lands in the middle of the free screen area.
	var offset := Vector2(-(left - right) * tan_h * distance, -(bottom - top) * tan_v * distance)
	var pose := CamPose.new()
	pose.pitch = pitch
	pose.yaw = yaw
	pose.distance = distance
	pose.size = board_fit_size.y + fit_margin * 2.0
	pose.fov = perspective_fov
	pose.offset = offset
	pose.orthogonal = false
	return pose


func _get_fit_corners() -> Array[Vector3]:
	var hx: float = board_fit_size.x * 0.5 + fit_margin
	var hz: float = board_fit_size.y * 0.5 + fit_margin
	var h: float = content_height
	return [
		Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(-hx, 0, hz), Vector3(hx, 0, hz),
		Vector3(-hx, h, -hz), Vector3(hx, h, -hz), Vector3(-hx, h, hz), Vector3(hx, h, hz),
	]


## HUD insets as fractions of the viewport (scaled like the HUD: min(w/refW, h/refH)).
## Returns Vector4(left, top, right, bottom) (C# out parameters).
func _get_inset_fractions() -> Vector4:
	var size: Vector2 = get_viewport().get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0 or inset_reference_size.x <= 0.0 or inset_reference_size.y <= 0.0:
		return Vector4.ZERO
	var scale_value: float = maxf(inset_min_scale, minf(size.x / inset_reference_size.x, size.y / inset_reference_size.y))
	var left: float = inset_left * scale_value / size.x
	var right: float = inset_right * scale_value / size.x
	var top: float = inset_top * scale_value / size.y
	var bottom: float = inset_bottom * scale_value / size.y
	return Vector4(left, top, right, bottom)


func _get_aspect() -> float:
	var size: Vector2 = get_viewport().get_visible_rect().size
	return size.x / size.y if size.y > 0.0 else 16.0 / 9.0
