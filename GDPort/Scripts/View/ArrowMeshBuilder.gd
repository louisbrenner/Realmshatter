class_name ArrowMeshBuilder
extends RefCounted
## Builds flat ribbon arrow meshes (for order_arrow.gdshader) from polylines, plus helpers to
## round corners, trim ends and create arcs. Body UV.x = distance along the path, UV.y = across;
## head triangle vertices carry UV2.x = 1.


## Replaces sharp polyline corners with quadratic Bezier fillets.
static func round_corners(points: Array[Vector3], radius: float, segments: int = 6) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if points == null or points.size() == 0:
		return result
	result.append(points[0])
	for i in range(1, points.size() - 1):
		var prev: Vector3 = points[i - 1]
		var cur: Vector3 = points[i]
		var next: Vector3 = points[i + 1]
		var d0: Vector3 = cur - prev
		var d1: Vector3 = next - cur
		var l0: float = d0.length()
		var l1: float = d1.length()
		if l0 < 0.0001 or l1 < 0.0001 or d0.normalized().dot(d1.normalized()) > 0.999:
			result.append(cur)
			continue
		var r: float = minf(radius, minf(l0, l1) * 0.5)
		var a: Vector3 = cur - d0.normalized() * r
		var b: Vector3 = cur + d1.normalized() * r
		for s in segments + 1:
			var t: float = float(s) / segments
			var u: float = 1.0 - t
			result.append(a * (u * u) + cur * (2.0 * u * t) + b * (t * t))
	if points.size() > 1:
		result.append(points[points.size() - 1])
	return result


## Quadratic arc from a to b rising to about 'height' with a sideways bulge (fraction of length).
static func arc(a: Vector3, b: Vector3, height: float, side_bulge: float, segments: int = 22) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var dir: Vector3 = b - a
	var side := Vector3(-dir.z, 0.0, dir.x)
	side = side.normalized() if side.length_squared() > 0.0001 else Vector3.ZERO
	var control: Vector3 = (a + b) * 0.5 + side * side_bulge * dir.length() + Vector3.UP * height * 2.0
	for i in segments + 1:
		var t: float = float(i) / segments
		var u: float = 1.0 - t
		result.append(a * (u * u) + control * (2.0 * u * t) + b * (t * t))
	return result


## Jagged lightning-like polyline from a to b: interior points are offset sideways (horizontally) by
## alternating, slightly randomized amounts up to 'amplitude'. Deterministic for a given seed.
static func zigzag(a: Vector3, b: Vector3, amplitude: float, segments: int, seed: float = 0.0) -> Array[Vector3]:
	segments = maxi(2, segments)
	var result: Array[Vector3] = []
	var dir: Vector3 = b - a
	var side := Vector3(-dir.z, 0.0, dir.x)
	side = side.normalized() if side.length_squared() > 0.0001 else Vector3.RIGHT
	for i in segments + 1:
		var t: float = float(i) / segments
		var p: Vector3 = a.lerp(b, t)
		if i > 0 and i < segments:
			var r: float = fmod(absf(sin(seed * 12.9898 + i * 78.233) * 43758.547), 1.0)
			var sign_value: float = 1.0 if i % 2 == 0 else -1.0
			p += side * sign_value * amplitude * (0.55 + 0.45 * r)
		result.append(p)
	return result


## Total length of a polyline.
static func length(points: Array[Vector3]) -> float:
	var len_sum: float = 0.0
	for i in range(1, points.size()):
		len_sum += points[i].distance_to(points[i - 1])
	return len_sum


## Cuts the given distances off the start and the end of a polyline.
static func trim(points: Array[Vector3], start_trim: float, end_trim: float) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if points == null or points.size() < 2:
		if points != null:
			result.append_array(points)
		return result
	var total: float = length(points)
	var from_dist: float = maxf(0.0, start_trim)
	var to_dist: float = maxf(from_dist + 0.01, total - maxf(0.0, end_trim))
	if to_dist > total:
		to_dist = total
	var acc: float = 0.0
	result.append(point_at(points, from_dist))
	for i in range(1, points.size()):
		acc += points[i].distance_to(points[i - 1])
		if acc > from_dist and acc < to_dist:
			result.append(points[i])
	result.append(point_at(points, to_dist))
	return result


## Point at a distance along a polyline (clamped).
static func point_at(points: Array[Vector3], distance: float) -> Vector3:
	if points.size() == 0:
		return Vector3.ZERO
	var acc: float = 0.0
	for i in range(1, points.size()):
		var seg: float = points[i].distance_to(points[i - 1])
		if acc + seg >= distance and seg > 0.0:
			return points[i - 1].lerp(points[i], (distance - acc) / seg)
		acc += seg
	return points[points.size() - 1]


## Builds a flat (horizontal) ribbon with an arrow head at the end of the polyline.
## Returns null if the polyline is too short.
static func build_arrow(points: Array[Vector3], width: float, head_length: float, head_width: float) -> ArrayMesh:
	if points == null or points.size() < 2:
		return null
	var total: float = length(points)
	if total < 0.08:
		return null
	var head_len: float = minf(head_length, total * 0.6)
	var body: Array[Vector3] = trim(points, 0.0, head_len)
	var tip: Vector3 = points[points.size() - 1]

	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()

	var dist: float = 0.0
	var last_side: Vector3 = Vector3.RIGHT
	for i in body.size():
		if i > 0:
			dist += body[i].distance_to(body[i - 1])
		var tangent: Vector3
		if i == 0:
			tangent = body[1] - body[0]
		elif i == body.size() - 1:
			tangent = body[i] - body[i - 1]
		else:
			tangent = body[i + 1] - body[i - 1]
		tangent.y = 0.0
		var side: Vector3 = Vector3(-tangent.z, 0.0, tangent.x).normalized() if tangent.length_squared() > 0.000001 else last_side
		last_side = side
		verts.append(body[i] - side * width * 0.5)
		verts.append(body[i] + side * width * 0.5)
		uvs.append(Vector2(dist, 0.0))
		uvs.append(Vector2(dist, 1.0))
		uv2s.append(Vector2.ZERO)
		uv2s.append(Vector2.ZERO)
		if i > 0:
			var a: int = (i - 1) * 2
			indices.append(a)
			indices.append(a + 2)
			indices.append(a + 1)
			indices.append(a + 1)
			indices.append(a + 2)
			indices.append(a + 3)

	var base_point: Vector3 = body[body.size() - 1]
	var head_dir: Vector3 = tip - base_point
	head_dir.y = 0.0
	var head_side: Vector3 = Vector3(-head_dir.z, 0.0, head_dir.x).normalized() if head_dir.length_squared() > 0.000001 else last_side
	var h: int = verts.size()
	verts.append(base_point - head_side * head_width * 0.5)
	verts.append(base_point + head_side * head_width * 0.5)
	verts.append(tip)
	uvs.append(Vector2(0.0, 0.0))
	uvs.append(Vector2(1.0, 0.0))
	uvs.append(Vector2(0.5, 1.0))
	uv2s.append(Vector2(1.0, 0.0))
	uv2s.append(Vector2(1.0, 0.0))
	uv2s.append(Vector2(1.0, 0.0))
	indices.append(h)
	indices.append(h + 1)
	indices.append(h + 2)

	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
