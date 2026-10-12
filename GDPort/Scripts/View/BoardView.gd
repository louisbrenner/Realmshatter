class_name BoardView
extends Node3D
## Renders the board (one stone/parchment shader surface with a glowing rune border around the
## scoring zone), the wooden frame with gold trims and the table beneath, plus pulsing tile
## highlights. Converts between grid and world coordinates and picks tiles under the mouse.
## Grid X maps to world X, grid Y maps to world Z (row 0 = -Z = far side / player 1,
## last row = +Z = near side / player 0). The board is centered at this node's origin;
## tile tops lie on local y = 0.

## Emitted on a left mouse click on a tile (not over UI).
signal tile_clicked(pos: Vector2i)

## Emitted when the hovered tile changes. (-1, -1) means the mouse left the board.
signal tile_hovered(pos: Vector2i)

@export_group("Layout")
@export var tile_size: float = 1.0
@export var tile_gap: float = 0.05
## How much higher the crown field's tiles stand than the rest of the board (pieces stand on top).
@export var crown_lift: float = 0.045
@export var tile_thickness: float = 0.2

@export_group("Tile Colors")
@export var normal_color: Color = Color(0.5, 0.47, 0.42)
@export var scoring_zone_color: Color = Color(0.88, 0.74, 0.47)
@export var player0_deploy_color: Color = Color(0.22, 0.42, 0.9)
@export var player1_deploy_color: Color = Color(0.9, 0.26, 0.2)
@export var base_color: Color = Color(0.12, 0.1, 0.09)
@export var rune_color: Color = Color(1.0, 0.68, 0.24)
## Brightness difference for the checkerboard pattern (0 = off).
@export_range(0, 0.3, 0.01) var checker_strength: float = 0.05
## Optional material for the board surface; replaces the procedural board shader if set.
@export var tile_material_template: StandardMaterial3D

@export_group("Decoration")
@export var build_decoration: bool = true
@export var frame_width: float = 0.46
@export var frame_height: float = 0.14
@export var wood_light: Color = Color(0.55, 0.32, 0.16)
@export var wood_dark: Color = Color(0.22, 0.11, 0.05)
@export var table_light: Color = Color(0.36, 0.21, 0.11)
@export var table_dark: Color = Color(0.13, 0.07, 0.035)

@export_group("Highlight Colors")
@export var move_highlight_color: Color = Color(0.30, 0.75, 1.00, 0.6)
@export var attack_highlight_color: Color = Color(1.00, 0.25, 0.20, 0.6)
@export var deploy_highlight_color: Color = Color(0.30, 1.00, 0.40, 0.55)
@export var spell_highlight_color: Color = Color(0.75, 0.35, 1.00, 0.6)
@export var selected_highlight_color: Color = Color(1.00, 0.85, 0.30, 0.65)
@export var hover_highlight_color: Color = Color(1.00, 0.95, 0.85, 0.45)
@export var range_highlight_color: Color = Color(0.25, 0.95, 0.95, 0.42)

## HighlightKind (int) -> Array of MeshInstance3D
var _highlights: Dictionary = {}
## HighlightKind (int) -> ShaderMaterial
var _highlight_materials: Dictionary = {}

var _tile_root: Node3D
var _highlight_root: Node3D
var _tile_effects: TileEffectLayer
var _terrain: TerrainLayer
var _crown: Rect2i = Rect2i()
var _trap_root: Node3D
## Vector2i -> {"type": int (TrapType), "node": Node3D}
var _trap_markers: Dictionary = {}
var _highlight_mesh: PlaneMesh
var _width: int = 10
var _height: int = 8
var _hovered: Vector2i = Vector2i(-1, -1)
## Array of {"flame": MeshInstance3D, "light": OmniLight3D, "seed": float}
var _candles: Array[Dictionary] = []
var _time: float = 0.0

## Board width in tiles (from the last Build, default 10).
var width: int:
	get:
		return _width

## Board height in tiles (from the last Build, default 8).
var height: int:
	get:
		return _height


func _ready() -> void:
	_ensure_roots()


## (Re)creates the board surface and decoration for the given board and clears highlights.
func build(board: BoardState) -> void:
	_ensure_roots()
	clear_highlights()
	_tile_effects.clear_all()
	for child: Node in _tile_root.get_children():
		child.queue_free()

	_width = board.width
	_crown = board.hot_zone
	_height = board.height
	var w: float = float(_width) * tile_size
	var h: float = float(_height) * tile_size

	# Physical board: one chamfered stone block per tile (real gaps, slight height / tilt variation).
	var surface := MeshInstance3D.new()
	surface.name = "Surface"
	surface.mesh = TileMeshBuilder.build(_width, _height, tile_size, tile_gap, 0.05, 0.1, 11,
		func(x: int, y: int) -> float: return crown_lift if _is_crown(x, y) else 0.0)
	surface.material_override = _create_surface_material(board)
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_tile_root.add_child(surface)

	# Dark bed the stones are set into (visible in the gaps).
	var base_instance := MeshInstance3D.new()
	base_instance.name = "BoardBase"
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(w + 0.1, tile_thickness, h + 0.1)
	base_instance.mesh = base_mesh
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = base_color.darkened(0.4)
	base_mat.roughness = 1.0
	base_instance.material_override = base_mat
	base_instance.position = Vector3(0, -tile_thickness * 0.5 - 0.07, 0)
	_tile_root.add_child(base_instance)

	if build_decoration:
		_build_frame(w, h)
		_build_table()
		_build_props(w, h)

	_highlight_mesh = PlaneMesh.new()
	_highlight_mesh.size = Vector2(tile_size, tile_size)
	_terrain.clear_all()
	sync_terrain(board)
	for entry: Dictionary in _trap_markers.values():
		(entry.node as Node3D).queue_free()
	_trap_markers.clear()


## Updates water, bridges and rocks from the board (rock_max_hp scales the rock height).
func sync_terrain(board: BoardState, rock_max_hp: int = 3) -> void:
	_ensure_roots()
	_terrain.sync(board, _grid_to_local, tile_size, rock_max_hp)


## Shows the hidden traps of 'viewer' as faint jaw markers on their tiles; the opponent's traps stay invisible
## until they spring.
func sync_traps(board: BoardState, viewer: int) -> void:
	_ensure_roots()
	var stale: Array = _trap_markers.keys()
	for trap: Trap in board.traps.values():
		if trap.owner_index != viewer:
			continue
		stale.erase(trap.position)
		var existing_node: Node3D = null
		if _trap_markers.has(trap.position):
			var existing: Dictionary = _trap_markers[trap.position]
			if existing["type"] == trap.type:
				continue
			existing_node = existing.node
		if existing_node != null:
			existing_node.queue_free()
		var marker: MeshInstance3D = VfxAssets.create_icon(FxIconShape.TRAP, tile_size * 0.56, TrapInfo.get_color(trap.type),
			Color(0.08, 0.06, 0.05, 0.8), true, 6)
		if marker.material_override is ShaderMaterial:
			var mat := marker.material_override as ShaderMaterial
			mat.set_shader_parameter("billboard", false)
			mat.set_shader_parameter("alpha", 0.62)
		marker.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
		marker.position = _grid_to_local(trap.position) + Vector3(0.0, 0.014, 0.0)
		_trap_root.add_child(marker)
		_trap_markers[trap.position] = {"type": trap.type, "node": marker}
	for pos: Vector2i in stale:
		(_trap_markers[pos].node as Node3D).queue_free()
		_trap_markers.erase(pos)


## Removes the marker of a sprung trap right away.
func remove_trap_marker(pos: Vector2i) -> void:
	if _trap_markers.has(pos):
		(_trap_markers[pos].node as Node3D).queue_free()
		_trap_markers.erase(pos)


## Shows a hit Rock with its remaining HP (0 = it crumbles).
func show_rock_hp(pos: Vector2i, hp: int) -> void:
	if _terrain != null:
		_terrain.set_rock_hp(pos, hp)


## The layer that renders lava / wall / healing tiles (child "TileEffects").
var tile_effects: TileEffectLayer:
	get:
		_ensure_roots()
		return _tile_effects


## Shows the board's tile effects: new effects appear animated, expired ones vanish, duration badges
## update. current_turn = -1 uses the turn number of the last call for the remaining-turn badges.
func sync_tile_effects(board: BoardState, current_turn: int = -1, animate: bool = true) -> void:
	tile_effects.sync(board, current_turn, animate)


## Animates a tile effect appearing on a tile (TileEffectApplied). Completes when it has formed.
func animate_tile_effect_applied(pos: Vector2i, type: int, expiry_turn: int) -> void:
	await tile_effects.play_applied(pos, type, expiry_turn)


## Animates the tile effect on a tile vanishing (TileEffectExpired). Completes when it is gone.
func animate_tile_effect_expired(pos: Vector2i) -> void:
	await tile_effects.play_expired(pos)


## World position of the center of a tile's top surface.
func grid_to_world(pos: Vector2i) -> Vector3:
	var local: Vector3 = _grid_to_local(pos)
	return to_global(local) if is_inside_tree() else local


## Grid position (Vector2i) for a world point, or null if it lies outside the board.
func world_to_grid(world: Vector3) -> Variant:
	var local: Vector3 = to_local(world) if is_inside_tree() else world
	var fx: float = local.x / tile_size + _width * 0.5
	var fy: float = local.z / tile_size + _height * 0.5
	var x: int = floori(fx)
	var y: int = floori(fy)
	if x < 0 or y < 0 or x >= _width or y >= _height:
		return null
	return Vector2i(x, y)


## Tile (Vector2i) under a screen position (ray vs. the board's y = 0 plane), or null.
func pick_tile(camera: Camera3D, screen_pos: Vector2) -> Variant:
	if camera == null:
		return null
	var origin: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	var plane := Plane(global_transform.basis.y.normalized(), global_position)
	var hit: Variant = plane.intersects_ray(origin, dir)
	if hit == null:
		return null
	return world_to_grid(hit)


## Shows highlights of the given kind on the tiles, replacing previous highlights of that kind.
func show_highlights(tiles: Array, kind: int) -> void:
	_ensure_roots()
	clear_highlights(kind)
	if tiles == null:
		return
	if _highlight_mesh == null:
		_highlight_mesh = PlaneMesh.new()
		_highlight_mesh.size = Vector2(tile_size, tile_size)

	var list: Array
	if _highlights.has(kind):
		list = _highlights[kind]
	else:
		list = []
		_highlights[kind] = list

	var lift: float = 0.007 if kind == HighlightKind.RANGE else 0.01 + 0.004 * kind
	var material: ShaderMaterial = _get_highlight_material(kind)
	for pos: Vector2i in tiles:
		if pos.x < 0 or pos.y < 0 or pos.x >= _width or pos.y >= _height:
			continue
		var local: Vector3 = _grid_to_local(pos)
		var marker := MeshInstance3D.new()
		marker.mesh = _highlight_mesh
		marker.material_override = material
		marker.position = Vector3(local.x, lift, local.z)
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_highlight_root.add_child(marker)
		list.append(marker)


## Removes all highlights of one kind, or of every kind if kind is -1 (default).
## (Merges the C# overloads ClearHighlights() and ClearHighlights(kind).)
func clear_highlights(kind: int = -1) -> void:
	if kind < 0:
		for k: int in _highlights.keys():
			_free_list(_highlights[k])
		_highlights.clear()
		return
	if _highlights.has(kind):
		_free_list(_highlights[kind])


func _unhandled_input(event: InputEvent) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			var pos: Variant = pick_tile(camera, button.position)
			if pos != null:
				tile_clicked.emit(pos)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var pos: Variant = pick_tile(camera, motion.position)
		var hovered: Vector2i = pos if pos != null else Vector2i(-1, -1)
		if hovered != _hovered:
			_hovered = hovered
			tile_hovered.emit(hovered)


func _grid_to_local(pos: Vector2i) -> Vector3:
	var x: float = (pos.x - (_width - 1) * 0.5) * tile_size
	var z: float = (pos.y - (_height - 1) * 0.5) * tile_size
	return Vector3(x, crown_lift if _is_crown(pos.x, pos.y) else 0.0, z)


## True for the crown field's tiles (they stand slightly raised).
func _is_crown(x: int, y: int) -> bool:
	return _crown.size.x > 0 and x >= _crown.position.x and x < _crown.end.x and y >= _crown.position.y and y < _crown.end.y


func _create_surface_material(board: BoardState) -> Material:
	if tile_material_template != null:
		return tile_material_template
	var mat: ShaderMaterial = VfxAssets.create_material("board_surface")
	var zone: Rect2i = board.scoring_zone
	mat.set_shader_parameter("board_size", Vector2(board.width, board.height))
	mat.set_shader_parameter("tile_size", tile_size)
	mat.set_shader_parameter("grout_width", 0.01)
	mat.set_shader_parameter("scoring_rect", Vector4(zone.position.x, zone.position.y, zone.size.x, zone.size.y))
	var hot: Rect2i = board.hot_zone
	mat.set_shader_parameter("hot_rect", Vector4(hot.position.x, hot.position.y, hot.size.x, hot.size.y))
	mat.set_shader_parameter("deploy_rows", float(board.deploy_rows))
	mat.set_shader_parameter("stone_color", normal_color)
	mat.set_shader_parameter("stone_dark", normal_color.darkened(0.45))
	mat.set_shader_parameter("parchment_color", scoring_zone_color)
	mat.set_shader_parameter("p0_tint", player0_deploy_color)
	mat.set_shader_parameter("p1_tint", player1_deploy_color)
	mat.set_shader_parameter("rune_color", rune_color)
	mat.set_shader_parameter("checker", checker_strength)
	return mat


func _build_frame(w: float, h: float) -> void:
	var frame := Node3D.new()
	frame.name = "Frame"
	_tile_root.add_child(frame)
	var fw: float = frame_width
	var depth: float = 0.32
	var top: float = frame_height
	var frame_h: float = top + depth
	var cy: float = top - frame_h * 0.5

	var wood_x: ShaderMaterial = _create_wood_material(Vector3.RIGHT)
	var wood_z: ShaderMaterial = _create_wood_material(Vector3.BACK)
	_add_box(frame, "FrameNear", Vector3(w + 2.0 * fw, frame_h, fw), Vector3(0, cy, h * 0.5 + fw * 0.5), wood_x)
	_add_box(frame, "FrameFar", Vector3(w + 2.0 * fw, frame_h, fw), Vector3(0, cy, -h * 0.5 - fw * 0.5), wood_x)
	_add_box(frame, "FrameLeft", Vector3(fw, frame_h, h), Vector3(-w * 0.5 - fw * 0.5, cy, 0), wood_z)
	_add_box(frame, "FrameRight", Vector3(fw, frame_h, h), Vector3(w * 0.5 + fw * 0.5, cy, 0), wood_z)

	# Gold trims: an inner lip around the board and an outer edge.
	var gold: StandardMaterial3D = VfxAssets.create_gold_material(0.15)
	var t: float = 0.055
	var th: float = 0.05
	var ty: float = top + th * 0.5 - 0.01
	_add_box(frame, "TrimInnerNear", Vector3(w + 2.0 * t, th, t), Vector3(0, ty, h * 0.5 + t * 0.5), gold)
	_add_box(frame, "TrimInnerFar", Vector3(w + 2.0 * t, th, t), Vector3(0, ty, -h * 0.5 - t * 0.5), gold)
	_add_box(frame, "TrimInnerLeft", Vector3(t, th, h), Vector3(-w * 0.5 - t * 0.5, ty, 0), gold)
	_add_box(frame, "TrimInnerRight", Vector3(t, th, h), Vector3(w * 0.5 + t * 0.5, ty, 0), gold)
	var ow: float = w + 2.0 * fw
	var oh: float = h + 2.0 * fw
	_add_box(frame, "TrimOuterNear", Vector3(ow, th * 0.7, t), Vector3(0, ty, oh * 0.5 - t * 0.5), gold)
	_add_box(frame, "TrimOuterFar", Vector3(ow, th * 0.7, t), Vector3(0, ty, -oh * 0.5 + t * 0.5), gold)
	_add_box(frame, "TrimOuterLeft", Vector3(t, th * 0.7, oh), Vector3(-ow * 0.5 + t * 0.5, ty, 0), gold)
	_add_box(frame, "TrimOuterRight", Vector3(t, th * 0.7, oh), Vector3(ow * 0.5 - t * 0.5, ty, 0), gold)

	# Corner ornaments with owner-colored gems (near = player 0, far = player 1).
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = fw * 0.42
	cap_mesh.bottom_radius = fw * 0.5
	cap_mesh.height = 0.1
	cap_mesh.radial_segments = 24
	cap_mesh.rings = 1
	var gem_mesh := SphereMesh.new()
	gem_mesh.radius = fw * 0.22
	gem_mesh.height = fw * 0.3
	gem_mesh.radial_segments = 16
	gem_mesh.rings = 8
	for i in range(4):
		var sx: float = -1.0 if i % 2 == 0 else 1.0
		var sz: float = 1.0 if i < 2 else -1.0
		var pos := Vector3(sx * (w * 0.5 + fw * 0.5), top + 0.05, sz * (h * 0.5 + fw * 0.5))
		var cap := MeshInstance3D.new()
		cap.name = "Corner%d" % i
		cap.mesh = cap_mesh
		cap.material_override = gold
		cap.position = pos
		frame.add_child(cap)
		var gem_color: Color = player0_deploy_color if sz > 0.0 else player1_deploy_color
		var gem_mat := StandardMaterial3D.new()
		gem_mat.albedo_color = gem_color
		gem_mat.metallic = 0.2
		gem_mat.roughness = 0.12
		gem_mat.emission_enabled = true
		gem_mat.emission = gem_color
		gem_mat.emission_energy_multiplier = 1.6
		var gem := MeshInstance3D.new()
		gem.name = "Gem%d" % i
		gem.mesh = gem_mesh
		gem.material_override = gem_mat
		gem.position = pos + Vector3(0, 0.07, 0)
		gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		frame.add_child(gem)

	# Small gold studs along the long sides.
	var stud_mesh := SphereMesh.new()
	stud_mesh.radius = 0.045
	stud_mesh.height = 0.05
	stud_mesh.radial_segments = 10
	stud_mesh.rings = 5
	for x in range(1, _width):
		var px: float = (x - _width * 0.5) * tile_size
		var near := MeshInstance3D.new()
		near.mesh = stud_mesh
		near.material_override = gold
		near.position = Vector3(px, top + 0.01, h * 0.5 + fw * 0.55)
		frame.add_child(near)
		var far := MeshInstance3D.new()
		far.mesh = stud_mesh
		far.material_override = gold
		far.position = Vector3(px, top + 0.01, -h * 0.5 - fw * 0.55)
		frame.add_child(far)


func _build_table() -> void:
	var wood: ShaderMaterial = VfxAssets.create_material("wood")
	wood.set_shader_parameter("wood_light", table_light)
	wood.set_shader_parameter("wood_dark", table_dark)
	wood.set_shader_parameter("grain_axis", Vector3.RIGHT)
	wood.set_shader_parameter("plank_width", 1.1)
	wood.set_shader_parameter("grain_scale", 0.8)
	wood.set_shader_parameter("roughness_value", 0.6)
	var table := MeshInstance3D.new()
	table.name = "Table"
	var table_mesh := PlaneMesh.new()
	table_mesh.size = Vector2(80.0, 60.0)
	table.mesh = table_mesh
	table.material_override = wood
	table.position = Vector3(0, -0.18, 0)
	_tile_root.add_child(table)


## Table dressing that makes the scene feel physical: a stitched leather play mat under the board, two candles
## with flickering light, coin stacks and a closed rule book.
func _build_props(w: float, h: float) -> void:
	_candles.clear()
	var props := Node3D.new()
	props.name = "Props"
	_tile_root.add_child(props)
	var fw: float = frame_width
	var mat_w: float = w + 2.0 * fw + 1.6
	var mat_h: float = h + 2.0 * fw + 1.6

	var noise := FastNoiseLite.new()
	noise.frequency = 0.09
	noise.fractal_octaves = 4
	noise.seed = 3
	var normal_tex := NoiseTexture2D.new()
	normal_tex.noise = noise
	normal_tex.as_normal_map = true
	normal_tex.bump_strength = 3.0
	normal_tex.width = 512
	normal_tex.height = 512
	normal_tex.seamless = true
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.3, 0.12, 0.07)
	leather.roughness = 0.72
	leather.normal_enabled = true
	leather.normal_texture = normal_tex
	leather.normal_scale = 0.6
	leather.uv1_scale = Vector3(3.0, 3.0, 3.0)
	var mat_instance := MeshInstance3D.new()
	mat_instance.name = "Mat"
	var mat_mesh := BoxMesh.new()
	mat_mesh.size = Vector3(mat_w, 0.03, mat_h)
	mat_instance.mesh = mat_mesh
	mat_instance.material_override = leather
	mat_instance.position = Vector3(0, -0.165, 0)
	props.add_child(mat_instance)
	# Stitching along the mat border.
	var stitch := StandardMaterial3D.new()
	stitch.albedo_color = Color(0.82, 0.68, 0.42)
	stitch.roughness = 0.9
	var stitch_mesh := BoxMesh.new()
	stitch_mesh.size = Vector3(0.14, 0.012, 0.03)
	var sx: float = -mat_w * 0.5 + 0.3
	while sx < mat_w * 0.5 - 0.2:
		_add_mesh(props, stitch_mesh, stitch, Vector3(sx, -0.146, -mat_h * 0.5 + 0.18))
		_add_mesh(props, stitch_mesh, stitch, Vector3(sx, -0.146, mat_h * 0.5 - 0.18))
		sx += 0.3
	var sz: float = -mat_h * 0.5 + 0.3
	while sz < mat_h * 0.5 - 0.2:
		var a: MeshInstance3D = _add_mesh(props, stitch_mesh, stitch, Vector3(-mat_w * 0.5 + 0.18, -0.146, sz))
		a.rotation = Vector3(0, PI / 2.0, 0)
		var b: MeshInstance3D = _add_mesh(props, stitch_mesh, stitch, Vector3(mat_w * 0.5 - 0.18, -0.146, sz))
		b.rotation = Vector3(0, PI / 2.0, 0)
		sz += 0.3

	var side_x: float = mat_w * 0.5 + 0.9
	_add_candle(props, Vector3(-side_x, -0.18, -h * 0.3), 0.9)
	_add_candle(props, Vector3(side_x, -0.18, -h * 0.3), 1.1)
	_add_candle(props, Vector3(side_x + 0.35, -0.18, -h * 0.3 + 0.35), 0.6)

	var gold: StandardMaterial3D = VfxAssets.create_gold_material(0.05)
	var coin := CylinderMesh.new()
	coin.top_radius = 0.16
	coin.bottom_radius = 0.16
	coin.height = 0.04
	coin.radial_segments = 20
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var stacks: Array = [
		[Vector3(-side_x + 0.2, -0.16, h * 0.32), 7],
		[Vector3(-side_x - 0.25, -0.16, h * 0.32 + 0.3), 4],
	]
	for stack: Array in stacks:
		var base_pos: Vector3 = stack[0]
		var count: int = stack[1]
		for i in range(count):
			_add_mesh(props, coin, gold,
				base_pos + Vector3(rng.randf_range(-0.02, 0.02), i * 0.042, rng.randf_range(-0.02, 0.02)))

	var book := Node3D.new()
	book.position = Vector3(side_x + 0.1, -0.18, h * 0.25)
	book.rotation = Vector3(0, 0.35, 0)
	props.add_child(book)
	var cover_mesh := BoxMesh.new()
	cover_mesh.size = Vector3(1.1, 0.22, 1.5)
	var cover_mat := StandardMaterial3D.new()
	cover_mat.albedo_color = Color(0.36, 0.1, 0.08)
	cover_mat.roughness = 0.6
	_add_mesh(book, cover_mesh, cover_mat, Vector3(0, 0.11, 0))
	var pages_mesh := BoxMesh.new()
	pages_mesh.size = Vector3(1.0, 0.16, 1.44)
	var pages_mat := StandardMaterial3D.new()
	pages_mat.albedo_color = Color(0.92, 0.86, 0.72)
	pages_mat.roughness = 0.95
	_add_mesh(book, pages_mesh, pages_mat, Vector3(0.04, 0.11, 0))
	var band_mesh := BoxMesh.new()
	band_mesh.size = Vector3(0.6, 0.01, 0.08)
	_add_mesh(book, band_mesh, gold, Vector3(0, 0.225, -0.4))


func _add_candle(parent: Node3D, base_pos: Vector3, candle_height: float) -> void:
	var wax := StandardMaterial3D.new()
	wax.albedo_color = Color(0.93, 0.88, 0.76)
	wax.roughness = 0.5
	wax.subsurf_scatter_enabled = true
	wax.subsurf_scatter_strength = 0.6
	var holder_mesh := CylinderMesh.new()
	holder_mesh.top_radius = 0.13
	holder_mesh.bottom_radius = 0.2
	holder_mesh.height = 0.06
	holder_mesh.radial_segments = 16
	_add_mesh(parent, holder_mesh, VfxAssets.create_gold_material(0.03), base_pos + Vector3(0, 0.03, 0))
	var wax_mesh := CylinderMesh.new()
	wax_mesh.top_radius = 0.1
	wax_mesh.bottom_radius = 0.11
	wax_mesh.height = candle_height
	wax_mesh.radial_segments = 16
	_add_mesh(parent, wax_mesh, wax, base_pos + Vector3(0, 0.06 + candle_height * 0.5, 0))
	var flame_mat := StandardMaterial3D.new()
	flame_mat.albedo_color = Color(1.0, 0.75, 0.35)
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1.0, 0.6, 0.2)
	flame_mat.emission_energy_multiplier = 6.0
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.045
	flame_mesh.height = 0.16
	flame_mesh.radial_segments = 10
	flame_mesh.rings = 6
	var flame := MeshInstance3D.new()
	flame.mesh = flame_mesh
	flame.material_override = flame_mat
	flame.position = base_pos + Vector3(0, 0.06 + candle_height + 0.08, 0)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(flame)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.66, 0.32)
	light.light_energy = 0.9
	light.omni_range = 4.5
	light.shadow_enabled = false
	light.position = flame.position + Vector3(0, 0.1, 0)
	parent.add_child(light)
	_candles.append({"flame": flame, "light": light, "seed": randf_range(0.0, 10.0)})


func _process(delta: float) -> void:
	_time += delta
	for candle: Dictionary in _candles:
		var flame: MeshInstance3D = candle.flame
		if not is_instance_valid(flame):
			continue
		var light: OmniLight3D = candle.light
		var seed_value: float = candle.seed
		var f: float = 0.85 + 0.1 * sin(_time * 9.0 + seed_value) + 0.06 * sin(_time * 23.0 + seed_value * 2.0)
		light.light_energy = 0.9 * f
		flame.scale = Vector3(1.0, 0.9 + 0.2 * f, 1.0)


func _create_wood_material(grain_axis: Vector3) -> ShaderMaterial:
	var wood: ShaderMaterial = VfxAssets.create_material("wood")
	wood.set_shader_parameter("wood_light", wood_light)
	wood.set_shader_parameter("wood_dark", wood_dark)
	wood.set_shader_parameter("grain_axis", grain_axis)
	wood.set_shader_parameter("grain_scale", 1.6)
	return wood


static func _add_box(parent: Node3D, box_name: String, size: Vector3, pos: Vector3, material: Material) -> void:
	var box := MeshInstance3D.new()
	box.name = box_name
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	box.mesh = box_mesh
	box.material_override = material
	box.position = pos
	parent.add_child(box)


## Port helper (replaces C# object initializers): adds a MeshInstance3D with mesh, material and position.
static func _add_mesh(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	parent.add_child(instance)
	return instance


func _ensure_roots() -> void:
	if _tile_root == null:
		_tile_root = Node3D.new()
		_tile_root.name = "Tiles"
		add_child(_tile_root)
	if _terrain == null:
		_terrain = TerrainLayer.new()
		_terrain.name = "Terrain"
		add_child(_terrain)
	if _trap_root == null:
		_trap_root = Node3D.new()
		_trap_root.name = "Traps"
		add_child(_trap_root)
	if _tile_effects == null:
		_tile_effects = TileEffectLayer.new()
		_tile_effects.name = "TileEffects"
		_tile_effects.setup(self)
		add_child(_tile_effects)
	if _highlight_root == null:
		_highlight_root = Node3D.new()
		_highlight_root.name = "Highlights"
		add_child(_highlight_root)


static func _free_list(list: Array) -> void:
	for m: Variant in list:
		if is_instance_valid(m):
			(m as Node).queue_free()
	list.clear()


func _get_highlight_material(kind: int) -> ShaderMaterial:
	if _highlight_materials.has(kind):
		return _highlight_materials[kind]
	var color: Color
	match kind:
		HighlightKind.MOVE:
			color = move_highlight_color
		HighlightKind.ATTACK:
			color = attack_highlight_color
		HighlightKind.DEPLOY:
			color = deploy_highlight_color
		HighlightKind.SPELL:
			color = spell_highlight_color
		HighlightKind.SELECTED:
			color = selected_highlight_color
		HighlightKind.RANGE:
			color = range_highlight_color
		_:
			color = hover_highlight_color
	var pattern: int = 0
	match kind:
		HighlightKind.ATTACK:
			pattern = 1
		HighlightKind.HOVER:
			pattern = 2
		HighlightKind.SELECTED:
			pattern = 3
		HighlightKind.RANGE:
			pattern = 4
		_:
			pattern = 0
	var mat: ShaderMaterial = VfxAssets.create_material("highlight", -1 if kind == HighlightKind.RANGE else kind)
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("pattern", pattern)
	mat.set_shader_parameter("pulse_speed", 5.0 if kind == HighlightKind.HOVER else 3.0)
	_highlight_materials[kind] = mat
	return mat
