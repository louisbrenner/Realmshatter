class_name OrderOverlay
extends Node3D
## Draws order indicators on the board: a move arrow along the orthogonal path, a curved attack
## arrow (red, or gold for a friendly chain trigger) with a target reticle, and a numbered badge
## (resolution order) over the piece. One extra, brighter "preview" set shows the order being planned.
## Also draws predicted attack consequences (show_attack_preview: chain shots, damage numbers, kills,
## pushes, pierce lines, new tile effects) and tile-spell area ghosts (show_spell_area_preview).
## Place it anywhere at the world origin (e.g. as a child of Main or the BoardView).

@export_group("Colors")
@export var move_color: Color = Color(0.35, 0.8, 1.0)
@export var attack_color: Color = Color(1.0, 0.26, 0.18)
@export var chain_color: Color = Color(1.0, 0.76, 0.2)
@export var badge_color: Color = Color(0.14, 0.22, 0.5)
@export var push_color: Color = Color(1.0, 0.62, 0.3)
@export var pierce_color: Color = Color(0.85, 0.93, 1.0)
@export var heal_color: Color = Color(0.45, 1.0, 0.5)
@export var damage_splat_color: Color = Color(0.85, 0.1, 0.08)
@export var shield_splat_color: Color = Color(0.75, 0.6, 0.25)
@export var frost_color: Color = Color(0.55, 0.85, 1.0)

@export_group("Shape")
@export var arrow_width: float = 0.2
@export var head_length: float = 0.32
@export var head_width: float = 0.48
@export var arrow_height: float = 0.07
@export var attack_arc_height: float = 0.42
@export var corner_radius: float = 0.32
@export var badge_size: float = 0.34
## Height of predicted damage numbers above the victim's tile.
@export var preview_number_height: float = 0.95
## Extra height of predicted chain / pierce shot lines so they pass over the tokens.
@export var shot_line_height: float = 0.2

var _orders_root: Node3D
var _preview_root: Node3D
var _attack_root: Node3D
var _spell_root: Node3D
var _order_groups: Dictionary[int, Node3D] = {}
var _state: GameState
var _preview_piece_id: int = -1
## func(piece: Piece, target: Vector2i) -> Array[Vector2i]; an invalid Callable = none (C# null).
var _path_provider: Callable = Callable()


func _ready() -> void:
	_ensure_roots()


## Remembers the game state used for path finding and chain detection in previews.
func set_state(state: GameState) -> void:
	_state = state


## Redraws the committed orders of every current-player piece. path_provider(piece, target) returns the
## rules path (tiles after the piece, ending with target), e.g. TurnController.get_planned_path; it is also
## remembered for later show_preview calls without an explicit path. Omitted (null) = keep the remembered
## provider (C# 2-arg overload); an invalid Callable() = built-in v3 path finding (C# explicit null).
func show_orders(state: GameState, board: BoardView, path_provider: Variant = null) -> void:
	var provider: Callable = _path_provider
	if path_provider != null:
		provider = path_provider
	_ensure_roots()
	_state = state if state != null else _state
	_path_provider = provider
	_clear_children(_orders_root)
	_order_groups.clear()
	if state == null or board == null:
		return
	for piece: Piece in state.get_pieces_of(state.current_player_index):
		if piece.order == null or not piece.is_alive:
			continue
		var path: Variant = null
		if piece.order.move_target != null and provider.is_valid():
			path = provider.call(piece, piece.order.move_target)
		var group: Node3D = _build_group(_orders_root, piece, piece.order.move_target, piece.order.attack_target,
			board, state.board, false, piece.order.order_index + 1, path)
		group.visible = piece.id != _preview_piece_id
		_order_groups[piece.id] = group


## Shows the order currently being planned for a piece (brighter, animated). Hides that piece's
## committed order until clear_preview. move/attack: Vector2i or null. path: explicit move path (tiles
## after the piece, ending with the move target, as returned by TurnController.get_planned_path); an
## empty array = path finding fallback; null (omitted) = use the remembered path provider.
## occupancy defaults to the state of the last show_orders/set_state.
func show_preview(piece: Piece, move: Variant, attack: Variant, board: BoardView, path: Variant = null, occupancy: BoardState = null) -> void:
	if path == null and piece != null and move != null and _path_provider.is_valid():
		path = _path_provider.call(piece, move)
	_ensure_roots()
	clear_preview()
	if piece == null or board == null:
		return
	_preview_piece_id = piece.id
	var committed: Variant = _order_groups.get(piece.id, null)
	if committed != null and is_instance_valid(committed):
		committed.visible = false
	var board_state: BoardState = occupancy
	if board_state == null and _state != null:
		board_state = _state.board
	_build_group(_preview_root, piece, move, attack, board, board_state, true, _preview_number(piece), path)


## Removes the planning preview and shows the piece's committed order again.
func clear_preview() -> void:
	_ensure_roots()
	_clear_children(_preview_root)
	if _preview_piece_id >= 0 and _order_groups.has(_preview_piece_id):
		var committed: Variant = _order_groups[_preview_piece_id]
		if is_instance_valid(committed):
			committed.visible = true
	_preview_piece_id = -1


## Removes all order indicators and every preview (planning, attack and spell area).
func clear_all() -> void:
	_ensure_roots()
	_clear_children(_orders_root)
	_clear_children(_preview_root)
	_clear_children(_attack_root)
	_clear_children(_spell_root)
	_order_groups.clear()
	_preview_piece_id = -1


# ------------------------------------------------------------------ attack consequences preview

## Draws the predicted consequences of one attack (TurnController.predict_attack): friendlies that get
## chain-triggered glow gold, chain shots are dashed lightning arrows (gold = hits a friendly and chains on,
## red = damages an enemy), predicted damage numbers float above victims (skull if lethal), heals (+N),
## Frost (snowflake), push arrows / blocked pushes, Pierce lines and ghost tiles for new tile effects.
## The direct attack arc itself is drawn by show_preview. Replaces the previous attack preview.
func show_attack_preview(preview: ChainPreview, board: BoardView, state: GameState) -> void:
	_ensure_roots()
	clear_attack_preview()
	if preview == null or not preview.is_valid or board == null:
		return
	if state == null:
		state = _state
	var lift := Vector3(0.0, arrow_height + 0.02, 0.0)
	var victims: Dictionary = {}
	var victim_order: Array[int] = []
	var triggered: Dictionary = {}
	for id: int in preview.triggered_piece_ids:
		triggered[id] = true
	var glow_done: Dictionary = {}

	for hit: PredictedHit in preview.hits:
		var a: Vector3 = _local(board.grid_to_world(hit.from)) + lift
		var b: Vector3 = _local(board.grid_to_world(hit.tile)) + lift
		var has_target: bool = hit.target_piece_id >= 0
		var color: Color = chain_color if hit.is_friendly else attack_color
		if hit.is_pierce:
			_add_pierce_line(a, b, has_target)
		elif hit.is_chain and has_target:
			_add_lightning_arrow(a, b, color)
		if has_target and (hit.is_chain or hit.is_pierce):
			_add_marker(_attack_root, b + Vector3(0, -0.035, 0), color, 0, true)
		if not has_target:
			continue
		if hit.is_friendly and triggered.has(hit.target_piece_id) and not glow_done.has(hit.target_piece_id):
			glow_done[hit.target_piece_id] = true
			_add_trigger_glow(_local(board.grid_to_world(hit.tile)))
		var v: Dictionary
		if victims.has(hit.target_piece_id):
			v = victims[hit.target_piece_id]
		else:
			v = { "tile": hit.tile, "hp": 0, "shield": 0, "heal": 0, "frozen": false, "friendly": hit.is_friendly }
			victim_order.append(hit.target_piece_id)
		v["hp"] += hit.hp_lost
		v["shield"] += hit.shield_absorbed
		v["heal"] += hit.healed
		v["frozen"] = v["frozen"] or (hit.effects & HitEffect.FROZEN) != 0
		victims[hit.target_piece_id] = v

	for e: ResolutionEvent in preview.events:
		if e.type == ResolutionEventType.PUSHED:
			_add_push_arrow(_local(board.grid_to_world(e.from)) + lift, _local(board.grid_to_world(e.to)) + lift, false)
		elif e.type == ResolutionEventType.PUSH_BLOCKED:
			var a: Vector3 = _local(board.grid_to_world(e.from)) + lift
			var b: Vector3 = _local(board.grid_to_world(e.to)) + lift
			_add_push_arrow(a, a.lerp(b, 0.62), true)

	for effect: TileEffect in preview.new_tile_effects:
		_add_ghost_tile(_attack_root, board, effect.position, effect.type)

	var killed: Dictionary = {}
	for id: int in preview.killed_piece_ids:
		killed[id] = true
	for id: int in victim_order:
		var v: Dictionary = victims[id]
		var v_tile: Vector2i = v["tile"]
		var v_hp: int = v["hp"]
		var v_shield: int = v["shield"]
		var v_heal: int = v["heal"]
		var v_frozen: bool = v["frozen"]
		var top: Vector3 = _local(board.grid_to_world(v_tile)) + Vector3(0.0, preview_number_height, 0.0)
		var lethal: bool = killed.has(id)
		if v_hp > 0 or v_shield > 0:
			_add_damage_number(top, ("-%d" % v_hp) if v_hp > 0 else ("-%d" % v_shield), damage_splat_color if v_hp > 0 else shield_splat_color, lethal)
		elif lethal:
			_add_damage_number(top, "", damage_splat_color, true)
		if v_heal > 0:
			_add_floating_label(top + Vector3(0.0, 0.36 if v_hp > 0 else 0.0, 0.0), "+%d" % v_heal, heal_color, 64)
		if v_frozen and not lethal:
			_add_icon(top + Vector3(-0.36, -0.05, 0.0), FxIconShape.SNOWFLAKE, Color(0.9, 0.97, 1.0), Color(0.2, 0.5, 0.85, 0.95), 0.28)
		if lethal and state != null:
			var victim: Piece = state.get_piece(id)
			if victim != null:
				_add_tile_tint(_local(board.grid_to_world(v_tile)), Color(1.0, 0.15, 0.1, 0.5), victim.owner_index)


## Removes the attack consequences preview.
func clear_attack_preview() -> void:
	_ensure_roots()
	_clear_children(_attack_root)


## Shows translucent ghosts of the tile effect a tile/area spell would create (lava, wall, healing runes) on
## the given tiles; type null/NONE shows violet target tiles. If occupancy is given, walls are not shown on
## occupied tiles (they cannot be placed there). Replaces the previous spell area preview.
func show_spell_area_preview(tiles: Array, type: Variant, board: BoardView, occupancy: BoardState = null) -> void:
	_ensure_roots()
	clear_spell_area_preview()
	if tiles == null or board == null:
		return
	var t: int = type if type != null else TileEffectType.NONE
	for pos: Vector2i in tiles:
		if t == TileEffectType.WALL and occupancy != null and occupancy.is_occupied(pos):
			_add_icon(_local(board.grid_to_world(pos)) + Vector3(0, 0.6, 0), FxIconShape.CROSS, Color(1.0, 0.4, 0.3), Color(0.15, 0.05, 0.04, 0.85), 0.3, _spell_root)
			continue
		_add_ghost_tile(_spell_root, board, pos, t)


## Removes the spell area preview.
func clear_spell_area_preview() -> void:
	_ensure_roots()
	_clear_children(_spell_root)


# ------------------------------------------------------------------ order groups

func _preview_number(piece: Piece) -> int:
	if piece.order != null:
		return piece.order.order_index + 1
	if _state == null:
		return 0
	var count: int = 0
	for p: Piece in _state.get_pieces_of(piece.owner_index):
		if p.order != null:
			count += 1
	return count + 1


func _build_group(parent: Node3D, piece: Piece, move: Variant, attack: Variant, board: BoardView,
		occupancy: BoardState, preview: bool, number: int, rules_path: Variant = null) -> Node3D:
	var group := Node3D.new()
	group.name = "Order_%d" % piece.id
	parent.add_child(group)
	var start: Vector2i = piece.position
	var from_pos: Vector2i = move if move != null else start
	var lift := Vector3(0.0, arrow_height, 0.0)

	if move != null and move != start:
		var move_pos: Vector2i = move
		var path: Array[Vector2i] = []
		if rules_path != null and rules_path.size() > 0:
			path.append(start)
			path.append_array(rules_path)
		else:
			var found: Variant = _find_rules_path(occupancy, piece, start, move_pos)
			if found == null:
				found = _find_path(occupancy, start, move_pos)
			if found == null:
				found = _straight_path(start, move_pos)
			path = found
		var points: Array[Vector3] = []
		for p: Vector2i in path:
			points.append(_local(board.grid_to_world(p)) + lift)
		var rounded: Array[Vector3] = ArrowMeshBuilder.round_corners(points, corner_radius)
		_add_arrow(group, ArrowMeshBuilder.trim(rounded, 0.34, 0.1), move_color, preview)
		_add_marker(group, _local(board.grid_to_world(move_pos)) + Vector3(0, arrow_height - 0.02, 0), move_color, 1, preview)

		# Ending on a friendly pushes it one tile along the last step.
		var occupant: Piece = occupancy.get_piece_at(move_pos) if occupancy != null else null
		if occupant != null and occupant.id != piece.id and occupant.owner_index == piece.owner_index and path.size() >= 2:
			var dir: Vector2i = path[path.size() - 1] - path[path.size() - 2]
			var dest: Vector2i = move_pos + dir
			var dest_piece: Piece = occupancy.get_piece_at(dest)
			var blocked: bool = not occupancy.is_passable(dest) or (dest_piece != null and dest_piece.owner_index != piece.owner_index)
			var a: Vector3 = _local(board.grid_to_world(move_pos)) + lift
			var b: Vector3 = _local(board.grid_to_world(dest)) + lift
			_add_push_arrow_to(group, a, a.lerp(b, 0.62) if blocked else b, blocked)

	if attack != null:
		var attack_pos: Vector2i = attack
		var target: Piece = occupancy.get_piece_at(attack_pos) if occupancy != null else null
		var chain: bool = target != null and target.owner_index == piece.owner_index and target.id != piece.id
		var color: Color = chain_color if chain else attack_color
		var a: Vector3 = _local(board.grid_to_world(from_pos)) + lift
		var b: Vector3 = _local(board.grid_to_world(attack_pos)) + lift
		var dist: float = a.distance_to(b)
		var height: float = attack_arc_height * clampf(dist * 0.5, 0.6, 1.6)
		var arc: Array[Vector3] = ArrowMeshBuilder.arc(a, b, height, 0.15)
		_add_arrow(group, ArrowMeshBuilder.trim(arc, 0.3, 0.3), color, preview)
		_add_marker(group, b + Vector3(0, -0.015, 0), color, 0, preview)

	if number > 0:
		_add_number_badge(group, _local(board.grid_to_world(start)), number, preview)
	return group


func _add_arrow(group: Node3D, points: Array[Vector3], color: Color, preview: bool, dash: float = 0.0, width_scale: float = 1.0) -> void:
	var width: float = (arrow_width * 1.15 if preview else arrow_width) * width_scale
	var head_w: float = (head_width * 1.1 if preview else head_width) * width_scale
	var mesh: ArrayMesh = ArrowMeshBuilder.build_arrow(points, width, head_length * maxf(0.6, width_scale), head_w)
	if mesh == null:
		return
	var mat: ShaderMaterial = VfxAssets.create_material("order_arrow", 9 if preview else 8)
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("speed", 2.4 if preview else 0.8)
	mat.set_shader_parameter("energy", 2.4 if preview else 1.2)
	mat.set_shader_parameter("opacity", 1.0 if preview else 0.82)
	mat.set_shader_parameter("pulse", 1.0 if preview else 0.0)
	mat.set_shader_parameter("dash", dash)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	group.add_child(mi)


static func _add_marker(group: Node3D, local_pos: Vector3, color: Color, pattern: int, preview: bool) -> void:
	var mat: ShaderMaterial = VfxAssets.create_material("reticle", 7)
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("pattern", pattern)
	mat.set_shader_parameter("opacity", 1.0 if preview else 0.75)
	mat.set_shader_parameter("spin", (2.2 if preview else 1.0) if pattern == 0 else 0.6)
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.95, 0.95)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position = local_pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	group.add_child(mi)


func _add_number_badge(group: Node3D, piece_local: Vector3, number: int, preview: bool) -> void:
	var root := Node3D.new()
	root.name = "OrderNumber"
	root.position = piece_local + Vector3(0.36, 0.24, -0.37)
	group.add_child(root)
	var badge: MeshInstance3D = VfxAssets.create_badge(3, badge_size, badge_color.lightened(0.25) if preview else badge_color, 34)
	root.add_child(badge)
	var label: Label3D = VfxAssets.create_label(str(number), 64, 0.0027 * badge_size / 0.26, Color.WHITE, 12, 36)
	root.add_child(label)
	if preview:
		var tween: Tween = root.create_tween().set_loops()
		tween.tween_property(root, "scale", Vector3.ONE * 1.15, 0.35).set_trans(Tween.TRANS_SINE)
		tween.tween_property(root, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_SINE)


# ------------------------------------------------------------------ attack preview parts

func _add_lightning_arrow(a: Vector3, b: Vector3, color: Color) -> void:
	var dist: float = a.distance_to(b)
	var segments: int = maxi(4, roundi(dist * 5.0))
	var up := Vector3(0.0, shot_line_height, 0.0)
	var zig: Array[Vector3] = ArrowMeshBuilder.zigzag(a + up, b + up, 0.08, segments, a.x * 3.1 + a.z * 1.7)
	_add_arrow(_attack_root, ArrowMeshBuilder.trim(zig, 0.32, 0.3), color, true, 3.2, 0.75)


func _add_pierce_line(a: Vector3, b: Vector3, has_target: bool) -> void:
	var dir: Vector3 = b - a
	var end: Vector3 = b + (dir.normalized() * 0.2 if dir.length_squared() > 0.0001 else Vector3.ZERO)
	var up := Vector3(0.0, shot_line_height + 0.04, 0.0)
	var line: Array[Vector3] = [a + up, end + up]
	_add_arrow(_attack_root, ArrowMeshBuilder.trim(line, 0.3, 0.0), pierce_color if has_target else pierce_color.darkened(0.3), true, 0.0, 0.45)


func _add_push_arrow(a: Vector3, b: Vector3, blocked: bool) -> void:
	_add_push_arrow_to(_attack_root, a, b, blocked)


func _add_push_arrow_to(parent: Node3D, a: Vector3, b: Vector3, blocked: bool) -> void:
	var line: Array[Vector3] = [a + Vector3(0, 0.06, 0), b + Vector3(0, 0.06, 0)]
	var group := Node3D.new()
	group.name = "PushBlocked" if blocked else "Push"
	parent.add_child(group)
	_add_arrow(group, ArrowMeshBuilder.trim(line, 0.22, 0.0 if blocked else 0.12), push_color.darkened(0.25) if blocked else push_color, true, 0.0, 0.85)
	if blocked:
		_add_icon(b + Vector3(0, 0.3, 0), FxIconShape.CROSS, Color(1.0, 0.45, 0.35), Color(0.15, 0.05, 0.04, 0.85), 0.26, group)


func _add_trigger_glow(tile_local: Vector3) -> void:
	var mat: ShaderMaterial = VfxAssets.create_material("highlight", 6)
	mat.set_shader_parameter("color", Color(chain_color.r, chain_color.g, chain_color.b, 0.85))
	mat.set_shader_parameter("pattern", 3)
	mat.set_shader_parameter("pulse_speed", 6.0)
	mat.set_shader_parameter("energy", 3.0)
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	var tile := MeshInstance3D.new()
	tile.name = "TriggerGlow"
	tile.mesh = plane
	tile.material_override = mat
	tile.position = tile_local + Vector3(0, 0.035, 0)
	tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_attack_root.add_child(tile)
	var glow := MeshInstance3D.new()
	glow.mesh = VfxAssets.glow_quad
	glow.scale = Vector3.ONE * 1.3
	glow.position = tile_local + Vector3(0, 0.35, 0)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.set_instance_shader_parameter("tint", Color(chain_color.r, chain_color.g, chain_color.b, 0.35))
	_attack_root.add_child(glow)
	_add_icon(tile_local + Vector3(0.36, 0.62, -0.3), FxIconShape.BOLT, Color(1.0, 0.95, 0.6), Color(0.55, 0.35, 0.05, 0.95), 0.26)


func _add_tile_tint(tile_local: Vector3, color: Color, owner_index: int) -> void:
	var mat: ShaderMaterial = VfxAssets.create_material("highlight", 5)
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("pattern", 1)
	mat.set_shader_parameter("pulse_speed", 5.0 + owner_index * 0.01)
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position = tile_local + Vector3(0, 0.03, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_attack_root.add_child(mi)


func _add_damage_number(local_pos: Vector3, text: String, splat: Color, lethal: bool) -> void:
	var root := Node3D.new()
	root.name = "PredictedDamage"
	root.position = local_pos
	_attack_root.add_child(root)
	if not text.is_empty():
		var badge: MeshInstance3D = VfxAssets.create_badge(4, 0.6, splat, 40)
		root.add_child(badge)
		root.add_child(VfxAssets.create_label(text, 80, 0.0036, Color.WHITE, 16, 42))
	if lethal:
		var x: float = 0.0 if text.is_empty() else 0.4
		var skull: MeshInstance3D = VfxAssets.create_icon(FxIconShape.SKULL, 0.4, Color(0.97, 0.94, 0.88), Color(0.35, 0.04, 0.03, 0.95), true, 43)
		skull.position = Vector3(x, 0.02, 0.0)
		root.add_child(skull)
	var tween: Tween = root.create_tween().set_loops()
	tween.tween_property(root, "scale", Vector3.ONE * 1.1, 0.4).set_trans(Tween.TRANS_SINE)
	tween.tween_property(root, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_SINE)


func _add_floating_label(local_pos: Vector3, text: String, color: Color, size: int) -> void:
	var label: Label3D = VfxAssets.create_label(text, size, 0.0036, color, 16, 42)
	label.position = local_pos
	_attack_root.add_child(label)


func _add_icon(local_pos: Vector3, shape: int, fg: Color, bg: Color, size: float, parent: Node3D = null) -> void:
	var icon: MeshInstance3D = VfxAssets.create_icon(shape, size, fg, bg, true, 41)
	icon.position = local_pos
	(parent if parent != null else _attack_root).add_child(icon)


func _add_ghost_tile(parent: Node3D, board: BoardView, pos: Vector2i, type: int) -> void:
	var ghost := TileEffectVisual.new()
	ghost.setup(type, board.tile_size, true, pos.x * 1.37 + pos.y * 2.11)
	parent.add_child(ghost)
	ghost.position = _local(board.grid_to_world(pos))
	ghost.play_appear()


# ------------------------------------------------------------------ path finding

## v3 move rules path (friendlies passable, enemies/walls block), start..goal inclusive, or null.
static func _find_rules_path(board: BoardState, piece: Piece, start: Vector2i, goal: Vector2i) -> Variant:
	if board == null or piece == null or not board.is_inside(goal):
		return null
	var tail: Variant = board.find_path(start, goal, 64, piece.owner_index)
	if tail == null or tail.size() == 0:
		return null
	var path: Array[Vector2i] = [start]
	path.append_array(tail)
	return path


## Orthogonal shortest path (start..goal inclusive) around occupied tiles, preferring straight runs.
static func _find_path(board: BoardState, start: Vector2i, goal: Vector2i) -> Variant:
	if board == null or not board.is_inside(goal):
		return null
	var dist: Dictionary = { start: 0 }
	var queue: Array[Vector2i] = [start]
	while queue.size() > 0:
		var cur: Vector2i = queue.pop_front()
		if cur == goal:
			break
		for n: Vector2i in GridPos.neighbors(cur):
			if not board.is_inside(n) or dist.has(n) or (board.is_occupied(n) and n != goal):
				continue
			dist[n] = dist[cur] + 1
			queue.append(n)
	if not dist.has(goal):
		return null

	var path: Array[Vector2i] = [goal]
	var current: Vector2i = goal
	var last_dir := Vector2i(0, 0)
	var guard: int = 0
	while current != start:
		if guard >= 256:
			break
		guard += 1
		var want: int = dist[current] - 1
		var best: Vector2i = current
		var found: bool = false
		for d: Vector2i in GridPos.ORTHOGONAL_DIRECTIONS:
			var n: Vector2i = current + d
			if not dist.has(n) or dist[n] != want:
				continue
			if not found or d == last_dir:
				best = n
				found = true
				if d == last_dir:
					break
		if not found:
			return null
		last_dir = best - current
		current = best
		path.append(current)
	path.reverse()
	return path


static func _straight_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [start]
	if start.x != goal.x:
		path.append(Vector2i(goal.x, start.y))
	if start.y != goal.y or path[path.size() - 1] != goal:
		path.append(goal)
	return path


func _local(world: Vector3) -> Vector3:
	return to_local(world) if is_inside_tree() else world


func _ensure_roots() -> void:
	if _orders_root == null:
		_orders_root = Node3D.new()
		_orders_root.name = "Orders"
		add_child(_orders_root)
	if _preview_root == null:
		_preview_root = Node3D.new()
		_preview_root.name = "Preview"
		add_child(_preview_root)
	if _attack_root == null:
		_attack_root = Node3D.new()
		_attack_root.name = "AttackPreview"
		add_child(_attack_root)
	if _spell_root == null:
		_spell_root = Node3D.new()
		_spell_root.name = "SpellPreview"
		add_child(_spell_root)


static func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
