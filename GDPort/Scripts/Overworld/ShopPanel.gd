class_name ShopPanel
extends OverlayWindow
## Vendor window: "Buy" lists the vendor's stock with prices (affordable cards glow), "Sell" lists every owned
## card with its sell price and how many copies are owned / in the deck. Hover a card for its full rules.

const CARD_SCALE := 0.62

var _vendor: VendorData
var _sell_mode: bool = false
var _buy_tab: Button
var _sell_tab: Button
var _grid: GridContainer
var _message: Label


## Opens the shop of a vendor on the Buy tab.
func open_for(vendor: VendorData) -> void:
	_vendor = vendor
	_sell_mode = false
	open()
	_build_layout()
	title_label.text = vendor.name
	_rebuild()


func _build_layout() -> void:
	if _grid != null:
		return
	_buy_tab = make_button("Buy")
	_buy_tab.pressed.connect(func() -> void: _set_mode(false))
	_sell_tab = make_button("Sell")
	_sell_tab.pressed.connect(func() -> void: _set_mode(true))
	header_buttons.add_child(_buy_tab)
	header_buttons.add_child(_sell_tab)

	_message = Label.new()
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message.add_theme_font_override("font", VfxAssets.get_card_text_font())
	_message.add_theme_font_size_override("font_size", 15)
	_message.add_theme_color_override("font_color", HudStyle.TEXT_LIGHT)
	body.add_child(_message)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 470)
	body.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 8
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)


func _set_mode(sell: bool) -> void:
	Sfx.play(SfxId.BUTTON_CLICK)
	_sell_mode = sell
	_rebuild()


func _rebuild() -> void:
	refresh_gold()
	_buy_tab.disabled = not _sell_mode
	_sell_tab.disabled = _sell_mode
	if _sell_mode:
		subtitle_label.text = "Sell cards you don't need."
		_message.text = "Selling a card used in your deck removes it from the deck."
	else:
		subtitle_label.text = _vendor.title if _vendor != null else ""
		_message.text = _vendor.greeting if _vendor != null else ""
	card_info.hide_panel()
	clear_children(_grid)

	var cards: Array[CardData] = []
	if _sell_mode:
		cards.append_array(PlayerProfile.get_owned_cards())
	elif _vendor != null:
		for c: CardData in _vendor.stock:
			if c != null and not cards.has(c):
				cards.append(c)
	cards.sort_custom(func(a: CardData, b: CardData) -> bool: return DeckBuilderPanel.compare_cards(a, b) < 0)
	for card: CardData in cards:
		var slot := CardSlot.new()
		slot.setup(card, CARD_SCALE, true)
		_grid.add_child(slot)
		track_hover(slot)
		var owned: int = PlayerProfile.owned_count(card)
		if _sell_mode:
			slot.set_caption("Own %d · Deck %d" % [owned, PlayerProfile.in_deck_count(card)], HudStyle.TEXT_LIGHT)
			slot.set_button("Sell %dg" % CardEconomy.sell_price(card), true)
		else:
			var price: int = CardEconomy.buy_price(card)
			var affordable: bool = PlayerProfile.gold >= price
			var rarity_name: String = CardRarity.name_of(card.rarity)
			slot.set_caption(("%s · own %d" % [rarity_name, owned]) if owned > 0 else rarity_name,
				CardEconomy.rarity_color(card.rarity).lightened(0.35))
			slot.set_button("Buy %dg" % price, affordable)
			slot.set_highlight(affordable)
			slot.set_dimmed(not affordable)
		slot.activated.connect(_on_slot_activated)


func _on_slot_activated(slot: CardSlot) -> void:
	var card: CardData = slot.card
	var r: Dictionary = PlayerProfile.try_sell(card) if _sell_mode else PlayerProfile.try_buy(card)
	if not r["result"]:
		_message.text = r["error"]
		Sfx.play(SfxId.BLOCKED)
		return
	Sfx.play(SfxId.COIN)
	var text: String
	if _sell_mode:
		text = "Sold %s for %d gold." % [card.name, CardEconomy.sell_price(card)]
	else:
		text = "Bought %s! Add it to your deck in the deck builder (Tab)." % card.name
	var deferred := func() -> void:
		_rebuild()
		_message.text = text
	deferred.call_deferred()
