class_name MapGenerator
extends RefCounted
## Random battlefield at game start. Every map has ONE theme so it stays readable:
## Open Field (nothing), Riverlands (a river on each side with bridges; water slows movement), Volcanic Wastes
## (lava patches), Ancient Ruins (breakable rock walls) or Sacred Springs (healing pools). The amount varies per
## map, from a few tiles up to about every third tile of the open middle. Maps are point-symmetric (rotated 180°),
## so both players face the same ground; deploy rows and the crown field stay free, and every map keeps a
## walkable route from each player's back rows to the crown. A river or wall that runs through the crown field is
## only drawn there (BoardState.decor: a ford / low rubble) - the crown always plays as plain ground.


## Name and one-line description of a generated map (C# record struct).
class MapInfo:
	var name: String
	var description: String

	func _init(p_name: String = "", p_description: String = "") -> void:
		name = p_name
		description = p_description


const MAX_ATTEMPTS: int = 30
const MIN_DENSITY: float = 0.04
const MAX_DENSITY: float = 0.33


## Generates terrain and permanent map effects on the state's board (uses state.random).
static func generate(state: GameState) -> MapInfo:
	var rng: RandomNumberGenerator = state.random
	var board: BoardState = state.board
	var roll: int = rng.randi_range(0, 99)
	var density: float = MIN_DENSITY + rng.randf() * (MAX_DENSITY - MIN_DENSITY)
	for attempt: int in MAX_ATTEMPTS:
		var terrain: Dictionary[Vector2i, int] = {}
		var effects: Dictionary[Vector2i, int] = {}
		var decor: Dictionary[Vector2i, int] = {}
		var info: MapInfo
		if roll < 15:
			info = MapInfo.new("Open Field", "Clear ground - nothing in the way.")
		elif roll < 40:
			info = MapInfo.new("Riverlands", "Rivers slow every unit that wades through. Cross at the bridges.")
			_build_rivers(board, rng, density, terrain, decor)
		elif roll < 60:
			info = MapInfo.new("Volcanic Wastes", "Lava fields burn whoever ends a turn on them.")
			for p: Vector2i in _blobs(board, rng, density, 1, 4, terrain, effects):
				effects[p] = TileEffectType.LAVA
		elif roll < 85:
			info = MapInfo.new("Ancient Ruins", "Crumbling rock walls block the way - break them with attacks.")
			for p: Vector2i in _segments(board, rng, density * 0.8, terrain, effects, decor):
				terrain[p] = TerrainType.ROCK
		else:
			info = MapInfo.new("Sacred Springs", "Healing pools mend whoever rests in them.")
			for p: Vector2i in _blobs(board, rng, density * 0.45, 1, 3, terrain, effects):
				effects[p] = TileEffectType.HEALING
		if not _is_connected(board, terrain) and attempt < MAX_ATTEMPTS - 1:
			continue
		_commit(state, terrain, effects, decor, info.name)
		return info
	board.clear_map()
	return MapInfo.new("Open Field", "Clear ground - nothing in the way.")


static func _commit(state: GameState, terrain: Dictionary[Vector2i, int], effects: Dictionary[Vector2i, int],
		decor: Dictionary[Vector2i, int], name: String) -> void:
	var board: BoardState = state.board
	board.clear_map()
	for k: Vector2i in decor:
		board.set_decor(k, decor[k])
	for k: Vector2i in terrain:
		var t: int = terrain[k]
		board.set_terrain(k, t, maxi(1, state.config.rock_hp) if t == TerrainType.ROCK else 0)
	for k: Vector2i in effects:
		board.set_tile_effect(TileEffect.new(effects[k], k, -1, 0, TileEffect.PERMANENT, name))


## Point mirror (rotation by 180°) of a tile.
static func _mirror(b: BoardState, p: Vector2i) -> Vector2i:
	return Vector2i(b.width - 1 - p.x, b.height - 1 - p.y)


## Open middle tiles where map features may go: no deploy rows, no crown field.
static func _is_eligible(b: BoardState, p: Vector2i) -> bool:
	return b.is_inside(p) and p.y >= b.deploy_rows and p.y < b.height - b.deploy_rows and not b.is_in_hot_zone(p)


static func _eligible_count(b: BoardState) -> int:
	var n: int = 0
	for y: int in b.height:
		for x: int in b.width:
			n += 1 if _is_eligible(b, Vector2i(x, y)) else 0
	return n


static func _is_free(b: BoardState, p: Vector2i, terrain: Dictionary[Vector2i, int], effects: Dictionary[Vector2i, int]) -> bool:
	return _is_eligible(b, p) and not terrain.has(p) and not effects.has(p)


## Random patches of 'min_size'..'max_size' tiles (plus their mirror images) until the density is reached.
static func _blobs(b: BoardState, rng: RandomNumberGenerator, density: float, min_size: int, max_size: int,
		terrain: Dictionary[Vector2i, int], effects: Dictionary[Vector2i, int]) -> Array[Vector2i]:
	var placed: Dictionary[Vector2i, bool] = {}
	var target: int = roundi(density * _eligible_count(b))
	var tries: int = 0
	while placed.size() < target and tries < 400:
		var seed_pos := Vector2i(rng.randi_range(0, b.width - 1), rng.randi_range(b.deploy_rows, b.height / 2 - 1))
		if not _is_free(b, seed_pos, terrain, effects) or placed.has(seed_pos):
			tries += 1
			continue
		var blob: Array[Vector2i] = [seed_pos]
		var size: int = rng.randi_range(min_size, max_size)
		var grow: int = 0
		while grow < size * 4 and blob.size() < size:
			var from: Vector2i = blob[rng.randi_range(0, blob.size() - 1)]
			var around: Array[Vector2i] = GridPos.neighbors(from)
			var next: Vector2i = around[rng.randi_range(0, around.size() - 1)]
			if _is_free(b, next, terrain, effects) and not placed.has(next) and not blob.has(next):
				blob.append(next)
			grow += 1
		for p: Vector2i in blob:
			placed[p] = true
			var m: Vector2i = _mirror(b, p)
			if _is_free(b, m, terrain, effects):
				placed[m] = true
		tries += 1
	var result: Array[Vector2i] = []
	result.assign(placed.keys())
	return result


## Short straight wall segments (1-3 tiles, plus mirror images) until the density is reached.
static func _segments(b: BoardState, rng: RandomNumberGenerator, density: float, terrain: Dictionary[Vector2i, int],
		effects: Dictionary[Vector2i, int], decor: Dictionary[Vector2i, int]) -> Array[Vector2i]:
	var placed: Dictionary[Vector2i, bool] = {}
	var target: int = roundi(density * _eligible_count(b))
	var tries: int = 0
	while placed.size() < target and tries < 400:
		var start := Vector2i(rng.randi_range(0, b.width - 1), rng.randi_range(b.deploy_rows, b.height / 2 - 1))
		var horizontal: bool = rng.randi_range(0, 1) == 0
		var length: int = rng.randi_range(1, 3)
		var segment: Array[Vector2i] = []
		for i: int in length:
			var p: Vector2i = Vector2i(start.x + i, start.y) if horizontal else Vector2i(start.x, start.y + i)
			if b.is_in_hot_zone(p):
				# The wall runs on through the crown field as low rubble only.
				decor[p] = TerrainType.ROCK
				decor[_mirror(b, p)] = TerrainType.ROCK
				continue
			if not _is_free(b, p, terrain, effects) or placed.has(p):
				break
			segment.append(p)
		for p: Vector2i in segment:
			placed[p] = true
			placed[_mirror(b, p)] = true
		tries += 1
	var result: Array[Vector2i] = []
	result.assign(placed.keys())
	return result


## One winding river across the board in front of each player (the second is the mirror image of the first),
## one or two tiles wide depending on the density, with 2-3 bridges each.
static func _build_rivers(b: BoardState, rng: RandomNumberGenerator, density: float, terrain: Dictionary[Vector2i, int],
		decor: Dictionary[Vector2i, int]) -> void:
	if rng.randi_range(0, 2) == 0:
		_build_central_river(b, rng, terrain, decor)
		return
	var wide: bool = density > 0.2
	var min_row: int = b.deploy_rows + 1
	var max_row: int = b.height / 2 - (3 if wide else 2)
	var row: int = rng.randi_range(min_row, max_row)
	var river: Array[Vector2i] = []
	var previous: int = row
	for x: int in b.width:
		if x > 0 and rng.randi_range(0, 2) == 0:
			row = clampi(row + (-1 if rng.randi_range(0, 1) == 0 else 1), min_row, max_row)
		# Keep the river connected orthogonally where it steps up or down.
		for y: int in range(mini(row, previous), maxi(row, previous) + 1):
			river.append(Vector2i(x, y))
			if wide:
				river.append(Vector2i(x, y + 1))
		previous = row
	var bridges: int = rng.randi_range(2, 3)
	var bridge_columns: Dictionary[int, bool] = {}
	var tries: int = 0
	while bridge_columns.size() < bridges and tries < 50:
		var c: int = rng.randi_range(1, b.width - 2)
		if not bridge_columns.has(c - 1) and not bridge_columns.has(c + 1):
			bridge_columns[c] = true
		tries += 1
	for p: Vector2i in river:
		if not b.is_inside(p) or b.is_in_hot_zone(p):
			continue
		var type: int = TerrainType.BRIDGE if bridge_columns.has(p.x) else TerrainType.WATER
		terrain[p] = type
		terrain[_mirror(b, p)] = type


## One straight river through the middle of the board (the two centre rows). Where it crosses the crown field it
## becomes a shallow ford (decoration only); 1-2 bridges on each side.
static func _build_central_river(b: BoardState, rng: RandomNumberGenerator, terrain: Dictionary[Vector2i, int],
		decor: Dictionary[Vector2i, int]) -> void:
	var top: int = b.height / 2 - 1
	var bridge_columns: Dictionary[int, bool] = {}
	var bridges: int = rng.randi_range(1, 2)
	var tries: int = 0
	while bridge_columns.size() < bridges and tries < 50:
		var c: int = rng.randi_range(0, b.width / 2 - 1)
		var near_crown: bool = c >= b.hot_zone.position.x - 1 and c < b.hot_zone.end.x + 1
		if not near_crown and not bridge_columns.has(c - 1) and not bridge_columns.has(c + 1):
			bridge_columns[c] = true
			bridge_columns[b.width - 1 - c] = true
		tries += 1
	for x: int in b.width:
		for y: int in range(top, top + 2):
			var p := Vector2i(x, y)
			if b.is_in_hot_zone(p):
				decor[p] = TerrainType.WATER
				continue
			terrain[p] = TerrainType.BRIDGE if bridge_columns.has(x) else TerrainType.WATER


## True if every back-row tile of player 0 can walk (ignoring pieces) to the crown field and to the enemy rows.
static func _is_connected(b: BoardState, terrain: Dictionary[Vector2i, int]) -> bool:
	var seen: Dictionary[Vector2i, bool] = {}
	var queue: Array[Vector2i] = []
	for x: int in b.width:
		var start := Vector2i(x, b.height - 1)
		seen[start] = true
		queue.append(start)
	var head: int = 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		for next: Vector2i in GridPos.neighbors(cur):
			if not b.is_inside(next) or seen.has(next) or terrain.get(next, TerrainType.NONE) == TerrainType.ROCK:
				continue
			seen[next] = true
			queue.append(next)
	for y: int in b.height:
		for x: int in b.width:
			var p := Vector2i(x, y)
			var needed: bool = b.is_in_hot_zone(p) or y == 0
			if needed and not seen.has(p):
				return false
			# No pocket of open ground may be cut off entirely.
			if not seen.has(p) and terrain.get(p, TerrainType.NONE) != TerrainType.ROCK:
				return false
	return true
