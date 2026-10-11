class_name DraftPopup
extends Control
## Modal "choose 1 of N" popup. While visible, the full-rect dim background blocks all board input.
## Cards are revealed dramatically (fly in as card backs, flip, flash gold).

signal card_chosen(offer_index: int)

## An offered card was hovered (true) or left (false); used for the card info panel.
signal card_hover_changed(card: CardView, hovered: bool)

@export var card_scene: PackedScene
## Delay between the reveals of consecutive cards, in seconds.
@export var reveal_stagger: float = 0.14

var _card_row: HBoxContainer
var _title_label: Label
var _panel: Control
var _cards: Array[CardView] = []


func _ready() -> void:
	_card_row = get_node("Center/Panel/Margin/VBox/Cards") as HBoxContainer
	_title_label = get_node("Center/Panel/Margin/VBox/Title") as Label
	_panel = get_node_or_null("Center/Panel") as Control
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_apply_style()


## Shows the offer (Array of CardData) and makes the popup visible. cost_of: Callable(CardData) -> int
## (an invalid Callable falls back to the card's ap_cost).
func show_offer(offer: Array, cost_of: Callable = Callable()) -> void:
	_clear_cards()
	if card_scene == null:
		push_error("DraftPopup: CardScene is not assigned.")
		return

	if offer != null:
		for card: CardData in offer:
			var view := card_scene.instantiate() as CardView
			_card_row.add_child(view)
			view.setup(card, int(cost_of.call(card)) if cost_of.is_valid() else card.ap_cost)
			view.card_clicked.connect(_on_card_clicked)
			view.hover_changed.connect(_on_card_hover_changed)
			_cards.append(view)

	_title_label.text = "Choose a card"
	visible = true
	Sfx.play(SfxId.CARD_DEAL)
	_play_open()
	for i in range(_cards.size()):
		_cards[i].play_reveal(0.12 + i * reveal_stagger)


## Hides the popup and removes the offered cards.
func hide_popup() -> void:
	visible = false
	_clear_cards()


func _play_open() -> void:
	if _panel == null:
		return
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(0.85, 0.85)
	_panel.modulate = Color(1, 1, 1, 0)
	var tween: Tween = _panel.create_tween()
	tween.set_parallel(true)
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_panel, "modulate:a", 1.0, 0.15)
	_title_label.pivot_offset = _title_label.size * 0.5
	_title_label.scale = Vector2(1.4, 1.4)
	tween.tween_property(_title_label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _apply_style() -> void:
	if _panel is PanelContainer:
		var panel := _panel as PanelContainer
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.14, 0.085, 0.05, 0.96)
		style.border_color = Color(0.92, 0.72, 0.34)
		style.shadow_color = Color(0.0, 0.0, 0.0, 0.6)
		style.shadow_size = 24
		style.corner_detail = 8
		style.anti_aliasing = true
		style.set_corner_radius_all(16)
		style.set_border_width_all(3)
		panel.add_theme_stylebox_override("panel", style)
	var font: Font = VfxAssets.card_font
	if font != null:
		_title_label.add_theme_font_override("font", font)
	_title_label.add_theme_font_size_override("font_size", 30)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.5))
	_title_label.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.02))
	_title_label.add_theme_constant_override("outline_size", 8)
	_card_row.add_theme_constant_override("separation", 28)


func _on_card_clicked(card: CardView) -> void:
	var index: int = _cards.find(card)
	if index >= 0:
		Sfx.play(SfxId.CARD_PICK)
		card_chosen.emit(index)


func _on_card_hover_changed(card: CardView, hovered: bool) -> void:
	if hovered:
		Sfx.play(SfxId.CARD_HOVER)
	card_hover_changed.emit(card, hovered)


func _clear_cards() -> void:
	for view: CardView in _cards:
		view.card_clicked.disconnect(_on_card_clicked)
		view.hover_changed.disconnect(_on_card_hover_changed)
		card_hover_changed.emit(view, false)
		_card_row.remove_child(view)
		view.queue_free()
	_cards.clear()
