class_name CardView
extends Control
## Hearthstone-style card (root of Scenes/UI/Card.tscn): stone frame with gold trim, oval (unit) or
## rounded (spell) art window, blue mana gem with the AP cost, name ribbon, parchment text box,
## attack/health badges for units, shield and AP bonus mini badges. Playable cards glow green,
## selected cards glow gold and lift. The root Control receives the mouse; the inner "Body" animates.

signal card_clicked(card: CardView)

## Emitted when the mouse enters (true) or leaves (false) the card.
signal hover_changed(card: CardView, hovered: bool)

const HOVER_RAISE := 10.0
const SELECTED_RAISE := 22.0
const TWEEN_TIME := 0.1
const DESCRIPTION_MAX_FONT := 12
const DESCRIPTION_MIN_FONT := 9
const NAME_MAX_FONT := 15
const STATS_MAX_FONT := 11
## Parchment text box (x, y, w, h) drawn by card_frame.gdshader; holds the stats line and the text.
const TEXT_RECT := Vector4(11.0, 106.0, 128.0, 80.0)

const UNIT_FRAME_COLOR := Color(0.5, 0.44, 0.37)
const SPELL_FRAME_COLOR := Color(0.38, 0.34, 0.54)
const UNIT_BANNER_COLOR := Color(0.78, 0.6, 0.36)
const SPELL_BANNER_COLOR := Color(0.6, 0.5, 0.82)
const PLAYABLE_GLOW_COLOR := Color(0.3, 1.0, 0.38)
const SELECTED_GLOW_COLOR := Color(1.0, 0.82, 0.25)
const HOVER_GLOW_COLOR := Color(1.0, 0.9, 0.6)

var _body: Control
var _glow: Panel
var _frame: ColorRect
var _art: ColorRect
var _banner: ColorRect
var _type_plate: ColorRect
var _gem: ColorRect
var _ap_badge: ColorRect
var _shield_badge: ColorRect
var _attack_badge: ColorRect
var _health_badge: ColorRect
var _name_label: Label
var _stats_label: Label
var _description_label: Label
var _type_label: Label
var _cost_label: Label
var _ap_label: Label
var _shield_label: Label
var _attack_label: Label
var _health_label: Label
var _rich_description: RichTextLabel
var _keyword_row: HBoxContainer
var _frame_mat: ShaderMaterial
var _art_mat: ShaderMaterial
var _banner_mat: ShaderMaterial
var _glow_style: StyleBoxFlat
var _raise_tween: Tween
var _reveal_tween: Tween
var _face_items: Array[CanvasItem] = []

var _ap_cost: int = 0
var _playable: bool = true
var _selected: bool = false
var _hovered: bool = false
var _revealing: bool = false
var _time: float = 0.0
var _reveal_glow: float = 0.0

## The card currently shown by this view (null before setup).
var card: CardData

## When true (set by HandView) the card does not raise/scale itself on hover or selection.
var managed_layout: bool = false

## True while the mouse is over the card.
var is_hovered: bool:
	get:
		return _hovered

## True if the card is shown as playable.
var is_playable: bool:
	get:
		return _playable

## True if the card is shown as selected.
var is_selected: bool:
	get:
		return _selected

## Effective AP cost shown in the mana gem.
var ap_cost: int:
	get:
		return _ap_cost


func _ready() -> void:
	_body = get_node("Body") as Control
	_glow = get_node("Body/Glow") as Panel
	_frame = get_node("Body/Frame") as ColorRect
	_art = get_node("Body/Art") as ColorRect
	_banner = get_node("Body/Banner") as ColorRect
	_type_plate = get_node("Body/TypePlate") as ColorRect
	_gem = get_node("Body/Gem") as ColorRect
	_ap_badge = get_node("Body/ApBadge") as ColorRect
	_shield_badge = get_node("Body/ShieldBadge") as ColorRect
	_attack_badge = get_node("Body/AttackBadge") as ColorRect
	_health_badge = get_node("Body/HealthBadge") as ColorRect
	_name_label = get_node("Body/NameLabel") as Label
	_stats_label = get_node("Body/StatsLabel") as Label
	_description_label = get_node("Body/DescriptionLabel") as Label
	_type_label = get_node("Body/TypeLabel") as Label
	_cost_label = get_node("Body/CostLabel") as Label
	_ap_label = get_node("Body/ApLabel") as Label
	_shield_label = get_node("Body/ShieldLabel") as Label
	_attack_label = get_node("Body/AttackLabel") as Label
	_health_label = get_node("Body/HealthLabel") as Label

	_apply_sharp_fonts()

	_frame_mat = ShaderMaterial.new()
	_frame_mat.shader = VfxAssets.get_shader("card_frame")
	_frame_mat.set_shader_parameter("card_size", size if size.x > 0 else Vector2(150, 210))
	_frame_mat.set_shader_parameter("art_rect", Vector4(_art.position.x, _art.position.y, _art.size.x, _art.size.y))
	_frame_mat.set_shader_parameter("text_rect", TEXT_RECT)
	_frame.material = _frame_mat
	_art_mat = ShaderMaterial.new()
	_art_mat.shader = VfxAssets.get_shader("card_art")
	_art_mat.set_shader_parameter("rect_size", _art.size)
	_art.material = _art_mat
	_banner_mat = _create_badge_material(_banner, 4, UNIT_BANNER_COLOR)
	_create_badge_material(_type_plate, 5, Color(0.42, 0.36, 0.3))
	_create_badge_material(_gem, 3, Color(0.22, 0.5, 1.0))
	_create_badge_material(_ap_badge, 6, Color(0.2, 0.65, 0.25))
	_create_badge_material(_shield_badge, 2, Color(0.78, 0.8, 0.86))
	_create_badge_material(_attack_badge, 0, Color(1.0, 0.78, 0.18))
	_create_badge_material(_health_badge, 1, Color(0.92, 0.13, 0.1))

	_glow_style = StyleBoxFlat.new()
	_glow_style.draw_center = false
	_glow_style.bg_color = Color(0, 0, 0, 0)
	_glow_style.border_color = PLAYABLE_GLOW_COLOR
	_glow_style.shadow_color = Color(PLAYABLE_GLOW_COLOR, 0.85)
	_glow_style.shadow_size = 14
	_glow_style.corner_detail = 8
	_glow_style.anti_aliasing = true
	_glow_style.set_corner_radius_all(14)
	_glow_style.set_border_width_all(3)
	_glow_style.set_expand_margin_all(3)
	_glow.add_theme_stylebox_override("panel", _glow_style)
	_create_keyword_nodes()

	for child: Node in _body.get_children():
		if child is CanvasItem and child != _glow and child != _frame:
			_face_items.append(child as CanvasItem)

	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	_refresh()


func _process(delta: float) -> void:
	_time += delta
	if _glow == null:
		return
	var color: Color
	var strength: float
	if _selected:
		color = SELECTED_GLOW_COLOR
		strength = 0.85 + 0.15 * sin(_time * 5.0)
	elif _playable:
		color = PLAYABLE_GLOW_COLOR
		strength = 0.6 + 0.25 * sin(_time * 3.0)
	elif _hovered and not managed_layout:
		color = HOVER_GLOW_COLOR
		strength = 0.6
	else:
		color = HOVER_GLOW_COLOR
		strength = 0.0
	if _reveal_glow > 0.0:
		color = color.lerp(Color(1.0, 0.9, 0.55), _reveal_glow)
		strength = maxf(strength, _reveal_glow)
	_glow.visible = strength > 0.01
	if _glow.visible:
		_glow_style.border_color = Color(color, clampf(strength, 0.0, 1.0))
		_glow_style.shadow_color = Color(color, clampf(strength * 0.8, 0.0, 1.0))
		_glow_style.shadow_size = int(10 + 10 * strength)


## Shows the given card with its effective AP cost.
func setup(p_card: CardData, p_ap_cost: int) -> void:
	card = p_card
	_ap_cost = p_ap_cost
	if is_node_ready():
		_refresh()


## Playable cards glow green; unplayable cards are slightly dimmed.
func set_playable(playable: bool) -> void:
	_playable = playable
	modulate = Color.WHITE if playable else Color(0.78, 0.76, 0.74, 1.0)


## Highlights (gold glow) and, unless managed_layout, raises the card while it is selected.
func set_selected(selected: bool) -> void:
	_selected = selected
	if is_node_ready():
		_update_raise()


## Dramatic reveal: fades in as a card back, flips to the face and flashes gold.
func play_reveal(delay: float) -> void:
	if not is_node_ready():
		return
	_revealing = true
	if _raise_tween != null:
		_raise_tween.kill()
	if _reveal_tween != null:
		_reveal_tween.kill()
	_set_show_back(true)
	_body.position = Vector2(0, -40.0)
	_body.scale = Vector2(0.5, 0.5)
	_body.modulate = Color(1, 1, 1, 0)
	_body.rotation = deg_to_rad(-8.0)

	_reveal_tween = create_tween()
	_reveal_tween.tween_interval(delay)
	_reveal_tween.set_parallel(true)
	_reveal_tween.tween_property(_body, "modulate:a", 1.0, 0.15)
	_reveal_tween.tween_property(_body, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_reveal_tween.tween_property(_body, "position:y", 0.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_reveal_tween.tween_property(_body, "rotation", 0.0, 0.22)
	_reveal_tween.chain().tween_property(_body, "scale:x", 0.0, 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_reveal_tween.chain().tween_callback(func() -> void:
		_set_show_back(false)
		_reveal_glow = 1.0
		Sfx.play(SfxId.CARD_FLIP)
	)
	_reveal_tween.chain().tween_property(_body, "scale", Vector2(1.1, 1.1), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_reveal_tween.chain().tween_property(_body, "scale", Vector2.ONE, 0.1)
	_reveal_tween.parallel().tween_method(func(v: float) -> void: _reveal_glow = v, 1.0, 0.0, 0.6)
	await _reveal_tween.finished
	_revealing = false
	_reveal_glow = 0.0
	_update_raise()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			card_clicked.emit(self)


func _on_mouse_entered() -> void:
	_hovered = true
	if not managed_layout:
		z_index = 1
		_update_raise()
	hover_changed.emit(self, true)


func _on_mouse_exited() -> void:
	_hovered = false
	if not managed_layout:
		z_index = 0
		_update_raise()
	hover_changed.emit(self, false)


func _set_show_back(back: bool) -> void:
	_frame_mat.set_shader_parameter("show_back", back)
	for item: CanvasItem in _face_items:
		item.visible = not back
	if not back:
		_refresh()


func _refresh() -> void:
	set_playable(_playable)
	_update_raise()

	if card == null:
		_name_label.text = ""
		_cost_label.text = ""
		_type_label.text = ""
		_stats_label.text = ""
		_description_label.text = ""
		_rich_description.text = ""
		tooltip_text = ""
		_keyword_row.visible = false
		_art_mat.set_shader_parameter("has_art", false)
		return

	var unit: bool = card.card_type == CardType.UNIT
	var tint := Color(card.tint.r, card.tint.g, card.tint.b)
	_frame_mat.set_shader_parameter("style", 0 if unit else 1)
	_frame_mat.set_shader_parameter("frame_color", UNIT_FRAME_COLOR if unit else SPELL_FRAME_COLOR)
	_frame_mat.set_shader_parameter("accent_color", tint)
	_banner_mat.set_shader_parameter("fill_color", UNIT_BANNER_COLOR if unit else SPELL_BANNER_COLOR)

	_art_mat.set_shader_parameter("has_art", card.art != null)
	if card.art != null:
		_art_mat.set_shader_parameter("art_texture", card.art)
	_art_mat.set_shader_parameter("tint", tint)
	_art_mat.set_shader_parameter("frame_shape", 0 if unit else 1)
	_art_mat.set_shader_parameter("emblem", _role_emblem(card.role) if unit else (3 if _spell_is_positive(card) else 4))
	var card_name: String = card.name
	_art_mat.set_shader_parameter("seed", float(absi(card_name.hash()) % 1000) * 0.01)

	_name_label.text = "(unnamed)" if card_name.is_empty() else card_name
	_cost_label.text = str(_ap_cost)
	_type_label.text = UnitRole.name_of(card.role) if unit else ("Area Spell" if card.targets_tile else "Spell")
	_stats_label.text = ("Move %d  ·  Range %d" % [card.movement, card.range]) if unit else _build_spell_stats(card)
	_fit_label(_name_label, NAME_MAX_FONT, 10)
	_fit_label(_stats_label, STATS_MAX_FONT, 8)
	_description_label.text = ""
	_rich_description.text = _build_description_bbcode(card)
	_layout_description(unit)
	_build_keyword_emblems(card)
	# Full rules are shown by the HUD's card info panel instead of a delayed native tooltip.
	tooltip_text = ""

	_attack_badge.visible = unit
	_attack_label.visible = unit
	_health_badge.visible = unit
	_health_label.visible = unit
	_attack_label.text = str(card.attack)
	_health_label.text = str(card.hp)
	var shield: bool = unit and card.shield > 0
	_shield_badge.visible = shield
	_shield_label.visible = shield
	_shield_label.text = str(card.shield)
	var ap: bool = unit and card.ap_bonus != 0
	_ap_badge.visible = ap
	_ap_label.visible = ap
	_ap_label.text = _format_delta(card.ap_bonus)
	_stats_label.modulate = Color.WHITE
	if not unit:
		if card.targets_tile:
			_stats_label.modulate = _tile_effect_text_color(card.tile_effect)
		else:
			_stats_label.modulate = Color(0.3, 0.75, 0.3) if _spell_is_positive(card) else Color(0.8, 0.4, 1.0)


# ------------------------------------------------------------------ keywords

## All card labels use the MSDF serif so they stay crisp at every hand / hover / HUD scale.
func _apply_sharp_fonts() -> void:
	for child: Node in _body.get_children():
		if child is Label:
			(child as Label).add_theme_font_override("font", VfxAssets.card_text_bold_font)


## Shrinks a single-line label's font until the text fits its width.
static func _fit_label(label: Label, max_size: int, min_size: int) -> void:
	var font: Font = VfxAssets.card_text_bold_font
	var width: float = label.size.x - 4.0
	var font_size: int = max_size
	while font_size > min_size and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		font_size -= 1
	label.add_theme_font_size_override("font_size", font_size)


## Places the card text inside the parchment box (narrower and shorter for units so the attack / health badges
## never cover it) and picks the largest font size at which the whole text fits.
func _layout_description(unit: bool) -> void:
	var pos: Vector2 = _description_label.position
	var box_size: Vector2 = _description_label.size
	if unit:
		pos.x += 4.0
		box_size.x -= 8.0
		box_size.y -= 10.0
	_rich_description.position = pos
	_rich_description.size = box_size
	var font_size: int = DESCRIPTION_MAX_FONT
	while font_size >= DESCRIPTION_MIN_FONT:
		_rich_description.add_theme_font_size_override("normal_font_size", font_size)
		_rich_description.add_theme_font_size_override("bold_font_size", font_size)
		if _rich_description.get_content_height() <= box_size.y:
			break
		font_size -= 1


func _create_keyword_nodes() -> void:
	_rich_description = RichTextLabel.new()
	_rich_description.name = "RichDescription"
	_rich_description.bbcode_enabled = true
	_rich_description.scroll_active = false
	_rich_description.fit_content = false
	_rich_description.clip_contents = true
	_rich_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rich_description.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rich_description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rich_description.position = _description_label.position
	_rich_description.size = _description_label.size
	_rich_description.add_theme_font_override("normal_font", VfxAssets.card_text_font)
	_rich_description.add_theme_font_override("bold_font", VfxAssets.card_text_bold_font)
	_rich_description.add_theme_font_size_override("normal_font_size", DESCRIPTION_MAX_FONT)
	_rich_description.add_theme_font_size_override("bold_font_size", DESCRIPTION_MAX_FONT)
	_rich_description.add_theme_color_override("default_color", Color(0.13, 0.08, 0.03))
	_rich_description.add_theme_constant_override("outline_size", 0)
	_rich_description.add_theme_constant_override("line_separation", 0)
	_body.add_child(_rich_description)
	_body.move_child(_rich_description, _description_label.get_index() + 1)

	_keyword_row = HBoxContainer.new()
	_keyword_row.name = "KeywordRow"
	_keyword_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keyword_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_keyword_row.position = Vector2(_art.position.x, _art.position.y + _art.size.y - 32.0)
	_keyword_row.size = Vector2(_art.size.x, 26.0)
	_keyword_row.add_theme_constant_override("separation", 2)
	_body.add_child(_keyword_row)
	_body.move_child(_keyword_row, _banner.get_index())


func _build_keyword_emblems(p_card: CardData) -> void:
	for child: Node in _keyword_row.get_children():
		_keyword_row.remove_child(child)
		child.queue_free()
	for k: int in KeywordInfo.split(p_card.keywords):
		var emblem := ColorRect.new()
		emblem.custom_minimum_size = Vector2(26.0, 26.0)
		emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
		emblem.material = _create_keyword_material(k)
		_keyword_row.add_child(emblem)
		if k == Keyword.UNDYING and p_card.level > 0:
			var lv := Label.new()
			lv.text = "+%d" % p_card.level
			lv.position = Vector2(13.0, 11.0)
			lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			lv.add_theme_font_override("font", VfxAssets.card_text_bold_font)
			lv.add_theme_font_size_override("font_size", 11)
			lv.add_theme_color_override("font_color", Color(0.75, 1.0, 0.9))
			lv.add_theme_color_override("font_outline_color", Color(0.03, 0.08, 0.07))
			lv.add_theme_constant_override("outline_size", 4)
			emblem.add_child(lv)
	_keyword_row.visible = _keyword_row.get_child_count() > 0 or p_card.keywords != Keyword.NONE


static func _create_keyword_material(k: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = VfxAssets.get_shader("keyword_icon")
	mat.set_shader_parameter("shape", int(KeywordVisuals.get_shape(k)))
	mat.set_shader_parameter("fg_color", KeywordVisuals.get_foreground(k))
	mat.set_shader_parameter("bg_color", KeywordVisuals.get_background(k))
	return mat


## Description with bold keyword names first ("Burning. ..."), as BBCode.
static func _build_description_bbcode(p_card: CardData) -> String:
	var text: String = p_card.description
	var heads: Array[String] = []
	for k: int in KeywordInfo.split(p_card.keywords):
		var kw_name: String = KeywordInfo.get_keyword_name(k)
		var trimmed: String = text.strip_edges(true, false)
		if trimmed.begins_with(kw_name + ".") or trimmed.begins_with(kw_name + ":"):
			text = trimmed.substr(kw_name.length() + 1).strip_edges(true, false)
		heads.append(("%s +%d" % [kw_name, p_card.level]) if (k == Keyword.UNDYING and p_card.level > 0) else kw_name)
	var body: String = _escape_bbcode(text)
	var head: String = ("[b]%s.[/b] " % ", ".join(heads)) if heads.size() > 0 else ""
	return "[center]%s%s[/center]" % [head, body]


static func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")


static func _tile_effect_text_color(type: int) -> Color:
	match type:
		TileEffectType.LAVA:
			return Color(0.85, 0.3, 0.05)
		TileEffectType.WALL:
			return Color(0.42, 0.36, 0.3)
		TileEffectType.HEALING:
			return Color(0.25, 0.6, 0.2)
		_:
			return Color(0.6, 0.35, 0.85)


static func _area_name(shape: int) -> String:
	match shape:
		AreaShape.PLUS:
			return "Cross"
		AreaShape.ROW3:
			return "Row 3"
		AreaShape.COLUMN3:
			return "Col 3"
		AreaShape.SQUARE2:
			return "2x2"
		_:
			return "1 tile"


func _update_raise() -> void:
	if _body == null or _revealing:
		return
	var target_y: float = 0.0
	var target_scale: float = 1.0
	if not managed_layout:
		target_y = -SELECTED_RAISE if _selected else (-HOVER_RAISE if _hovered else 0.0)
		target_scale = 1.06 if _selected else (1.05 if _hovered else 1.0)
	if _raise_tween != null:
		_raise_tween.kill()
	_raise_tween = create_tween()
	_raise_tween.set_parallel(true)
	_raise_tween.tween_property(_body, "position:y", target_y, TWEEN_TIME)
	_raise_tween.tween_property(_body, "scale", Vector2(target_scale, target_scale), TWEEN_TIME)


static func _create_badge_material(rect: ColorRect, shape: int, fill: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = VfxAssets.get_shader("card_badge")
	mat.set_shader_parameter("shape", shape)
	mat.set_shader_parameter("fill_color", fill)
	mat.set_shader_parameter("rect_size", rect.size)
	rect.material = mat
	return mat


static func _role_emblem(role: int) -> int:
	match role:
		UnitRole.ATTACK:
			return 0
		UnitRole.UTILITY:
			return 1
		_:
			return 2


static func _spell_is_positive(p_card: CardData) -> bool:
	return p_card.attack_delta + p_card.hp_delta + p_card.shield_delta + p_card.movement_delta + p_card.range_delta >= 0


static func _build_spell_stats(p_card: CardData) -> String:
	var parts: Array[String] = []
	if p_card.targets_tile:
		parts.append(_area_name(p_card.area_shape))
		if p_card.spell_damage > 0:
			parts.append("%d dmg" % p_card.spell_damage)
		if p_card.spell_heal > 0:
			parts.append("+%d HP" % p_card.spell_heal)
		if p_card.tile_effect != TileEffectType.NONE:
			parts.append("%s %dT" % [KeywordInfo.get_tile_effect_name(p_card.tile_effect), p_card.tile_effect_duration])
		return " · ".join(parts)
	if p_card.grant_status != StatusEffectType.NONE:
		parts.append(KeywordInfo.get_status_name(p_card.grant_status))
	_add_delta(parts, p_card.attack_delta, "Atk")
	_add_delta(parts, p_card.hp_delta, "HP")
	_add_delta(parts, p_card.shield_delta, "Shield")
	_add_delta(parts, p_card.movement_delta, "Move")
	_add_delta(parts, p_card.range_delta, "Range")
	return "  ".join(parts) if parts.size() > 0 else "No stat change"


static func _add_delta(parts: Array[String], value: int, label: String) -> void:
	if value != 0:
		parts.append("%s %s" % [_format_delta(value), label])


static func _format_delta(value: int) -> String:
	return ("+%d" % value) if value > 0 else str(value)
