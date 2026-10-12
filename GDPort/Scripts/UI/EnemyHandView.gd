class_name EnemyHandView
extends Control
## The opponent's hand, face down: a centred fan of card backs with the card count (inside the enemy window).

@export var card_size: Vector2 = Vector2(34, 48)
@export var spacing: float = 18.0

var _count: int = 0
var _pop: float = 0.0
var _tween: Tween


## Sets the number of cards; a change pops the fan briefly.
func set_count(count: int) -> void:
	if count == _count:
		return
	_count = count
	if _tween != null:
		_tween.kill()
	var step := func(v: float) -> void:
		_pop = v
		queue_redraw()
	_tween = create_tween()
	_tween.tween_method(step, 1.0, 0.0, 0.35)
	queue_redraw()


func _draw() -> void:
	var n: int = mini(_count, 10)
	var total: float = (n - 1) * spacing + card_size.x if n > 0 else 0.0
	var start_x: float = (size.x - total) * 0.5
	for i in range(n):
		var off: float = i - (n - 1) * 0.5
		var center := Vector2(start_x + i * spacing + card_size.x * 0.5, 6.0 + card_size.y * 0.5 + off * off * 0.6 - _pop * 6.0)
		draw_set_transform(center, deg_to_rad(off * 4.0), Vector2.ONE)
		var rect := Rect2(-card_size * 0.5, card_size)
		draw_colored_polygon(HudStyle.round_rect(rect.grow(1.5), 5.0), Color(0, 0, 0, 0.45))
		draw_colored_polygon(HudStyle.round_rect(rect, 4.0), Color(0.27, 0.14, 0.08))
		draw_colored_polygon(HudStyle.round_rect(rect.grow(-3.0), 3.0), Color(0.43, 0.24, 0.12))
		draw_polyline(HudStyle.close(HudStyle.round_rect(rect, 4.0)), HudStyle.GOLD_DARK, 1.5, true)
		HudStyle.stroke_ellipse(self, Vector2.ZERO, Vector2(8.0, 8.0), Color(HudStyle.GOLD, 0.85), 1.5, 16)
		HudStyle.fill_ellipse(self, Vector2.ZERO, Vector2(3.5, 3.5), HudStyle.GOLD, 10)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _count > 0:
		HudStyle.draw_text_centered(self, "Hand: %d" % _count, Vector2(size.x * 0.5, card_size.y + 18.0), 13, HudStyle.TEXT_LIGHT, 4)
