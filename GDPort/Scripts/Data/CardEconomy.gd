class_name CardEconomy
extends RefCounted
## Shop prices of cards (rarity, AP cost and effects) and the rarity colours.


## Gold a vendor asks for the card.
static func buy_price(card: CardData) -> int:
	if card == null:
		return 0
	var price: int = 25
	match card.rarity:
		CardRarity.LEGENDARY: price = 900
		CardRarity.EPIC: price = 160
		CardRarity.RARE: price = 60
	var cost: int = card.ap_cost if card.ap_cost > 0 else (1 if card.card_type == CardType.UNIT else 2)
	price += cost * 10
	price += KeywordInfo.split(card.keywords).size() * 5
	price += 10 if card.deathrattle != DeathrattleType.NONE else 0
	price += 10 if card.on_first_hit != FirstHitType.NONE else 0
	return price


## Gold a vendor pays for the card (40 % of its price).
static func sell_price(card: CardData) -> int:
	return 0 if card == null else maxi(5, buy_price(card) * 2 / 5)


## Colour of a rarity (type plate, labels).
static func rarity_color(rarity: int) -> Color:
	match rarity:
		CardRarity.LEGENDARY: return Color(1.0, 0.62, 0.15)
		CardRarity.EPIC: return Color(0.66, 0.34, 0.92)
		CardRarity.RARE: return Color(0.24, 0.5, 0.95)
	return Color(0.42, 0.36, 0.3)
