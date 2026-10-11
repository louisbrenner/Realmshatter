class_name SwirlEffect
extends Node3D
## Glowing motes that spiral down into the node's position and finish with a burst
## (spell cast). Create via Vfx.spell_swirl; frees itself when done.

var _motes: Array[MeshInstance3D] = []
var _primary: Color = Color(0.4, 1.0, 0.5)
var _secondary: Color = Color(1.0, 0.85, 0.35)
var _duration: float = 0.6
var _radius: float = 0.65
var _count: int = 16
var _time: float = 0.0
var _finished: bool = false


## Configures colors and duration. Call before adding to the tree.
func setup(primary: Color, secondary: Color, duration: float, radius: float = 0.65, count: int = 16) -> void:
	_primary = primary
	_secondary = secondary
	_duration = maxf(0.1, duration)
	_radius = radius
	_count = maxi(3, count)


func _ready() -> void:
	for i in range(_count):
		var mote := MeshInstance3D.new()
		mote.mesh = VfxAssets.sparkle_quad if i % 3 == 0 else VfxAssets.glow_quad
		mote.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mote.scale = Vector3.ONE * 0.2
		mote.set_instance_shader_parameter("tint", _primary if i % 2 == 0 else _secondary)
		add_child(mote)
		_motes.append(mote)

	var dust := CPUParticles3D.new()
	dust.mesh = VfxAssets.glow_quad
	dust.amount = 30
	dust.lifetime = 0.4
	dust.local_coords = false
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = _radius * 0.8
	dust.gravity = Vector3(0, -0.5, 0)
	dust.initial_velocity_min = 0.0
	dust.initial_velocity_max = 0.2
	dust.scale_amount_min = 0.1
	dust.scale_amount_max = 0.22
	dust.scale_amount_curve = Vfx.linear_curve(1.0, 0.0)
	dust.color_ramp = Vfx.ramp([_secondary, Color(_primary.r, _primary.g, _primary.b, 0.0)])
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dust.position = Vector3(0, 0.5, 0)
	add_child(dust)
	dust.emitting = true
	_update_motes(0.0)


func _process(delta: float) -> void:
	if _finished:
		return
	_time += delta
	var t: float = clampf(_time / _duration, 0.0, 1.0)
	_update_motes(t)
	if t >= 1.0:
		_finish()


func _update_motes(t: float) -> void:
	var eased: float = 1.0 - (1.0 - t) * (1.0 - t)
	for i in range(_motes.size()):
		var f: float = float(i) / _motes.size()
		var angle: float = f * TAU + eased * TAU * 1.6
		var r: float = _radius * (1.0 - 0.85 * eased) + 0.05
		var y: float = 1.3 * (1.0 - eased) + 0.3 + 0.15 * sin(f * 17.0 + t * 6.0) * (1.0 - t)
		_motes[i].position = Vector3(cos(angle) * r, y, sin(angle) * r)
		_motes[i].scale = Vector3.ONE * (0.3 + 0.12 * sin(t * 12.0 + f * 9.0) * (1.0 - t) + 0.1 * t)


func _finish() -> void:
	_finished = true
	var parent: Node3D = get_parent() as Node3D
	var center: Vector3 = global_position + Vector3(0, 0.35, 0)
	if parent != null:
		Vfx.sparkle(parent, center, _primary, 20, 0.7, 0.35)
		Vfx.glow_flash(parent, center, _primary, 1.8, 0.3)
		Vfx.shockwave(parent, Vector3(center.x, 0.05, center.z), _secondary, 1.1, 0.35, 0.1)
		Vfx.light_flash(parent, center + Vector3(0, 0.4, 0), _primary, 3.0, 3.0, 0.35)
	for mote in _motes:
		mote.visible = false
	Vfx.auto_free(self, 0.5)
