class_name TownMap
extends Node2D
## The small town, drawn procedurally: grass with flowers, dirt roads, a cobblestone plaza with a fountain, one
## house per clan (roof and banner in the clan colour, an enterable door with the hall's duel progress), market
## stalls, trees and a fence around the map. Creates static collision bodies for everything solid. Purely visual +
## collision; entering the halls is handled by OverworldMain.


## A clan house: wall rectangle and clan.
class House:
	var body: Rect2
	var clan: int

	func _init(p_body: Rect2 = Rect2(), p_clan: int = 0) -> void:
		body = p_body
		clan = p_clan


## A market stall: counter rectangle and awning colour.
class Stall:
	var counter: Rect2
	var color: Color

	func _init(p_counter: Rect2 = Rect2(), p_color: Color = Color.WHITE) -> void:
		counter = p_counter
		color = p_color


## Size of the walkable town in pixels.
const MAP_SIZE := Vector2(1920, 1280)
const PLAZA_CENTER := Vector2(960, 640)
const PLAZA_RADIUS := 170.0
const FOUNTAIN_RADIUS := 58.0

const GRASS := Color(0.36, 0.55, 0.27)
const GRASS_DARK := Color(0.29, 0.46, 0.22)
const DIRT := Color(0.62, 0.5, 0.34)
const DIRT_EDGE := Color(0.5, 0.39, 0.26)
const COBBLE := Color(0.62, 0.6, 0.56)
const COBBLE_DARK := Color(0.47, 0.45, 0.42)
const WOOD := Color(0.45, 0.29, 0.16)
const WOOD_DARK := Color(0.3, 0.18, 0.09)
const WALL := Color(0.86, 0.8, 0.68)
const WATER := Color(0.32, 0.6, 0.88)

var _houses: Array[House] = [
	House.new(Rect2(200, 230, 240, 140), Clan.FIRE),
	House.new(Rect2(1480, 230, 240, 140), Clan.HEALING),
	House.new(Rect2(200, 880, 240, 140), Clan.FROST),
	House.new(Rect2(1480, 880, 240, 140), Clan.STORM),
	House.new(Rect2(1080, 170, 240, 140), Clan.STONE),
]

var _stalls: Array[Stall] = []
var _reserved: Array[Vector2] = []
## Clan -> {"beaten": int, "total": int}.
var _progress: Dictionary = {}
## {"pos": Vector2, "radius": float, "shade": float}
var _trees: Array[Dictionary] = []
## {"pos": Vector2, "color": Color}
var _flowers: Array[Dictionary] = []
## {"pos": Vector2, "size": float}
var _tufts: Array[Dictionary] = []
var _time: float = 0.0

## Clan houses (for placing NPCs).
var houses: Array[House]:
	get:
		return _houses

## House whose door glows (the player stands in front of it), or Clan.NONE.
var highlighted_door: int = Clan.NONE


## Where the player stands in front of a house's door (just below the door step).
static func door_of(h: House) -> Vector2:
	return Vector2(h.body.get_center().x, h.body.end.y + 18.0)


## Keeps trees and props away from a spot (an NPC stands there). Call before the node is ready.
func reserve_spot(spot: Vector2) -> void:
	_reserved.append(spot)


## Shows "beaten / total" duel stars on a house's door sign.
func set_house_progress(clan: int, beaten: int, total: int) -> void:
	_progress[clan] = {"beaten": beaten, "total": total}
	queue_redraw()


## Registers a market stall (counter drawn below the vendor, solid). Call before the node is ready.
func add_stall(vendor_position: Vector2, color: Color) -> void:
	_stalls.append(Stall.new(Rect2(vendor_position.x - 70, vendor_position.y + 18, 140, 42), color))


func _ready() -> void:
	z_index = -10
	_generate_scenery()
	_build_collision()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


## True if a point is on a road, the plaza or near a building (no trees / props there).
func _is_busy(p: Vector2, margin: float) -> bool:
	if absf(p.y - 640) < 60 + margin or absf(p.x - 960) < 60 + margin:
		return true
	if p.distance_to(PLAZA_CENTER) < PLAZA_RADIUS + 40 + margin:
		return true
	for h: House in _houses:
		if h.body.grow(90 + margin).has_point(p):
			return true
	for r: Vector2 in _reserved:
		if r.distance_to(p) < 50 + margin:
			return true
	for s: Stall in _stalls:
		var stall_area := Rect2(s.counter.position - Vector2(0, 100), s.counter.size + Vector2(0, 100))
		if stall_area.grow(60 + margin).has_point(p):
			return true
	return p.x < 60 or p.y < 60 or p.x > MAP_SIZE.x - 60 or p.y > MAP_SIZE.y - 60


func _generate_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 400:
		if _trees.size() >= 46:
			break
		var p := Vector2(rng.randi_range(70, int(MAP_SIZE.x) - 70 - 1), rng.randi_range(70, int(MAP_SIZE.y) - 70 - 1))
		if _is_busy(p, 10):
			continue
		var clash: bool = false
		for t: Dictionary in _trees:
			clash = clash or (t["pos"] as Vector2).distance_to(p) < 70
		if not clash:
			_trees.append({"pos": p, "radius": 22.0 + rng.randf() * 10.0, "shade": rng.randf()})
	var petals: Array[Color] = [Color(1.0, 0.85, 0.3), Color(1.0, 0.5, 0.6), Color(0.85, 0.85, 1.0), Color(1.0, 1.0, 1.0)]
	for i in 260:
		var p := Vector2(rng.randi_range(40, int(MAP_SIZE.x) - 40 - 1), rng.randi_range(40, int(MAP_SIZE.y) - 40 - 1))
		if not _is_busy(p, -40):
			_flowers.append({"pos": p, "color": petals[rng.randi_range(0, petals.size() - 1)]})
	for i in 700:
		var p := Vector2(rng.randi_range(0, int(MAP_SIZE.x) - 1), rng.randi_range(0, int(MAP_SIZE.y) - 1))
		_tufts.append({"pos": p, "size": 3.0 + rng.randf() * 4.0})


func _build_collision() -> void:
	var body := StaticBody2D.new()
	body.name = "Solid"
	add_child(body)
	var rect := func(r: Rect2) -> void:
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = r.size
		shape.shape = box
		shape.position = r.get_center()
		body.add_child(shape)
	var circle := func(c: Vector2, radius: float) -> void:
		var shape := CollisionShape2D.new()
		var round_shape := CircleShape2D.new()
		round_shape.radius = radius
		shape.shape = round_shape
		shape.position = c
		body.add_child(shape)
	# Map border (fence).
	rect.call(Rect2(-40, -40, MAP_SIZE.x + 80, 64))
	rect.call(Rect2(-40, MAP_SIZE.y - 24, MAP_SIZE.x + 80, 64))
	rect.call(Rect2(-40, -40, 64, MAP_SIZE.y + 80))
	rect.call(Rect2(MAP_SIZE.x - 24, -40, 64, MAP_SIZE.y + 80))
	for h: House in _houses:
		rect.call(Rect2(h.body.position + Vector2(0, -50), h.body.size + Vector2(0, 50)))
	for s: Stall in _stalls:
		rect.call(s.counter)
	for t: Dictionary in _trees:
		var radius: float = t["radius"]
		circle.call((t["pos"] as Vector2) + Vector2(0, radius * 0.5), radius * 0.55)
	circle.call(PLAZA_CENTER, FOUNTAIN_RADIUS)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), GRASS)
	for t: Dictionary in _tufts:
		var p: Vector2 = t["pos"]
		var s: float = t["size"]
		draw_line(p, p + Vector2(-1.5, -s), GRASS_DARK, 1.5)
		draw_line(p, p + Vector2(1.5, -s * 0.8), GRASS_DARK, 1.5)

	# Roads.
	draw_rect(Rect2(40, 596, MAP_SIZE.x - 80, 88), DIRT_EDGE)
	draw_rect(Rect2(40, 600, MAP_SIZE.x - 80, 80), DIRT)
	draw_rect(Rect2(916, 40, 88, MAP_SIZE.y - 80), DIRT_EDGE)
	draw_rect(Rect2(920, 40, 80, MAP_SIZE.y - 80), DIRT)
	for h: House in _houses:
		# Side path from the house to the main road.
		var cx: float = h.body.get_center().x
		if h.body.end.y < 600:
			draw_rect(Rect2(cx - 26, h.body.end.y, 52, 600 - h.body.end.y), DIRT)
		else:
			draw_rect(Rect2(cx - 26, 680, 52, h.body.position.y - 680), DIRT)

	# Plaza with cobbles.
	draw_circle(PLAZA_CENTER, PLAZA_RADIUS + 6, COBBLE_DARK)
	draw_circle(PLAZA_CENTER, PLAZA_RADIUS, COBBLE)
	for ring in range(1, 6):
		var r: float = PLAZA_RADIUS * ring / 5.5 + 6.0
		var stones: int = 8 + ring * 7
		for i in stones:
			var a: float = TAU * (i + ring * 0.37) / stones
			var c: Vector2 = PLAZA_CENTER + Vector2(cos(a), sin(a)) * r
			draw_circle(c, 6.5, COBBLE_DARK)
			draw_circle(c, 5.0, COBBLE.lightened(0.06 * ((i + ring) % 3)))
	_draw_fountain()

	for f: Dictionary in _flowers:
		var p: Vector2 = f["pos"]
		draw_circle(p, 3.0, f["color"])
		draw_circle(p, 1.2, Color(1.0, 0.9, 0.3))
	for s: Stall in _stalls:
		_draw_stall(s)
	for h: House in _houses:
		_draw_house(h)
	for t: Dictionary in _trees:
		_draw_tree(t["pos"], t["radius"], t["shade"])
	_draw_fence()


func _draw_fountain() -> void:
	var c: Vector2 = PLAZA_CENTER
	draw_circle(c + Vector2(0, 6), FOUNTAIN_RADIUS + 4, Color(0, 0, 0, 0.2))
	draw_circle(c, FOUNTAIN_RADIUS, Color(0.7, 0.68, 0.64))
	draw_circle(c, FOUNTAIN_RADIUS - 9, WATER.darkened(0.15))
	for i in 3:
		var r: float = (FOUNTAIN_RADIUS - 14) * fposmod(_time * 0.35 + i / 3.0, 1.0)
		draw_arc(c, r, 0, TAU, 32, Color(0.8, 0.92, 1.0, 0.5 * (1.0 - r / FOUNTAIN_RADIUS)), 2.0)
	draw_circle(c, 16, Color(0.74, 0.72, 0.68))
	draw_circle(c + Vector2(0, -6), 8, Color(0.85, 0.95, 1.0, 0.9))


func _draw_house(h: House) -> void:
	var b: Rect2 = h.body
	var clan_color: Color = ClanInfo.get_color(h.clan)
	draw_rect(Rect2(b.position + Vector2(10, 12), b.size), Color(0, 0, 0, 0.25))
	draw_rect(b, WALL)
	for y in range(1, 5):
		draw_line(Vector2(b.position.x, b.position.y + y * b.size.y / 5), Vector2(b.end.x, b.position.y + y * b.size.y / 5),
			WALL.darkened(0.08), 1.0)
	# Timber frame.
	draw_rect(b, WOOD_DARK, false, 4.0)
	draw_line(Vector2(b.position.x, b.position.y + 40), Vector2(b.end.x, b.position.y + 40), WOOD_DARK, 4.0)
	# Roof.
	var roof := PackedVector2Array([
		Vector2(b.position.x - 18, b.position.y + 8), Vector2(b.get_center().x, b.position.y - 62),
		Vector2(b.end.x + 18, b.position.y + 8),
	])
	draw_colored_polygon(roof, clan_color.darkened(0.25))
	for i in range(1, 6):
		var t: float = i / 6.0
		draw_line(roof[0].lerp(roof[1], t), roof[2].lerp(roof[1], t), clan_color.darkened(0.4), 2.0)
	draw_polyline(PackedVector2Array([roof[0], roof[1], roof[2]]), clan_color.darkened(0.55), 3.0, true)
	# Door (glows when the player can enter), door step and windows.
	var cx: float = b.get_center().x
	if highlighted_door == h.clan:
		var pulse: float = 0.5 + 0.5 * sin(_time * 5.0)
		draw_rect(Rect2(cx - 26, b.end.y - 64, 52, 64), Color(1.0, 0.85, 0.45, 0.35 + 0.3 * pulse))
	draw_rect(Rect2(cx - 20, b.end.y - 58, 40, 58), WOOD_DARK)
	draw_rect(Rect2(cx - 16, b.end.y - 54, 32, 54), WOOD)
	draw_line(Vector2(cx, b.end.y - 54), Vector2(cx, b.end.y), WOOD_DARK, 1.5)
	draw_circle(Vector2(cx + 9, b.end.y - 28), 2.5, Color(1.0, 0.85, 0.4))
	draw_rect(Rect2(cx - 28, b.end.y, 56, 8), COBBLE_DARK)
	draw_rect(Rect2(cx - 26, b.end.y, 52, 6), COBBLE)
	if _progress.has(h.clan) and int(_progress[h.clan]["total"]) > 0:
		var prog: Dictionary = _progress[h.clan]
		var total: int = prog["total"]
		var beaten: int = prog["beaten"]
		# Sign above the door: one star per duelist of the hall, gold once beaten.
		var w: float = total * 14.0 + 8.0
		var sign_rect := Rect2(cx - w / 2, b.end.y - 80, w, 18)
		draw_rect(sign_rect, WOOD_DARK)
		draw_rect(sign_rect.grow(-2), WOOD)
		for i in total:
			var star: Color = Color(1.0, 0.82, 0.3) if i < beaten else Color(0.3, 0.2, 0.12)
			_draw_star(Vector2(sign_rect.position.x + 11 + i * 14, sign_rect.get_center().y), 5.5, star)
	for wx: float in [b.position.x + 30, b.end.x - 70]:
		draw_rect(Rect2(wx, b.position.y + 58, 40, 32), WOOD_DARK)
		var glow: float = 0.75 + 0.25 * sin(_time * 2.0 + wx)
		draw_rect(Rect2(wx + 4, b.position.y + 62, 32, 24), Color(1.0, 0.85, 0.45) * glow)
		draw_line(Vector2(wx + 20, b.position.y + 62), Vector2(wx + 20, b.position.y + 86), WOOD_DARK, 2.0)
	# Clan banner.
	var pole := Vector2(b.end.x + 26, b.end.y)
	draw_line(pole, pole + Vector2(0, -110), WOOD_DARK, 4.0)
	var wave: float = sin(_time * 3.0) * 4.0
	var flag := PackedVector2Array([
		pole + Vector2(2, -106), pole + Vector2(46 + wave, -100), pole + Vector2(40 + wave * 0.5, -84),
		pole + Vector2(46 + wave, -66), pole + Vector2(2, -70),
	])
	draw_colored_polygon(flag, clan_color)
	draw_polyline(PackedVector2Array([flag[0], flag[1], flag[2], flag[3], flag[4]]), clan_color.darkened(0.4), 1.5, true)
	var font: Font = VfxAssets.get_card_text_bold_font()
	var clan_name: String = ClanInfo.display_name(h.clan)
	var text_size: Vector2 = font.get_string_size(clan_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	var at := Vector2(cx - text_size.x / 2, b.position.y + 28)
	draw_string_outline(font, at, clan_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 6, Color(0.1, 0.06, 0.03))
	draw_string(font, at, clan_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, clan_color.lightened(0.35))


func _draw_star(c: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	pts.resize(10)
	for i in 10:
		var a: float = -PI / 2 + i * PI / 5
		var rr: float = r if i % 2 == 0 else r * 0.45
		pts[i] = c + Vector2(cos(a), sin(a)) * rr
	draw_colored_polygon(pts, color)


func _draw_stall(s: Stall) -> void:
	var r: Rect2 = s.counter
	draw_rect(Rect2(r.position + Vector2(6, 8), r.size), Color(0, 0, 0, 0.22))
	draw_rect(r, WOOD)
	draw_rect(r, WOOD_DARK, false, 3.0)
	for i in 5:
		var crate := Rect2(r.position.x + 10 + i * 26, r.position.y + 8, 18, 14)
		draw_rect(crate, Color(0.85, 0.75, 0.5).darkened(0.1 * (i % 2)))
	# Striped awning behind the vendor.
	var awning := Rect2(r.position.x - 8, r.position.y - 92, r.size.x + 16, 26)
	for i in 8:
		draw_rect(Rect2(awning.position.x + i * awning.size.x / 8, awning.position.y, awning.size.x / 8 + 1, awning.size.y),
			s.color if i % 2 == 0 else Color(0.95, 0.92, 0.85))
	draw_rect(awning, WOOD_DARK, false, 2.0)
	draw_line(Vector2(r.position.x - 4, awning.end.y), Vector2(r.position.x - 4, r.end.y), WOOD_DARK, 4.0)
	draw_line(Vector2(r.end.x + 4, awning.end.y), Vector2(r.end.x + 4, r.end.y), WOOD_DARK, 4.0)


func _draw_tree(pos: Vector2, radius: float, shade: float) -> void:
	draw_circle(pos + Vector2(6, radius * 0.7), radius * 0.8, Color(0, 0, 0, 0.22))
	draw_rect(Rect2(pos.x - 5, pos.y, 10, radius * 0.9), WOOD_DARK)
	var leaf: Color = Color(0.2, 0.42, 0.18).lerp(Color(0.3, 0.52, 0.2), shade)
	var sway: float = sin(_time * 1.3 + pos.x * 0.01) * 1.5
	draw_circle(pos + Vector2(sway, -radius * 0.2), radius, leaf.darkened(0.2))
	draw_circle(pos + Vector2(-radius * 0.35 + sway, -radius * 0.4), radius * 0.7, leaf)
	draw_circle(pos + Vector2(radius * 0.3 + sway, -radius * 0.55), radius * 0.55, leaf.lightened(0.12))


func _draw_fence() -> void:
	var x: float = 20
	while x < MAP_SIZE.x - 10:
		_draw_fence_post(Vector2(x, 22))
		_draw_fence_post(Vector2(x, MAP_SIZE.y - 18))
		x += 34
	var y: float = 20
	while y < MAP_SIZE.y - 10:
		_draw_fence_post(Vector2(18, y))
		_draw_fence_post(Vector2(MAP_SIZE.x - 18, y))
		y += 34
	draw_rect(Rect2(10, 10, MAP_SIZE.x - 20, MAP_SIZE.y - 20), WOOD_DARK, false, 3.0)


func _draw_fence_post(p: Vector2) -> void:
	draw_rect(Rect2(p.x - 4, p.y - 10, 8, 18), WOOD)
	draw_rect(Rect2(p.x - 4, p.y - 10, 8, 18), WOOD_DARK, false, 1.5)
