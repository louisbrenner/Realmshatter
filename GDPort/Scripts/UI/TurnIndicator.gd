class_name TurnIndicator
extends Control
## Top-bar turn plaque: "TURN n" with a phase line, flanked by the two players' shields (YOU / AI).
## The active player's shield glows; a chevron points toward the player who goes next.

var _turn: int = 1
var _current: int = 0
var _phase: String = ""
var _time: float = 0.0
var _switch: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Updates turn number, current player and the small phase caption.
func set_turn(turn_number: int, current_player: int, phase: String) -> void:
	if current_player != _current:
		_switch = 1.0
	_turn = turn_number
	_current = current_player
	_phase = phase
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	_switch = maxf(0.0, _switch - delta * 2.0)
	queue_redraw()


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var plaque_w: float = minf(size.x - 120.0, 200.0)
	var plaque := Rect2(c.x - plaque_w * 0.5, 2.0, plaque_w, size.y - 4.0)

	# Plaque with banner tails.
	var shape := PackedVector2Array([
		plaque.position + Vector2(14.0, 0.0), Vector2(plaque.end.x - 14.0, plaque.position.y),
		Vector2(plaque.end.x, c.y), Vector2(plaque.end.x - 14.0, plaque.end.y),
		Vector2(plaque.position.x + 14.0, plaque.end.y), Vector2(plaque.position.x, c.y),
	])
	draw_colored_polygon(shape, Color(HudStyle.WOOD_DARK, 0.96))
	draw_polyline(HudStyle.close(shape), HudStyle.GOLD_DARK, 2.0, true)
	var inner := PackedVector2Array()
	inner.resize(shape.size())
	for i in range(shape.size()):
		inner[i] = c + (shape[i] - c) * Vector2(0.95, 0.78)
	draw_polyline(HudStyle.close(inner), Color(HudStyle.GOLD, 0.35), 1.0, true)

	HudStyle.draw_text_centered(self, "TURN %d" % _turn, Vector2(c.x, c.y - (0.0 if _phase.is_empty() else 6.0)), 19, HudStyle.GOLD, 5)
	if not _phase.is_empty():
		HudStyle.draw_text_centered(self, _phase, Vector2(c.x, c.y + 11.0), 11, Color(HudStyle.TEXT_LIGHT, 0.85), 3)

	_draw_shield(Vector2(plaque.position.x - 26.0, c.y), 0, "YOU")
	_draw_shield(Vector2(plaque.end.x + 26.0, c.y), 1, "AI")

	# Chevron from the active player toward the next one.
	var dir: float = 1.0 if _current == 0 else -1.0
	var slide: float = 3.0 * sin(_time * 4.0)
	var side: float = plaque.position.x + 22.0 if _current == 0 else plaque.end.x - 22.0
	var chevron := Color(HudStyle.accent(_current), 0.85)
	for k in range(2):
		var x: float = side + dir * (k * 7.0 + slide)
		draw_polyline(PackedVector2Array([Vector2(x - dir * 4.0, c.y - 6.0), Vector2(x + dir * 2.0, c.y), Vector2(x - dir * 4.0, c.y + 6.0)]),
			chevron, 2.2, true)


func _draw_shield(center: Vector2, player: int, text: String) -> void:
	var active: bool = player == _current
	var accent: Color = HudStyle.accent(player)
	var s: float = 1.0 + 0.15 * _switch if active else 0.85
	var w: float = 16.0 * s
	var h: float = 17.0 * s
	var shield := PackedVector2Array([
		center + Vector2(-w, -h * 0.8), center + Vector2(w, -h * 0.8), center + Vector2(w, h * 0.1),
		center + Vector2(0, h), center + Vector2(-w, h * 0.1),
	])
	if active:
		var pulse: float = 0.5 + 0.5 * sin(_time * 3.0)
		HudStyle.fill_ellipse(self, center, Vector2(w * 1.6, h * 1.3), Color(accent, 0.18 + 0.14 * pulse), 24)
	draw_colored_polygon(shield, accent.darkened(0.35) if active else Color(0.22, 0.2, 0.19, 0.9))
	var inner := PackedVector2Array()
	inner.resize(shield.size())
	for i in range(shield.size()):
		inner[i] = center + (shield[i] - center) * 0.72
	draw_colored_polygon(inner, accent if active else Color(0.35, 0.33, 0.31, 0.9))
	draw_polyline(HudStyle.close(shield), HudStyle.GOLD if active else HudStyle.GOLD_DARK, 2.0, true)
	HudStyle.draw_text_centered(self, text, center + Vector2(0, -2.0), 10 if active else 9, Color.WHITE, 3)
