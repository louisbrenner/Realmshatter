class_name DeckBuilderPanel
extends OverlayWindow
## Deck builder: the left grid shows every owned card (click to add a copy to the deck; caption = copies in deck /
## owned), the right column lists the deck (mana gem with the cost, name, copies; click an entry to remove a copy,
## hover it to see the full card beside the list). Cards are ordered by clan, then rarity, then cost and name.
## Filters: All / Units / Spells. The deck must hold PlayerProfile.DECK_MIN..DECK_MAX cards with at most MAX_COPIES
## copies of a card.

const CARD_SCALE := 0.56
const PREVIEW_SCALE := 0.95
const GEM_SIZE := 24.0

## Filter (private C# enum Filter).
enum { ALL = 0, UNITS = 1, SPELLS = 2 }

var _filter: int = ALL
var _grid: GridContainer
var _deck_list: VBoxContainer
var _deck_title: Label
var _deck_status: Label
var _message: Label
var _filter_buttons: Array[Button] = []
var _deck_panel: PanelContainer
var _preview: CardView
var _preview_owner: Control


func open() -> void:
	super.open()
	_build_layout()
	title_label.text = "Deck Builder"
	subtitle_label.text = "Click a card to add it, click a deck entry to remove it."
	_message.text = ""
	_rebuild()


func _build_layout() -> void:
	if _grid != null:
		return
	for entry: Array in [["All", ALL], ["Units", UNITS], ["Spells", SPELLS]]:
		var label: String = entry[0]
		var f: int = entry[1]
		var b: Button = make_button(label)
		b.pressed.connect(func() -> void:
			Sfx.play(SfxId.BUTTON_CLICK)
			_filter = f
			_rebuild()
		)
		header_buttons.add_child(b)
		_filter_buttons.append(b)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_theme_constant_override("separation", 14)
	body.add_child(columns)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(760, 500)
	columns.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 8
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_grid)

	var deck_panel := PanelContainer.new()
	deck_panel.custom_minimum_size = Vector2(260, 0)
	deck_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deck_panel = deck_panel
	deck_panel.add_theme_stylebox_override("panel", HudStyle.box(Color(0.08, 0.05, 0.03, 0.9), HudStyle.GOLD_DARK, 10, 2, 4))
	columns.add_child(deck_panel)
	var deck_box := VBoxContainer.new()
	deck_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deck_box.add_theme_constant_override("separation", 6)
	deck_panel.add_child(deck_box)
	_deck_title = Label.new()
	_deck_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_deck_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deck_title.add_theme_font_override("font", VfxAssets.get_card_text_bold_font())
	_deck_title.add_theme_font_size_override("font_size", 20)
	_deck_title.add_theme_color_override("font_color", HudStyle.GOLD)
	_deck_title.add_theme_constant_override("outline_size", 5)
	deck_box.add_child(_deck_title)
	_deck_status = Label.new()
	_deck_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_deck_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_deck_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deck_status.add_theme_font_override("font", VfxAssets.get_card_text_font())
	_deck_status.add_theme_font_size_override("font_size", 13)
	deck_box.add_child(_deck_status)
	var deck_scroll := ScrollContainer.new()
	deck_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	deck_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	deck_scroll.custom_minimum_size = Vector2(240, 360)
	deck_box.add_child(deck_scroll)
	_deck_list = VBoxContainer.new()
	_deck_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_deck_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deck_list.add_theme_constant_override("separation", 3)
	deck_scroll.add_child(_deck_list)
	_message = Label.new()
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message.add_theme_font_override("font", VfxAssets.get_card_text_font())
	_message.add_theme_font_size_override("font_size", 13)
	_message.add_theme_color_override("font_color", Color(1.0, 0.6, 0.45))
	deck_box.add_child(_message)


func _rebuild() -> void:
	refresh_gold()
	for i in _filter_buttons.size():
		_filter_buttons[i].disabled = _filter == i
	card_info.hide_panel()
	_hide_preview()
	clear_children(_grid)
	var owned_cards: Array[CardData] = PlayerProfile.get_owned_cards()
	owned_cards.sort_custom(func(a: CardData, b: CardData) -> bool: return compare_cards(a, b) < 0)
	for card: CardData in owned_cards:
		if (_filter == UNITS and card.card_type != CardType.UNIT) or (_filter == SPELLS and card.card_type != CardType.SPELL):
			continue
		var slot := CardSlot.new()
		slot.setup(card, CARD_SCALE, false)
		_grid.add_child(slot)
		track_hover(slot)
		var owned: int = PlayerProfile.owned_count(card)
		var in_deck: int = PlayerProfile.in_deck_count(card)
		var can_add: bool = in_deck < owned and in_deck < PlayerProfile.MAX_COPIES and PlayerProfile.get_deck_count() < PlayerProfile.DECK_MAX
		slot.set_caption("%d / %d in deck" % [in_deck, owned], HudStyle.GOLD if in_deck > 0 else HudStyle.TEXT_LIGHT)
		slot.set_highlight(can_add)
		slot.set_dimmed(not can_add and in_deck >= owned)
		slot.activated.connect(_on_add_card)
	_rebuild_deck_list()


func _rebuild_deck_list() -> void:
	clear_children(_deck_list)
	var count: int = PlayerProfile.get_deck_count()
	_deck_title.text = "Your Deck (%d)" % count
	var valid: bool = PlayerProfile.get_deck_is_valid()
	if valid:
		_deck_status.text = "Ready for battle. (%d-%d cards, max %d copies)" % [PlayerProfile.DECK_MIN, PlayerProfile.DECK_MAX, PlayerProfile.MAX_COPIES]
	else:
		_deck_status.text = "Needs %d-%d cards to battle." % [PlayerProfile.DECK_MIN, PlayerProfile.DECK_MAX]
	_deck_status.add_theme_color_override("font_color", Color(0.55, 1.0, 0.55) if valid else Color(1.0, 0.55, 0.45))

	# Entries: {"card": CardData, "count": int}.
	var counts: Array[Dictionary] = []
	for card: CardData in PlayerProfile.get_deck():
		var found: int = -1
		for i in counts.size():
			if counts[i]["card"] == card:
				found = i
				break
		if found >= 0:
			counts[found] = {"card": card, "count": int(counts[found]["count"]) + 1}
		else:
			counts.append({"card": card, "count": 1})
	counts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return compare_cards(a["card"], b["card"]) < 0)
	for e: Dictionary in counts:
		_deck_list.add_child(_build_deck_entry(e["card"], e["count"]))


## Clan (basic cards first), then rarity, then AP cost, then name. Returns -1 / 0 / 1.
static func compare_cards(a: CardData, b: CardData) -> int:
	if a.clan != b.clan:
		return -1 if a.clan < b.clan else 1
	if a.rarity != b.rarity:
		return -1 if a.rarity < b.rarity else 1
	var ca: int = _cost_of(a)
	var cb: int = _cost_of(b)
	if ca != cb:
		return -1 if ca < cb else 1
	if a.name == b.name:
		return 0
	return -1 if a.name < b.name else 1


static func _cost_of(card: CardData) -> int:
	return card.ap_cost if card.ap_cost > 0 else (1 if card.card_type == CardType.UNIT else 2)


## One deck row: clan stripe, mana gem with the cost, name (rarity colour) and the number of copies.
func _build_deck_entry(card: CardData, copies: int) -> Button:
	var entry := Button.new()
	entry.focus_mode = Control.FOCUS_NONE
	entry.tooltip_text = "Click to remove one copy"
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.custom_minimum_size = Vector2(0.0, 30.0)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 6.0
	row.offset_right = -8.0
	row.add_theme_constant_override("separation", 7)
	entry.add_child(row)

	var stripe := ColorRect.new()
	stripe.color = Color(0.3, 0.28, 0.26) if card.clan == Clan.NONE else ClanInfo.get_color(card.clan)
	stripe.custom_minimum_size = Vector2(4.0, 22.0)
	stripe.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(stripe)

	var gem := ColorRect.new()
	gem.custom_minimum_size = Vector2(GEM_SIZE, GEM_SIZE)
	gem.size = Vector2(GEM_SIZE, GEM_SIZE)
	gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = VfxAssets.get_shader("card_badge")
	mat.set_shader_parameter("shape", 3)
	mat.set_shader_parameter("fill_color", Color(0.22, 0.5, 1.0))
	mat.set_shader_parameter("rect_size", Vector2(GEM_SIZE, GEM_SIZE))
	gem.material = mat
	var cost := Label.new()
	cost.text = str(_cost_of(card))
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost.set_anchors_preset(Control.PRESET_FULL_RECT)
	cost.add_theme_font_override("font", VfxAssets.get_number_font())
	cost.add_theme_font_size_override("font_size", 14)
	cost.add_theme_color_override("font_color", Color.WHITE)
	cost.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.16))
	cost.add_theme_constant_override("outline_size", 4)
	gem.add_child(cost)
	row.add_child(gem)

	var name_label := Label.new()
	name_label.text = card.name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_override("font", VfxAssets.get_card_text_bold_font())
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", CardEconomy.rarity_color(card.rarity).lightened(0.55))
	name_label.add_theme_constant_override("outline_size", 4)
	row.add_child(name_label)

	var count_label := Label.new()
	count_label.text = "x%d" % copies
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_label.add_theme_font_override("font", VfxAssets.get_number_font())
	count_label.add_theme_font_size_override("font_size", 14)
	count_label.add_theme_color_override("font_color", HudStyle.GOLD)
	count_label.add_theme_constant_override("outline_size", 4)
	row.add_child(count_label)

	entry.mouse_entered.connect(func() -> void: _show_preview(entry, card))
	entry.mouse_exited.connect(func() -> void:
		if _preview_owner == entry:
			_hide_preview()
	)
	entry.pressed.connect(func() -> void:
		Sfx.play(SfxId.CARD_HOVER)
		PlayerProfile.remove_from_deck(card)
		_message.text = ""
		_rebuild.call_deferred()
	)
	return entry


## Shows the full card left of the deck list, level with the hovered entry (kept inside the window).
func _show_preview(entry: Control, card: CardData) -> void:
	if _preview == null:
		if _card_scene == null:
			_card_scene = load(CardSlot.CARD_SCENE_PATH) as PackedScene
		_preview = _card_scene.instantiate() as CardView
		_preview.managed_layout = true
		_preview.z_index = 40
		add_child(_preview)
		_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_preview.pivot_offset = Vector2.ZERO
		_preview.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	_preview_owner = entry
	_preview.setup(card, _cost_of(card))
	_preview.set_playable(false)
	_preview.modulate = Color.WHITE
	var to_local_xf: Transform2D = get_global_transform().affine_inverse()
	var panel_pos: Vector2 = to_local_xf * _deck_panel.get_global_rect().position
	var entry_pos: Vector2 = to_local_xf * entry.get_global_rect().position
	var preview_size: Vector2 = Vector2(150.0, 210.0) * PREVIEW_SCALE
	var x: float = panel_pos.x - preview_size.x - 12.0
	var y: float = clampf(entry_pos.y - preview_size.y * 0.4, 8.0, maxf(8.0, size.y - preview_size.y - 8.0))
	_preview.position = Vector2(x, y)
	_preview.visible = true
	Sfx.play(SfxId.CARD_HOVER)


func _hide_preview() -> void:
	_preview_owner = null
	if _preview != null:
		_preview.visible = false


static var _card_scene: PackedScene


func _on_add_card(slot: CardSlot) -> void:
	var r: Dictionary = PlayerProfile.try_add_to_deck(slot.card)
	if not r["result"]:
		_message.text = r["error"]
		Sfx.play(SfxId.BLOCKED)
		return
	Sfx.play(SfxId.CARD_PICK)
	_message.text = ""
	_rebuild.call_deferred()
