class_name BattleSession
extends RefCounted
## Hand-over between the overworld and the battle scene: which NPC is challenged, where the player stood, and the
## result message shown back in town. Rewards: first win = NPC gold + reward cards, rematch win = half the gold,
## loss = a small consolation.

const BATTLE_SCENE := "res://Scenes/Main.tscn"
const OVERWORLD_SCENE := "res://Scenes/Overworld.tscn"
const CONSOLATION_GOLD := 10

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
	if PlayerProfile.has_defeated(npc.id):
		return "Rematch reward: %d gold." % (npc.reward_gold / 2)
	var names: Array[String] = []
	for card: CardData in npc.reward_cards:
		if card != null:
			names.append(card.name)
	if npc.reward_one_of.size() > 0:
		names.append("one Legendary card you do not own yet")
	if names.size() > 0:
		return "Reward: %d gold + %s." % [npc.reward_gold, ", ".join(names)]
	return "Reward: %d gold." % npc.reward_gold


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
		var cards: Array[String] = []
		if first:
			for card: CardData in npc.reward_cards:
				if card != null:
					PlayerProfile.add_card(card)
					cards.append(card.name)
			var pick: CardData = _pick_one_of(npc)
			if pick != null:
				PlayerProfile.add_card(pick)
				cards.append(pick.name)
			PlayerProfile.mark_defeated(npc.id)
		var tail: String = (", new cards: %s." % ", ".join(cards)) if cards.size() > 0 else "."
		text = ("You beat %s! +%d gold" % [npc.name, gold]) + tail
	else:
		PlayerProfile.add_gold(CONSOLATION_GOLD)
		text = "%s won this time. +%d gold for the effort." % [npc.name, CONSOLATION_GOLD]
	pending_message = text
	return text
