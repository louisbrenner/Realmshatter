class_name VictoryCoinStack
extends Control
## Victory points as stacking gold coins: the target is split into columns (e.g. 20 = 4 stacks of 5),
## faint slots show the remaining progress. Gained coins drop in with a bounce and a glint,
## spent coins float up and fade.

@export var coin_radius: float = 15.0
@export var coin_thickness: float = 5.0
@export var column_gap: float = 7.0
@export var max_columns: int = 5
@export var accent: Color = HudStyle.PLAYER_BLUE

const DROP_HEIGHT := 70.0
const DROP_TIME := 0.42
const DROP_STAGGER := 0.09
const LEAVE_TIME := 0.45
## Drop progress value of a coin lying on its stack (negative = waiting, 0..1 = falling).
const RESTING := 2.0

var _target: int = 20
var _points: int = 0
var _drop: Array[float] = []
var _flash: Array[float] = []
## Leaving coins as [index: int, t: float] pairs.
var _leaving: Array[Array] = []
var _time: float = 0.0

## Victory points needed to win.
var target: int:
	get:
		return _target
	set(value):
		_target = maxi(1, value)
		_points = mini(_points, _target)
		_sync_lists(_points)
		update_minimum_size()
		queue_redraw()

## Current points (clamped to the target for display).
var points: int:
	get:
		return _points


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sync_lists(_points)


## Sets the points; animates coin drops (gain) or coins floating away (loss) unless animate is false.
func set_points(p_points: int, animate: bool = true) -> void:
	p_points = clampi(p_points, 0, _target)
	var old: int = _points
	_points = p_points
	_sync_lists(p_points)
	if not animate or not is_inside_tree():
		for i in range(_drop.size()):
			_drop[i] = RESTING
		_leaving.clear()
		queue_redraw()
		return
	for i in range(old, p_points):
		# Negative = waiting (stagger), 0..1 = falling.
		_drop[i] = -(i - old) * DROP_STAGGER / DROP_TIME
	for i in range(p_points, old):
		_leaving.append([i, 0.0])
	queue_redraw()


func _get_minimum_size() -> Vector2:
	var layout: Vector2i = _get_layout()
	var cols: int = layout.x
	var per_stack: int = layout.y
	var w: float = cols * coin_radius * 2.0 + (cols - 1) * column_gap + 4.0
	var h: float = per_stack * coin_thickness + coin_radius * 0.84 + coin_thickness + 6.0
	return Vector2(w, h)


func _process(delta: float) -> void:
	var dt: float = delta
	_time += dt
	var busy: bool = false
	for i in range(_drop.size()):
		if _drop[i] < 1.0:
			_drop[i] += dt / DROP_TIME
			if _drop[i] >= 1.0:
				_drop[i] = RESTING
				_flash[i] = 1.0
			busy = true
		if _flash[i] > 0.0:
			_flash[i] = maxf(0.0, _flash[i] - dt * 2.5)
			busy = true
	for i in range(_leaving.size() - 1, -1, -1):
		var index: int = _leaving[i][0]
		var t: float = _leaving[i][1]
		t += dt / LEAVE_TIME
		if t >= 1.0:
			_leaving.remove_at(i)
		else:
			_leaving[i] = [index, t]
		busy = true
	if busy:
		queue_redraw()


func _draw() -> void:
	var layout: Vector2i = _get_layout()
	var cols: int = layout.x
	var per_stack: int = layout.y
	var r: float = coin_radius
	var t: float = coin_thickness
	var col_w: float = r * 2.0
	var total_w: float = cols * col_w + (cols - 1) * column_gap
	var x0: float = (size.x - total_w) * 0.5 + r
	var base_y: float = size.y - r * 0.42 - t - 3.0

	# Accent felt pad under the stacks.
	var pad := Rect2(x0 - r - 2.0, base_y - r * 0.1, total_w + 4.0, r * 0.84 + t + 4.0)
	draw_colored_polygon(HudStyle.round_rect(pad, 6.0), Color(accent.darkened(0.65), 0.55))

	for c in range(cols):
		var cx: float = x0 + c * (col_w + column_gap)
		for k in range(per_stack):
			var index: int = c * per_stack + k
			if index >= _target:
				break
			var pos := Vector2(cx, base_y - k * t)
			if index >= _points:
				if not _is_leaving(index):
					HudStyle.draw_coin(self, pos, r, t, 1.0, 0.0, true)
				continue
			var d: float = _drop[index] if index < _drop.size() else RESTING
			if d < 0.0:
				continue
			var offset: float = 0.0
			var alpha: float = 1.0
			if d < 1.0:
				var e: float = _bounce_out(d)
				offset = -DROP_HEIGHT * (1.0 - e)
				alpha = clampf(d * 4.0, 0.0, 1.0)
			var flash: float = _flash[index] if index < _flash.size() else 0.0
			HudStyle.draw_coin(self, pos + Vector2(0, offset), r, t, alpha, flash)
		# Column complete: small shine above the stack.
		var top: int = (c + 1) * per_stack
		if top <= _points and top <= _target:
			var pulse: float = 0.5 + 0.5 * sin(_time * 3.0 + c)
			HudStyle.fill_ellipse(self, Vector2(cx, base_y - per_stack * t - 2.0), Vector2(r * 0.35, r * 0.12),
				Color(1.0, 0.95, 0.7, 0.25 + 0.25 * pulse), 12)

	for entry in _leaving:
		var index: int = entry[0]
		var lt: float = entry[1]
		var c: int = index / per_stack
		var k: int = index % per_stack
		var cx: float = x0 + c * (col_w + column_gap)
		var pos := Vector2(cx, base_y - k * t - lt * 40.0)
		HudStyle.draw_coin(self, pos, r * (1.0 + 0.3 * lt), t, 1.0 - lt, 0.6)


func _is_leaving(index: int) -> bool:
	for entry in _leaving:
		if entry[0] == index:
			return true
	return false


## Returns Vector2i(cols, per_stack) (C# out parameters).
func _get_layout() -> Vector2i:
	var max_cols: int = maxi(1, max_columns)
	var cols: int = clampi(ceili(_target / 5.0), 1, max_cols)
	var per_stack: int = ceili(_target / float(cols))
	return Vector2i(cols, per_stack)


func _sync_lists(count: int) -> void:
	while _drop.size() < _target:
		_drop.append(RESTING)
		_flash.append(0.0)
	for i in range(count, _drop.size()):
		_drop[i] = RESTING


static func _bounce_out(x: float) -> float:
	const N1 := 7.5625
	const D1 := 2.75
	if x < 1.0 / D1:
		return N1 * x * x
	if x < 2.0 / D1:
		x -= 1.5 / D1
		return N1 * x * x + 0.75
	if x < 2.5 / D1:
		x -= 2.25 / D1
		return N1 * x * x + 0.9375
	x -= 2.625 / D1
	return N1 * x * x + 0.984375
