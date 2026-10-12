class_name KeywordVisuals
extends RefCounted
## Emblem glyph and colors per keyword, shared by the piece tokens (PieceView) and the cards (CardView):
## flame = Burning, snowflake = Frost, fist = Push, spear = Pierce, cross = Mending, bolt = Arc,
## bell = Echo, skull = Undying, hammer = Builder, sun = Aura, stake = Planted, gem = Plunder, jaws = Trapper.


## Glyph of the keyword emblem (FxIconShape value).
static func get_shape(keyword: int) -> int:
	match keyword:
		Keyword.BURNING: return FxIconShape.FLAME
		Keyword.FROST: return FxIconShape.SNOWFLAKE
		Keyword.PUSH: return FxIconShape.FIST
		Keyword.PIERCE: return FxIconShape.SPEAR
		Keyword.MENDING: return FxIconShape.PLUS
		Keyword.ARC: return FxIconShape.BOLT
		Keyword.ECHO: return FxIconShape.BELL
		Keyword.UNDYING: return FxIconShape.SKULL
		Keyword.BUILDER: return FxIconShape.HAMMER
		Keyword.AURA: return FxIconShape.SUN
		Keyword.PLANTED: return FxIconShape.STAKE
		Keyword.PLUNDER: return FxIconShape.GEM
		Keyword.TRAPPER: return FxIconShape.TRAP
	return FxIconShape.PLUS


## Every emblem a card shows, in order: its keywords, then the first-hit burst and the deathrattle tombstone.
## Each entry is {"shape": int (FxIconShape), "fg": Color, "bg": Color}. first_hit_used drops the
## first-hit burst (a piece token whose first-hit effect already fired).
static func icons_for(card: CardData, first_hit_used: bool = false) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	if card == null:
		return list
	for k: int in KeywordInfo.split(card.keywords):
		var fg: Color = get_foreground(k)
		var bg: Color = get_background(k)
		if k == Keyword.AURA:
			fg = ClanInfo.get_color(card.clan).lightened(0.35)
			bg = ClanInfo.get_color(card.clan).darkened(0.65)
		list.append({"shape": get_shape(k), "fg": fg, "bg": bg})
	if card.on_first_hit != FirstHitType.NONE and not first_hit_used:
		list.append({"shape": FxIconShape.BURST, "fg": Color(1.0, 0.82, 0.45), "bg": Color(0.45, 0.16, 0.08, 0.97)})
	if card.legend != LegendEffect.NONE:
		list.append({"shape": LegendInfo.get_shape(card.legend), "fg": LegendInfo.get_color(card.legend), "bg": LegendInfo.EMBLEM_BACKGROUND})
	if card.deathrattle != DeathrattleType.NONE:
		list.append({"shape": FxIconShape.TOMB, "fg": Color(0.85, 0.85, 0.95), "bg": Color(0.18, 0.16, 0.26, 0.97)})
	return list


## Glyph color of the keyword emblem.
static func get_foreground(keyword: int) -> Color:
	match keyword:
		Keyword.BURNING: return Color(1.0, 0.45, 0.08)
		Keyword.FROST: return Color(0.88, 0.97, 1.0)
		Keyword.PUSH: return Color(1.0, 0.86, 0.66)
		Keyword.PIERCE: return Color(0.92, 0.95, 1.0)
		Keyword.MENDING: return Color(0.55, 1.0, 0.55)
		Keyword.ARC: return Color(1.0, 0.93, 0.4)
		Keyword.ECHO: return Color(1.0, 0.83, 0.42)
		Keyword.UNDYING: return Color(0.86, 1.0, 0.94)
		Keyword.BUILDER: return Color(0.95, 0.85, 0.65)
		Keyword.AURA: return Color(1.0, 0.92, 0.55)
		Keyword.PLANTED: return Color(0.78, 1.0, 0.62)
		Keyword.PLUNDER: return Color(0.6, 0.88, 1.0)
		Keyword.TRAPPER: return Color(0.9, 0.86, 0.78)
	return Color.WHITE


## Coin (background) color of the keyword emblem.
static func get_background(keyword: int) -> Color:
	match keyword:
		Keyword.BURNING: return Color(0.42, 0.08, 0.03, 0.97)
		Keyword.FROST: return Color(0.14, 0.38, 0.72, 0.97)
		Keyword.PUSH: return Color(0.45, 0.26, 0.12, 0.97)
		Keyword.PIERCE: return Color(0.28, 0.33, 0.42, 0.97)
		Keyword.MENDING: return Color(0.1, 0.38, 0.14, 0.97)
		Keyword.ARC: return Color(0.42, 0.3, 0.04, 0.97)
		Keyword.ECHO: return Color(0.46, 0.22, 0.08, 0.97)
		Keyword.UNDYING: return Color(0.16, 0.3, 0.3, 0.97)
		Keyword.BUILDER: return Color(0.36, 0.24, 0.14, 0.97)
		Keyword.AURA: return Color(0.4, 0.32, 0.08, 0.97)
		Keyword.PLANTED: return Color(0.2, 0.32, 0.12, 0.97)
		Keyword.PLUNDER: return Color(0.08, 0.22, 0.5, 0.97)
		Keyword.TRAPPER: return Color(0.26, 0.22, 0.18, 0.97)
	return Color(0.2, 0.2, 0.2, 0.97)
