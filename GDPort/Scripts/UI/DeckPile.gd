class_name DeckPile
extends Button
## Draw button drawn as a deck pile: a stack of card backs (height grows with the deck count),
## the remaining card count and a mana gem with the draw cost. Glows green while a draw is possible,
## the top card lifts on hover. Pressing emits BaseButton.pressed.

const BACK_COLOR := Color(0.32, 0.16, 0.1)
const BACK_LIGHT := Color(0.55, 0.3, 0.16)

var _count: int = 0
var _cost: int = 1
var _time: float = 0.0
var _hover: float = 0.0
var _draw_anim: float = 0.0
var _shown_count: int = 0

## Cards left in the deck.
var count: int:
	get:
		return _count


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	flat = true
	text = ""
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_update_tooltip()


## Sets the deck count and the AP cost of a draw.
func set_deck(p_count: int, cost: int) -> void:
	if p_count < _shown_count and is_inside_tree():
		_draw_anim = 1.0
	_count = maxi(0, p_count)
	_shown_count = _count
	_cost = cost
	_update_tooltip()
	queue_redraw()


func _update_tooltip() -> void:
	tooltip_text = "Draw (D): pay %d AP, choose 1 of the offered cards. %d cards left in your deck." % [_cost, _count]


func _process(delta: float) -> void:
	var dt: float = delta
	_time += dt
	_hover = move_toward(_hover, 1.0 if (is_hovered() and not disabled) else 0.0, dt * 8.0)
	_draw_anim = maxf(0.0, _draw_anim - dt * 2.0)
	queue_redraw()


func _draw() -> void:
	var card_size := Vector2(size.x * 0.62, size.y * 0.7)
	var origin := Vector2((size.x - card_size.x) * 0.5, size.y - card_size.y - 18.0)
	var layers: int = 0 if _count <= 0 else clampi(ceili(_count / 3.0), 1, 6)
	var live: bool = not disabled and _count > 0
	var pulse: float = 0.5 + 0.5 * sin(_time * 3.0)

	if live:
		var glow_rect := Rect2(origin - Vector2(layers * 1.5, layers * 2.5), card_size + Vector2(layers * 3.0, layers * 2.5))
		for i in range(3, 0, -1):
			draw_colored_polygon(HudStyle.round_rect(glow_rect.grow(i * 3.0), 10.0 + i * 2.0),
				Color(HudStyle.READY_GREEN, (0.1 + 0.08 * pulse + 0.1 * _hover) * (4 - i) / 3.0))

	if layers == 0:
		var empty := Rect2(origin, card_size)
		draw_colored_polygon(HudStyle.round_rect(empty, 8.0), Color(0.0, 0.0, 0.0, 0.35))
		draw_polyline(HudStyle.close(HudStyle.round_rect(empty, 8.0)), Color(0.6, 0.5, 0.4, 0.6), 1.5, true)
	for i in range(layers):
		var top: bool = i == layers - 1
		var lift: float = -6.0 * _hover if top else 0.0
		var offset := Vector2(-i * 1.5 + (layers - 1) * 0.75, -i * 2.5 + lift)
		_draw_card_back(Rect2(origin + offset, card_size), top, 0.7 if disabled else 1.0)

	# Card flying off the top on a draw.
	if _draw_anim > 0.0 and layers > 0:
		var t: float = 1.0 - _draw_anim
		var offset := Vector2(-60.0 * t, -layers * 2.5 - 40.0 * t)
		draw_set_transform(origin + card_size * 0.5 + offset, -0.5 * t, Vector2.ONE * (1.0 + 0.2 * t))
		var m := Color(1.0, 1.0, 1.0, _draw_anim)
		draw_colored_polygon(HudStyle.round_rect(Rect2(-card_size * 0.5, card_size), 8.0), Color(BACK_LIGHT, m.a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Count badge.
	var badge := Vector2(size.x * 0.5, size.y - 14.0)
	var badge_rect := Rect2(badge - Vector2(26.0, 11.0), Vector2(52.0, 22.0))
	draw_colored_polygon(HudStyle.round_rect(badge_rect, 10.0), Color(HudStyle.WOOD_DARK, 0.95))
	draw_polyline(HudStyle.close(HudStyle.round_rect(badge_rect, 10.0)), HudStyle.GOLD_DARK, 1.5, true)
	HudStyle.draw_text_centered(self, str(_count), badge, 15, HudStyle.TEXT_LIGHT, 3)

	# Cost gem (top-left, like on the cards).
	var gem: Vector2 = origin + Vector2(2.0, -layers * 2.5 + 4.0)
	HudStyle.draw_crystal(self, gem, 26.0, 1.0, 0.25 * _hover if live else 0.0, 0.7 if disabled else 1.0)
	HudStyle.draw_text_centered(self, str(_cost), gem + Vector2(0, 1.0), 16, Color.WHITE, 4, Color(0.02, 0.05, 0.16))

	# Caption.
	HudStyle.draw_text_centered(self, "DRAW", origin + Vector2(card_size.x * 0.5, card_size.y * 0.5 - layers * 2.5),
		16, HudStyle.GOLD if live else Color(0.75, 0.7, 0.65), 5)


func _draw_card_back(rect: Rect2, top: bool, brightness: float) -> void:
	var back: Color = BACK_COLOR * brightness
	back.a = 1.0
	var outer = HudStyle.round_rect(rect, 8.0)
	draw_colored_polygon(outer, back)
	if top:
		var inner: Rect2 = rect.grow(-5.0)
		draw_colored_polygon(HudStyle.round_rect(inner, 5.0), Color(BACK_LIGHT * brightness, 1.0))
		var c: Vector2 = inner.get_center()
		# Ornament: gold diamond with a ring.
		HudStyle.stroke_ellipse(self, c, Vector2(inner.size.x * 0.32, inner.size.x * 0.32), Color(HudStyle.GOLD, 0.8), 2.0, 28)
		var diamond := PackedVector2Array([
			c + Vector2(0, -inner.size.y * 0.28), c + Vector2(inner.size.x * 0.18, 0),
			c + Vector2(0, inner.size.y * 0.28), c + Vector2(-inner.size.x * 0.18, 0),
		])
		draw_colored_polygon(diamond, Color(HudStyle.GOLD_DARK, 0.85))
		draw_polyline(HudStyle.close(diamond), HudStyle.GOLD, 1.5, true)
		draw_polyline(HudStyle.close(HudStyle.round_rect(inner, 5.0)), Color(HudStyle.GOLD, 0.7), 1.2, true)
	draw_polyline(HudStyle.close(outer), Color(0.12, 0.06, 0.03), 1.5, true)
	if not top:
		draw_line(rect.position + Vector2(6.0, 1.0), Vector2(rect.end.x - 6.0, rect.position.y + 1.0), Color(0.7, 0.5, 0.3, 0.6), 1.0)
