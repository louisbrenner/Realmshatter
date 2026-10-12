class_name VictoryBanner
extends Control
## End-of-game crest: rotating light rays, a shield crest and a big ribbon with "VICTORY" (gold/blue)
## or "DEFEAT" (dark red/grey), plus a subtitle. Call present to (re)play the entrance animation.

var _victory: bool = true
var _title: String = "VICTORY"
var _subtitle: String = ""
var _time: float = 0.0
var _intro: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(520.0, 300.0)


## Sets victory/defeat look and texts and restarts the entrance animation.
## An empty title falls back to "VICTORY"/"DEFEAT" (C# null).
func present(victory: bool, title: String, subtitle: String) -> void:
	_victory = victory
	_title = title if not title.is_empty() else ("VICTORY" if victory else "DEFEAT")
	_subtitle = subtitle
	_intro = 0.0
	_time = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	var dt: float = delta
	_time += dt
	_intro = minf(1.0, _intro + dt * 1.8)
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	var c := Vector2(size.x * 0.5, size.y * 0.45)
	var e: float = 1.0 - pow(1.0 - _intro, 3.0)
	var s: float = 0.6 + 0.4 * e + 0.06 * sin(clampf(_intro, 0.0, 1.0) * PI)
	var main: Color = HudStyle.GOLD if _victory else Color(0.7, 0.25, 0.2)
	var dark: Color = Color(0.16, 0.3, 0.6) if _victory else Color(0.25, 0.2, 0.2)

	# Rays.
	if _victory:
		var rays: int = 18
		for i in range(rays):
			var a: float = _time * 0.25 + TAU * i / rays
			var length: float = 260.0 * e
			var d1 := Vector2(cos(a - 0.07), sin(a - 0.07))
			var d2 := Vector2(cos(a + 0.07), sin(a + 0.07))
			draw_polygon(PackedVector2Array([c, c + d1 * length, c + d2 * length]),
				PackedColorArray([Color(1.0, 0.9, 0.55, 0.35 * e), Color(1.0, 0.9, 0.55, 0.0), Color(1.0, 0.9, 0.55, 0.0)]))
	HudStyle.fill_ellipse(self, c, Vector2.ONE * 120.0 * e, Color(main, 0.18 * e), 40)

	draw_set_transform(c, 0.0, Vector2.ONE * s)
	# Shield crest.
	var shield := PackedVector2Array([
		Vector2(-80, -105), Vector2(80, -105), Vector2(86, -10), Vector2(0, 95), Vector2(-86, -10),
	])
	draw_colored_polygon(shield, dark.darkened(0.3))
	var inner_shield := PackedVector2Array()
	inner_shield.resize(shield.size())
	for i in range(shield.size()):
		inner_shield[i] = shield[i] * 0.84
	draw_colored_polygon(inner_shield, dark)
	draw_polyline(HudStyle.close(shield), main, 5.0, true)
	draw_polyline(HudStyle.close(inner_shield), Color(main, 0.6), 2.0, true)
	# Emblem: crossed swords (victory) or broken sword (defeat).
	var steel := Color(0.88, 0.9, 0.95)
	if _victory:
		draw_set_transform(c + Vector2(0, -30.0 * s), 0.0, Vector2.ONE * s)
		draw_line(Vector2(-38, 30), Vector2(38, -60), steel, 7.0, true)
		draw_line(Vector2(38, 30), Vector2(-38, -60), steel, 7.0, true)
		draw_line(Vector2(-50, 16), Vector2(-24, 40), main, 6.0, true)
		draw_line(Vector2(50, 16), Vector2(24, 40), main, 6.0, true)
		draw_set_transform(c, 0.0, Vector2.ONE * s)
	else:
		# Broken sword: hilt + lower blade with a jagged break, the tip fallen aside.
		var blade: Color = steel.darkened(0.25)
		draw_set_transform(c + Vector2(0, -48.0 * s), 0.0, Vector2.ONE * s * 0.85)
		draw_colored_polygon(PackedVector2Array([Vector2(-7, 22), Vector2(7, 22), Vector2(7, -18), Vector2(2, -10), Vector2(-3, -22), Vector2(-7, -14)]), blade)
		draw_colored_polygon(PackedVector2Array([Vector2(-26, 22), Vector2(26, 22), Vector2(26, 31), Vector2(-26, 31)]), main)
		draw_colored_polygon(PackedVector2Array([Vector2(-5, 31), Vector2(5, 31), Vector2(5, 52), Vector2(-5, 52)]), Color(0.35, 0.2, 0.1))
		draw_circle(Vector2(0, 57), 7.0, main)
		draw_colored_polygon(PackedVector2Array([Vector2(22, -34), Vector2(30, -40), Vector2(58, -78), Vector2(26, -48), Vector2(18, -40)]), blade.darkened(0.15))
		draw_set_transform(c, 0.0, Vector2.ONE * s)

	# Ribbon.
	var rw: float = 230.0
	var rh: float = 64.0
	var ry: float = 50.0
	var tail_l := PackedVector2Array([
		Vector2(-rw - 40, ry - rh * 0.3), Vector2(-rw + 10, ry - rh * 0.3), Vector2(-rw + 10, ry + rh * 0.7),
		Vector2(-rw - 40, ry + rh * 0.7), Vector2(-rw - 22, ry + rh * 0.2),
	])
	var tail_r := PackedVector2Array()
	tail_r.resize(tail_l.size())
	for i in range(tail_l.size()):
		tail_r[i] = Vector2(-tail_l[i].x, tail_l[i].y)
	var ribbon: Color = Color(0.75, 0.12, 0.1) if _victory else Color(0.3, 0.28, 0.27)
	draw_colored_polygon(tail_l, ribbon.darkened(0.4))
	draw_colored_polygon(tail_r, ribbon.darkened(0.4))
	var body := PackedVector2Array([
		Vector2(-rw, ry - rh * 0.5), Vector2(0, ry - rh * 0.5 - 12.0), Vector2(rw, ry - rh * 0.5),
		Vector2(rw, ry + rh * 0.5), Vector2(0, ry + rh * 0.5 - 12.0), Vector2(-rw, ry + rh * 0.5),
	])
	draw_colored_polygon(body, ribbon)
	draw_polyline(HudStyle.close(body), main, 3.0, true)
	HudStyle.draw_text_centered(self, _title, Vector2(0, ry - 6.0), 50, Color(1.0, 0.95, 0.82), 10, Color(0.15, 0.04, 0.02))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if not _subtitle.is_empty():
		HudStyle.draw_text_centered(self, _subtitle, Vector2(c.x, c.y + 130.0 * s), 20, Color(HudStyle.TEXT_LIGHT, e), 5)
