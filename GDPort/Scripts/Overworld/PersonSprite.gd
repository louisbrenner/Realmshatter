class_name PersonSprite
extends RefCounted
## Draws a small top-down townsperson (shadow, robe, arms, head, hood/hat) on any CanvasItem.

const SKIN := Color(0.95, 0.78, 0.62)
const OUTLINE := Color(0.12, 0.08, 0.05)


## Draws the figure with its feet at 'feet'. bob = walk phase (0 = standing), facing = -1 left / 1 right,
## crown = gold crown instead of a hood (clan leaders), staff = carries a staff.
static func draw(ci: CanvasItem, feet: Vector2, robe: Color, accent: Color, bob: float, facing: float, crown: bool = false, staff: bool = false) -> void:
	var lift: float = absf(sin(bob)) * 3.0
	var body: Vector2 = feet + Vector2(0, -18 - lift)
	ci.draw_set_transform(Vector2.ZERO)
	HudStyle.fill_ellipse(ci, feet + Vector2(0, 1), Vector2(14, 5), Color(0, 0, 0, 0.28), 16)

	# Legs.
	var step: float = sin(bob) * 4.0
	ci.draw_line(feet + Vector2(-5, -10 - lift), feet + Vector2(-5 + step, -1), OUTLINE, 4.0)
	ci.draw_line(feet + Vector2(5, -10 - lift), feet + Vector2(5 - step, -1), OUTLINE, 4.0)

	# Robe (trapezoid) with trim.
	var robe_shape := PackedVector2Array([
		body + Vector2(-9, -10), body + Vector2(9, -10), body + Vector2(13, 10), body + Vector2(-13, 10),
	])
	ci.draw_colored_polygon(robe_shape, robe)
	ci.draw_polyline(PackedVector2Array([robe_shape[0], robe_shape[1], robe_shape[2], robe_shape[3], robe_shape[0]]), OUTLINE, 1.5, true)
	ci.draw_line(body + Vector2(-12, 7), body + Vector2(12, 7), accent, 2.5)
	ci.draw_line(body + Vector2(0, -9), body + Vector2(0, 9), accent.darkened(0.2), 1.5)

	# Arms.
	var swing: float = sin(bob) * 3.0
	ci.draw_line(body + Vector2(-9, -7), body + Vector2(-14, 4 + swing), robe.darkened(0.2), 4.0)
	ci.draw_line(body + Vector2(9, -7), body + Vector2(14, 4 - swing), robe.darkened(0.2), 4.0)
	if staff:
		var hand: Vector2 = body + Vector2(14 * facing, 4)
		ci.draw_line(hand + Vector2(0, 10), hand + Vector2(0, -30), Color(0.4, 0.26, 0.12), 3.0)
		ci.draw_circle(hand + Vector2(0, -32), 4.5, accent.lightened(0.3))

	# Head.
	var head: Vector2 = body + Vector2(0, -18)
	ci.draw_circle(head, 9.0, OUTLINE)
	ci.draw_circle(head, 7.8, SKIN)
	ci.draw_circle(head + Vector2(2.5 * facing + 1.5, -1), 1.3, OUTLINE)
	ci.draw_circle(head + Vector2(2.5 * facing - 2.5, -1), 1.3, OUTLINE)
	if crown:
		var c := PackedVector2Array([
			head + Vector2(-8, -5), head + Vector2(-8, -14), head + Vector2(-4, -9), head + Vector2(0, -16),
			head + Vector2(4, -9), head + Vector2(8, -14), head + Vector2(8, -5),
		])
		ci.draw_colored_polygon(c, Color(1.0, 0.8, 0.25))
		ci.draw_polyline(PackedVector2Array([c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[0]]), OUTLINE, 1.2, true)
	else:
		# Hood.
		ci.draw_arc(head, 9.0, PI * 1.05, PI * 1.95, 12, robe.darkened(0.15), 5.0)


## Draws a text centred above a point with an outline (names, prompts).
static func draw_label(ci: CanvasItem, center: Vector2, text: String, size: int, color: Color) -> void:
	var font: Font = VfxAssets.get_card_text_bold_font()
	var s: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var at := Vector2(center.x - s.x / 2, center.y)
	ci.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color(0.08, 0.05, 0.03))
	ci.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
