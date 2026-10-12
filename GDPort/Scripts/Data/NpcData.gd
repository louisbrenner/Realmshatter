class_name NpcData
extends Resource
## A duelist in the town: clan, own deck, dialogue lines, rewards and where it stands.

## Unique id (used for the "defeated" flags in the save game).
@export var id: String = ""
@export var name: String = ""
## Rank shown under the name, e.g. "Clan Leader".
@export var title: String = ""
@export_enum("None", "Fire", "Healing", "Frost", "Storm", "Stone") var clan: int = Clan.NONE
@export var deck: DeckData
## Clan hall the duelist waits in (None = out in the town).
@export_enum("None", "Fire", "Healing", "Frost", "Storm", "Stone") var house: int = Clan.NONE
## Position in pixels: town coordinates, or room coordinates inside its House (HouseInterior).
@export var position: Vector2

@export_group("Dialogue")
@export_multiline var greeting: String = ""
## Said when the player wants to battle again after winning.
@export_multiline var rematch_line: String = ""
## Said after the NPC lost.
@export_multiline var defeat_line: String = ""
## Said after the NPC won.
@export_multiline var victory_line: String = ""

@export_group("Rewards")
## Gold for the first win (rematch wins pay half, losses a small consolation).
@export var reward_gold: int = 40
## Cards given on the FIRST win only.
@export var reward_cards: Array[CardData] = []
## On the first win, ONE of these (one the player does not own yet, picked at random) is given as well.
@export var reward_one_of: Array[CardData] = []

## Extra AP the duelist gets every turn in battle (the endboss plays its expensive legends).
@export_group("Battle")
@export var bonus_ap_per_turn: int = 0

## Ids of the duelists the player must have beaten before this one accepts a challenge (e.g. the endboss).
@export_group("Unlock")
@export var requires_defeated: Array[String] = []
## Said while the duelist is still locked.
@export_multiline var locked_line: String = ""
