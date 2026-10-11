class_name BeamEffect
extends MeshInstance3D
## Straight, camera-facing glowing beam between two world points (e.g. a Pierce lance) that shoots out
## from the start, flares and thins out, then frees itself. Create via RuleVfx.beam.

var _from: Vector3
var _to: Vector3
var _color: Color = Color(1.0, 0.8, 0.5)
var _duration: float = 0.35
var _width: float = 0.22
var _time: float = 0.0
var _mesh: ImmediateMesh
var _material: ShaderMaterial


## Sets endpoints (world space), color, lifetime and width. Call before adding to the tree.
func setup(from_world: Vector3, to_world: Vector3, color: Color, duration: float, width: float = 0.22) -> void:
	_from = from_world
	_to = to_world
	_color = color
	_duration = maxf(0.05, duration)
	_width = width


func _ready() -> void:
	_mesh = ImmediateMesh.new()
	mesh = _mesh
	_material = VfxAssets.create_material("vfx_ribbon", 6)
	_material.set_shader_parameter("color", _color)
	_material.set_shader_parameter("energy", 5.0)
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rebuild(0.0)


func _process(delta: float) -> void:
	_time += delta
	var t: float = _time / _duration
	if t >= 1.0:
		queue_free()
		return
	_rebuild(t)


func _rebuild(t: float) -> void:
	var extend: float = clampf(t / 0.25, 0.0, 1.0)
	var fade: float = 1.0 if t < 0.25 else 1.0 - (t - 0.25) / 0.75
	var width: float = _width * ((0.6 + 0.6 * extend) if t < 0.25 else (1.2 * fade + 0.05))
	_material.set_shader_parameter("opacity", clampf(fade * 1.3, 0.0, 1.0))

	var vp: Viewport = get_viewport()
	var camera: Camera3D = vp.get_camera_3d() if vp != null else null
	var view_dir_world: Vector3 = camera.global_transform.basis.z.normalized() if camera != null else Vector3.UP
	var view_dir: Vector3 = (global_transform.basis.inverse() * view_dir_world).normalized()
	var a: Vector3 = to_local(_from)
	var b: Vector3 = to_local(_from.lerp(_to, extend))
	var seg: Vector3 = b - a
	var w: Vector3 = seg.cross(view_dir)
	w = w.normalized() * width * 0.5 if w.length_squared() > 0.000001 else Vector3.RIGHT * width * 0.5

	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_vertex(a - w, Vector2(0.0, 0.0))
	_add_vertex(a + w, Vector2(0.0, 1.0))
	_add_vertex(b + w, Vector2(1.0, 1.0))
	_add_vertex(a - w, Vector2(0.0, 0.0))
	_add_vertex(b + w, Vector2(1.0, 1.0))
	_add_vertex(b - w, Vector2(1.0, 0.0))
	_mesh.surface_end()


func _add_vertex(v: Vector3, uv: Vector2) -> void:
	_mesh.surface_set_uv(uv)
	_mesh.surface_add_vertex(v)
