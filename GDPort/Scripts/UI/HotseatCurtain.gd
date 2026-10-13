class_name HotseatCurtain
extends CanvasLayer
## Opaque "pass the device" screen between two hotseat turns: covers the board and the hand until the next
## player clicks anywhere (or presses Enter / Space). show_async is awaitable (coroutine).

## Internal: the curtain was dismissed (replaces the C# TaskCompletionSource).
signal _confirmed()

## Input lock in seconds after the curtain appears.
@export var input_delay: float = 0.4

var _root: Control
var _dim: ColorRect
var _title: Label
var _subtitle: Label
var _ready_button: Button
var _panel: PanelContainer
## Clicks / keys are ignored until this time (ms), so a double-click on End Turn cannot skip the curtain.
var _accept_after_ms: int = 0


func _ready() -> void:
	layer = 20
	_root = Control.new()
	_root.name = "Root"
	_root.theme = HudStyle.create_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_dim = ColorRect.new()
	_dim.color = Color(0.04, 0.025, 0.015, 0.97)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_dim)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_panel.add_child(box)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 34)
	_title.add_theme_constant_override("outline_size", 8)
	_title.add_theme_color_override("font_outline_color", HudStyle.OUTLINE)
	box.add_child(_title)

	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.add_theme_font_size_override("font_size", 16)
	_subtitle.add_theme_color_override("font_color", HudStyle.TEXT_LIGHT)
	box.add_child(_subtitle)

	var hint := Label.new()
	hint.text = "Click anywhere to continue"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(1.0, 1.0, 1.0, 0.6)

	_ready_button = Button.new()
	_ready_button.text = "I'm ready"
	_ready_button.focus_mode = Control.FOCUS_NONE
	_ready_button.custom_minimum_size = Vector2(180, 44)
	_ready_button.add_theme_font_size_override("font_size", 20)
	_ready_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_ready_button)
	box.add_child(hint)

	visible = false


## Covers the screen with 'title' / 'subtitle' in the player's accent colour; returns once dismissed.
func show_async(title: String, subtitle: String, accent: Color) -> void:
	_title.text = title
	_title.add_theme_color_override("font_color", accent.lerp(Color.WHITE, 0.2))
	_subtitle.text = subtitle
	_panel.add_theme_stylebox_override("panel", HudStyle.wood_panel(accent, 22))
	visible = true
	_accept_after_ms = Time.get_ticks_msec() + int(maxf(0.0, input_delay) * 1000.0)
	_root.modulate = Color(1.0, 1.0, 1.0, 0.0)
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.25)
	await _confirmed


## Any mouse click (on the button or anywhere else) or Enter / Space closes the curtain.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var click: bool = event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
		and ((event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT or (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT)
	var key: bool = false
	if event is InputEventKey:
		var k := event as InputEventKey
		key = k.pressed and not k.echo and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER or k.keycode == KEY_SPACE)
	if not click and not key and not event is InputEventMouseButton:
		return
	# Swallow every mouse button event (incl. releases) while covered, so nothing reaches the board.
	get_viewport().set_input_as_handled()
	if (click or key) and Time.get_ticks_msec() >= _accept_after_ms:
		_confirm()


func _exit_tree() -> void:
	_confirmed.emit()


func _confirm() -> void:
	if not visible:
		return
	Sfx.play(SfxId.BUTTON_CLICK)
	visible = false
	_confirmed.emit()
