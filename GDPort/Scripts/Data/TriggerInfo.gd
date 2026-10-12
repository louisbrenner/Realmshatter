class_name TriggerInfo
extends RefCounted
## Display names and rule texts of deathrattles and first-hit effects (cards, tooltips, log).
## NOTE: the C# overloads GetName/Describe(FirstHitType, ...) are ported as get_first_hit_name / describe_first_hit
## (both enums are ints in GDScript); get_name / describe take a DeathrattleType.


## Display name of a deathrattle.
static func display_name(type: int) -> String:
	match type:
		DeathrattleType.EXPLODE: return "Explode"
		DeathrattleType.SHOCKWAVE: return "Shockwave"
		DeathrattleType.LAVA_POOL: return "Lava Pool"
		DeathrattleType.HEAL_ALLIES: return "Last Blessing"
		DeathrattleType.RAISE_WALLS: return "Landslide"
		DeathrattleType.DRAW_CARD: return "Last Word"
		DeathrattleType.FROST_NOVA: return "Frost Nova"
		DeathrattleType.TRIBUTE: return "Tribute"
	return ""


## The standard deathrattle of a clan (special cards may differ).
static func clan_deathrattle(clan: int) -> int:
	match clan:
		Clan.FIRE: return DeathrattleType.LAVA_POOL
		Clan.HEALING: return DeathrattleType.HEAL_ALLIES
		Clan.FROST: return DeathrattleType.FROST_NOVA
		Clan.STORM: return DeathrattleType.EXPLODE
		Clan.STONE: return DeathrattleType.RAISE_WALLS
	return DeathrattleType.NONE


## The standard first-hit effect of a class (special cards may differ).
static func class_first_hit(unit_class: int) -> int:
	match unit_class:
		UnitClass.SWORDSMAN: return FirstHitType.ENRAGE
		UnitClass.GUARDIAN: return FirstHitType.HARDEN
		UnitClass.BRUTE: return FirstHitType.SHOCKWAVE
		UnitClass.ARCHER: return FirstHitType.REPEL
		UnitClass.MAGE: return FirstHitType.REPEL
		UnitClass.LANCER: return FirstHitType.THORNS
	return FirstHitType.NONE


## Name of a clan's aura.
static func aura_name(clan: int) -> String:
	match clan:
		Clan.FIRE: return "Heat Aura"
		Clan.HEALING: return "Mending Aura"
		Clan.FROST: return "Chill Aura"
		Clan.STORM: return "Static Aura"
		Clan.STONE: return "Bulwark Aura"
	return "Aura"


## What a clan's aura does at the owner's turn start on the 8 surrounding tiles.
static func aura_text(clan: int) -> String:
	match clan:
		Clan.FIRE: return "deals 1 damage to every adjacent enemy."
		Clan.HEALING: return "heals every adjacent ally by 1."
		Clan.FROST: return "freezes every adjacent enemy."
		Clan.STORM: return "gives every adjacent ally +1 Attack this turn."
		Clan.STONE: return "gives every adjacent ally +1 Shield (up to 2)."
	return "has no effect."


## Display name of a first-hit effect (C# overload GetName(FirstHitType)).
static func get_first_hit_name(type: int) -> String:
	match type:
		FirstHitType.THORNS: return "Thorns"
		FirstHitType.REPEL: return "Repel"
		FirstHitType.HARDEN: return "Harden"
		FirstHitType.ENRAGE: return "Enrage"
		FirstHitType.SHOCKWAVE: return "Shockwave"
	return ""


## Rule text of a deathrattle with its strength.
static func describe(type: int, amount: int) -> String:
	match type:
		DeathrattleType.EXPLODE: return "deals %d damage to every piece next to it - friend or foe." % amount
		DeathrattleType.SHOCKWAVE: return "pushes every piece next to it 1 tile away."
		DeathrattleType.LAVA_POOL: return "its tile and the tiles next to it turn into Lava."
		DeathrattleType.HEAL_ALLIES: return "heals your pieces within 2 tiles by %d HP." % amount
		DeathrattleType.RAISE_WALLS: return "raises Walls on the free tiles next to it."
		DeathrattleType.DRAW_CARD:
			return "you draw a card from your deck." if amount == 1 else "you draw %d cards from your deck." % amount
		DeathrattleType.FROST_NOVA: return "every enemy next to it is Frozen."
		DeathrattleType.TRIBUTE: return "you gain %d AP at the start of your next turn." % amount
	return ""


## Rule text of a first-hit effect with its strength (C# overload Describe(FirstHitType, int)).
static func describe_first_hit(type: int, amount: int) -> String:
	match type:
		FirstHitType.THORNS: return "the attacker takes %d damage." % amount
		FirstHitType.REPEL: return "the attacker is pushed 1 tile away."
		FirstHitType.HARDEN: return "it gains %d Shield." % amount
		FirstHitType.ENRAGE: return "it gains +%d Attack for the rest of the game." % amount
		FirstHitType.SHOCKWAVE: return "it pushes every piece next to it 1 tile away."
	return ""


## Short card-face lines, e.g. "Deathrattle: Explode 2" / "First hit: Thorns 1".
static func card_face_lines(card: CardData) -> Array[String]:
	var lines: Array[String] = []
	if card == null or card.card_type != CardType.UNIT:
		return lines
	if card.has_keyword(Keyword.BUILDER) and BuildingInfo.for_class(card.class_) != BuildingType.NONE:
		lines.append("Builds: %s" % BuildingInfo.display_name(BuildingInfo.for_class(card.class_)))
	if card.has_keyword(Keyword.AURA):
		lines.append("Aura: %s" % aura_name(card.clan))
	if card.on_first_hit != FirstHitType.NONE:
		lines.append("First hit: %s%s" % [get_first_hit_name(card.on_first_hit), _amount_suffix_first_hit(card.on_first_hit, card.on_first_hit_amount)])
	if card.deathrattle != DeathrattleType.NONE:
		lines.append("Deathrattle: %s%s" % [display_name(card.deathrattle), _amount_suffix_deathrattle(card.deathrattle, card.deathrattle_amount)])
	return lines


static func _amount_suffix_deathrattle(type: int, amount: int) -> String:
	if type == DeathrattleType.EXPLODE or type == DeathrattleType.HEAL_ALLIES or type == DeathrattleType.DRAW_CARD:
		return " %d" % amount
	return " +%d AP" % amount if type == DeathrattleType.TRIBUTE else ""


static func _amount_suffix_first_hit(type: int, amount: int) -> String:
	if type == FirstHitType.THORNS or type == FirstHitType.HARDEN or type == FirstHitType.ENRAGE:
		return " %d" % amount
	return ""
