class_name HouseInterior
extends Node2D
## The inside of a clan hall, drawn procedurally like the town: plank floor, plastered back wall with timber, clan
## banners and the hall's name, a fireplace, a carpet from the door to the leader's throne, side tables with
## benches and torches. Creates collision for the walls and furniture. The room is placed at ORIGIN (far away
## from the town) so both maps never touch; NPC positions in NpcData are room-local (0..ROOM_SIZE).

## Size of the room in pixels.
const ROOM_SIZE := Vector2(960, 640)

## World position of the room's top-left corner.
const ORIGIN := Vector2(4000, 0)

## Room-local spot where the player appears when entering (just inside the door).
const ENTRY_POINT := Vector2(480, 560)

## Room-local area of the doorway: standing in it and walking down leaves the hall.
const DOORWAY := Rect2(440, 575, 80, 60)

const BACK_WALL := 130.0
const SIDE_WALL := 36.0
const DOOR_WIDTH := 80.0

const PLANK := Color(0.55, 0.38, 0.22)
const PLANK_DARK := Color(0.42, 0.28, 0.15)
const PLASTER := Color(0.82, 0.75, 0.62)
const WOOD := Color(0.45, 0.29, 0.16)
const WOOD_DARK := Color(0.28, 0.17, 0.08)
const STONE := Color(0.55, 0.53, 0.5)
const STONE_DARK := Color(0.38, 0.36, 0.34)

const TABLE_LEFT := Rect2(90, 300, 140, 56)
const TABLE_RIGHT := Rect2(730, 300, 140, 56)
const DAIS := Rect2(400, 140, 160, 70)

var _time: float = 0.0

## Clan whose hall this is.
var clan: int = Clan.NONE


## Sets the clan (colours, name). Call before adding the node to the tree.
func setup(p_clan: int) -> void:
	clan = p_clan
	name = "Hall_%s" % Clan.name_of(p_clan)
	position = ORIGIN


## True if a world position lies in the doorway.
func is_in_doorway(world: Vector2) -> bool:
	return DOORWAY.has_point(world - ORIGIN)


func _ready() -> void:
	z_index = -10
	_build_collision()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


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
	var door_left: float = (ROOM_SIZE.x - DOOR_WIDTH) / 2.0
	rect.call(Rect2(0, 0, ROOM_SIZE.x, BACK_WALL))
	rect.call(Rect2(0, 0, SIDE_WALL, ROOM_SIZE.y))
	rect.call(Rect2(ROOM_SIZE.x - SIDE_WALL, 0, SIDE_WALL, ROOM_SIZE.y))
	rect.call(Rect2(0, ROOM_SIZE.y - 40, door_left, 40))
	rect.call(Rect2(door_left + DOOR_WIDTH, ROOM_SIZE.y - 40, door_left, 40))
	# Behind the doorway: the player can step into it, but not walk off the map.
	rect.call(Rect2(door_left, ROOM_SIZE.y + 4, DOOR_WIDTH, 40))
	rect.call(TABLE_LEFT)
	rect.call(TABLE_RIGHT)
	rect.call(Rect2(DAIS.position.x + 50, DAIS.position.y - 10, 60, 40))


func _draw() -> void:
	var clan_color: Color = ClanInfo.get_color(clan)
	draw_rect(Rect2(-400, -300, ROOM_SIZE.x + 800, ROOM_SIZE.y + 600), Color(0.08, 0.05, 0.03))
	_draw_floor()
	_draw_carpet(clan_color)
	_draw_back_wall(clan_color)
	draw_rect(Rect2(0, 0, SIDE_WALL, ROOM_SIZE.y), WOOD_DARK)
	draw_rect(Rect2(ROOM_SIZE.x - SIDE_WALL, 0, SIDE_WALL, ROOM_SIZE.y), WOOD_DARK)
	draw_rect(Rect2(SIDE_WALL - 6, BACK_WALL, 6, ROOM_SIZE.y - BACK_WALL), WOOD)
	draw_rect(Rect2(ROOM_SIZE.x - SIDE_WALL, BACK_WALL, 6, ROOM_SIZE.y - BACK_WALL), WOOD)
	_draw_front_wall()
	_draw_dais(clan_color)
	_draw_table(TABLE_LEFT)
	_draw_table(TABLE_RIGHT)
	for torch: Vector2 in [Vector2(SIDE_WALL + 14, 260), Vector2(ROOM_SIZE.x - SIDE_WALL - 14, 260),
			Vector2(SIDE_WALL + 14, 470), Vector2(ROOM_SIZE.x - SIDE_WALL - 14, 470)]:
		_draw_torch(torch)


func _draw_floor() -> void:
	var y: float = BACK_WALL
	while y < ROOM_SIZE.y:
		var row: int = int(y / 24.0)
		draw_rect(Rect2(0, y, ROOM_SIZE.x, 24.0), PLANK if row % 2 == 0 else PLANK.darkened(0.06))
		draw_line(Vector2(0, y), Vector2(ROOM_SIZE.x, y), PLANK_DARK, 1.5)
		var x: float = (row % 3) * 70.0
		while x < ROOM_SIZE.x:
			draw_line(Vector2(x, y), Vector2(x, y + 24.0), PLANK_DARK, 1.5)
			x += 210.0
		y += 24.0


func _draw_carpet(clan_color: Color) -> void:
	var carpet := Rect2(ROOM_SIZE.x / 2 - 60, DAIS.end.y - 10, 120, ROOM_SIZE.y - DAIS.end.y)
	draw_rect(carpet, clan_color.darkened(0.45))
	draw_rect(carpet.grow(-6), clan_color.darkened(0.2))
	var y: float = carpet.position.y + 30
	while y < carpet.end.y - 20:
		var c := Vector2(carpet.get_center().x, y)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -14), c + Vector2(14, 0), c + Vector2(0, 14), c + Vector2(-14, 0)]),
			clan_color.lightened(0.25))
		y += 60


func _draw_back_wall(clan_color: Color) -> void:
	draw_rect(Rect2(0, 0, ROOM_SIZE.x, BACK_WALL), PLASTER)
	draw_rect(Rect2(0, 0, ROOM_SIZE.x, 14), WOOD_DARK)
	draw_rect(Rect2(0, BACK_WALL - 12, ROOM_SIZE.x, 12), WOOD_DARK)
	var x: float = 80
	while x < ROOM_SIZE.x:
		draw_rect(Rect2(x - 5, 14, 10, BACK_WALL - 26), WOOD_DARK)
		x += 160
	# Banners between the beams.
	for bx: float in [160.0, 320.0, 640.0, 800.0]:
		var sway: float = sin(_time * 1.6 + bx) * 2.0
		var flag := PackedVector2Array([
			Vector2(bx - 22, 26), Vector2(bx + 22, 26), Vector2(bx + 22 + sway, 92),
			Vector2(bx + sway, 80), Vector2(bx - 22 + sway, 92),
		])
		draw_colored_polygon(flag, clan_color.darkened(0.1))
		draw_polyline(HudStyle.close(flag), clan_color.darkened(0.5), 2.0, true)
		draw_circle(Vector2(bx + sway * 0.5, 52), 9.0, clan_color.lightened(0.45))
		draw_line(Vector2(bx - 26, 25), Vector2(bx + 26, 25), WOOD_DARK, 4.0)
	_draw_fireplace(Vector2(480, BACK_WALL))
	var clan_name: String = ClanInfo.display_name(clan)
	var font: Font = VfxAssets.get_card_text_bold_font()
	var title: String = "Hall of the %s" % clan_name
	var text_size: Vector2 = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
	var at := Vector2(ROOM_SIZE.x / 2 - text_size.x / 2, 36)
	draw_string_outline(font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 6, Color(0.1, 0.06, 0.03))
	draw_string(font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, clan_color.lightened(0.4))


func _draw_fireplace(bottom: Vector2) -> void:
	var outer := Rect2(bottom.x - 70, bottom.y - 82, 140, 82)
	draw_rect(outer, STONE_DARK)
	for i in 6:
		draw_rect(Rect2(outer.position.x + 4 + (i % 3) * 45, outer.position.y + 4 + int(i / 3.0) * 18, 42, 15), STONE)
	var hearth := Rect2(bottom.x - 42, bottom.y - 46, 84, 46)
	draw_rect(hearth, Color(0.1, 0.06, 0.04))
	for i in 5:
		var x: float = hearth.position.x + 14 + i * 14
		var h: float = 18 + 10 * sin(_time * 7.0 + i * 1.7)
		var b := Vector2(x, hearth.end.y - 4)
		draw_colored_polygon(PackedVector2Array([b + Vector2(-8, 0), b + Vector2(0, -h), b + Vector2(8, 0)]), Color(1.0, 0.5, 0.12, 0.9))
		draw_colored_polygon(PackedVector2Array([b + Vector2(-4, 0), b + Vector2(0, -h * 0.55), b + Vector2(4, 0)]), Color(1.0, 0.9, 0.45))
	draw_rect(Rect2(hearth.position.x + 6, hearth.end.y - 6, hearth.size.x - 12, 6), WOOD_DARK)


func _draw_front_wall() -> void:
	var door_left: float = (ROOM_SIZE.x - DOOR_WIDTH) / 2.0
	draw_rect(Rect2(0, ROOM_SIZE.y - 40, door_left, 40), WOOD_DARK)
	draw_rect(Rect2(door_left + DOOR_WIDTH, ROOM_SIZE.y - 40, door_left, 40), WOOD_DARK)
	draw_rect(Rect2(0, ROOM_SIZE.y - 40, ROOM_SIZE.x, 5), WOOD)
	# Open doorway with daylight and a door mat.
	draw_rect(Rect2(door_left, ROOM_SIZE.y - 40, DOOR_WIDTH, 48), Color(0.45, 0.62, 0.32))
	draw_rect(Rect2(door_left + 10, ROOM_SIZE.y - 64, DOOR_WIDTH - 20, 22), Color(0.6, 0.45, 0.28))
	draw_rect(Rect2(door_left - 6, ROOM_SIZE.y - 44, 6, 48), WOOD)
	draw_rect(Rect2(door_left + DOOR_WIDTH, ROOM_SIZE.y - 44, 6, 48), WOOD)


func _draw_dais(clan_color: Color) -> void:
	draw_rect(Rect2(DAIS.position + Vector2(6, 8), DAIS.size), Color(0, 0, 0, 0.25))
	draw_rect(DAIS, STONE_DARK)
	draw_rect(DAIS.grow(-5), STONE)
	# Throne.
	var back := Rect2(DAIS.get_center().x - 30, DAIS.position.y - 34, 60, 64)
	draw_rect(back, WOOD_DARK)
	draw_rect(back.grow(-5), clan_color.darkened(0.35))
	draw_colored_polygon(PackedVector2Array([
		Vector2(back.position.x, back.position.y), Vector2(back.get_center().x, back.position.y - 18),
		Vector2(back.end.x, back.position.y),
	]), WOOD_DARK)
	draw_circle(Vector2(back.get_center().x, back.position.y - 4), 6.0, Color(1.0, 0.82, 0.35))


func _draw_table(t: Rect2) -> void:
	draw_rect(Rect2(t.position + Vector2(6, 8), t.size), Color(0, 0, 0, 0.25))
	draw_rect(Rect2(t.position.x, t.position.y - 18, t.size.x, 12), WOOD_DARK)
	draw_rect(Rect2(t.position.x, t.end.y + 6, t.size.x, 12), WOOD_DARK)
	draw_rect(t, WOOD)
	draw_rect(t, WOOD_DARK, false, 3.0)
	draw_line(Vector2(t.position.x, t.get_center().y), Vector2(t.end.x, t.get_center().y), WOOD_DARK, 1.5)
	# Mugs and a candle.
	draw_circle(t.position + Vector2(28, 18), 6.0, Color(0.75, 0.7, 0.6))
	draw_circle(t.position + Vector2(t.size.x - 30, 36), 6.0, Color(0.75, 0.7, 0.6))
	var candle: Vector2 = t.get_center()
	draw_rect(Rect2(candle.x - 3, candle.y - 12, 6, 14), Color(0.95, 0.92, 0.82))
	var flick: float = 1.0 + 0.2 * sin(_time * 9.0 + t.position.x)
	draw_circle(candle + Vector2(0, -15), 3.5 * flick, Color(1.0, 0.8, 0.3))
	draw_circle(candle + Vector2(0, -15), 14.0 * flick, Color(1.0, 0.75, 0.3, 0.12))


func _draw_torch(p: Vector2) -> void:
	draw_rect(Rect2(p.x - 3, p.y - 6, 6, 22), WOOD_DARK)
	var flick: float = 1.0 + 0.25 * sin(_time * 8.0 + p.y)
	draw_circle(p + Vector2(0, -10), 30.0 * flick, Color(1.0, 0.7, 0.3, 0.1))
	draw_circle(p + Vector2(0, -10), 7.0 * flick, Color(1.0, 0.55, 0.15))
	draw_circle(p + Vector2(0, -11), 3.5 * flick, Color(1.0, 0.92, 0.5))
