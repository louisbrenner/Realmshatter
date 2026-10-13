class_name ShopUnlocks
extends RefCounted
## Which cards the vendors offer, based on the player's progress. Neutral 1-AP commons are always for sale, other
## neutral commons after NEUTRAL_COMMON_WINS wins and neutral rares after NEUTRAL_RARE_WINS wins. Clan cards unlock clan
## by clan: every clan card has a rank (rank), and beating a clan's duelists (Initiate, Apprentice, Adept, Champion -
## any order) raises that clan's progress by one each; beating the clan Leader unlocks every card of the clan, its
## Legendary included.

## Total wins (any NPC) before neutral commons of 2+ AP are sold.
const NEUTRAL_COMMON_WINS := 1
## Total wins (any NPC) before neutral Rare cards are sold.
const NEUTRAL_RARE_WINS := 3


## Unlock rank of a clan card: 0 = from the start (1-AP common units), 1 = the other commons, 2 = 1-AP rares and rare
## spells, 3 = 2-AP rare units, 4 = the expensive rares and the Epic, 5 = the Legendary (only after the Leader).
static func rank(card: CardData) -> int:
	var cost: int = card.ap_cost if card.ap_cost > 0 else 1
	var unit: bool = card.card_type == CardType.UNIT
	match card.rarity:
		CardRarity.COMMON:
			return 0 if unit and cost <= 1 else 1
		CardRarity.RARE:
			if cost <= 1 or not unit:
				return 2
			return 3 if cost == 2 else 4
		CardRarity.EPIC:
			return 4
	return 5


## NPC id prefix of a clan's duelists ("fire_", ...).
static func id_prefix(clan: int) -> String:
	return "" if clan == Clan.NONE else Clan.name_of(clan).to_lower() + "_"


## True once the clan's Leader has been beaten.
static func leader_defeated(clan: int) -> bool:
	return clan != Clan.NONE and PlayerProfile.has_defeated(id_prefix(clan) + "leader")


## Number of the clan's four duelists (not the Leader) the player has beaten.
static func clan_progress(clan: int) -> int:
	var n: int = 0
	for rank_name: String in ["initiate", "apprentice", "adept", "champion"]:
		n += 1 if PlayerProfile.has_defeated(id_prefix(clan) + rank_name) else 0
	return n


## True if the vendors currently sell this card.
static func is_available(card: CardData) -> bool:
	if card == null:
		return false
	if card.clan == Clan.NONE:
		var cost: int = card.ap_cost if card.ap_cost > 0 else 1
		if card.rarity == CardRarity.COMMON:
			return cost <= 1 or PlayerProfile.get_defeated_count() >= NEUTRAL_COMMON_WINS
		return PlayerProfile.get_defeated_count() >= NEUTRAL_RARE_WINS
	return leader_defeated(card.clan) or rank(card) <= clan_progress(card.clan)
