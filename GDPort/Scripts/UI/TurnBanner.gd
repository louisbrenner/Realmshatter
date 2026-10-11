class_name TurnBanner
extends Control
## Full-width sweeping banner for turn changes ("YOUR TURN" / "ENEMY TURN" + turn number).
## The ribbon sweeps in from the left, the title pops, holds and the banner fades out to the right.
## play is awaitable; a new play replaces a running one (the previous await then completes).

## Emitted whenever a pending play completes (internal; replaces C# TaskCompletionSource).
signal _pending_completed

@export var duration: float = 1.25

var _title: String = ""
var _subtitle: String = ""
var _accent: Color = HudStyle.PLAYER_BLUE
var _t: float = 1.0
var _time: float = 0.0
var _tween: Tween
var _play_id: int = 0
var _completed_id: int = 0

## True while a banner animation runs.
var is_playing: bool:
	get:
		return _tween != null and _tween.is_valid() and _tween.is_running()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## Plays the banner; completes (when awaited) when it has faded out.
func play(title: String, subtitle: String, accent: Color) -> void:
	if _tween != null:
		_tween.kill()
	_complete(_play_id)
	_play_id += 1
	var id: int = _play_id
	_title = title
	_subtitle = subtitle
	_accent = accent
	_t = 0.0
	visible = true
	var step := func(v: float) -> void:
		_t = v
		queue_redraw()
	var finish := func() -> void:
		visible = false
		_complete(id)
	_tween = create_tween()
	_tween.tween_method(step, 0.0, 1.0, maxf(0.3, duration))
	_tween.tween_callback(finish)
	while _completed_id < id:
		await _pending_completed


## GDScript helper (no C# equivalent): awaits the most recently started play, like awaiting the
## Task that play returned. Returns immediately when nothing is pending.
func wait_current() -> void:
	var id: int = _play_id
	while _completed_id < id:
		await _pending_completed


func _complete(id: int) -> void:
	if id > _completed_id:
		_completed_id = id
		_pending_completed.emit()


func _exit_tree() -> void:
	_complete(_play_id)


func _process(delta: float) -> void:
	_time += delta
	if visible:
		queue_redraw()


func _draw() -> void:
	if _t >= 1.0:
		return
	# Phases: 0..0.22 sweep in, 0.22..0.75 hold, 0.75..1 fade out.
	var in_t: float = clampf(_t / 0.22, 0.0, 1.0)
	var out_t: float = clampf((_t - 0.75) / 0.25, 0.0, 1.0)
	var sweep: float = 1.0 - pow(1.0 - in_t, 3.0)
	var alpha: float = 1.0 - out_t
	var cy: float = size.y * 0.44
	var h: float = 96.0
	var w: float = size.x

	# Dim band.
	var band := Rect2(0.0, cy - h * 0.9, w, h * 1.8)
	draw_rect(band, Color(0.0, 0.0, 0.0, 0.35 * alpha * sweep))

	# Ribbon (grows from the center outward, slides right while fading).
	var half: float = w * 0.5 * sweep
	var shift: float = out_t * 80.0
	var cx: float = w * 0.5 + shift
	var body: Color = _accent.darkened(0.45)
	# The notched ribbon is only a valid (simple) polygon while it is wider than its two notches;
	# at the very start of the sweep (or in a zero-sized control) it would be degenerate/self-intersecting.
	var notch: float = minf(24.0, half * 0.4)
	if half > 4.0 and h > 1.0 and w > 1.0:
		var ribbon := PackedVector2Array([
			Vector2(cx - half, cy - h * 0.5), Vector2(cx + half, cy - h * 0.5),
			Vector2(cx + half - notch, cy), Vector2(cx + half, cy + h * 0.5),
			Vector2(cx - half, cy + h * 0.5), Vector2(cx - half + notch, cy),
		])
		draw_colored_polygon(ribbon, Color(body, 0.92 * alpha))
	draw_rect(Rect2(cx - half, cy - h * 0.5, half * 2.0, 5.0), Color(HudStyle.GOLD, alpha))
	draw_rect(Rect2(cx - half, cy + h * 0.5 - 5.0, half * 2.0, 5.0), Color(HudStyle.GOLD, alpha))
	draw_rect(Rect2(cx - half, cy - h * 0.5 + 8.0, half * 2.0, 1.5), Color(HudStyle.GOLD, 0.5 * alpha))
	draw_rect(Rect2(cx - half, cy + h * 0.5 - 9.5, half * 2.0, 1.5), Color(HudStyle.GOLD, 0.5 * alpha))

	# Light streak sweeping across.
	var streak_x: float = lerpf(-200.0, w + 200.0, clampf(_t / 0.6, 0.0, 1.0))
	var streak := PackedVector2Array([
		Vector2(streak_x - 40.0, cy - h * 0.5 + 5.0), Vector2(streak_x + 10.0, cy - h * 0.5 + 5.0),
		Vector2(streak_x - 10.0, cy + h * 0.5 - 5.0), Vector2(streak_x - 60.0, cy + h * 0.5 - 5.0),
	])
	if h > 12.0:
		draw_colored_polygon(streak, Color(1.0, 1.0, 1.0, 0.18 * alpha))

	# Title pop.
	var pop: float = 0.0 if in_t < 1.0 else clampf((_t - 0.22) / 0.18, 0.0, 1.0)
	var title_scale: float = 1.0 + 0.35 * (1.0 - _ease_out_back(pop))
	var title_alpha: float = alpha * clampf((_t - 0.12) / 0.12, 0.0, 1.0)
	var font_size: int = roundi(52.0 * title_scale)
	HudStyle.draw_text_centered(self, _title, Vector2(cx, cy - 10.0), font_size, Color(1.0, 0.95, 0.8, title_alpha), 10,
		Color(0.08, 0.04, 0.01, title_alpha))
	HudStyle.draw_text_centered(self, _subtitle, Vector2(cx, cy + 30.0), 20, Color(HudStyle.GOLD, title_alpha), 5,
		Color(0.08, 0.04, 0.01, title_alpha))


static func _ease_out_back(x: float) -> float:
	const C1 := 1.70158
	const C3 := C1 + 1.0
	return 1.0 + C3 * pow(x - 1.0, 3.0) + C1 * pow(x - 1.0, 2.0)
