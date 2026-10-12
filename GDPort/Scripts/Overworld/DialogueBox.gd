class_name DialogueBox
extends PanelContainer
## Parchment dialogue box at the bottom of the screen: speaker name, title, text and answer buttons.

var _name: Label
var _title: Label
var _text: RichTextLabel
var _buttons: HBoxContainer
var _tween: Tween

## True while visible.
var is_open: bool:
	get:
		return visible


func _ready() -> void:
	_ensure_built()


## Shows a line with answer options. options: Array of {"label": String, "action": Callable}.
## Selecting an option runs its action.
func open(speaker: String, speaker_color: Color, title: String, text: String, options: Array) -> void:
	_ensure_built()
	_name.text = speaker
	_name.add_theme_color_override("font_color", speaker_color)
	_title.text = title
	_text.text = text
	for child: Node in _buttons.get_children():
		child.queue_free()
	for option: Dictionary in options:
		var label: String = option.get("label", "")
		var action: Variant = option.get("action")
		var button := Button.new()
		button.text = label
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(130, 34)
		button.add_theme_font_size_override("font_size", 16)
		button.pressed.connect(func() -> void:
			Sfx.play(SfxId.BUTTON_CLICK)
			if action is Callable:
				var cb: Callable = action
				if cb.is_valid():
					cb.call()
		)
		_buttons.add_child(button)
	if not visible:
		visible = true
		modulate = Color(1, 1, 1, 0)
		if _tween != null:
			_tween.kill()
		_tween = create_tween()
		_tween.tween_property(self, "modulate:a", 1.0, 0.15)
		Sfx.play(SfxId.CARD_FLIP, -4.0, 0.8)


## Hides the box.
func close() -> void:
	visible = false


## Runs the first option (keyboard confirm).
func confirm_first() -> void:
	if visible and _buttons.get_child_count() > 0 and _buttons.get_child(0) is Button:
		var b := _buttons.get_child(0) as Button
		b.pressed.emit()


func _ensure_built() -> void:
	if _name != null:
		return
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style: StyleBoxFlat = HudStyle.parchment_panel(22, 14)
	style.set_border_width_all(3)
	style.border_color = Color(0.42, 0.26, 0.09)
	style.shadow_size = 16
	style.set_corner_radius_all(10)
	add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", 12)
	box.add_child(header)
	_name = Label.new()
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name.add_theme_font_override("font", VfxAssets.get_card_text_bold_font())
	_name.add_theme_font_size_override("font_size", 22)
	_name.add_theme_color_override("font_outline_color", Color(0.12, 0.07, 0.03))
	_name.add_theme_constant_override("outline_size", 6)
	header.add_child(_name)
	_title = Label.new()
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title.add_theme_font_override("font", VfxAssets.get_card_text_font())
	_title.add_theme_font_size_override("font_size", 15)
	_title.add_theme_color_override("font_color", Color(0.4, 0.28, 0.15))
	_title.add_theme_constant_override("outline_size", 0)
	header.add_child(_title)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.custom_minimum_size = Vector2(640, 0)
	_text.add_theme_font_override("normal_font", VfxAssets.get_card_text_font())
	_text.add_theme_font_override("bold_font", VfxAssets.get_card_text_bold_font())
	_text.add_theme_font_size_override("normal_font_size", 17)
	_text.add_theme_font_size_override("bold_font_size", 17)
	_text.add_theme_color_override("default_color", HudStyle.INK)
	_text.add_theme_constant_override("outline_size", 0)
	box.add_child(_text)

	_buttons = HBoxContainer.new()
	_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buttons.alignment = BoxContainer.ALIGNMENT_END
	_buttons.add_theme_constant_override("separation", 10)
	box.add_child(_buttons)
