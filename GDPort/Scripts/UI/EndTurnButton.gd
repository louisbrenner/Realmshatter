class_name EndTurnButton
extends Button
## End Turn medallion: a brass ring with engraved hour marks around a glass hourglass, and a cloth ribbon with
## the caption underneath. Your turn: warm amber face, the sand trickles slowly; nothing left to do: pulsing
## green; enemy turn: dark crimson face and the hourglass flips and runs. Presses sink the medallion.

const BRASS := Color(0.86, 0.66, 0.3)
const BRASS_DARK := Color(0.42, 0.28, 0.1)
const GLASS := Color(0.85, 0.92, 1.0, 0.35)
const SAND := Color(1.0, 0.82, 0.45)

var _player_turn: bool = true
var _nothing_left: bool = false
var _time: float = 0.0
var _hover: float = 0.0
var _press: float = 0.0
var _flip: float = 0.0
var _sand: float = 0.7

## True while it is the human player's turn.
var is_player_turn: bool:
	get:
		return _player_turn


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	flat = true
	text = ""
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pivot_offset = size * 0.5
	resized.connect(func() -> void: pivot_offset = size * 0.5)


## Sets whose turn it is (the hourglass flips).
func set_player_turn(player_turn: bool) -> void:
	if _player_turn == player_turn:
		return
	_player_turn = player_turn
	_flip = 1.0
	_sand = 1.0
	queue_redraw()


## Green "you're done" glow (e.g. no AP left).
func set_nothing_left(nothing_left: bool) -> void:
	_nothing_left = nothing_left
	queue_redraw()


func _process(delta: float) -> void:
	var dt: float = delta
	_time += dt
	var hovered: bool = is_hovered() and not disabled
	_hover = move_toward(_hover, 1.0 if hovered else 0.0, dt * 8.0)
	var pressing: bool = button_pressed or (hovered and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	_press = move_toward(_press, 1.0 if pressing else 0.0, dt * 14.0)
	_flip = maxf(0.0, _flip - dt * 2.2)
	_sand = maxf(0.05, _sand - dt * (0.01 if _player_turn else 0.12))
	if not _player_turn and _sand <= 0.05:
		_sand = 1.0
		_flip = 1.0
	var s: float = 1.0 + 0.035 * _hover - 0.05 * _press
	scale = Vector2(s, s)
	queue_redraw()


func _draw() -> void:
	var ribbon_h: float = 30.0
	var c := Vector2(size.x * 0.5, (size.y - ribbon_h * 0.6) * 0.5)
	var r: float = minf(size.x * 0.5 - 6.0, (size.y - ribbon_h * 0.6) * 0.5 - 6.0)
	var active: bool = _player_turn and not disabled
	var pulse: float = 0.5 + 0.5 * sin(_time * (4.5 if _nothing_left else 2.2))

	var face: Color
	if not _player_turn:
		face = Color(0.36, 0.08, 0.07)
	elif disabled:
		face = Color(0.3, 0.27, 0.22)
	elif _nothing_left:
		face = Color(0.16, 0.45, 0.14).lerp(Color(0.3, 0.7, 0.22), pulse)
	else:
		face = Color(0.5, 0.3, 0.08).lerp(Color(0.62, 0.4, 0.1), _hover)

	# Glow halo.
	if active:
		var glow: Color = HudStyle.READY_GREEN if _nothing_left else Color(1.0, 0.78, 0.3)
		var strength: float = maxf(0.5 + 0.5 * pulse if _nothing_left else 0.25 + 0.15 * pulse, _hover * 0.7)
		for i in range(5, 0, -1):
			draw_circle(c, r + i * 3.0, Color(glow, 0.08 * strength * (6 - i)))

	# Brass ring with bevel and hour marks.
	draw_circle(c + Vector2(0, 4.0), r + 2.0, Color(0, 0, 0, 0.45))
	draw_circle(c, r + 1.0, BRASS_DARK)
	draw_circle(c, r - 1.0, BRASS.lerp(Color.WHITE, 0.12 * _hover))
	draw_arc(c, r - 3.0, PI * 1.1, PI * 1.9, 24, Color(1.0, 0.95, 0.75, 0.6), 2.0, true)
	draw_circle(c, r - 9.0, BRASS_DARK)
	for i in range(12):
		var a: float = TAU * i / 12.0
		var dir := Vector2(cos(a), sin(a))
		draw_line(c + dir * (r - 7.5), c + dir * (r - 3.5), BRASS_DARK, 2.5 if i % 3 == 0 else 1.5, true)
	# Face.
	var fr: float = r - 11.0
	draw_circle(c, fr, face.darkened(0.3))
	draw_circle(c + Vector2(0, -fr * 0.06), fr * 0.94, face)
	draw_circle(c + Vector2(-fr * 0.25, -fr * 0.35), fr * 0.45, Color(1.0, 1.0, 1.0, 0.07))

	_draw_hourglass(c, fr * 0.62)

	# Ribbon with caption.
	var caption: String = "ENEMY TURN" if not _player_turn else "END TURN"
	var rw: float = size.x - 4.0
	var ribbon := Rect2(Vector2(2.0, size.y - ribbon_h - 2.0), Vector2(rw, ribbon_h))
	var cloth: Color
	if not _player_turn:
		cloth = Color(0.45, 0.1, 0.08)
	elif _nothing_left:
		cloth = Color(0.18, 0.45, 0.14)
	else:
		cloth = Color(0.55, 0.16, 0.1)
	var tail := PackedVector2Array([
		ribbon.position + Vector2(-2.0, 6.0), ribbon.position + Vector2(14.0, 6.0), ribbon.position + Vector2(14.0, ribbon_h + 4.0),
		ribbon.position + Vector2(-2.0, ribbon_h + 4.0), ribbon.position + Vector2(5.0, ribbon_h * 0.5 + 5.0),
	])
	draw_colored_polygon(tail, cloth.darkened(0.35))
	var tail2 := PackedVector2Array()
	tail2.resize(tail.size())
	for i in range(tail.size()):
		tail2[i] = Vector2(size.x - tail[i].x, tail[i].y)
	draw_colored_polygon(tail2, cloth.darkened(0.35))
	var band := Rect2(ribbon.position + Vector2(8.0, 0.0), Vector2(rw - 16.0, ribbon_h))
	draw_rect(band, cloth)
	draw_rect(Rect2(band.position, Vector2(band.size.x, 3.0)), cloth.lightened(0.25))
	draw_rect(Rect2(band.position + Vector2(0, band.size.y - 3.0), Vector2(band.size.x, 3.0)), cloth.darkened(0.3))
	draw_rect(band, BRASS_DARK, false, 1.5)
	var font_size: int = 16
	var fit: float = (band.size.x - 12.0) / maxf(1.0, HudStyle.text_width(caption, font_size))
	if fit < 1.0:
		font_size = maxi(10, floori(font_size * fit))
	HudStyle.draw_text_centered(self, caption, band.get_center() + Vector2(0, 1.0), font_size,
		Color(0.8, 0.76, 0.7) if (disabled and _player_turn) else Color.WHITE, 5, Color(0.12, 0.04, 0.02))


func _draw_hourglass(c: Vector2, h: float) -> void:
	var angle: float = PI * smoothstep(0.0, 1.0, 1.0 - _flip)
	draw_set_transform(c, angle if _flip > 0.0 else 0.0, Vector2.ONE)
	var w: float = h * 0.62
	var frame := Color(0.32, 0.2, 0.08)
	# Glass bulbs.
	var glass := PackedVector2Array([
		Vector2(-w, -h * 0.85), Vector2(w, -h * 0.85), Vector2(w * 0.18, -h * 0.05), Vector2(w * 0.18, h * 0.05),
		Vector2(w, h * 0.85), Vector2(-w, h * 0.85), Vector2(-w * 0.18, h * 0.05), Vector2(-w * 0.18, -h * 0.05),
	])
	draw_colored_polygon(glass, GLASS)
	# Sand: top bulb holds _sand, bottom the rest.
	var top: float = clampf(_sand, 0.0, 1.0)
	if top > 0.02:
		var ty: float = -h * 0.05 - h * 0.8 * top
		var tw: float = lerpf(w * 0.18, w, top)
		draw_colored_polygon(PackedVector2Array([Vector2(-tw, ty), Vector2(tw, ty), Vector2(w * 0.12, -h * 0.06), Vector2(-w * 0.12, -h * 0.06)]), SAND)
	var bottom: float = 1.0 - top
	var by: float = h * 0.85 - h * 0.7 * bottom
	draw_colored_polygon(PackedVector2Array([Vector2(-w * 0.9, h * 0.84), Vector2(w * 0.9, h * 0.84), Vector2(0.0, by)]), SAND.darkened(0.1))
	if top > 0.02:
		draw_line(Vector2(0, -h * 0.05), Vector2(0, by), SAND, 1.5)
	draw_polyline(PackedVector2Array([glass[0], glass[1], glass[2], glass[3], glass[4], glass[5], glass[6], glass[7], glass[0]]),
		Color(1.0, 1.0, 1.0, 0.55), 1.5, true)
	# Wooden caps and posts.
	draw_rect(Rect2(-w - 4.0, -h - 4.0, (w + 4.0) * 2.0, 7.0), frame)
	draw_rect(Rect2(-w - 4.0, h - 3.0, (w + 4.0) * 2.0, 7.0), frame)
	draw_line(Vector2(-w - 2.0, -h), Vector2(-w - 2.0, h), frame, 2.5)
	draw_line(Vector2(w + 2.0, -h), Vector2(w + 2.0, h), frame, 2.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
