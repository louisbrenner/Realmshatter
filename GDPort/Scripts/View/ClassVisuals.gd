class_name ClassVisuals
extends RefCounted
## Picture subject of a card / piece until it has real artwork: one symbol (glyph of icon_glyphs.gdshaderinc) per
## unit class, building or spell effect. Shared by the card art (card_art.gdshader) and the piece token portraits
## (piece_portrait.gdshader), so a card and its piece always show the same symbol. -1 = generic role emblem.


## Glyph id for the card's picture, or -1 for the role emblem (Swordsman: crossed swords, Guardian: shield).
static func art_glyph(card: CardData) -> int:
	if card == null:
		return -1
	if card.card_type == CardType.BUILDING:
		match card.building:
			BuildingType.TURRET: return FxIconShape.BOW
			BuildingType.MANA_WELL: return FxIconShape.GEM
			BuildingType.SHRINE: return FxIconShape.PLUS
			BuildingType.BARRICADE: return FxIconShape.BRICKS
			BuildingType.OBELISK: return FxIconShape.BURST
		return -1
	if card.card_type == CardType.SPELL:
		if card.ap_gain > 0: return FxIconShape.GEM
		if card.grant_status == StatusEffectType.FROZEN: return FxIconShape.SNOWFLAKE
		if card.grant_status == StatusEffectType.OVERCHARGED: return FxIconShape.BOLT
		if card.tile_effect == TileEffectType.LAVA: return FxIconShape.FLAME
		if card.tile_effect == TileEffectType.WALL: return FxIconShape.BRICKS
		if card.tile_effect == TileEffectType.HEALING or card.spell_heal > 0: return FxIconShape.PLUS
		if card.spell_damage > 0: return FxIconShape.BURST
		if card.spell_push: return FxIconShape.FIST
		var net: int = card.attack_delta + card.hp_delta + card.shield_delta + card.movement_delta + card.range_delta
		return FxIconShape.SUN if net >= 0 else FxIconShape.SKULL
	match card.class_:
		UnitClass.ARCHER: return FxIconShape.BOW
		UnitClass.SCOUT: return FxIconShape.CHEVRONS
		UnitClass.LANCER: return FxIconShape.SPEAR
		UnitClass.MAGE: return FxIconShape.BURST
		UnitClass.CLERIC: return FxIconShape.PLUS
		UnitClass.BRUTE: return FxIconShape.FIST
		UnitClass.WORKER:
			return FxIconShape.GEM if card.ap_bonus > 0 else FxIconShape.HAMMER
		UnitClass.TOTEM:
			if card.ap_bonus > 0:
				return FxIconShape.GEM
			if card.has_keyword(Keyword.ARC):
				return FxIconShape.BOLT
			return FxIconShape.BURST if card.deathrattle == DeathrattleType.EXPLODE else FxIconShape.STAKE
	return -1
