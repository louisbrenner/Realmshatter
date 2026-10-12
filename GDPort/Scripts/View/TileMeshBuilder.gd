class_name TileMeshBuilder
extends RefCounted
## Builds the board as real geometry: one raised, chamfered stone block per tile with a small gap between the
## blocks and a tiny random height / tilt so the surface reads as physical stones instead of a painted plane.
## Vertex positions use the same local frame as the old flat surface (x/z centred, tile tops at y ~ 0), so the
## board_surface shader keeps colouring the zone, deploy rows and crown field from the local position.


## Creates the tile mesh for a width x height board; lift (Callable(x, y) -> float) raises single tiles (e.g. the crown field).
static func build(width: int, height: int, tile_size: float, gap: float, bevel: float, depth: float, seed_value: int = 11,
		lift: Callable = Callable()) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var half: float = tile_size * 0.5 - gap * 0.5
	for y in range(height):
		for x in range(width):
			var cx: float = (x - (width - 1) * 0.5) * tile_size
			var cz: float = (y - (height - 1) * 0.5) * tile_size
			# Tops sink slightly (never rise above y = 0 so highlights and pieces stay on top) and tilt a hair.
			var lifted: float = float(lift.call(x, y)) if lift.is_valid() else 0.0
			var top: float = -rng.randf() * 0.012 + lifted
			var tilt_x: float = (rng.randf() - 0.5) * 0.008
			var tilt_z: float = (rng.randf() - 0.5) * 0.008
			_add_block(st, Vector3(cx, top, cz), half, bevel, depth, tilt_x, tilt_z)
	return st.commit()


static func _add_block(st: SurfaceTool, c: Vector3, half: float, bevel: float, depth: float, tilt_x: float, tilt_z: float) -> void:
	var inner: float = half - bevel
	var bevel_y: float = c.y - bevel * 0.55
	var bottom: float = -depth
	var lift := func(dx: float, dz: float) -> float: return dx * tilt_x + dz * tilt_z - maxf(0.0, 0.004)

	# Top face (inset by the chamfer).
	var t00 := Vector3(c.x - inner, c.y + lift.call(-inner, -inner), c.z - inner)
	var t10 := Vector3(c.x + inner, c.y + lift.call(inner, -inner), c.z - inner)
	var t11 := Vector3(c.x + inner, c.y + lift.call(inner, inner), c.z + inner)
	var t01 := Vector3(c.x - inner, c.y + lift.call(-inner, inner), c.z + inner)
	# Chamfer foot (full size, a bit lower).
	var b00 := Vector3(c.x - half, bevel_y, c.z - half)
	var b10 := Vector3(c.x + half, bevel_y, c.z - half)
	var b11 := Vector3(c.x + half, bevel_y, c.z + half)
	var b01 := Vector3(c.x - half, bevel_y, c.z + half)
	# Bottom ring.
	var d00 := Vector3(c.x - half, bottom, c.z - half)
	var d10 := Vector3(c.x + half, bottom, c.z - half)
	var d11 := Vector3(c.x + half, bottom, c.z + half)
	var d01 := Vector3(c.x - half, bottom, c.z + half)

	_quad(st, t00, t10, t11, t01, Vector3.UP)
	_quad(st, b00, b10, t10, t00, Vector3(0, 1, -1).normalized())
	_quad(st, b10, b11, t11, t10, Vector3(1, 1, 0).normalized())
	_quad(st, b11, b01, t01, t11, Vector3(0, 1, 1).normalized())
	_quad(st, b01, b00, t00, t01, Vector3(-1, 1, 0).normalized())
	_quad(st, d00, d10, b10, b00, Vector3.FORWARD)
	_quad(st, d10, d11, b11, b10, Vector3.RIGHT)
	_quad(st, d11, d01, b01, b11, Vector3.BACK)
	_quad(st, d01, d00, b00, b01, Vector3.LEFT)


## Adds a quad (a, b, c, d around the face) with an explicit normal; winding chosen to face the normal.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	var face_normal: Vector3 = (b - a).cross(c - a)
	var flip: bool = face_normal.dot(normal) > 0.0
	var tri1: Array = [a, c, b] if flip else [a, b, c]
	var tri2: Array = [a, d, c] if flip else [a, c, d]
	for v: Vector3 in tri1:
		st.set_normal(normal)
		st.add_vertex(v)
	for v: Vector3 in tri2:
		st.set_normal(normal)
		st.add_vertex(v)
