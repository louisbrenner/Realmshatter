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
@export var tile_gap: float = 0.06
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

## HighlightKind (int) -> Array of MeshInstance3D
var _highlights: Dictionary = {}
## HighlightKind (int) -> ShaderMaterial
var _highlight_materials: Dictionary = {}

var _tile_root: Node3D
var _highlight_root: Node3D
var _tile_effects: TileEffectLayer
var _highlight_mesh: PlaneMesh
var _width: int = 10
var _height: int = 8
var _hovered: Vector2i = Vector2i(-1, -1)

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
	_height = board.height
	var w: float = float(_width) * tile_size
	var h: float = float(_height) * tile_size

	var surface := MeshInstance3D.new()
	surface.name = "Surface"
	var surface_mesh := PlaneMesh.new()
	surface_mesh.size = Vector2(w, h)
	surface.mesh = surface_mesh
	surface.material_override = _create_surface_material(board)
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tile_root.add_child(surface)

	var base_instance := MeshInstance3D.new()
	base_instance.name = "BoardBase"
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(w + 0.1, tile_thickness, h + 0.1)
	base_instance.mesh = base_mesh
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = base_color
	base_mat.roughness = 0.9
	base_instance.material_override = base_mat
	base_instance.position = Vector3(0, -tile_thickness * 0.5 - 0.005, 0)
	_tile_root.add_child(base_instance)

	if build_decoration:
		_build_frame(w, h)
		_build_table()

	_highlight_mesh = PlaneMesh.new()
	_highlight_mesh.size = Vector2(tile_size, tile_size)


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

	var lift: float = 0.01 + 0.004 * kind
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
	return Vector3(x, 0.0, z)


func _create_surface_material(board: BoardState) -> Material:
	if tile_material_template != null:
		return tile_material_template
	var mat: ShaderMaterial = VfxAssets.create_material("board_surface")
	var zone: Rect2i = board.scoring_zone
	mat.set_shader_parameter("board_size", Vector2(board.width, board.height))
	mat.set_shader_parameter("tile_size", tile_size)
	mat.set_shader_parameter("grout_width", clampf(tile_gap / maxf(0.01, tile_size), 0.01, 0.3))
	mat.set_shader_parameter("scoring_rect", Vector4(zone.position.x, zone.position.y, zone.size.x, zone.size.y))
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


func _ensure_roots() -> void:
	if _tile_root == null:
		_tile_root = Node3D.new()
		_tile_root.name = "Tiles"
		add_child(_tile_root)
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
		_:
			pattern = 0
	var mat: ShaderMaterial = VfxAssets.create_material("highlight", kind)
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("pattern", pattern)
	mat.set_shader_parameter("pulse_speed", 5.0 if kind == HighlightKind.HOVER else 3.0)
	_highlight_materials[kind] = mat
	return mat
