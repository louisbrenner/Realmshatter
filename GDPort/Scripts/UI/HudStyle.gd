class_name HudStyle
extends RefCounted
## Shared palette, style boxes, theme and procedural drawing helpers for the Hearthstone-styled HUD
## (dark wood plaques with gold trim, parchment ribbons, gold coins, blue mana crystals).

const WOOD_DARK := Color(0.13, 0.075, 0.04)
const WOOD_MID := Color(0.27, 0.16, 0.08)
const WOOD_LIGHT := Color(0.42, 0.26, 0.13)
const GOLD := Color(0.98, 0.79, 0.38)
const GOLD_DARK := Color(0.55, 0.37, 0.13)
const GOLD_DEEP := Color(0.32, 0.2, 0.06)
const PARCHMENT := Color(0.95, 0.87, 0.69)
const PARCHMENT_DARK := Color(0.78, 0.64, 0.42)
const INK := Color(0.24, 0.14, 0.06)
const TEXT_LIGHT := Color(1.0, 0.94, 0.8)
const OUTLINE := Color(0.07, 0.04, 0.02)
const PLAYER_BLUE := Color(0.35, 0.65, 1.0)
const ENEMY_RED := Color(1.0, 0.38, 0.3)
const MANA_BLUE := Color(0.22, 0.58, 1.0)
const MANA_LIGHT := Color(0.7, 0.92, 1.0)
const READY_GREEN := Color(0.35, 1.0, 0.35)
const STONE_GREY := Color(0.42, 0.4, 0.38)

static var _font: Font
static var _theme: Theme

## The serif HUD font (Resources/UI/CardFont.tres).
static var font: Font:
	get:
		if _font == null:
			_font = VfxAssets.card_font
		return _font


## Player accent color (0 = you / blue, 1 = AI / red).
static func accent(player: int) -> Color:
	return PLAYER_BLUE if player == 0 else ENEMY_RED


## Creates a flat style box with rounded corners, border and drop shadow.
static func box(bg: Color, border: Color, radius: int = 10, border_width: int = 2, shadow: int = 6, shadow_alpha: float = 0.45) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.shadow_color = Color(0.0, 0.0, 0.0, shadow_alpha)
	b.shadow_size = shadow
	b.shadow_offset = Vector2(0.0, 2.0)
	b.corner_detail = 8
	b.anti_aliasing = true
	b.set_corner_radius_all(radius)
	b.set_border_width_all(border_width)
	return b


## Dark wood plaque with gold trim; an optional accent (Color or null) colors the top border.
static func wood_panel(p_accent: Variant = null, padding: int = 10) -> StyleBoxFlat:
	var b: StyleBoxFlat = box(Color(WOOD_DARK, 0.93), GOLD_DARK, 12, 2, 10, 0.5)
	if p_accent != null:
		var a: Color = p_accent
		b.border_color = a.lerp(GOLD_DARK, 0.35)
		b.border_width_top = 4
	b.set_content_margin_all(padding)
	return b


## Parchment ribbon used for hints and toasts.
static func parchment_panel(pad_h: int = 18, pad_v: int = 6) -> StyleBoxFlat:
	var b: StyleBoxFlat = box(Color(PARCHMENT, 0.95), Color(0.45, 0.28, 0.1), 6, 2, 8, 0.5)
	b.content_margin_left = pad_h
	b.content_margin_right = pad_h
	b.content_margin_top = pad_v
	b.content_margin_bottom = pad_v
	return b


## The HUD theme: serif font, wood/gold buttons, parchment tooltips.
static func create_theme() -> Theme:
	if _theme != null:
		return _theme
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 16

	theme.set_color("font_color", "Label", TEXT_LIGHT)
	# No Label outline in the theme: card labels inside the HUD inherit it. HUD labels set their own.
	theme.set_color("font_outline_color", "Label", OUTLINE)

	var normal: StyleBoxFlat = box(WOOD_MID, GOLD_DARK, 8, 2, 4)
	var hover: StyleBoxFlat = box(WOOD_LIGHT, GOLD, 8, 2, 6)
	var pressed: StyleBoxFlat = box(WOOD_DARK, GOLD, 8, 2, 2)
	var disabled: StyleBoxFlat = box(Color(0.2, 0.17, 0.15, 0.85), Color(0.35, 0.3, 0.25), 8, 2, 2)
	for b: StyleBoxFlat in [normal, hover, pressed, disabled]:
		b.content_margin_left = 12
		b.content_margin_right = 12
		b.content_margin_top = 4
		b.content_margin_bottom = 4
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", TEXT_LIGHT)
	theme.set_color("font_hover_color", "Button", Color(1.0, 0.97, 0.88))
	theme.set_color("font_pressed_color", "Button", GOLD)
	theme.set_color("font_disabled_color", "Button", Color(0.6, 0.55, 0.5))
	theme.set_color("font_outline_color", "Button", OUTLINE)
	theme.set_constant("outline_size", "Button", 4)

	theme.set_stylebox("panel", "PanelContainer", wood_panel())
	theme.set_stylebox("panel", "TooltipPanel", parchment_panel(10, 6))
	theme.set_color("font_color", "TooltipLabel", INK)
	theme.set_font_size("font_size", "TooltipLabel", 15)

	theme.set_font("normal_font", "RichTextLabel", font)
	theme.set_font("bold_font", "RichTextLabel", font)
	theme.set_font_size("normal_font_size", "RichTextLabel", 13)
	theme.set_font_size("bold_font_size", "RichTextLabel", 13)
	theme.set_color("default_color", "RichTextLabel", TEXT_LIGHT)
	theme.set_color("font_outline_color", "RichTextLabel", OUTLINE)
	theme.set_constant("outline_size", "RichTextLabel", 2)
	theme.set_constant("line_separation", "RichTextLabel", 2)
	_theme = theme
	return theme


## Points of an ellipse (closed polygon, not repeating the first point).
static func ellipse(center: Vector2, radius: Vector2, segments: int = 28, start_angle: float = 0.0, arc: float = TAU) -> PackedVector2Array:
	var full: bool = is_equal_approx(arc, TAU)
	var count: int = segments if full else segments + 1
	var points := PackedVector2Array()
	points.resize(count)
	for i in range(count):
		var a: float = start_angle + arc * i / segments
		points[i] = center + Vector2(cos(a) * radius.x, sin(a) * radius.y)
	return points


## Filled ellipse with an antialiased edge.
static func fill_ellipse(ci: CanvasItem, center: Vector2, radius: Vector2, color: Color, segments: int = 28) -> void:
	var pts: PackedVector2Array = ellipse(center, radius, segments)
	ci.draw_colored_polygon(pts, color)
	ci.draw_polyline(close(pts), color, 1.2, true)


## Ellipse outline.
static func stroke_ellipse(ci: CanvasItem, center: Vector2, radius: Vector2, color: Color, width: float = 1.5, segments: int = 28) -> void:
	ci.draw_polyline(close(ellipse(center, radius, segments)), color, width, true)


## Appends the first point to close a polyline (accepts PackedVector2Array or Array of Vector2).
static func close(pts) -> PackedVector2Array:
	var closed := PackedVector2Array(pts)
	closed.append(closed[0])
	return closed


## Gold coin seen slightly from above. center = middle of the top face; radius = face radius;
## thickness = visible edge height. ghost draws only a faint slot outline.
static func draw_coin(ci: CanvasItem, center: Vector2, radius: float, thickness: float, alpha: float = 1.0, flash: float = 0.0, ghost: bool = false) -> void:
	var r := Vector2(radius, radius * 0.42)
	if ghost:
		stroke_ellipse(ci, center + Vector2(0, thickness), r, Color(GOLD, 0.18 * alpha), 1.2, 24)
		return
	var edge := Color(0.62, 0.4, 0.12, alpha)
	var edge_dark := Color(0.36, 0.22, 0.06, alpha)
	# Edge band: bottom ellipse + rectangle between the faces.
	fill_ellipse(ci, center + Vector2(0, thickness), r, edge_dark, 24)
	ci.draw_rect(Rect2(center.x - radius, center.y, radius * 2.0, thickness), edge)
	# Ridges along the edge.
	for i in range(1, 8):
		var x: float = center.x - radius + radius * 2.0 * i / 8.0
		var h: float = sqrt(maxf(0.0, 1.0 - pow((x - center.x) / radius, 2.0))) * r.y
		ci.draw_line(Vector2(x, center.y + h), Vector2(x, center.y + h + thickness), Color(edge_dark, alpha * 0.6), 1.0)
	var face: Color = Color(1.0, 0.8, 0.36, alpha).lerp(Color(1.0, 1.0, 0.85, alpha), flash)
	fill_ellipse(ci, center, r, face, 26)
	fill_ellipse(ci, center, r * 0.74, Color(0.9, 0.64, 0.22, alpha).lerp(Color(1.0, 1.0, 0.9, alpha), flash), 22)
	fill_ellipse(ci, center + Vector2(-radius * 0.12, -r.y * 0.12), r * 0.5, Color(1.0, 0.88, 0.5, alpha * 0.9), 18)
	stroke_ellipse(ci, center, r, Color(0.45, 0.28, 0.08, alpha), 1.2, 26)
	# Highlight glint.
	ci.draw_line(center + Vector2(-radius * 0.45, -r.y * 0.45), center + Vector2(-radius * 0.1, -r.y * 0.62),
		Color(1.0, 1.0, 0.9, 0.75 * alpha), 1.5, true)


## Hearthstone-like mana crystal (faceted gem). fill 0..1 blends from empty socket to glowing crystal.
static func draw_crystal(ci: CanvasItem, center: Vector2, size: float, fill: float, flash: float = 0.0, alpha: float = 1.0) -> void:
	var w: float = size * 0.5
	var h: float = size * 0.62
	var outer := PackedVector2Array([
		center + Vector2(0, -h), center + Vector2(w, -h * 0.35), center + Vector2(w * 0.8, h * 0.55),
		center + Vector2(0, h), center + Vector2(-w * 0.8, h * 0.55), center + Vector2(-w, -h * 0.35),
	])
	var socket := Color(0.06, 0.08, 0.15, 0.9 * alpha)
	var socket_rim := Color(0.3, 0.32, 0.4, alpha)
	ci.draw_colored_polygon(outer, socket)
	if fill > 0.001:
		var glow := Color(MANA_BLUE, 0.35 * fill * alpha)
		fill_ellipse(ci, center, Vector2(w * 1.5, h * 1.25), glow, 20)
		var base_col: Color = MANA_BLUE.lerp(Color.WHITE, flash * 0.6)
		var dark: Color = Color(0.08, 0.25, 0.7).lerp(Color.WHITE, flash * 0.4)
		var light: Color = MANA_LIGHT.lerp(Color.WHITE, flash)
		var k: float = clampf(fill, 0.0, 1.0)
		var c: Vector2 = center
		var top: Vector2 = c + Vector2(0, -h) * k
		var scaled := PackedVector2Array()
		scaled.resize(outer.size())
		for i in range(outer.size()):
			scaled[i] = c + (outer[i] - c) * (0.55 + 0.45 * k)
		ci.draw_colored_polygon(scaled, Color(base_col, alpha * k))
		# Facets: upper-left light, lower-right dark, central table.
		var mid: Vector2 = c + Vector2(0, -h * 0.1) * k
		ci.draw_colored_polygon(PackedVector2Array([scaled[0], scaled[5], mid]), Color(light, alpha * k))
		ci.draw_colored_polygon(PackedVector2Array([scaled[0], scaled[1], mid]), Color(base_col.lerp(light, 0.45), alpha * k))
		ci.draw_colored_polygon(PackedVector2Array([scaled[2], scaled[3], mid]), Color(dark, alpha * k))
		ci.draw_colored_polygon(PackedVector2Array([scaled[3], scaled[4], mid]), Color(dark.lerp(base_col, 0.5), alpha * k))
		ci.draw_line(top + Vector2(-w * 0.25, h * 0.35), top + Vector2(-w * 0.05, h * 0.15), Color(1, 1, 1, 0.8 * alpha * k), 1.5, true)
	ci.draw_polyline(close(outer), Color(0.75, 0.9, 1.0, alpha) if fill > 0.5 else socket_rim, 1.6, true)


## Draws text centered on a point with an outline (outline_color: Color or null = OUTLINE).
static func draw_text_centered(ci: CanvasItem, text: String, center: Vector2, font_size: int, color: Color, outline: int = 4, outline_color: Variant = null) -> void:
	var f: Font = font
	if f == null or text.is_empty():
		return
	var size: Vector2 = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var ascent: float = f.get_ascent(font_size)
	var descent: float = f.get_descent(font_size)
	var pos := Vector2(center.x - size.x * 0.5, center.y + (ascent - descent) * 0.5)
	if outline > 0:
		var oc: Color = outline_color if outline_color != null else OUTLINE
		ci.draw_string_outline(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline, oc)
	ci.draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## Width of a text in the HUD font.
static func text_width(text: String, font_size: int) -> float:
	var f: Font = font
	if f == null:
		return 0.0
	return f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


## Points of a rounded rectangle.
static func round_rect(rect: Rect2, radius: float, corner_segments: int = 5) -> PackedVector2Array:
	var pts := PackedVector2Array()
	radius = minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var centers: Array[Vector2] = [
		Vector2(rect.end.x - radius, rect.position.y + radius),
		Vector2(rect.end.x - radius, rect.end.y - radius),
		Vector2(rect.position.x + radius, rect.end.y - radius),
		Vector2(rect.position.x + radius, rect.position.y + radius),
	]
	var starts: Array[float] = [-PI * 0.5, 0.0, PI * 0.5, PI]
	for c in range(4):
		for i in range(corner_segments + 1):
			var a: float = starts[c] + PI * 0.5 * i / corner_segments
			pts.append(centers[c] + Vector2(cos(a), sin(a)) * radius)
	return pts
