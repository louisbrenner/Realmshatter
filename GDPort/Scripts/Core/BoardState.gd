class_name BoardState
extends RefCounted
## Grid and occupancy. Coordinate convention: x = column (0 = left), y = row (0 = top).
## Deploy ownership: player 0 owns the bottom deploy_rows rows (height-deploy_rows .. height-1)
## and faces up (toward row 0, forward = -y). Player 1 owns the top rows (0 .. deploy_rows-1)
## and faces down (forward = +y).

var _occupancy: Dictionary[Vector2i, Piece] = {}
var _tile_effects: Dictionary[Vector2i, TileEffect] = {}

var width: int = 0
var height: int = 0
var scoring_zone: Rect2i = Rect2i()
var deploy_rows: int = 0


## Merged C# constructors: BoardState.new(config: GameConfig) builds from the config;
## BoardState.new(other: BoardState) copies dimensions and tile effects (occupancy is rebuilt by the
## cloning GameState).
func _init(source: Variant = null) -> void:
	if source is GameConfig:
		var config := source as GameConfig
		width = config.board_width
		height = config.board_height
		scoring_zone = config.scoring_zone
		deploy_rows = config.deploy_rows
	elif source is BoardState:
		var other := source as BoardState
		width = other.width
		height = other.height
		scoring_zone = other.scoring_zone
		deploy_rows = other.deploy_rows
		for key: Vector2i in other._tile_effects:
			_tile_effects[key] = other._tile_effects[key]


## Tiles of an area shape anchored at 'anchor', clipped to the board.
func get_area_tiles(anchor: Vector2i, shape: int) -> Array[Vector2i]:
	var offsets: Array[Vector2i]
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


## All occupied tiles and their pieces (read-only by convention).
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
	if _tile_effects.has(pos):
		return _tile_effects[pos].type
	return TileEffectType.NONE


## True if the tile carries a Wall (impassable, unoccupiable).
func is_wall(pos: Vector2i) -> bool:
	return get_tile_effect_type(pos) == TileEffectType.WALL


## True if the tile is on the board and not a wall (pieces may stand on / walk over it).
func is_passable(pos: Vector2i) -> bool:
	return is_inside(pos) and not is_wall(pos)


func set_tile_effect(effect: TileEffect) -> void:
	_tile_effects[effect.position] = effect


func remove_tile_effect(pos: Vector2i) -> void:
	_tile_effects.erase(pos)


# ------------------------------------------------------------------ movement

## Tiles reachable from 'from' with at most 'movement' orthogonal steps. Excludes the start tile, BFS order.
## mover_owner == null (C# overload without moverOwner): strict variant, paths blocked by ALL occupied
## tiles and walls. mover_owner = player index (move rules v3): FRIENDLY pieces do not block (they can be
## passed and the move may end on them - they get pushed at resolution); enemies and walls block.
func get_reachable_tiles(from: Vector2i, movement: int, mover_owner: Variant = null) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if mover_owner != null:
		for pos: Vector2i in _build_path_tree(from, movement, int(mover_owner)):
			if pos != from:
				result.append(pos)
		return result

	if movement <= 0:
		return result
	var dist: Dictionary[Vector2i, int] = {from: 0}
	var queue: Array[Vector2i] = [from]
	var head: int = 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var d: int = dist[cur]
		if d >= movement:
			continue
		for next: Vector2i in GridPos.neighbors(cur):
			if not is_passable(next) or is_occupied(next) or dist.has(next):
				continue
			dist[next] = d + 1
			result.append(next)
			queue.append(next)
	return result


## True if 'to' equals 'from' or is reachable within 'movement' steps (strict variant).
func can_reach(from: Vector2i, to: Vector2i, movement: int) -> bool:
	return from == to or get_reachable_tiles(from, movement).has(to)


## Shortest orthogonal path (move rules v3, see get_reachable_tiles with mover_owner) from 'from' to 'to'
## within 'movement' steps. Returns the tiles AFTER 'from' (ending with 'to'), an empty array if
## from == to, or null if unreachable. Deterministic (neighbor order right, left, down, up).
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


## BFS parent map (start maps to itself). Friendlies passable, enemies / walls block.
func _build_path_tree(from: Vector2i, movement: int, mover_owner: int) -> Dictionary[Vector2i, Vector2i]:
	var parents: Dictionary[Vector2i, Vector2i] = {from: from}
	if movement <= 0:
		return parents
	var dist: Dictionary[Vector2i, int] = {from: 0}
	var queue: Array[Vector2i] = [from]
	var head: int = 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var d: int = dist[cur]
		if d >= movement:
			continue
		for next: Vector2i in GridPos.neighbors(cur):
			if not is_passable(next) or dist.has(next):
				continue
			var occupant: Piece = get_piece_at(next)
			if occupant != null and occupant.owner_index != mover_owner:
				continue
			dist[next] = d + 1
			parents[next] = cur
			queue.append(next)
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
