class_name CardSlot
extends VBoxContainer
## A card shown in a grid (shop, deck builder): a scaled CardView, a caption line and an optional action button.
## Clicking the card or the button emits activated; hovering emits hover_changed (for the card info panel).

signal activated(slot: CardSlot)
signal hover_changed(slot: CardSlot, hovered: bool)

const CARD_SCENE_PATH := "res://Scenes/UI/Card.tscn"
static var _card_scene: PackedScene

var _view: CardView
var _caption: Label
var _button: Button
var _scale: float = 0.62

## The card shown.
var card: CardData

## The card view (for anchoring the info panel).
var view: CardView:
	get:
		return _view


## Builds the slot for a card at the given scale (call before adding it to the tree).
func setup(p_card: CardData, p_scale: float, with_button: bool) -> void:
	card = p_card
	_scale = p_scale
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)

	var holder := Control.new()
	holder.custom_minimum_size = Vector2(150.0, 210.0) * p_scale
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	if _card_scene == null:
		_card_scene = load(CARD_SCENE_PATH) as PackedScene
	_view = _card_scene.instantiate() as CardView
	_view.managed_layout = true
	holder.add_child(_view)
	_view.pivot_offset = Vector2.ZERO
	_view.scale = Vector2(p_scale, p_scale)
	_view.setup(p_card, p_card.ap_cost if p_card.ap_cost > 0 else (1 if p_card.card_type == CardType.UNIT else 2))
	_view.set_playable(false)
	_view.modulate = Color.WHITE
	_view.card_clicked.connect(func(_c: CardView) -> void: activated.emit(self))
	_view.hover_changed.connect(func(_c: CardView, hovered: bool) -> void: hover_changed.emit(self, hovered))

	_caption = Label.new()
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.custom_minimum_size = Vector2(150.0 * p_scale, 0.0)
	_caption.clip_text = true
	_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.add_theme_font_override("font", VfxAssets.get_card_text_bold_font())
	_caption.add_theme_font_size_override("font_size", 11)
	_caption.add_theme_constant_override("outline_size", 4)
	add_child(_caption)

	if with_button:
		_button = Button.new()
		_button.focus_mode = Control.FOCUS_NONE
		_button.custom_minimum_size = Vector2(150.0 * p_scale, 24.0)
		_button.clip_text = true
		_button.add_theme_font_size_override("font_size", 13)
		_button.pressed.connect(func() -> void: activated.emit(self))
		add_child(_button)


## Sets the caption under the card.
func set_caption(text: String, color: Color) -> void:
	_caption.text = text
	_caption.add_theme_color_override("font_color", color)


## Sets the action button (if any).
func set_button(text: String, enabled: bool) -> void:
	if _button == null:
		return
	_button.text = text
	_button.disabled = not enabled


## Greys the card out (e.g. not affordable, all copies in the deck).
func set_dimmed(dimmed: bool) -> void:
	_view.modulate = Color(0.55, 0.55, 0.55) if dimmed else Color.WHITE


## Green glow (e.g. affordable / addable).
func set_highlight(on: bool) -> void:
	_view.set_playable(on)
	if _view.modulate != Color.WHITE and on:
		_view.modulate = Color.WHITE
