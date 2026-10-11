class_name ManaCrystalBar
extends Control
## Hearthstone-style row of mana crystals for action points: "current/max" text followed by
## filled (glowing blue) and empty (dark socket) crystals. Filling pops a crystal in with a flash,
## spending drains it with a burst.

@export var crystal_size: float = 24.0
@export var gap: float = 4.0
@export var font_size: int = 22
@export var show_text: bool = true
## Minimum number of crystal slots drawn (e.g. the base AP per turn).
@export var min_slots: int = 3

var _text_width: float:
	get:
		return font_size * 2.7
var _current: int = 0
var _max: int = 0
var _fill: Array[float] = []
var _flash: Array[float] = []
var _burst: Array[float] = []
var _time: float = 0.0
var _text_pulse: float = 0.0

## Current action points.
var current: int:
	get:
		return _current

## Maximum action points this turn (number of slots). (C# `Max`; renamed to avoid shadowing max().)
var max_: int:
	get:
		return _max


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Sets current and maximum AP; animates the difference unless animate is false.
func set_values(p_current: int, p_max: int, animate: bool = true) -> void:
	p_current = maxi(0, p_current)
	p_max = maxi(p_current, p_max)
	var changed: bool = p_current != _current or p_max != _max
	_current = p_current
	_max = p_max
	var slots: int = _slot_count
	while _fill.size() < slots:
		_fill.append(0.0)
		_flash.append(0.0)
		_burst.append(0.0)
	if not animate or not is_inside_tree():
		for i in range(_fill.size()):
			_fill[i] = 1.0 if i < p_current else 0.0
	elif changed:
		_text_pulse = 1.0
	update_minimum_size()
	queue_redraw()


var _slot_count: int:
	get:
		return maxi(maxi(_max, _current), min_slots)


func _get_minimum_size() -> Vector2:
	var slots: int = _slot_count
	var w: float = (_text_width if show_text else 0.0) + slots * crystal_size + (slots - 1) * gap + 6.0
	return Vector2(w, crystal_size * 1.4)


func _process(delta: float) -> void:
	var dt: float = delta
	_time += dt
	var busy: bool = _text_pulse > 0.0
	_text_pulse = maxf(0.0, _text_pulse - dt * 2.5)
	for i in range(_fill.size()):
		var target: float = 1.0 if i < _current else 0.0
		if not is_equal_approx(_fill[i], target):
			# Staggered: crystals further right react slightly later.
			var speed: float = 4.0 if target > _fill[i] else 5.0
			var before: float = _fill[i]
			_fill[i] = move_toward(_fill[i], target, dt * speed)
			if target > before and _fill[i] >= 1.0:
				_flash[i] = 1.0
			if target < before and before >= 0.999:
				_burst[i] = 1.0
			busy = true
		if _flash[i] > 0.0 or _burst[i] > 0.0:
			_flash[i] = maxf(0.0, _flash[i] - dt * 3.0)
			_burst[i] = maxf(0.0, _burst[i] - dt * 2.5)
			busy = true
	if busy or _current > 0:
		queue_redraw()


func _draw() -> void:
	var x: float = 2.0
	var cy: float = size.y * 0.5
	if show_text:
		var text_scale: float = 1.0 + 0.25 * _text_pulse
		HudStyle.draw_text_centered(self, "%d/%d" % [_current, _max], Vector2(x + _text_width * 0.5, cy),
			roundi(font_size * text_scale), Color(0.85, 0.95, 1.0), 5, Color(0.02, 0.05, 0.16))
		x += _text_width
	var slots: int = _slot_count
	for i in range(slots):
		var fill: float = _fill[i] if i < _fill.size() else 0.0
		var flash: float = _flash[i] if i < _flash.size() else 0.0
		var burst: float = _burst[i] if i < _burst.size() else 0.0
		var c := Vector2(x + crystal_size * 0.5, cy)
		# Gentle shimmer on full crystals.
		var shimmer: float = 0.12 * maxf(0.0, sin(_time * 2.2 - i * 0.6)) if fill >= 0.999 else 0.0
		var pop: float = 1.0 + 0.18 * flash
		var extra: bool = i >= _max
		HudStyle.draw_crystal(self, c, crystal_size * pop, fill, maxf(flash, shimmer), 0.75 if extra else 1.0)
		if burst > 0.0:
			HudStyle.stroke_ellipse(self, c, Vector2.ONE * crystal_size * (0.4 + 0.6 * (1.0 - burst)),
				Color(0.7, 0.9, 1.0, burst), 2.0, 20)
		x += crystal_size + gap
