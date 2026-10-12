class_name PlayerProfile
extends RefCounted
## The player's persistent progress: gold, card collection (card resource path -> copies), the current deck
## (list of card paths) and the NPCs already defeated. Stored as JSON in user://. Static so it survives scene
## changes without an autoload. A new profile starts with the Starter Deck and STARTING_GOLD.

const SAVE_PATH := "user://realmshatter_profile.json"
const STARTER_DECK_PATH := "res://Resources/Decks/StarterDeck.tres"
const STARTING_GOLD := 120
const DECK_MIN := 25
const DECK_MAX := 40
const MAX_COPIES := 3
## Save format / balance version; older saves are discarded (e.g. after a card rebalance).
const SAVE_VERSION := 3

static var _owned: Dictionary = {}
static var _deck_paths: Array[String] = []
static var _defeated_ids: Dictionary = {}
static var _cache: Dictionary = {}
static var _loaded: bool = false

## Raised whenever gold, collection or deck change (replaces the C# static event Changed).
static var changed_listeners: Array[Callable] = []

## Current gold.
static var gold: int = 0


## Card path -> owned copies.
static func get_collection() -> Dictionary:
	ensure_loaded()
	return _owned


## Number of cards in the deck.
static func get_deck_count() -> int:
	ensure_loaded()
	return _deck_paths.size()


## True if the deck size is within DECK_MIN..DECK_MAX.
static func get_deck_is_valid() -> bool:
	return get_deck_count() >= DECK_MIN and get_deck_count() <= DECK_MAX


## Loads the save game once (or creates the starter profile).
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not _load():
		reset_to_starter()


## Discards all progress and starts over with the Starter Deck.
static func reset_to_starter() -> void:
	_loaded = true
	_owned.clear()
	_deck_paths.clear()
	_defeated_ids.clear()
	gold = STARTING_GOLD
	var starter: DeckData = load(STARTER_DECK_PATH) as DeckData
	if starter != null:
		for card: CardData in starter.cards:
			if card != null and not card.resource_path.is_empty():
				var n: int = _owned.get(card.resource_path, 0)
				_owned[card.resource_path] = n + 1
				_deck_paths.append(card.resource_path)
	save()


## Loads a card resource by path (cached).
static func get_card(path: String) -> CardData:
	if path.is_empty():
		return null
	if not _cache.has(path):
		var loaded: CardData = (load(path) as CardData) if ResourceLoader.exists(path) else null
		_cache[path] = loaded
	return _cache[path] as CardData


## Owned copies of a card.
static func owned_count(card: CardData) -> int:
	ensure_loaded()
	if card != null and _owned.has(card.resource_path):
		return int(_owned[card.resource_path])
	return 0


## Copies of a card in the deck.
static func in_deck_count(card: CardData) -> int:
	ensure_loaded()
	if card == null:
		return 0
	var n: int = 0
	for p: String in _deck_paths:
		n += 1 if p == card.resource_path else 0
	return n


## The deck as card resources (missing resources are skipped).
static func get_deck() -> Array[CardData]:
	ensure_loaded()
	var list: Array[CardData] = []
	for p: String in _deck_paths:
		var card: CardData = get_card(p)
		if card != null:
			list.append(card)
	return list


## All owned cards (one entry per card type), sorted by AP cost then name.
static func get_owned_cards() -> Array[CardData]:
	ensure_loaded()
	var list: Array[CardData] = []
	for p: String in _owned.keys():
		var card: CardData = get_card(p)
		if card != null and int(_owned[p]) > 0:
			list.append(card)
	list.sort_custom(func(a: CardData, b: CardData) -> bool:
		var ca: int = a.ap_cost if a.ap_cost > 0 else 1
		var cb: int = b.ap_cost if b.ap_cost > 0 else 1
		if ca != cb:
			return ca < cb
		return a.name < b.name
	)
	return list


## Adds a copy to the deck if one is owned and not yet used, the copy limit and DECK_MAX allow it.
## Returns {"result": bool, "error": String}.
static func try_add_to_deck(card: CardData) -> Dictionary:
	ensure_loaded()
	var in_deck: int = in_deck_count(card)
	if card == null or in_deck >= owned_count(card):
		return {"result": false, "error": "You have no more copies of this card."}
	if in_deck >= MAX_COPIES:
		return {"result": false, "error": "At most %d copies of a card per deck." % MAX_COPIES}
	if card.rarity == CardRarity.LEGENDARY and in_deck >= 1:
		return {"result": false, "error": "Only one copy of a Legendary card per deck."}
	if _deck_paths.size() >= DECK_MAX:
		return {"result": false, "error": "A deck holds at most %d cards." % DECK_MAX}
	_deck_paths.append(card.resource_path)
	_save_and_notify()
	return {"result": true, "error": ""}


## Removes one copy from the deck.
static func remove_from_deck(card: CardData) -> bool:
	ensure_loaded()
	if card == null or not _deck_paths.has(card.resource_path):
		return false
	_deck_paths.erase(card.resource_path)
	_save_and_notify()
	return true


## Adds owned copies (purchases, rewards).
static func add_card(card: CardData, copies: int = 1) -> void:
	ensure_loaded()
	if card == null or card.resource_path.is_empty() or copies <= 0:
		return
	var n: int = _owned.get(card.resource_path, 0)
	_owned[card.resource_path] = n + copies
	_save_and_notify()


## Buys a card for its buy price. Returns {"result": bool, "error": String}; result false if gold is short.
static func try_buy(card: CardData) -> Dictionary:
	ensure_loaded()
	var price: int = CardEconomy.buy_price(card)
	if gold < price:
		return {"result": false, "error": "Not enough gold (%d needed)." % price}
	gold -= price
	add_card(card)
	return {"result": true, "error": ""}


## Sells one copy for its sell price; a copy used in the deck is removed from it.
## Returns {"result": bool, "error": String}.
static func try_sell(card: CardData) -> Dictionary:
	ensure_loaded()
	var owned: int = owned_count(card)
	if owned <= 0:
		return {"result": false, "error": "You do not own this card."}
	_owned[card.resource_path] = owned - 1
	if owned - 1 <= 0:
		_owned.erase(card.resource_path)
	if in_deck_count(card) > owned - 1:
		_deck_paths.erase(card.resource_path)
	gold += CardEconomy.sell_price(card)
	_save_and_notify()
	return {"result": true, "error": ""}


## Adds (or with a negative amount removes) gold.
static func add_gold(amount: int) -> void:
	ensure_loaded()
	gold = maxi(0, gold + amount)
	_save_and_notify()


## True if the NPC was beaten at least once.
static func has_defeated(npc_id: String) -> bool:
	ensure_loaded()
	return not npc_id.is_empty() and _defeated_ids.has(npc_id)


## Marks an NPC as beaten.
static func mark_defeated(npc_id: String) -> void:
	ensure_loaded()
	if not npc_id.is_empty() and not _defeated_ids.has(npc_id):
		_defeated_ids[npc_id] = true
		_save_and_notify()


## Number of NPCs beaten.
static func get_defeated_count() -> int:
	ensure_loaded()
	return _defeated_ids.size()


## Writes the profile to user://.
static func save() -> void:
	var collection: Dictionary = {}
	for k: String in _owned.keys():
		collection[k] = int(_owned[k])
	var deck: Array = []
	for p: String in _deck_paths:
		deck.append(p)
	var defeated: Array = []
	for id: String in _defeated_ids.keys():
		defeated.append(id)
	var dto: Dictionary = {
		"Version": SAVE_VERSION,
		"Gold": gold,
		"Collection": collection,
		"Deck": deck,
		"Defeated": defeated,
	}
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(dto, "\t", false))
		file.close()


static func _load() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("PlayerProfile: could not read the save game (invalid JSON); starting fresh.")
		return false
	var dto: Dictionary = parsed
	var version: Variant = dto.get("Version", 0)
	if not (version is float or version is int) or int(version) != SAVE_VERSION:
		return false
	var saved_gold: Variant = dto.get("Gold", 0)
	gold = maxi(0, int(saved_gold) if (saved_gold is float or saved_gold is int) else 0)
	_owned.clear()
	var collection: Variant = dto.get("Collection", {})
	if collection is Dictionary:
		for key: Variant in (collection as Dictionary).keys():
			var value: Variant = collection[key]
			if not (value is float or value is int):
				continue
			var path: String = str(key)
			if int(value) > 0 and get_card(path) != null:
				_owned[path] = int(value)
	_deck_paths.clear()
	var deck: Variant = dto.get("Deck", [])
	if deck is Array:
		for p: Variant in deck:
			if p is String and get_card(p) != null:
				_deck_paths.append(p)
	_defeated_ids.clear()
	var defeated: Variant = dto.get("Defeated", [])
	if defeated is Array:
		for id: Variant in defeated:
			if id is String:
				_defeated_ids[id] = true
	return _owned.size() > 0


static func _save_and_notify() -> void:
	save()
	for cb: Callable in changed_listeners.duplicate():
		if cb.is_valid():
			cb.call()
