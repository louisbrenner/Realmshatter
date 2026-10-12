class_name ClanInfo
extends RefCounted
## Display names, mottos and colours of the clans.


## Display name, e.g. "Ember Legion".
static func display_name(clan: int) -> String:
	match clan:
		Clan.FIRE: return "Ember Legion"
		Clan.HEALING: return "Dawn Covenant"
		Clan.FROST: return "Frostbound"
		Clan.STORM: return "Storm Circuit"
		Clan.STONE: return "Stone Bastion"
	return "Townsfolk"


## Main colour of the clan (roofs, banners, name plates).
static func get_color(clan: int) -> Color:
	match clan:
		Clan.FIRE: return Color(0.92, 0.38, 0.14)
		Clan.HEALING: return Color(0.98, 0.84, 0.4)
		Clan.FROST: return Color(0.5, 0.82, 1.0)
		Clan.STORM: return Color(0.62, 0.52, 1.0)
		Clan.STONE: return Color(0.66, 0.6, 0.5)
	return Color(0.75, 0.7, 0.62)
