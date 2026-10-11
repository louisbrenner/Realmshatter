class_name DeckSelectScreen
extends Control
## Full-screen deck selection shown before a game: one wooden plaque per themed deck with its name, signature
## card, description and composition. Hovering a plaque lifts it and shows the full deck list; clicking it emits
## deck_chosen. Built entirely in code (Hud adds it to its root); blocks all input below while visible.

signal deck_chosen(deck_index: int)

## Card scene used for the signature cards (Scenes/UI/Card.tscn).
@export var card_scene: PackedScene
@export var plaque_width: float = 214.0
@export var card_scale: float = 0.86

var _dim: ColorRect
var _content: VBoxContainer
var _row: HBoxContainer
var _title: Label
var _subtitle: Label
var _info: InfoPanel
var _plaques: Array[PanelContainer] = []
var _styles: Array[StyleBoxFlat] = []
var _accents: Array[Color] = []
var _decks: Array = []
var _choosing: bool = false
var _hovered: int = -1


func _ready() -> void:
	_ensure_built()


## Shows the screen with one plaque per deck (Array of DeckData).
func present(decks: Array) -> void:
	_ensure_built()
	_clear_plaques()
	_decks = decks if decks != null else []
	_choosing = false
	_hovered = -1
	for i in range(_decks.size()):
		_build_plaque(i, _decks[i])

	visible = true
	modulate = Color(1.0, 1.0, 1.0, 0.0)
	var fade: Tween = create_tween()
	fade.tween_property(self, "modulate:a", 1.0, 0.3)
	_title.pivot_offset = _title.size * 0.5
	_title.scale = Vector2(1.3, 1.3)
	fade.parallel().tween_property(_title, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop_in_plaques.call_deferred()


## Hides the screen immediately.
func hide_screen() -> void:
	if _info != null:
		_info.hide_panel()
	visible = false


func _pop_in_plaques() -> void:
	for i in range(_plaques.size()):
		var plaque: PanelContainer = _plaques[i]
		plaque.pivot_offset = plaque.size * 0.5
		plaque.scale = Vector2(0.85, 0.85)
		plaque.modulate = Color(1.0, 1.0, 1.0, 0.0)
		var delay: float = 0.15 + i * 0.09
		var tween: Tween = plaque.create_tween()
		tween.tween_interval(delay)
		tween.set_parallel(true)
		tween.tween_property(plaque, "modulate:a", 1.0, 0.2)
		tween.tween_property(plaque, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		Sfx.play_delayed(SfxId.CARD_DEAL, delay)


func _build_plaque(index: int, deck: DeckData) -> void:
	var accent: Color = deck.accent_color if deck != null else HudStyle.GOLD
	var style: StyleBoxFlat = HudStyle.wood_panel(accent, 12)
	style.border_width_top = 6
	var plaque := PanelContainer.new()
	plaque.name = "Deck%d" % index
	plaque.custom_minimum_size = Vector2(plaque_width, 0.0)
	plaque.mouse_filter = Control.MOUSE_FILTER_STOP
	plaque.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	plaque.add_theme_stylebox_override("panel", style)
	_row.add_child(plaque)
	_plaques.append(plaque)
	_styles.append(style)
	_accents.append(accent)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)
	plaque.add_child(box)

	var name_label := Label.new()
	name_label.text = deck.name if deck != null else "Deck"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_override("font", VfxAssets.card_text_bold_font)
	name_label.add_theme_font_size_override("font_size", 21)
	name_label.add_theme_color_override("font_color", accent.lerp(Color.WHITE, 0.35))
	name_label.add_theme_color_override("font_outline_color", HudStyle.OUTLINE)
	name_label.add_theme_constant_override("outline_size", 6)
	box.add_child(name_label)

	var showcase: CardData = deck.showcase if deck != null else null
	if showcase == null and deck != null and deck.cards.size() > 0:
		showcase = deck.cards[0]
	if showcase != null and card_scene != null:
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(150.0, 210.0) * card_scale + Vector2(0.0, 6.0)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(holder)
		var card := card_scene.instantiate() as CardView
		holder.add_child(card)
		card.setup(showcase, showcase.ap_cost if showcase.ap_cost > 0 else (1 if showcase.card_type == CardType.UNIT else 2))
		card.set_playable(false)
		card.modulate = Color.WHITE
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.pivot_offset = Vector2.ZERO
		card.scale = Vector2(card_scale, card_scale)
		card.position = Vector2((plaque_width - 24.0 - 150.0 * card_scale) * 0.5, 4.0)

	var description := Label.new()
	description.text = deck.description if deck != null else ""
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.custom_minimum_size = Vector2(plaque_width - 24.0, 0.0)
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	description.add_theme_font_override("font", VfxAssets.card_text_font)
	description.add_theme_font_size_override("font_size", 14)
	description.add_theme_color_override("font_color", HudStyle.TEXT_LIGHT)
	description.add_theme_constant_override("outline_size", 0)
	box.add_child(description)

	var units: int = 0
	var spells: int = 0
	if deck != null:
		for c: CardData in deck.cards:
			if c == null:
				continue
			if c.card_type == CardType.UNIT:
				units += 1
			else:
				spells += 1
	var composition := Label.new()
	composition.text = "%d units  ·  %d spells" % [units, spells]
	composition.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	composition.mouse_filter = Control.MOUSE_FILTER_IGNORE
	composition.add_theme_font_override("font", VfxAssets.card_text_bold_font)
	composition.add_theme_font_size_override("font_size", 13)
	composition.add_theme_color_override("font_color", HudStyle.GOLD)
	composition.add_theme_constant_override("outline_size", 0)
	box.add_child(composition)

	plaque.mouse_entered.connect(func() -> void: _on_plaque_hover(index, true))
	plaque.mouse_exited.connect(func() -> void: _on_plaque_hover(index, false))
	plaque.gui_input.connect(func(e: InputEvent) -> void: _on_plaque_input(index, e))


func _on_plaque_hover(index: int, hovered: bool) -> void:
	if index < 0 or index >= _plaques.size() or _choosing:
		return
	var plaque: PanelContainer = _plaques[index]
	var style: StyleBoxFlat = _styles[index]
	var accent: Color = _accents[index]
	plaque.pivot_offset = plaque.size * 0.5
	var tween: Tween = plaque.create_tween()
	tween.set_parallel(true)
	tween.tween_property(plaque, "scale", Vector2(1.04, 1.04) if hovered else Vector2.ONE, 0.12) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	style.border_color = accent.lerp(HudStyle.GOLD, 0.3) if hovered else accent.lerp(HudStyle.GOLD_DARK, 0.35)
	style.shadow_color = Color(accent, 0.55) if hovered else Color(0.0, 0.0, 0.0, 0.5)
	style.shadow_size = 22 if hovered else 10
	style.set_border_width_all(3 if hovered else 2)
	style.border_width_top = 6
	if hovered:
		_hovered = index
		Sfx.play(SfxId.CARD_HOVER)
		_info.show_beside(plaque, InfoText.deck(_decks[index]))
	elif _hovered == index:
		_hovered = -1
		_info.hide_panel()


func _on_plaque_input(index: int, e: InputEvent) -> void:
	if _choosing or not (e is InputEventMouseButton):
		return
	var mouse := e as InputEventMouseButton
	if not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	_choosing = true
	_info.hide_panel()
	Sfx.play(SfxId.CARD_PICK)
	Sfx.play(SfxId.SUMMON, -6.0)
	var plaque: PanelContainer = _plaques[index]
	var tween: Tween = create_tween()
	tween.tween_property(plaque, "scale", Vector2(1.1, 1.1), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func() -> void:
		visible = false
		deck_chosen.emit(index)
	)


func _clear_plaques() -> void:
	for plaque: PanelContainer in _plaques:
		_row.remove_child(plaque)
		plaque.queue_free()
	_plaques.clear()
	_styles.clear()
	_accents.clear()


func _ensure_built() -> void:
	if _dim != null:
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(0.03, 0.02, 0.01, 0.84)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_content = VBoxContainer.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_theme_constant_override("separation", 10)
	center.add_child(_content)

	var game_title := Label.new()
	game_title.text = "REALMSHATTER"
	game_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title_font := FontVariation.new()
	title_font.base_font = VfxAssets.card_text_bold_font
	title_font.spacing_glyph = 6
	game_title.add_theme_font_override("font", title_font)
	game_title.add_theme_font_size_override("font_size", 58)
	game_title.add_theme_color_override("font_color", HudStyle.GOLD)
	game_title.add_theme_color_override("font_shadow_color", Color(1.0, 0.45, 0.1, 0.55))
	game_title.add_theme_constant_override("shadow_outline_size", 8)
	game_title.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.02))
	game_title.add_theme_constant_override("outline_size", 8)
	_content.add_child(game_title)

	_title = Label.new()
	_title.text = "Choose your deck"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_theme_font_override("font", VfxAssets.card_text_bold_font)
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.5))
	_title.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.02))
	_title.add_theme_constant_override("outline_size", 8)
	_content.add_child(_title)

	_subtitle = Label.new()
	_subtitle.text = "Every deck has a theme - and a few cards borrowed from the others. Hover a deck to see its list."
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle.add_theme_font_override("font", VfxAssets.card_text_font)
	_subtitle.add_theme_font_size_override("font_size", 15)
	_subtitle.add_theme_color_override("font_color", HudStyle.TEXT_LIGHT)
	_subtitle.add_theme_constant_override("outline_size", 0)
	_content.add_child(_subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 8.0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(spacer)

	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 18)
	_content.add_child(_row)

	_info = InfoPanel.new()
	_info.name = "DeckInfo"
	_info.text_width = 230.0
	_info.font_size = 13
	add_child(_info)
