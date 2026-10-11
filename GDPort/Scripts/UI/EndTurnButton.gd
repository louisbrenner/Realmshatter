class_name EndTurnButton
extends Button
## Big oval stone End Turn button (Hearthstone style). Yellow glowing "END TURN" while it is your
## turn, pulsing green when you have nothing left to do, grey "ENEMY TURN" while the AI acts.

const YELLOW_GLOW := Color(1.0, 0.82, 0.25)

var _player_turn: bool = true
var _nothing_left: bool = false
var _time: float = 0.0
var _hover: float = 0.0
var _press: float = 0.0
var _flip: float = 0.0
var _caption: String = "END TURN"

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


## Sets whose turn it is (flips the caption with a short animation).
func set_player_turn(player_turn: bool) -> void:
	if _player_turn == player_turn:
		return
	_player_turn = player_turn
	_flip = 1.0
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
	_flip = maxf(0.0, _flip - dt * 3.0)
	var s: float = (1.0 + 0.04 * _hover - 0.05 * _press) * (1.0 - 0.12 * sin(_flip * PI))
	scale = Vector2(s, s)
	queue_redraw()


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r := Vector2(size.x * 0.5 - 8.0, size.y * 0.5 - 7.0)
	var active: bool = _player_turn and not disabled
	var pulse: float = 0.5 + 0.5 * sin(_time * (4.5 if _nothing_left else 2.5))

	if active:
		var glow: Color = HudStyle.READY_GREEN if _nothing_left else YELLOW_GLOW
		var strength: float = (0.55 + 0.45 * pulse) if _nothing_left else (0.35 + 0.2 * pulse)
		strength = maxf(strength, _hover * 0.8)
		for i in range(4, 0, -1):
			HudStyle.fill_ellipse(self, c, r + Vector2.ONE * (i * 2.2 + 1.0), Color(glow, 0.12 * strength * (5 - i)), 40)

	# Stone rim with bevel.
	HudStyle.fill_ellipse(self, c + Vector2(0, 3.0), r + Vector2(2.0, 2.0), Color(0.0, 0.0, 0.0, 0.5), 40)
	HudStyle.fill_ellipse(self, c, r + Vector2(1.0, 1.0), Color(0.2, 0.17, 0.15), 40)
	HudStyle.fill_ellipse(self, c, r, Color(0.55, 0.52, 0.48), 40)
	HudStyle.fill_ellipse(self, c + Vector2(0, 1.5), r - Vector2(5.0, 5.0), Color(0.3, 0.28, 0.26), 40)

	# Face.
	var face: Color
	var face_light: Color
	if not _player_turn:
		face = Color(0.36, 0.35, 0.34)
		face_light = Color(0.5, 0.49, 0.47)
	elif disabled:
		face = Color(0.45, 0.4, 0.3)
		face_light = Color(0.58, 0.53, 0.42)
	elif _nothing_left:
		face = Color(0.25, 0.62, 0.2)
		face_light = Color(0.55, 0.9, 0.4)
	else:
		face = Color(0.85, 0.62, 0.12)
		face_light = Color(1.0, 0.86, 0.4)
	face = face.lerp(face_light, _hover * 0.35)
	var fr: Vector2 = r - Vector2(7.0, 7.0)
	HudStyle.fill_ellipse(self, c, fr, face.darkened(0.25), 40)
	HudStyle.fill_ellipse(self, c + Vector2(0, -fr.y * 0.18), fr * Vector2(0.92, 0.72), face, 40)
	HudStyle.fill_ellipse(self, c + Vector2(0, -fr.y * 0.42), fr * Vector2(0.7, 0.3), Color(face_light, 0.6), 32)
	HudStyle.stroke_ellipse(self, c, fr, Color(0.15, 0.1, 0.05, 0.9), 2.0, 40)

	# Rim rivets.
	for i in range(10):
		var a: float = TAU * i / 10.0 + 0.3
		var p: Vector2 = c + Vector2(cos(a) * (r.x - 3.0), sin(a) * (r.y - 3.0))
		draw_circle(p, 1.8, Color(0.75, 0.7, 0.62))

	var caption: String = "ENEMY TURN" if not _player_turn else "END TURN"
	var text_color: Color
	if not _player_turn:
		text_color = Color(0.82, 0.8, 0.78)
	else:
		text_color = Color(0.9, 0.86, 0.76) if disabled else Color.WHITE
	var font_size: int = roundi(clampf(size.y * 0.3, 12.0, 30.0))
	var fit: float = (fr.x * 1.7) / maxf(1.0, HudStyle.text_width(caption, font_size))
	if fit < 1.0:
		font_size = maxi(10, floori(font_size * fit))
	_caption = caption
	HudStyle.draw_text_centered(self, _caption, c + Vector2(0, 1.0), font_size, text_color, 6, Color(0.12, 0.07, 0.02))
