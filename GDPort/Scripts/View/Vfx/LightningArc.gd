class_name LightningArc
extends MeshInstance3D
## Jagged, camera-facing lightning ribbon between two world points that re-jitters a few times
## per frame-second and fades out, then frees itself. Create via Vfx.lightning.

const JITTER_INTERVAL := 0.045

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _from: Vector3
var _to: Vector3
var _color: Color = Color(0.6, 0.8, 1.0)
var _duration: float = 0.35
var _time: float = 0.0
var _next_jitter: float = 0.0
var _mesh: ImmediateMesh
var _material: ShaderMaterial


## Sets endpoints (world space), color and lifetime. Call before adding to the tree.
func setup(from_world: Vector3, to_world: Vector3, color: Color, duration: float) -> void:
	_from = from_world
	_to = to_world
	_color = color
	_duration = maxf(0.05, duration)


func _ready() -> void:
	_mesh = ImmediateMesh.new()
	mesh = _mesh
	_material = VfxAssets.create_material("vfx_ribbon", 6)
	_material.set_shader_parameter("color", _color)
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rebuild()


func _process(delta: float) -> void:
	_time += delta
	if _time >= _duration:
		queue_free()
		return
	var k: float = 1.0 - _time / _duration
	_material.set_shader_parameter("opacity", clampf(k * 1.4, 0.0, 1.0))
	_next_jitter -= delta
	if _next_jitter <= 0.0:
		_rebuild()
		_next_jitter = JITTER_INTERVAL


func _rebuild() -> void:
	var camera: Camera3D = null
	var viewport: Viewport = get_viewport()
	if viewport != null:
		camera = viewport.get_camera_3d()
	var view_dir: Vector3 = camera.global_transform.basis.z.normalized() if camera != null else Vector3.UP
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_bolt(_build_points(0.2), view_dir, 0.13)
	_add_bolt(_build_points(0.32), view_dir, 0.06)
	_mesh.surface_end()


func _build_points(jitter: float) -> Array[Vector3]:
	const SEGMENTS := 14
	var points: Array[Vector3] = []
	var dir: Vector3 = _to - _from
	var length: float = dir.length()
	var side: Vector3 = dir.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 0.0001 else Vector3.RIGHT
	for i in range(SEGMENTS + 1):
		var t: float = float(i) / SEGMENTS
		var p: Vector3 = _from.lerp(_to, t) + Vector3.UP * sin(t * PI) * 0.12 * length
		if i > 0 and i < SEGMENTS:
			p += side * _rng.randf_range(-jitter, jitter) + Vector3.UP * _rng.randf_range(-jitter, jitter) * 0.6
		points.append(to_local(p))
	return points


func _add_bolt(points: Array[Vector3], view_dir_world: Vector3, width: float) -> void:
	var view_dir: Vector3 = (global_transform.basis.inverse() * view_dir_world).normalized()
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var seg: Vector3 = b - a
		var w: Vector3 = seg.cross(view_dir)
		w = w.normalized() * width * 0.5 if w.length_squared() > 0.000001 else Vector3.RIGHT * width * 0.5
		var ta: float = float(i) / (points.size() - 1)
		var tb: float = float(i + 1) / (points.size() - 1)
		_add_vertex(a - w, Vector2(ta, 0.0))
		_add_vertex(a + w, Vector2(ta, 1.0))
		_add_vertex(b + w, Vector2(tb, 1.0))
		_add_vertex(a - w, Vector2(ta, 0.0))
		_add_vertex(b + w, Vector2(tb, 1.0))
		_add_vertex(b - w, Vector2(tb, 0.0))


func _add_vertex(v: Vector3, uv: Vector2) -> void:
	_mesh.surface_set_uv(uv)
	_mesh.surface_add_vertex(v)
