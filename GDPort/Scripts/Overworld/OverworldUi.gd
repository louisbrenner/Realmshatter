class_name OverworldUi
extends CanvasLayer
## Screen UI of the town (scaled uniformly like the battle HUD): a status plaque (gold, deck size, duels won),
## a Deck button, the interaction prompt, a toast line, the dialogue box, the shop and the deck builder.

signal deck_button_pressed

@export var reference_resolution: Vector2 = Vector2(1152, 648)

var _root: Control
var _gold: Label
var _deck: Label
var _wins: Label
var _prompt: PanelContainer
var _prompt_label: Label
var _toast: PanelContainer
var _toast_label: Label
var _toast_tween: Tween

var dialogue: DialogueBox
var shop: ShopPanel
var deck_builder: DeckBuilderPanel

## True while any modal UI (dialogue, shop, deck builder) is open.
var is_busy: bool:
	get:
		return dialogue.is_open or shop.is_open or deck_builder.is_open


func _ready() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = HudStyle.create_theme()
	add_child(_root)

	var status := PanelContainer.new()
	status.position = Vector2(10, 10)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.add_theme_stylebox_override("panel", HudStyle.wood_panel(HudStyle.GOLD, 10))
	_root.add_child(status)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 18)
	status.add_child(row)
	_gold = _make_stat(row, HudStyle.GOLD)
	_deck = _make_stat(row, HudStyle.TEXT_LIGHT)
	_wins = _make_stat(row, Color(1.0, 0.82, 0.4))

	var deck_button := Button.new()
	deck_button.text = "Deck Builder (Tab)"
	deck_button.focus_mode = Control.FOCUS_NONE
	deck_button.anchor_left = 1.0
	deck_button.anchor_right = 1.0
	deck_button.offset_left = -200
	deck_button.offset_right = -10
	deck_button.offset_top = 12
	deck_button.offset_bottom = 48
	deck_button.add_theme_font_size_override("font_size", 16)
	deck_button.pressed.connect(func() -> void:
		Sfx.play(SfxId.BUTTON_CLICK)
		deck_button_pressed.emit()
	)
	_root.add_child(deck_button)

	var help := Label.new()
	help.text = "WASD / arrows: walk   E / Space: talk   Tab: deck builder"
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.offset_left = 12
	help.offset_top = -30
	help.offset_bottom = -8
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help.add_theme_font_size_override("font_size", 13)
	help.add_theme_constant_override("outline_size", 4)
	help.modulate = Color(1, 1, 1, 0.8)
	_root.add_child(help)

	var prompt_parts: Array = _make_ribbon()
	_prompt = prompt_parts[0]
	_prompt_label = prompt_parts[1]
	_prompt.anchor_top = 1.0
	_prompt.anchor_bottom = 1.0
	_root.add_child(_prompt)
	var toast_parts: Array = _make_ribbon()
	_toast = toast_parts[0]
	_toast_label = toast_parts[1]
	_root.add_child(_toast)

	dialogue = DialogueBox.new()
	dialogue.name = "Dialogue"
	_root.add_child(dialogue)
	shop = ShopPanel.new()
	shop.name = "Shop"
	_root.add_child(shop)
	deck_builder = DeckBuilderPanel.new()
	deck_builder.name = "DeckBuilder"
	_root.add_child(deck_builder)
	shop.closed.connect(refresh_status)
	deck_builder.closed.connect(refresh_status)

	PlayerProfile.changed_listeners.append(refresh_status)
	get_viewport().size_changed.connect(_apply_scale)
	_apply_scale()
	refresh_status()


func _exit_tree() -> void:
	PlayerProfile.changed_listeners.erase(refresh_status)
	var viewport: Viewport = get_viewport()
	if viewport != null and viewport.size_changed.is_connected(_apply_scale):
		viewport.size_changed.disconnect(_apply_scale)


func _process(_delta: float) -> void:
	# Keep floating ribbons centred (their size depends on the text).
	var root_size: Vector2 = _root.size
	_prompt.position = Vector2((root_size.x - _prompt.size.x) * 0.5, root_size.y - 70.0)
	_toast.position = Vector2((root_size.x - _toast.size.x) * 0.5, 60.0)
	dialogue.position = Vector2((root_size.x - dialogue.size.x) * 0.5, root_size.y - dialogue.size.y - 16.0)


## Shows / hides the interaction prompt ("E: Talk to ...").
func set_prompt(text: String) -> void:
	_prompt_label.text = text
	_prompt.visible = not text.is_empty() and not is_busy
	_prompt.reset_size()


## Shows a message ribbon at the top for a few seconds.
func show_toast(text: String, seconds: float = 3.5) -> void:
	_toast_label.text = text
	_toast.reset_size()
	_toast.visible = true
	_toast.modulate = Color.WHITE
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)
	_toast_tween.tween_callback(func() -> void: _toast.visible = false)


## Refreshes gold / deck / duel counters.
func refresh_status() -> void:
	if _gold == null:
		return
	_gold.text = "%d gold" % PlayerProfile.gold
	var valid: bool = PlayerProfile.get_deck_is_valid()
	_deck.text = ("Deck %d" % PlayerProfile.get_deck_count()) + ("" if valid else " (!)")
	_deck.add_theme_color_override("font_color", HudStyle.TEXT_LIGHT if valid else Color(1.0, 0.5, 0.4))
	_wins.text = "Duels won %d" % PlayerProfile.get_defeated_count()


static func _make_stat(parent: Container, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", VfxAssets.get_card_text_bold_font())
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 5)
	parent.add_child(label)
	return label


## Returns [ribbon: PanelContainer, label: Label] (C# out parameter).
static func _make_ribbon() -> Array:
	var ribbon := PanelContainer.new()
	ribbon.visible = false
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ribbon.add_theme_stylebox_override("panel", HudStyle.parchment_panel(20, 6))
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", VfxAssets.get_card_text_bold_font())
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", HudStyle.INK)
	label.add_theme_constant_override("outline_size", 0)
	ribbon.add_child(label)
	return [ribbon, label]


func _apply_scale() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var s: float = maxf(0.7, minf(viewport_size.x / reference_resolution.x, viewport_size.y / reference_resolution.y))
	_root.scale = Vector2(s, s)
	_root.size = viewport_size / s
