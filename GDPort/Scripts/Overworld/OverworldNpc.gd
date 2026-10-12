class_name OverworldNpc
extends Node2D
## A townsperson in the overworld: a duelist (NpcData) or a vendor (VendorData). Draws itself in its clan colour
## with name and title, shows a "!" until beaten (a gold star afterwards, a padlock while it still waits for other
## duels) and blocks movement.

## Duelist data (null for vendors).
var npc: NpcData

## Vendor data (null for duelists).
var vendor: VendorData

## True while the player stands close enough to talk.
var highlighted: bool = false

var _time: float = 0.0
var _facing: float = 1.0


## Sets up a duelist.
func setup_npc(p_npc: NpcData) -> void:
	npc = p_npc
	position = p_npc.position
	name = "Npc_%s" % p_npc.id


## Sets up a vendor.
func setup_vendor(p_vendor: VendorData) -> void:
	vendor = p_vendor
	position = p_vendor.position
	name = "Vendor_%s" % p_vendor.id


## Display name.
var display_name: String:
	get:
		if npc != null:
			return npc.name
		if vendor != null:
			return vendor.name
		return ""


func _ready() -> void:
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 14.0
	shape.shape = circle
	shape.position = Vector2(0, -6)
	body.add_child(shape)
	add_child(body)
	_time = randf_range(0.0, 10.0)


## Turns toward a world position (when talking).
func face_toward(target: Vector2) -> void:
	_facing = -1.0 if target.x < global_position.x else 1.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var robe: Color
	var accent: Color
	var leader: bool = false
	var title: String
	if npc != null:
		robe = ClanInfo.get_color(npc.clan).darkened(0.15)
		accent = ClanInfo.get_color(npc.clan).lightened(0.4)
		leader = "Leader" in npc.title
		title = npc.title
	else:
		robe = vendor.color if vendor != null else Color.GRAY
		accent = Color(1.0, 0.85, 0.45)
		title = vendor.title if vendor != null else ""
	if highlighted:
		var pulse: float = 0.5 + 0.5 * sin(_time * 5.0)
		HudStyle.stroke_ellipse(self, Vector2(0, 1), Vector2(22, 9), Color(1.0, 0.9, 0.5, 0.6 + 0.4 * pulse), 2.5, 24)
	var idle: float = sin(_time * 1.5) * 0.3
	PersonSprite.draw(self, Vector2.ZERO, robe, accent, idle, _facing, leader, npc != null and npc.clan != Clan.NONE)

	var name_color: Color = ClanInfo.get_color(npc.clan).lightened(0.35) if npc != null else Color(1.0, 0.88, 0.55)
	# Vendors stand under their stall awning: lift their labels above it.
	var lift: float = -50.0 if vendor != null else 0.0
	PersonSprite.draw_label(self, Vector2(0, -62 + lift), display_name, 14, name_color)
	PersonSprite.draw_label(self, Vector2(0, -78 + lift), title, 11, Color(0.92, 0.88, 0.8))

	var hover: float = sin(_time * 3.0) * 3.0 + lift
	if npc != null:
		if PlayerProfile.has_defeated(npc.id):
			_draw_star(Vector2(0, -98 + hover), 8.0, Color(1.0, 0.82, 0.3))
		elif not BattleSession.is_unlocked(npc)["result"]:
			_draw_lock(Vector2(0, -100 + hover))
		else:
			draw_circle(Vector2(0, -102 + hover), 10.0, Color(0.1, 0.06, 0.03))
			draw_circle(Vector2(0, -102 + hover), 8.5, Color(1.0, 0.85, 0.3))
			PersonSprite.draw_label(self, Vector2(0, -96 + hover), "!", 14, Color(0.25, 0.12, 0.04))
	else:
		draw_circle(Vector2(0, -102 + hover), 9.5, Color(0.1, 0.06, 0.03))
		draw_circle(Vector2(0, -102 + hover), 8.0, Color(0.98, 0.8, 0.3))
		PersonSprite.draw_label(self, Vector2(0, -97 + hover), "$", 12, Color(0.35, 0.2, 0.05))


func _draw_lock(c: Vector2) -> void:
	var outline := Color(0.1, 0.06, 0.03)
	draw_arc(c + Vector2(0, -4), 5.5, PI, TAU, 12, outline, 4.5)
	draw_arc(c + Vector2(0, -4), 5.5, PI, TAU, 12, Color(0.7, 0.7, 0.74), 2.2)
	draw_rect(Rect2(c.x - 9, c.y - 5, 18, 14), outline)
	draw_rect(Rect2(c.x - 7.5, c.y - 3.5, 15, 11), Color(0.62, 0.6, 0.66))
	draw_circle(c + Vector2(0, 1.5), 2.0, outline)


func _draw_star(c: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	pts.resize(10)
	for i in 10:
		var a: float = -PI / 2 + i * PI / 5
		var rr: float = r if i % 2 == 0 else r * 0.45
		pts[i] = c + Vector2(cos(a), sin(a)) * rr
	draw_colored_polygon(pts, color)
	draw_polyline(HudStyle.close(pts), Color(0.3, 0.18, 0.05), 1.2, true)
