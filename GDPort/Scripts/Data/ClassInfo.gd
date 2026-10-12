class_name ClassInfo
extends RefCounted
## Display names, rule-of-thumb descriptions and base stat lines of the unit classes.


## Display name of a class ("" for None).
static func display_name(unit_class: int) -> String:
	return "" if unit_class == UnitClass.NONE else UnitClass.name_of(unit_class)


## Short description of what the class is good at.
static func get_description(unit_class: int) -> String:
	match unit_class:
		UnitClass.SWORDSMAN: return "Sturdy melee fighter with a solid hit."
		UnitClass.ARCHER: return "Fragile, but shoots from 3 tiles away."
		UnitClass.GUARDIAN: return "Slow defender with a shield that soaks damage first."
		UnitClass.SCOUT: return "Very fast runner that grabs the zone early."
		UnitClass.LANCER: return "Mobile spearman with a hard thrust."
		UnitClass.MAGE: return "Slow caster that strikes from 2 tiles away."
		UnitClass.CLERIC: return "Mobile support that reaches 2 tiles."
		UnitClass.BRUTE: return "Heavy, slow bruiser with lots of HP."
		UnitClass.TOTEM: return "Immobile relay that never leaves its tile."
		UnitClass.WORKER: return "Barely fights, but brings extra AP every turn."
	return ""


## Display name of a card's class, falling back to its role for class-less units.
static func class_or_role(card: CardData) -> String:
	return display_name(card.class_) if card.class_ != UnitClass.NONE else UnitRole.name_of(card.role)


## "Archer · Burning, Arc" style line: class plus effects (keywords).
static func class_with_effects(card: CardData) -> String:
	var effects: String = KeywordInfo.format(card.keywords)
	var cls: String = class_or_role(card)
	return "%s · %s" % [cls, effects] if effects.length() > 0 else cls
