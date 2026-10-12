class_name CardView
extends Control
## Printed tabletop card (root of Scenes/UI/Card.tscn): the artwork fills the whole face (CardData.art, or a
## procedural painting while a card has no picture yet) inside a thin clan-coloured card-stock border. A printed
## overlay (card_overlay.gdshader) adds the name bar, a rules panel (only when the card has rules text) and the
## type plate at the bottom, whose outline shows the kind of card. Attack / health badges sit in the bottom
## corners, the shield badge stacks above the health badge. Playable cards glow green, selected cards glow gold
## and lift. The root Control receives the mouse; the inner "Body" animates.

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
## Rules panel (x, y, w, h) drawn by card_overlay.gdshader; holds the rules text.
const TEXT_RECT := Vector4(10.0, 124.0, 130.0, 44.0)
## Name bar (x, y, w, h) drawn by card_overlay.gdshader.
const NAME_RECT := Vector4(5.0, 5.0, 140.0, 25.0)
## Type plate (x, y, w, h) at the bottom; its outline depends on the card kind.
const PLATE_RECT := Vector4(38.0, 186.0, 74.0, 20.0)
## Painting centre offset (pixels, y down) so the subject sits above the rules panel.
const ART_FOCUS_WITH_TEXT := Vector2(0.0, -34.0)
const ART_FOCUS_NO_TEXT := Vector2(0.0, -16.0)

const UNIT_BANNER_COLOR := Color(0.78, 0.6, 0.36)
## Card colour of neutral (clan-less) cards: near-black card stock.
const NEUTRAL_CARD_COLOR := Color(0.14, 0.13, 0.125)
const RULES_INK := Color(0.16, 0.1, 0.05)
## Every icon in the rules panel has the same size, however many there are.
const RULE_ICON_SIZE := 21.0
const RULE_FONT_SIZE := 12
const RULE_ICON_GAP := 2.0
const RULE_H_GAP := 5.0
const RULE_V_GAP := 1.0
const RULE_MIN_SCALE := 0.6
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
var _rules_box: VBoxContainer
var _rules_flow: HFlowContainer
var _rule_items: Array[RuleItem] = []
var _frame_mat: ShaderMaterial
var _art_mat: ShaderMaterial
var _banner_mat: ShaderMaterial
var _plate_mat: ShaderMaterial
var _overlay_mat: ShaderMaterial
var _overlay: ColorRect
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
	_frame.material = _frame_mat
	_art_mat = ShaderMaterial.new()
	_art_mat.shader = VfxAssets.get_shader("card_art")
	_art_mat.set_shader_parameter("rect_size", _art.size)
	_art_mat.set_shader_parameter("frame_shape", 2)
	_art.material = _art_mat
	_overlay_mat = ShaderMaterial.new()
	_overlay_mat.shader = VfxAssets.get_shader("card_overlay")
	_overlay_mat.set_shader_parameter("card_size", size if size.x > 0 else Vector2(150, 210))
	_overlay_mat.set_shader_parameter("name_rect", NAME_RECT)
	_overlay_mat.set_shader_parameter("text_rect", TEXT_RECT)
	_overlay_mat.set_shader_parameter("plate_rect", PLATE_RECT)
	_overlay = ColorRect.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.material = _overlay_mat
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_body.add_child(_overlay)
	_body.move_child(_overlay, _art.get_index() + 1)
	# Drawn by the overlay now; the old ribbon / plate nodes and the stats line stay hidden.
	_banner.visible = false
	_type_plate.visible = false
	_stats_label.visible = false
	_banner_mat = _create_badge_material(_banner, 4, UNIT_BANNER_COLOR)
	_plate_mat = _create_badge_material(_type_plate, 5, Color(0.42, 0.36, 0.3))
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
		if child is CanvasItem and child != _glow and child != _frame and child != _banner and child != _type_plate and child != _stats_label:
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


## Dramatic reveal: fades in as a card back, flips to the face and flashes gold (coroutine).
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
	for item in _face_items:
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
		_rules_box.visible = false
		_art_mat.set_shader_parameter("has_art", false)
		return

	var unit: bool = card.card_type == CardType.UNIT
	var planted: bool = unit and card.has_keyword(Keyword.PLANTED)
	var tint := Color(card.tint.r, card.tint.g, card.tint.b)
	var clan: Color = NEUTRAL_CARD_COLOR if card.clan == Clan.NONE else ClanInfo.get_color(card.clan)
	# Legendary cards get a gold card stock border.
	_frame_mat.set_shader_parameter("frame_color", Color(0.95, 0.72, 0.3) if card.rarity == CardRarity.LEGENDARY else clan.darkened(0.12))

	# Artwork: a real picture (CardData.art) fills the face; without one the procedural painting stands in.
	_art_mat.set_shader_parameter("has_art", card.art != null)
	if card.art != null:
		_art_mat.set_shader_parameter("art_texture", card.art)
	_art_mat.set_shader_parameter("tint", tint)
	_art_mat.set_shader_parameter("emblem", _role_emblem(card.role) if unit else (3 if _spell_is_positive(card) else 4))
	_art_mat.set_shader_parameter("glyph", ClassVisuals.art_glyph(card))
	_art_mat.set_shader_parameter("animate", card.rarity != CardRarity.COMMON)
	_art_mat.set_shader_parameter("seed", float(absi(card.name.hash()) % 1000) * 0.01)

	# Rules panel: icons (keywords, triggers, stat changes, statuses, tile effects) with short values.
	_rule_items = _unit_rule_items(card) if unit else _spell_rule_items(card)
	var rule_items: int = _rule_items.size()
	_rules_box.visible = rule_items > 0
	var has_text: bool = rule_items > 0
	_art_mat.set_shader_parameter("focus", ART_FOCUS_WITH_TEXT if has_text else ART_FOCUS_NO_TEXT)
	_overlay_mat.set_shader_parameter("has_text", has_text)
	_overlay_mat.set_shader_parameter("clan_color", clan)
	_overlay_mat.set_shader_parameter("rarity_color", CardEconomy.rarity_color(card.rarity))
	_overlay_mat.set_shader_parameter("plate_shape", (3 if planted else 0) if unit else (2 if card.targets_tile else 1))

	_name_label.text = "(unnamed)" if card.name.is_empty() else card.name
	_cost_label.text = str(_ap_cost)
	_type_label.text = ClassInfo.class_or_role(card) if unit else ("Area Spell" if card.targets_tile else "Spell")
	_fit_label(_type_label, 10, 7)
	_fit_label(_name_label, NAME_MAX_FONT, 8)
	_description_label.text = ""
	_rich_description.text = ""
	_rich_description.visible = false
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
	_layout_description(shield)
	var ap: bool = unit and card.ap_bonus != 0
	_ap_badge.visible = ap
	_ap_label.visible = ap
	_ap_label.text = _format_delta(card.ap_bonus)


# ------------------------------------------------------------------ keywords

## All card labels use the MSDF serif so they stay crisp at every hand / hover / HUD scale.
func _apply_sharp_fonts() -> void:
	for child: Node in _body.get_children():
		if child is Label:
			(child as Label).add_theme_font_override("font", VfxAssets.get_card_text_bold_font())
	# Badge numbers: lining figures, centred in their badge (label box = badge box, ink centred via margins).
	var pairs: Array = [
		{"number": _cost_label, "badge": _gem},
		{"number": _attack_label, "badge": _attack_badge},
		{"number": _health_label, "badge": _health_badge},
		{"number": _shield_label, "badge": _shield_badge},
		{"number": _ap_label, "badge": _ap_badge},
	]
	for pair: Dictionary in pairs:
		var number: Label = pair["number"]
		var badge: ColorRect = pair["badge"]
		number.add_theme_font_override("font", VfxAssets.get_number_font())
		number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		number.position = badge.position
		number.size = badge.size
		var drop: float = VfxAssets.digit_drop(number.get_theme_font_size("font_size"))
		var empty := StyleBoxEmpty.new()
		empty.content_margin_top = maxf(0.0, -drop * 2.0)
		empty.content_margin_bottom = maxf(0.0, drop * 2.0)
		number.add_theme_stylebox_override("normal", empty)


## Shrinks a single-line label's font until the text fits its width.
static func _fit_label(label: Label, max_size: int, min_size: int) -> void:
	var font: Font = VfxAssets.get_card_text_bold_font()
	var width: float = label.size.x - 4.0
	var font_size: int = max_size
	while font_size > min_size and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		font_size -= 1
	label.add_theme_font_size_override("font_size", font_size)


## Places the rules text inside the rules panel (leaving room on the right for the shield badge) and picks the
## largest font size at which the whole text fits; the rule icons are built at the largest scale that fits.
func _layout_description(shield: bool) -> void:
	var pos: Vector2 = _description_label.position
	var box_size: Vector2 = _description_label.size
	if shield:
		box_size.x -= 18.0
	_rich_description.position = pos
	_rich_description.size = box_size
	# The icon box keeps clear of the shield badge, which overlaps the panel's right corner.
	_rules_box.position = Vector2(TEXT_RECT.x + 3.0, TEXT_RECT.y + 2.0)
	_rules_box.size = Vector2(TEXT_RECT.z - 6.0 - (20.0 if shield else 0.0), TEXT_RECT.w - 4.0)
	_build_rule_icons(_rule_items, _fit_rule_scale(_rule_items, _rules_box.size))
	for font_size in range(DESCRIPTION_MAX_FONT, DESCRIPTION_MIN_FONT - 1, -1):
		_rich_description.add_theme_font_size_override("normal_font_size", font_size)
		_rich_description.add_theme_font_size_override("bold_font_size", font_size)
		if _rich_description.get_content_height() <= box_size.y:
			break


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
	_rich_description.add_theme_font_override("normal_font", VfxAssets.get_card_text_font())
	_rich_description.add_theme_font_override("bold_font", VfxAssets.get_card_text_bold_font())
	_rich_description.add_theme_font_size_override("normal_font_size", DESCRIPTION_MAX_FONT)
	_rich_description.add_theme_font_size_override("bold_font_size", DESCRIPTION_MAX_FONT)
	_rich_description.add_theme_color_override("default_color", Color(0.13, 0.08, 0.03))
	_rich_description.add_theme_constant_override("outline_size", 0)
	_rich_description.add_theme_constant_override("line_separation", 0)
	_body.add_child(_rich_description)
	_body.move_child(_rich_description, _description_label.get_index() + 1)

	_rules_box = VBoxContainer.new()
	_rules_box.name = "RulesBox"
	_rules_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rules_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_rules_box.position = Vector2(TEXT_RECT.x + 3.0, TEXT_RECT.y + 2.0)
	_rules_box.size = Vector2(TEXT_RECT.z - 6.0, TEXT_RECT.w - 4.0)
	_rules_box.visible = false
	_rules_flow = HFlowContainer.new()
	_rules_flow.name = "RulesFlow"
	_rules_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rules_flow.alignment = FlowContainer.ALIGNMENT_CENTER
	_rules_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rules_flow.add_theme_constant_override("h_separation", int(RULE_H_GAP))
	_rules_flow.add_theme_constant_override("v_separation", int(RULE_V_GAP))
	_rules_box.add_child(_rules_flow)
	_body.add_child(_rules_box)
	_body.move_child(_rules_box, _rich_description.get_index() + 1)


## One entry of the rules panel: a keyword emblem (glyph = FxIconShape) or a card badge (badge = card_badge shape:
## 0 attack, 1 health, 2 shield), its colours, an optional value / name next to it and an optional small overlay
## (Undying level). glyph and badge both -1 = plain text.
class RuleItem:
	var glyph: int
	var badge: int
	var fg: Color
	var bg: Color
	var label: String
	var overlay: String

	func _init(p_glyph: int = -1, p_badge: int = -1, p_fg: Color = Color.WHITE, p_bg: Color = Color.WHITE, p_label: String = "", p_overlay: String = "") -> void:
		glyph = p_glyph
		badge = p_badge
		fg = p_fg
		bg = p_bg
		label = p_label
		overlay = p_overlay


static func _emblem(shape: int, fg: Color, bg: Color, label: String = "") -> RuleItem:
	return RuleItem.new(shape, -1, fg, bg, label)


static func _stat_badge(badge: int, fill: Color, label: String) -> RuleItem:
	return RuleItem.new(-1, badge, fill, fill, label)


const ATTACK_FILL := Color(1.0, 0.66, 0.2)
const HEALTH_FILL := Color(0.86, 0.12, 0.1)
const SHIELD_FILL := Color(0.78, 0.8, 0.86)


## Unit rules: one emblem per keyword (the icon replaces the name; Builder adds its building, Undying its level), then triggers.
static func _unit_rule_items(c: CardData) -> Array[RuleItem]:
	var items: Array[RuleItem] = []
	for k: int in KeywordInfo.split(c.keywords):
		var fg: Color = KeywordVisuals.get_foreground(k)
		var bg: Color = KeywordVisuals.get_background(k)
		if k == Keyword.AURA:
			fg = ClanInfo.get_color(c.clan).lightened(0.35)
			bg = ClanInfo.get_color(c.clan).darkened(0.65)
		var label: String = ""
		if k == Keyword.BUILDER and BuildingInfo.for_class(c.class_) != BuildingType.NONE:
			label = BuildingInfo.display_name(BuildingInfo.for_class(c.class_))
		elif k == Keyword.TRAPPER:
			label = TrapInfo.display_name(TrapInfo.for_clan(c.clan))
		var overlay: String = "+%d" % c.level if k == Keyword.UNDYING and c.level > 0 else ""
		items.append(RuleItem.new(KeywordVisuals.get_shape(k), -1, fg, bg, label, overlay))
	if c.legend != LegendEffect.NONE:
		items.append(_emblem(LegendInfo.get_shape(c.legend), LegendInfo.get_color(c.legend), LegendInfo.EMBLEM_BACKGROUND, LegendInfo.display_name(c.legend)))
	for line: String in TriggerInfo.card_face_lines(c):
		var colon: int = line.find(":")
		var head: String = line.substr(0, colon) if colon >= 0 else line
		var effect: String = line.substr(colon + 1).strip_edges() if colon >= 0 else ""
		if head == "First hit":
			items.append(_emblem(FxIconShape.BURST, Color(1.0, 0.82, 0.45), Color(0.45, 0.16, 0.08, 0.97), effect))
		elif head == "Deathrattle":
			items.append(_emblem(FxIconShape.TOMB, Color(0.85, 0.85, 0.95), Color(0.18, 0.16, 0.26, 0.97), effect))
	return items


## Spell rules: area (text), damage / heal / push, tile effect with its duration, stat changes, status, AP.
static func _spell_rule_items(c: CardData) -> Array[RuleItem]:
	var items: Array[RuleItem] = []
	if c.targets_tile:
		items.append(RuleItem.new(-1, -1, RULES_INK, RULES_INK, _area_name(AreaShape.SINGLE if c.spell_target == SpellTargetType.TILE else c.area_shape)))
		if c.spell_damage > 0:
			items.append(_emblem(FxIconShape.BURST, Color(1.0, 0.75, 0.4), Color(0.5, 0.1, 0.06, 0.97), str(c.spell_damage)))
		if c.spell_heal > 0:
			items.append(_stat_badge(1, HEALTH_FILL, "+%d" % c.spell_heal))
		if c.spell_push:
			items.append(_emblem(FxIconShape.FIST, KeywordVisuals.get_foreground(Keyword.PUSH), KeywordVisuals.get_background(Keyword.PUSH)))
		if c.tile_effect != TileEffectType.NONE:
			var shape: int
			var fg: Color
			var bg: Color
			match c.tile_effect:
				TileEffectType.LAVA:
					shape = FxIconShape.FLAME
					fg = Color(1.0, 0.55, 0.15)
					bg = Color(0.42, 0.1, 0.03, 0.97)
				TileEffectType.HEALING:
					shape = FxIconShape.PLUS
					fg = Color(0.55, 1.0, 0.55)
					bg = Color(0.1, 0.38, 0.14, 0.97)
				_:
					shape = FxIconShape.BRICKS
					fg = Color(0.88, 0.82, 0.72)
					bg = Color(0.3, 0.27, 0.24, 0.97)
			items.append(_emblem(shape, fg, bg, "%dT" % c.tile_effect_duration))
	else:
		_add_stat(items, c.attack_delta, 0, ATTACK_FILL)
		_add_stat(items, c.hp_delta, 1, HEALTH_FILL)
		_add_stat(items, c.shield_delta, 2, SHIELD_FILL)
		if c.movement_delta != 0:
			items.append(_emblem(FxIconShape.CHEVRONS, Color(0.75, 1.0, 0.7), Color(0.14, 0.32, 0.16, 0.97), _format_delta(c.movement_delta)))
		if c.range_delta != 0:
			items.append(_emblem(FxIconShape.CROSSHAIR, Color(1.0, 0.88, 0.65), Color(0.38, 0.22, 0.1, 0.97), _format_delta(c.range_delta)))
		if c.grant_status == StatusEffectType.FROZEN:
			items.append(_emblem(FxIconShape.SNOWFLAKE, KeywordVisuals.get_foreground(Keyword.FROST), KeywordVisuals.get_background(Keyword.FROST)))
		elif c.grant_status == StatusEffectType.OVERCHARGED:
			items.append(_emblem(FxIconShape.BOLT, KeywordVisuals.get_foreground(Keyword.ARC), KeywordVisuals.get_background(Keyword.ARC), "x2"))
	if c.ap_gain > 0:
		items.append(_emblem(FxIconShape.GEM, KeywordVisuals.get_foreground(Keyword.PLUNDER), KeywordVisuals.get_background(Keyword.PLUNDER), "+%d" % c.ap_gain))
	return items


static func _add_stat(items: Array[RuleItem], value: int, badge: int, fill: Color) -> void:
	if value != 0:
		items.append(_stat_badge(badge, fill, _format_delta(value)))


## Largest scale (1 = full size, down to RULE_MIN_SCALE) at which the rule items, flowed into rows like the
## HFlowContainer does, fit the rules panel (long trigger names on legendaries / epics would overflow it).
static func _fit_rule_scale(items: Array[RuleItem], box: Vector2) -> float:
	var font: Font = VfxAssets.get_card_text_bold_font()
	var rule_scale: float = 1.0
	while rule_scale > RULE_MIN_SCALE:
		var icon: float = RULE_ICON_SIZE * rule_scale
		var font_size: int = maxi(7, roundi(RULE_FONT_SIZE * rule_scale))
		var row_height: float = maxf(icon, font.get_height(font_size))
		var rows: int = 1
		var x: float = 0.0
		for rule in items:
			var has_icon: bool = rule.glyph >= 0 or rule.badge >= 0
			var w: float = (icon if has_icon else 0.0) + (RULE_ICON_GAP if has_icon and rule.label.length() > 0 else 0.0) \
				+ (font.get_string_size(rule.label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x if rule.label.length() > 0 else 0.0)
			if x > 0.0 and x + RULE_H_GAP + w > box.x:
				rows += 1
				x = w
			else:
				x += (RULE_H_GAP if x > 0.0 else 0.0) + w
		if rows * row_height + (rows - 1) * RULE_V_GAP <= box.y:
			return rule_scale
		rule_scale -= 0.05
	return RULE_MIN_SCALE


## Fills the rules panel with the given items (icon + value) at a size scale; returns their number (0 = no panel).
func _build_rule_icons(items: Array[RuleItem], rule_scale: float = 1.0) -> int:
	for child: Node in _rules_flow.get_children():
		_rules_flow.remove_child(child)
		child.queue_free()
	var icon_size: float = RULE_ICON_SIZE * rule_scale
	var font_size: int = maxi(7, roundi(RULE_FONT_SIZE * rule_scale))
	for rule in items:
		var item := HBoxContainer.new()
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_theme_constant_override("separation", int(RULE_ICON_GAP))
		if rule.glyph >= 0 or rule.badge >= 0:
			var icon := ColorRect.new()
			icon.custom_minimum_size = Vector2(icon_size, icon_size)
			icon.size = Vector2(icon_size, icon_size)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			if rule.glyph >= 0:
				var mat := ShaderMaterial.new()
				mat.shader = VfxAssets.get_shader("keyword_icon")
				mat.set_shader_parameter("shape", rule.glyph)
				mat.set_shader_parameter("fg_color", rule.fg)
				mat.set_shader_parameter("bg_color", rule.bg)
				icon.material = mat
			else:
				_create_badge_material(icon, rule.badge, rule.fg)
			if rule.overlay.length() > 0:
				var lv := Label.new()
				lv.text = rule.overlay
				lv.position = Vector2(icon_size * 0.5, icon_size * 0.42)
				lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
				lv.add_theme_font_override("font", VfxAssets.get_card_text_bold_font())
				lv.add_theme_font_size_override("font_size", 10)
				lv.add_theme_color_override("font_color", Color(0.75, 1.0, 0.9))
				lv.add_theme_color_override("font_outline_color", Color(0.03, 0.08, 0.07))
				lv.add_theme_constant_override("outline_size", 4)
				icon.add_child(lv)
			item.add_child(icon)
		if rule.label.length() > 0:
			var text := Label.new()
			text.text = rule.label
			text.mouse_filter = Control.MOUSE_FILTER_IGNORE
			text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			text.add_theme_font_override("font", VfxAssets.get_card_text_bold_font())
			text.add_theme_font_size_override("font_size", font_size)
			text.add_theme_color_override("font_color", RULES_INK)
			text.add_theme_constant_override("outline_size", 0)
			item.add_child(text)
		_rules_flow.add_child(item)
	return items.size()


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
	var s: float = 1.0
	if not managed_layout:
		target_y = -SELECTED_RAISE if _selected else (-HOVER_RAISE if _hovered else 0.0)
		s = 1.06 if _selected else (1.05 if _hovered else 1.0)
	if _raise_tween != null:
		_raise_tween.kill()
	_raise_tween = create_tween()
	_raise_tween.set_parallel(true)
	_raise_tween.tween_property(_body, "position:y", target_y, TWEEN_TIME)
	_raise_tween.tween_property(_body, "scale", Vector2(s, s), TWEEN_TIME)


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


static func _spell_is_positive(c: CardData) -> bool:
	return c.attack_delta + c.hp_delta + c.shield_delta + c.movement_delta + c.range_delta >= 0


static func _format_delta(value: int) -> String:
	return "+%d" % value if value > 0 else str(value)
