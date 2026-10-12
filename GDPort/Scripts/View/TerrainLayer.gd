class_name TerrainLayer
extends Node3D
## Renders the permanent terrain of the board (child of BoardView): flowing water, wooden plank bridges over it and
## breakable rocks, which shrink as they lose HP. sync() diffs against the BoardState, so it can be called after
## every resolved action (a crumbled rock simply disappears; the animator plays its dust).

const PLANK_COLOR := Color(0.5, 0.33, 0.18)
const RAIL_COLOR := Color(0.36, 0.23, 0.12)

## pos (Vector2i) -> {"type": int (TerrainType), "hp": int, "node": Node3D}
var _nodes: Dictionary = {}
var _decor: Array[Node3D] = []
var _water: ShaderMaterial
var _plank: StandardMaterial3D
var _rail: StandardMaterial3D
var _to_local: Callable = Callable()
var _tile_size: float = 1.0
var _rock_max_hp: int = 3


## Removes every terrain node.
func clear_all() -> void:
	for entry: Dictionary in _nodes.values():
		(entry.node as Node3D).queue_free()
	_nodes.clear()
	for node in _decor:
		node.queue_free()
	_decor.clear()


## Brings the visuals in line with the board's terrain. to_local (Callable(Vector2i) -> Vector3) maps a tile to its top centre.
func sync(board: BoardState, to_local: Callable, tile_size: float, rock_max_hp: int) -> void:
	_to_local = to_local
	_tile_size = tile_size
	_rock_max_hp = rock_max_hp
	if _decor.is_empty():
		var decor: Dictionary = board.decor
		for key: Vector2i in decor.keys():
			var node: Node3D = _create_decor(decor[key], tile_size, key)
			node.position = to_local.call(key)
			add_child(node)
			_decor.append(node)
	var stale: Array = _nodes.keys()
	var terrain: Dictionary = board.terrain
	for pos: Vector2i in terrain.keys():
		var type: int = terrain[pos]
		var hp: int = board.get_terrain_hp(pos)
		stale.erase(pos)
		if _nodes.has(pos):
			var existing: Dictionary = _nodes[pos]
			if existing.type == type and existing.hp == hp:
				continue
			(existing.node as Node3D).queue_free()
		var node: Node3D = _create(type, hp, rock_max_hp, tile_size, pos)
		node.position = to_local.call(pos)
		add_child(node)
		_nodes[pos] = {"type": type, "hp": hp, "node": node}
	for pos: Vector2i in stale:
		(_nodes[pos].node as Node3D).queue_free()
		_nodes.erase(pos)


## Shows a hit Rock with its new HP right away (0 = it crumbles and disappears).
func set_rock_hp(pos: Vector2i, hp: int) -> void:
	if not _nodes.has(pos) or _nodes[pos].type != TerrainType.ROCK:
		return
	var existing: Dictionary = _nodes[pos]
	(existing.node as Node3D).queue_free()
	_nodes.erase(pos)
	if hp > 0 and _to_local.is_valid():
		var node: Node3D = _create(TerrainType.ROCK, hp, _rock_max_hp, _tile_size, pos)
		node.position = _to_local.call(pos)
		add_child(node)
		_nodes[pos] = {"type": TerrainType.ROCK, "hp": hp, "node": node}


func _create(type: int, hp: int, max_hp: int, ts: float, pos: Vector2i) -> Node3D:
	var root := Node3D.new()
	root.name = "%s_%d_%d" % [TerrainType.name_of(type), pos.x, pos.y]
	var seed_value: float = pos.x * 12.9898 + pos.y * 78.233
	match type:
		TerrainType.WATER:
			root.add_child(_water_plane(ts, 0.005))
		TerrainType.BRIDGE:
			_build_bridge(root, ts, seed_value)
		TerrainType.ROCK:
			_build_rock(root, ts, hp, max_hp, seed_value)
	return root


## Visual-only terrain on the crown field: a river becomes a shallow ford with stepping stones, a wall low
## rubble - it plays as plain ground.
func _create_decor(type: int, ts: float, pos: Vector2i) -> Node3D:
	var root := Node3D.new()
	root.name = "Decor%s_%d_%d" % [TerrainType.name_of(type), pos.x, pos.y]
	var seed_value: float = pos.x * 12.9898 + pos.y * 78.233
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(seed_value * 1000.0)) + 5
	var stone: ShaderMaterial = VfxAssets.create_material("stone_wall")
	stone.set_shader_parameter("seed", fmod(seed_value, 10.0))
	if type == TerrainType.WATER:
		var ford: MeshInstance3D = _water_plane(ts * 0.96, 0.004)
		ford.transparency = 0.6
		root.add_child(ford)
	var stones: int = 3 if type == TerrainType.WATER else 6
	for i in range(stones):
		var s: float = rng.randf_range(0.16, 0.22) if type == TerrainType.WATER else rng.randf_range(0.07, 0.13)
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(s * 1.2, 0.025, s)
		mi.mesh = box
		mi.material_override = stone
		mi.position = Vector3(rng.randf_range(-0.32, 0.32) * ts, -0.004, rng.randf_range(-0.32, 0.32) * ts)
		mi.rotation = Vector3(0.0, rng.randf_range(0.0, TAU), 0.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_instance_shader_parameter("top_size", Vector2(s * 1.2, s))
		root.add_child(mi)
	return root


func _water_plane(ts: float, y: float) -> MeshInstance3D:
	if _water == null:
		_water = VfxAssets.create_material("tile_water")
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(ts, ts)
	mi.mesh = plane
	mi.material_override = _water
	mi.position = Vector3(0, y, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Water underneath, planks across the river (crossing runs along the board's Z axis) and low side rails.
func _build_bridge(root: Node3D, ts: float, seed_value: float) -> void:
	if _plank == null:
		_plank = StandardMaterial3D.new()
		_plank.albedo_color = PLANK_COLOR
		_plank.roughness = 0.9
	if _rail == null:
		_rail = StandardMaterial3D.new()
		_rail.albedo_color = RAIL_COLOR
		_rail.roughness = 0.9
	root.add_child(_water_plane(ts, -0.01))
	const PLANKS: int = 5
	var step: float = ts / PLANKS
	for i in range(PLANKS):
		var jitter: float = 0.01 * sin(seed_value + i * 1.7)
		root.add_child(_box_instance(Vector3(ts * 0.78, 0.03, step * 0.86), _plank,
			Vector3(jitter, -0.008, -ts * 0.5 + step * (i + 0.5)), Vector3(0.0, 0.03 * sin(seed_value * 0.7 + i), 0.0)))
	for side: float in [-1.0, 1.0]:
		root.add_child(_box_instance(Vector3(0.04, 0.05, ts * 0.96), _rail, Vector3(side * ts * 0.43, 0.03, 0.0), Vector3.ZERO))
		for k in range(2):
			root.add_child(_box_instance(Vector3(0.06, 0.1, 0.06), _rail,
				Vector3(side * ts * 0.43, 0.04, (-1.0 if k == 0 else 1.0) * ts * 0.4), Vector3.ZERO))


static func _box_instance(size: Vector3, mat: Material, pos: Vector3, rot: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	return mi


## A rough boulder wall; lower and more broken the less HP it has left.
static func _build_rock(root: Node3D, ts: float, hp: int, max_hp: int, seed_value: float) -> void:
	var health: float = clampf(hp / float(max_hp), 0.2, 1.0) if max_hp > 0 else 1.0
	var height: float = 0.22 + 0.36 * health
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(seed_value * 1000.0)) + 3
	var stone: ShaderMaterial = VfxAssets.create_material("stone_wall")
	stone.set_shader_parameter("seed", fmod(seed_value, 10.0))
	var add_block := func(size: Vector3, pos: Vector3, rot: Vector3) -> void:
		var mi: MeshInstance3D = _box_instance(size, stone, pos, rot)
		mi.set_instance_shader_parameter("top_size", Vector2(size.x, size.z))
		root.add_child(mi)
	add_block.call(Vector3(0.8 * ts, height, 0.74 * ts), Vector3(0, height * 0.5, 0), Vector3(0, rng.randf_range(-0.15, 0.15), 0))
	var p2 := Vector3(rng.randf_range(-0.12, 0.12) * ts, height + height * 0.2, rng.randf_range(-0.1, 0.1) * ts)
	var r2 := Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(0.0, TAU), rng.randf_range(-0.12, 0.12))
	add_block.call(Vector3(0.5 * ts, height * 0.45, 0.46 * ts), p2, r2)
	var chips: int = 3 + roundi((1.0 - health) * 4.0)
	for i in range(chips):
		var ang: float = TAU * i / chips + rng.randf_range(-0.4, 0.4)
		var s: float = rng.randf_range(0.07, 0.14)
		var pos := Vector3(cos(ang) * 0.42 * ts, s * 0.35, sin(ang) * 0.42 * ts)
		var rot := Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(0.0, TAU), rng.randf_range(-0.4, 0.4))
		add_block.call(Vector3(s * 1.3, s * 0.8, s), pos, rot)
