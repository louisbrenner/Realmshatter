class_name BattleSession
extends RefCounted
## Hand-over between the overworld and the battle scene: which NPC is challenged, where the player stood, and the
## result message shown back in town. Rewards: first win = NPC gold + reward cards, rematch win = half the gold,
## loss = a small consolation.

const BATTLE_SCENE := "res://Scenes/Main.tscn"
const OVERWORLD_SCENE := "res://Scenes/Overworld.tscn"
## Share of an NPC's gold reward the player loses on a defeat (at least MIN_LOSS_GOLD).
const LOSS_DIVISOR := 4
const MIN_LOSS_GOLD := 5

## The NPC being fought, or null outside a town battle.
static var opponent: NpcData = null

## Where the player stood before the battle (restored on return): Vector2 or null.
static var return_position: Variant = null

## Clan hall the player was in before the battle (Clan.NONE = the town).
static var return_house: int = Clan.NONE

## Message for the overworld after a battle (consumed once shown).
static var pending_message: String = ""

## The NPC of the last finished battle (for its after-battle line), or null.
static var last_opponent: NpcData = null

## True if the player won the last finished battle.
static var last_won: bool = false


## True while a town battle is pending / running.
static func get_is_active() -> bool:
	return opponent != null


## Starts a battle against the NPC (call change_scene_to_file(BATTLE_SCENE) afterwards).
static func begin(npc: NpcData, player_position: Vector2, house: int = Clan.NONE) -> void:
	opponent = npc
	return_position = player_position
	return_house = house


## The player's profile deck wrapped in a DeckData for the battle.
static func build_player_deck() -> DeckData:
	var deck := DeckData.new()
	deck.name = "Your Deck"
	for card: CardData in PlayerProfile.get_deck():
		deck.cards.append(card)
	return deck


## Text listing what a win against the NPC would give.
static func describe_reward(npc: NpcData) -> String:
	if npc == null:
		return ""
	var stake: String = " Defeat costs %d gold." % loss_gold(npc)
	if PlayerProfile.has_defeated(npc.id):
		return "Rematch reward: %d gold.%s" % [npc.reward_gold / 2, stake]
	var names: Array[String] = _counted_names(npc.reward_cards)
	if npc.reward_one_of.size() > 0:
		names.append("one Legendary card you do not own yet")
	if names.size() > 0:
		return "Reward: %d gold + %s.%s" % [npc.reward_gold, ", ".join(names), stake]
	return "Reward: %d gold.%s" % [npc.reward_gold, stake]


## Gold the player loses when this NPC wins: a quarter of its reward, at least MIN_LOSS_GOLD.
static func loss_gold(npc: NpcData) -> int:
	return 0 if npc == null else maxi(MIN_LOSS_GOLD, npc.reward_gold / LOSS_DIVISOR)


## "Ember Imp x2, Fireball" - card names with their copy counts, in list order.
static func _counted_names(cards: Array) -> Array[String]:
	var order: Array[String] = []
	var counts: Dictionary = {}
	for card: CardData in cards:
		if card == null:
			continue
		if not counts.has(card.name):
			order.append(card.name)
			counts[card.name] = 0
		counts[card.name] += 1
	var result: Array[String] = []
	for n: String in order:
		result.append("%s x%d" % [n, counts[n]] if counts[n] > 1 else n)
	return result


## A random card of the NPC's reward_one_of list that the player does not own yet (any, if all are owned).
static func _pick_one_of(npc: NpcData) -> CardData:
	var unowned: Array[CardData] = []
	var all: Array[CardData] = []
	for card: CardData in npc.reward_one_of:
		if card == null:
			continue
		all.append(card)
		if PlayerProfile.owned_count(card) == 0:
			unowned.append(card)
	var pool: Array[CardData] = unowned if unowned.size() > 0 else all
	if pool.size() > 0:
		return pool[randi() % pool.size()]
	return null


## True if the player has beaten every duelist the NPC requires (a clan leader waits for the three duelists of
## its hall, the endboss for the clan leaders). Returns {"result": bool, "beaten": int, "needed": int}.
static func is_unlocked(npc: NpcData) -> Dictionary:
	var beaten: int = 0
	var needed: int = npc.requires_defeated.size() if npc != null else 0
	if npc == null:
		return {"result": false, "beaten": beaten, "needed": needed}
	for id: String in npc.requires_defeated:
		beaten += 1 if PlayerProfile.has_defeated(id) else 0
	return {"result": beaten >= needed, "beaten": beaten, "needed": needed}


## Applies the result to the profile, clears the session and returns the summary text.
static func complete(won: bool) -> String:
	var npc: NpcData = opponent
	opponent = null
	if npc == null:
		return ""
	last_opponent = npc
	last_won = won
	var text: String
	if won:
		var first: bool = not PlayerProfile.has_defeated(npc.id)
		var gold: int = npc.reward_gold if first else npc.reward_gold / 2
		PlayerProfile.add_gold(gold)
		var gained: Array[CardData] = []
		var unlock: String = ""
		if first:
			# reward_cards may list a card several times: one copy per entry.
			for card: CardData in npc.reward_cards:
				if card != null:
					PlayerProfile.add_card(card)
					gained.append(card)
			var pick: CardData = _pick_one_of(npc)
			if pick != null:
				PlayerProfile.add_card(pick)
				gained.append(pick)
			PlayerProfile.mark_defeated(npc.id)
			if npc.clan != Clan.NONE and npc.id.begins_with(ShopUnlocks.id_prefix(npc.clan)):
				if ShopUnlocks.leader_defeated(npc.clan):
					unlock = " Every %s card is now sold in the shops!" % ClanInfo.display_name(npc.clan)
				else:
					unlock = " New %s cards are now sold in the shops." % ClanInfo.display_name(npc.clan)
		var tail: String = (", new cards: %s." % ", ".join(_counted_names(gained))) if gained.size() > 0 else "."
		text = ("You beat %s! +%d gold" % [npc.name, gold]) + tail + unlock
	else:
		var loss: int = mini(loss_gold(npc), PlayerProfile.gold)
		PlayerProfile.add_gold(-loss)
		text = ("%s won and takes %d gold from you." % [npc.name, loss]) if loss > 0 \
			else "%s won - luckily your purse was already empty." % npc.name
	pending_message = text
	return text
