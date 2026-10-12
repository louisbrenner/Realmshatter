class_name VpConvertButton
extends Button
## Coin-to-crystal conversion slots next to the mana bar: one slot per allowed conversion this turn.
## Available slots show a gold coin with an arrow into a crystal and glow while a conversion is
## possible; used slots are greyed with a check mark. Pressing emits BaseButton.pressed.

@export var slot_size: float = 34.0
@export var gap: float = 4.0

var _used: int = 0
var _max: int = 2
var _can_convert: bool = false
var _time: float = 0.0
var _press_flash: float = 0.0

## Conversions already used this turn.
var used: int:
	get:
		return _used

## Maximum conversions per turn.
var max_per_turn: int:
	get:
		return _max


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	flat = true
	text = ""
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Spend 1 VP for 1 AP (max 2 per turn)"
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(func() -> void: _press_flash = 1.0)


## Updates the slots. can_convert enables the button.
func set_state(p_used: int, p_max_per_turn: int, can_convert: bool) -> void:
	var old: int = _used
	_max = maxi(0, p_max_per_turn)
	_used = clampi(p_used, 0, _max)
	_can_convert = can_convert and _used < _max
	disabled = not _can_convert
	tooltip_text = "Spend 1 VP for 1 AP (max %d per turn) - %d left this turn" % [_max, _max - _used]
	if _used > old:
		_press_flash = 1.0
	visible = _max > 0
	custom_minimum_size = _compute_size()
	queue_redraw()


func _compute_size() -> Vector2:
	var n: int = maxi(1, _max)
	return Vector2(n * slot_size + (n - 1) * gap, slot_size + 12.0)


func _process(delta: float) -> void:
	_time += delta
	_press_flash = maxf(0.0, _press_flash - delta * 2.5)
	if _can_convert or _press_flash > 0.0:
		queue_redraw()


func _draw() -> void:
	var hover: bool = is_hovered() and not disabled
	var pulse: float = 0.5 + 0.5 * sin(_time * 3.5)
	for i in range(_max):
		var x: float = i * (slot_size + gap)
		var rect := Rect2(x, 0.0, slot_size, slot_size)
		var is_used: bool = i < _used
		var next: bool = i == _used
		var live: bool = not is_used and _can_convert
		var bg: Color = Color(0.12, 0.1, 0.09, 0.85) if is_used else Color(0.16, 0.1, 0.05, 0.92)
		var border: Color
		if is_used:
			border = Color(0.35, 0.3, 0.26)
		else:
			border = HudStyle.GOLD if live else HudStyle.GOLD_DARK
		if live and next:
			var glow: float = 1.0 if hover else 0.45 + 0.35 * pulse
			draw_colored_polygon(HudStyle.round_rect(rect.grow(3.0), 9.0), Color(1.0, 0.85, 0.35, 0.35 * glow))
		draw_colored_polygon(HudStyle.round_rect(rect, 7.0), bg)
		draw_polyline(HudStyle.close(HudStyle.round_rect(rect, 7.0)), border, 1.6, true)

		var a: float
		if is_used:
			a = 0.35
		else:
			a = 1.0 if live else 0.5
		var coin_pos: Vector2 = rect.position + Vector2(slot_size * 0.3, slot_size * 0.42)
		HudStyle.draw_coin(self, coin_pos, slot_size * 0.2, 3.0, a, _press_flash if (live and next) else 0.0)
		var crystal_pos: Vector2 = rect.position + Vector2(slot_size * 0.74, slot_size * 0.5)
		HudStyle.draw_crystal(self, crystal_pos, slot_size * 0.42, 0.0 if is_used else 1.0, 0.5 if (live and hover) else 0.0, a)
		# Arrow coin -> crystal.
		var from: Vector2 = rect.position + Vector2(slot_size * 0.42, slot_size * 0.78)
		var to: Vector2 = rect.position + Vector2(slot_size * 0.62, slot_size * 0.78)
		var arrow := Color(1.0, 0.92, 0.7, a)
		draw_line(from, to, arrow, 1.6, true)
		draw_line(to, to + Vector2(-4.0, -3.0), arrow, 1.6, true)
		draw_line(to, to + Vector2(-4.0, 3.0), arrow, 1.6, true)
		if is_used:
			var c: Vector2 = rect.get_center()
			draw_polyline(PackedVector2Array([c + Vector2(-7.0, 0.0), c + Vector2(-2.0, 6.0), c + Vector2(8.0, -7.0)]),
				Color(0.45, 1.0, 0.45, 0.95), 3.0, true)
	HudStyle.draw_text_centered(self, "VP > AP", Vector2(size.x * 0.5, slot_size + 6.0), 10,
		HudStyle.GOLD if _can_convert else Color(0.65, 0.6, 0.55), 3)
