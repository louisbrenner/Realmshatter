class_name BoardState
extends RefCounted
## Grid and occupancy. Coordinate convention: x = column (0 = left), y = row (0 = top).
## Deploy ownership: player 0 owns the bottom deploy_rows rows (height-deploy_rows .. height-1)
## and faces up (toward row 0, forward = -y). Player 1 owns the top rows (0 .. deploy_rows-1)
## and faces down (forward = +y).

var _occupancy: Dictionary[Vector2i, Piece] = {}
var _tile_effects: Dictionary[Vector2i, TileEffect] = {}
var _terrain: Dictionary[Vector2i, int] = {}
var _terrain_hp: Dictionary[Vector2i, int] = {}
var _decor: Dictionary[Vector2i, int] = {}
var _traps: Dictionary[Vector2i, Trap] = {}
var _trap_serial: int = 0

var width: int = 0
var height: int = 0
var scoring_zone: Rect2i = Rect2i()
## The crown field inside the scoring zone (worth hot_zone_points per piece).
var hot_zone: Rect2i = Rect2i()
var hot_zone_points: int = 0
var deploy_rows: int = 0
## Movement spent to enter a Water tile.
var water_move_cost: int = 1


func _init(config: GameConfig = null) -> void:
	if config == null:
		return # used by copy_of
	water_move_cost = maxi(1, config.water_move_cost)
	width = config.board_width
	height = config.board_height
	scoring_zone = config.scoring_zone
	hot_zone = config.hot_zone
	hot_zone_points = config.hot_zone_points
	deploy_rows = config.deploy_rows


## Copies dimensions and tile effects (occupancy is rebuilt by the cloning GameState). C# internal copy constructor.
static func copy_of(other: BoardState) -> BoardState:
	var b := BoardState.new()
	b.width = other.width
	b.height = other.height
	b.scoring_zone = other.scoring_zone
	b.hot_zone = other.hot_zone
	b.hot_zone_points = other.hot_zone_points
	b.deploy_rows = other.deploy_rows
	b.water_move_cost = other.water_move_cost
	for k: Vector2i in other._tile_effects:
		b._tile_effects[k] = other._tile_effects[k]
	for k: Vector2i in other._terrain:
		b._terrain[k] = other._terrain[k]
	for k: Vector2i in other._terrain_hp:
		b._terrain_hp[k] = other._terrain_hp[k]
	for k: Vector2i in other._decor:
		b._decor[k] = other._decor[k]
	for k: Vector2i in other._traps:
		b._traps[k] = other._traps[k]
	b._trap_serial = other._trap_serial
	return b


## Tiles of an area shape anchored at 'anchor', clipped to the board.
func get_area_tiles(anchor: Vector2i, shape: int) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	match shape:
		AreaShape.PLUS:
			offsets = [Vector2i(0, 0), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]
		AreaShape.ROW3:
			offsets = [Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0)]
		AreaShape.COLUMN3:
			offsets = [Vector2i(0, -1), Vector2i(0, 0), Vector2i(0, 1)]
		AreaShape.SQUARE2:
			offsets = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
		_:
			offsets = [Vector2i(0, 0)]
	var result: Array[Vector2i] = []
	for o: Vector2i in offsets:
		var p: Vector2i = anchor + o
		if is_inside(p):
			result.append(p)
	return result


## All occupied tiles and their pieces (read-only).
var occupancy: Dictionary[Vector2i, Piece]:
	get:
		return _occupancy


## True if the position lies on the board.
func is_inside(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < width and pos.y < height


## True if a piece stands on the tile.
func is_occupied(pos: Vector2i) -> bool:
	return _occupancy.has(pos)


## Returns the piece on the tile, or null.
func get_piece_at(pos: Vector2i) -> Piece:
	return _occupancy.get(pos, null)


## True if the tile is inside the scoring zone.
func is_in_scoring_zone(pos: Vector2i) -> bool:
	return pos.x >= scoring_zone.position.x and pos.x < scoring_zone.end.x \
		and pos.y >= scoring_zone.position.y and pos.y < scoring_zone.end.y


## True if the tile is on the crown field (inside the scoring zone, worth more VP).
func is_in_hot_zone(pos: Vector2i) -> bool:
	return hot_zone.size.x > 0 and hot_zone.size.y > 0 and is_in_scoring_zone(pos) \
		and pos.x >= hot_zone.position.x and pos.x < hot_zone.end.x \
		and pos.y >= hot_zone.position.y and pos.y < hot_zone.end.y


## VP a piece on this tile scores at its owner's turn start: hot_zone_points on the crown field, 1 in the zone, else 0.
func score_value(pos: Vector2i) -> int:
	return hot_zone_points if is_in_hot_zone(pos) else (1 if is_in_scoring_zone(pos) else 0)


## True if the tile is in the given player's deploy rows (player 0 bottom, player 1 top).
func is_in_deploy_zone(player_index: int, pos: Vector2i) -> bool:
	if not is_inside(pos):
		return false
	return pos.y >= height - deploy_rows if player_index == 0 else pos.y < deploy_rows


## Forward row direction of a player: -1 for player 0 (up), +1 for player 1 (down).
static func forward_direction(player_index: int) -> int:
	return -1 if player_index == 0 else 1


## Column offset of the player's LEFT side, as seen from that player's facing.
## Player 0 faces up, so left = -x; player 1 faces down, so left = +x.
static func left_direction(player_index: int) -> int:
	return -1 if player_index == 0 else 1


# ------------------------------------------------------------------ tile effects

## All active tile effects by position (at most one per tile).
var tile_effects: Dictionary[Vector2i, TileEffect]:
	get:
		return _tile_effects


## The tile effect on pos, or null.
func get_tile_effect(pos: Vector2i) -> TileEffect:
	return _tile_effects.get(pos, null)


## Type of the tile effect on pos (NONE if there is none).
func get_tile_effect_type(pos: Vector2i) -> int:
	var e: TileEffect = _tile_effects.get(pos, null)
	return e.type if e != null else TileEffectType.NONE


## True if the tile carries a Wall or Rubble, or is a Rock (impassable, unoccupiable).
func is_wall(pos: Vector2i) -> bool:
	var t: int = get_tile_effect_type(pos)
	return t == TileEffectType.WALL or t == TileEffectType.RUBBLE or get_terrain(pos) == TerrainType.ROCK


## True if the tile is on the board and not a wall (pieces may stand on / walk over it).
func is_passable(pos: Vector2i) -> bool:
	return is_inside(pos) and not is_wall(pos)


func set_tile_effect(effect: TileEffect) -> void:
	_tile_effects[effect.position] = effect


func remove_tile_effect(pos: Vector2i) -> void:
	_tile_effects.erase(pos)


# ------------------------------------------------------------------ terrain

## All terrain tiles (water, bridges, rocks) by position (TerrainType values).
var terrain: Dictionary[Vector2i, int]:
	get:
		return _terrain


## Terrain of the tile (NONE = plain ground).
func get_terrain(pos: Vector2i) -> int:
	return _terrain.get(pos, TerrainType.NONE)


## Purely visual terrain (no rules): where a river or a ruined wall runs through the crown field it is shown as
## a shallow ford / low rubble there, but the tiles play as plain ground.
var decor: Dictionary[Vector2i, int]:
	get:
		return _decor


func set_decor(pos: Vector2i, type: int) -> void:
	if type == TerrainType.NONE:
		_decor.erase(pos)
	else:
		_decor[pos] = type


## All hidden traps by tile (the view shows only the viewer's own ones).
var traps: Dictionary[Vector2i, Trap]:
	get:
		return _traps


## The trap on the tile, or null.
func get_trap(pos: Vector2i) -> Trap:
	return _traps.get(pos, null)


func add_trap(pos: Vector2i, owner: int, type: int, source_piece_id: int) -> Trap:
	_trap_serial += 1
	var trap := Trap.new(pos, owner, type, source_piece_id, _trap_serial)
	_traps[pos] = trap
	return trap


func remove_trap(pos: Vector2i) -> void:
	_traps.erase(pos)


## Remaining hit points of a Rock (0 for other tiles).
func get_terrain_hp(pos: Vector2i) -> int:
	return _terrain_hp.get(pos, 0)


## Movement needed to step onto the tile (Water costs water_move_cost, Mud 2, everything else 1).
func move_cost(pos: Vector2i) -> int:
	if get_terrain(pos) == TerrainType.WATER:
		return water_move_cost
	return 2 if get_tile_effect_type(pos) == TileEffectType.MUD else 1


func set_terrain(pos: Vector2i, type: int, hp: int = 0) -> void:
	if type == TerrainType.NONE:
		_terrain.erase(pos)
		_terrain_hp.erase(pos)
		return
	_terrain[pos] = type
	if hp > 0:
		_terrain_hp[pos] = hp
	else:
		_terrain_hp.erase(pos)


## Damages a Rock; at 0 HP it crumbles to plain ground. Returns the remaining HP (-1 if no rock).
func damage_rock(pos: Vector2i, amount: int) -> int:
	if get_terrain(pos) != TerrainType.ROCK:
		return -1
	var hp: int = maxi(0, get_terrain_hp(pos) - maxi(0, amount))
	if hp <= 0:
		set_terrain(pos, TerrainType.NONE)
	else:
		_terrain_hp[pos] = hp
	return hp


## Removes all terrain and permanent map effects (the map generator starts from a clean board).
func clear_map() -> void:
	_terrain.clear()
	_terrain_hp.clear()
	_decor.clear()
	var permanent: Array[Vector2i] = []
	for k: Vector2i in _tile_effects:
		if _tile_effects[k].is_permanent:
			permanent.append(k)
	for pos: Vector2i in permanent:
		_tile_effects.erase(pos)


# ------------------------------------------------------------------ movement

## Tiles reachable from 'from' with at most 'movement' movement. Excludes the start tile. BFS order.
## mover_owner -2 (default): strict variant, every piece blocks. Otherwise move rules (v3): FRIENDLY pieces of
## mover_owner do not block (they can be passed and the move may end on them - they get pushed at resolution);
## enemies and walls block. Merges both C# overloads.
func get_reachable_tiles(from: Vector2i, movement: int, mover_owner: int = -2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for pos: Vector2i in _build_path_tree(from, movement, mover_owner):
		if pos != from:
			result.append(pos)
	return result


## True if 'to' equals 'from' or is reachable within 'movement' steps (strict variant).
func can_reach(from: Vector2i, to: Vector2i, movement: int) -> bool:
	return from == to or get_reachable_tiles(from, movement).has(to)


## Shortest orthogonal path (move rules v3, see get_reachable_tiles with mover_owner) from 'from' to 'to'
## within 'movement' steps. Returns an Array[Vector2i] of the tiles AFTER 'from' (ending with 'to'), an empty
## array if from == to, or null if unreachable. Deterministic (neighbor order right, left, down, up).
func find_path(from: Vector2i, to: Vector2i, movement: int, mover_owner: int) -> Variant:
	if from == to:
		var empty: Array[Vector2i] = []
		return empty
	var parents: Dictionary[Vector2i, Vector2i] = _build_path_tree(from, movement, mover_owner)
	if not parents.has(to):
		return null
	var path: Array[Vector2i] = []
	var cur: Vector2i = to
	while cur != from:
		path.append(cur)
		cur = parents[cur]
	path.reverse()
	return path


## Cheapest-path parent map (start maps to itself; Dijkstra, entering Water costs water_move_cost). Friendlies
## of 'mover_owner' are passable, enemies / buildings / walls block (mover_owner -2: every piece blocks).
## Deterministic: ties keep the first found path (neighbor order right, left, down, up).
func _build_path_tree(from: Vector2i, movement: int, mover_owner: int) -> Dictionary[Vector2i, Vector2i]:
	var parents: Dictionary[Vector2i, Vector2i] = {from: from}
	if movement <= 0:
		return parents
	var dist: Dictionary[Vector2i, int] = {from: 0}
	var open: Array[Vector2i] = [from]
	var done: Dictionary[Vector2i, bool] = {}
	while open.size() > 0:
		var best: int = 0
		for i: int in range(1, open.size()):
			if dist[open[i]] < dist[open[best]]:
				best = i
		var cur: Vector2i = open[best]
		open.remove_at(best)
		if done.has(cur):
			continue
		done[cur] = true
		for next: Vector2i in GridPos.neighbors(cur):
			if not is_passable(next) or done.has(next):
				continue
			var occupant: Piece = get_piece_at(next)
			if occupant != null and (mover_owner == -2 or occupant.owner_index != mover_owner or occupant.is_building):
				continue
			var nd: int = dist[cur] + move_cost(next)
			if nd > movement or (dist.has(next) and dist[next] <= nd):
				continue
			dist[next] = nd
			parents[next] = cur
			open.append(next)
	return parents


## Tiles with Manhattan distance 1..range from 'center' that are on the board.
func get_tiles_in_range(center: Vector2i, range_: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dy: int in range(-range_, range_ + 1):
		for dx: int in range(-range_, range_ + 1):
			var d: int = absi(dx) + absi(dy)
			if d == 0 or d > range_:
				continue
			var pos := Vector2i(center.x + dx, center.y + dy)
			if is_inside(pos):
				result.append(pos)
	return result


## True if 'target' is on the board and within Manhattan distance 1..range.
func is_in_attack_range(from: Vector2i, target: Vector2i, range_: int) -> bool:
	var d: int = GridPos.manhattan_distance(from, target)
	return is_inside(target) and d >= 1 and d <= range_


func place(piece: Piece, pos: Vector2i) -> void:
	_occupancy[pos] = piece
	piece.position = pos


func move_piece(piece: Piece, to: Vector2i) -> void:
	_occupancy.erase(piece.position)
	_occupancy[to] = piece
	piece.position = to


func remove(piece: Piece) -> void:
	if _occupancy.has(piece.position) and _occupancy[piece.position] == piece:
		_occupancy.erase(piece.position)
