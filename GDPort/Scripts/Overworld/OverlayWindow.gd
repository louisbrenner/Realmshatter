class_name OverlayWindow
extends Control
## Base for full-screen modal windows in the town (shop, deck builder): dim background, a wooden panel with a
## title row, gold display and a close button. Derived classes fill body. Emits closed when dismissed.

signal closed

## Panel size in HUD pixels.
@export var panel_size: Vector2 = Vector2(1080, 600)

var title_label: Label
var subtitle_label: Label
var gold_label: Label
var header_buttons: HBoxContainer
var body: VBoxContainer
var card_info: InfoPanel

var _info_owner: CardSlot

## True while open.
var is_open: bool:
	get:
		return visible


func _ready() -> void:
	_ensure_built()


## Shows the window (derived classes refresh their content first).
func open() -> void:
	_ensure_built()
	visible = true
	modulate = Color(1, 1, 1, 0)
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.15)
	refresh_gold()


## Hides the window and emits closed.
func close() -> void:
	if not visible:
		return
	if card_info != null:
		card_info.hide_panel()
	visible = false
	Sfx.play(SfxId.BUTTON_CLICK)
	closed.emit()


## Updates the gold display.
func refresh_gold() -> void:
	if gold_label != null:
		gold_label.text = "%d gold" % PlayerProfile.gold


## Connects a slot's hover to the shared card info panel.
func track_hover(slot: CardSlot) -> void:
	slot.hover_changed.connect(func(s: CardSlot, hovered: bool) -> void:
		if hovered:
			_info_owner = s
			Sfx.play(SfxId.CARD_HOVER)
			var cost: int = s.card.ap_cost if s.card.ap_cost > 0 else (1 if s.card.card_type == CardType.UNIT else 2)
			card_info.show_beside(s.view, InfoText.card(s.card, cost))
		elif _info_owner == s:
			_info_owner = null
			card_info.hide_panel()
	)


## Builds a wood-styled small toggle/tab button.
static func make_button(text: String, font_size: int = 15) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(96, 30)
	b.add_theme_font_size_override("font_size", font_size)
	return b


## Removes all children of a container.
static func clear_children(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _ensure_built() -> void:
	if body != null:
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.0, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = panel_size
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style: StyleBoxFlat = HudStyle.wood_panel(HudStyle.GOLD, 14)
	style.set_corner_radius_all(14)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var outer := VBoxContainer.new()
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_theme_constant_override("separation", 8)
	panel.add_child(outer)

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", 14)
	outer.add_child(header)
	title_label = Label.new()
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.add_theme_font_override("font", VfxAssets.get_card_text_bold_font())
	title_label.add_theme_font_size_override("font_size", 26)
	title_label.add_theme_color_override("font_color", HudStyle.GOLD)
	title_label.add_theme_constant_override("outline_size", 6)
	header.add_child(title_label)
	subtitle_label = Label.new()
	subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	subtitle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subtitle_label.add_theme_font_override("font", VfxAssets.get_card_text_font())
	subtitle_label.add_theme_font_size_override("font_size", 15)
	subtitle_label.add_theme_color_override("font_color", HudStyle.TEXT_LIGHT)
	header.add_child(subtitle_label)
	header_buttons = HBoxContainer.new()
	header_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_buttons.add_theme_constant_override("separation", 6)
	header.add_child(header_buttons)
	gold_label = Label.new()
	gold_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gold_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gold_label.add_theme_font_override("font", VfxAssets.get_card_text_bold_font())
	gold_label.add_theme_font_size_override("font_size", 20)
	gold_label.add_theme_color_override("font_color", HudStyle.GOLD)
	gold_label.add_theme_constant_override("outline_size", 5)
	header.add_child(gold_label)
	var close_button: Button = make_button("Close", 16)
	close_button.pressed.connect(close)
	header.add_child(close_button)

	body = VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	outer.add_child(body)

	card_info = InfoPanel.new()
	card_info.name = "CardInfo"
	card_info.text_width = 240.0
	add_child(card_info)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and key.keycode == KEY_ESCAPE:
			close()
			accept_event()
