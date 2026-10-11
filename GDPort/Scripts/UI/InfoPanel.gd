class_name InfoPanel
extends PanelContainer
## Parchment hover panel with rich text (built in code, never blocks the mouse). It either follows the mouse
## cursor (board info) or sits beside a target control such as a hovered card, flipping sides and clamping so it
## always stays inside its parent. Fades in softly.

const CURSOR_OFFSET := 22.0
const GAP := 10.0
const MARGIN := 6.0

## Width of the text area in pixels (parent space).
@export var text_width: float = 250.0
@export var font_size: int = 14

var _text: RichTextLabel
var _fade: Tween
var _target: Control
var _follow_cursor: bool = false
var _content: String = ""


func _ready() -> void:
	_ensure_built()


## Shows the text next to the mouse cursor and keeps following it.
func show_at_cursor(bbcode: String) -> void:
	_target = null
	_follow_cursor = true
	_show_text(bbcode)


## Shows the text beside the target control (right side preferred) and tracks it while it moves.
func show_beside(target: Control, bbcode: String) -> void:
	_target = target
	_follow_cursor = false
	_show_text(bbcode)


## Hides the panel.
func hide_panel() -> void:
	_target = null
	if _fade != null:
		_fade.kill()
	visible = false


func _process(_delta: float) -> void:
	if not visible:
		return
	if not _follow_cursor and (_target == null or not is_instance_valid(_target) or not _target.is_visible_in_tree()):
		hide_panel()
		return
	_place()


func _show_text(bbcode: String) -> void:
	_ensure_built()
	if bbcode.is_empty():
		hide_panel()
		return
	if bbcode != _content:
		_content = bbcode
		_text.text = bbcode
		reset_size()
	if not visible:
		visible = true
		modulate = Color(1.0, 1.0, 1.0, 0.0)
		if _fade != null:
			_fade.kill()
		_fade = create_tween()
		_fade.tween_property(self, "modulate:a", 1.0, 0.12)
	_place()


func _place() -> void:
	var parent := get_parent() as Control
	if parent == null:
		return
	reset_size()
	var size_now: Vector2 = get_combined_minimum_size()
	var bounds: Vector2 = parent.size
	var pos: Vector2
	if _follow_cursor:
		var mouse: Vector2 = parent.get_local_mouse_position()
		pos = mouse + Vector2(CURSOR_OFFSET, CURSOR_OFFSET)
		if pos.x + size_now.x > bounds.x - MARGIN:
			pos.x = mouse.x - CURSOR_OFFSET - size_now.x
		if pos.y + size_now.y > bounds.y - MARGIN:
			pos.y = mouse.y - CURSOR_OFFSET * 0.5 - size_now.y
	else:
		var to_parent: Transform2D = parent.get_global_transform().affine_inverse()
		var global_rect: Rect2 = _target.get_global_rect()
		var a: Vector2 = to_parent * global_rect.position
		var b: Vector2 = to_parent * global_rect.end
		var rect := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs())
		pos = Vector2(rect.end.x + GAP, rect.position.y + 8.0)
		if pos.x + size_now.x > bounds.x - MARGIN:
			pos.x = rect.position.x - GAP - size_now.x
	pos.x = clampf(pos.x, MARGIN, maxf(MARGIN, bounds.x - size_now.x - MARGIN))
	pos.y = clampf(pos.y, MARGIN, maxf(MARGIN, bounds.y - size_now.y - MARGIN))
	position = pos


func _ensure_built() -> void:
	if _text != null:
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	z_index = 50
	var style: StyleBoxFlat = HudStyle.parchment_panel(12, 9)
	style.border_color = Color(0.42, 0.26, 0.09)
	style.set_border_width_all(2)
	style.shadow_size = 12
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	style.set_corner_radius_all(8)
	add_theme_stylebox_override("panel", style)

	_text = RichTextLabel.new()
	_text.name = "Text"
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.custom_minimum_size = Vector2(text_width, 0.0)
	_text.add_theme_font_override("normal_font", VfxAssets.card_text_font)
	_text.add_theme_font_override("bold_font", VfxAssets.card_text_bold_font)
	var italics := FontVariation.new()
	italics.base_font = VfxAssets.card_text_font
	italics.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(0.2, 1.0), Vector2.ZERO)
	_text.add_theme_font_override("italics_font", italics)
	_text.add_theme_font_size_override("normal_font_size", font_size)
	_text.add_theme_font_size_override("bold_font_size", font_size)
	_text.add_theme_font_size_override("italics_font_size", font_size)
	_text.add_theme_color_override("default_color", HudStyle.INK)
	_text.add_theme_constant_override("outline_size", 0)
	_text.add_theme_constant_override("line_separation", 1)
	add_child(_text)
