class_name InfoText
extends RefCounted
## Builds the InfoSheets of the hover info panels (InfoPanel): full card rules, pieces on the board (stats,
## keywords, active spells, statuses), tile effects and deck lists. Texts are kept short; icons and colours carry
## most of the information (see InfoSheet for the palette).

const TRIGGER_BG := Color(0.45, 0.16, 0.08, 0.97)
const DEATH_BG := Color(0.18, 0.16, 0.26, 0.97)
const BUILD_BG := Color(0.36, 0.24, 0.14, 0.97)
const BUFF_BG := Color(0.12, 0.36, 0.14, 0.97)
const DEBUFF_BG := Color(0.32, 0.12, 0.42, 0.97)



## Full rules of a card: type line, AP gem, card text, stat chips and every keyword / effect.
static func card(p_card: CardData, ap_cost: int) -> InfoSheet:
	var sheet := InfoSheet.new()
	if p_card == null:
		return sheet
	var unit: bool = p_card.card_type == CardType.UNIT
	sheet.title = p_card.name
	sheet.ap_cost = ap_cost
	sheet.subtitle = (ClassInfo.class_or_role(p_card) if unit else ("Area spell" if p_card.targets_tile else "Spell")) \
		+ ((" · %s" % ClanInfo.display_name(p_card.clan)) if p_card.clan != Clan.NONE else " · Basic")
	sheet.tag = CardRarity.name_of(p_card.rarity)
	sheet.tag_color = CardEconomy.rarity_color(p_card.rarity).lightened(0.2)
	sheet.accent = ClanInfo.get_color(p_card.clan) if p_card.clan != Clan.NONE else HudStyle.GOLD_DARK
	sheet.flavor = _esc(p_card.description.strip_edges())

	if unit:
		_add_unit_stats(sheet, p_card.attack, p_card.attack, p_card.hp, p_card.hp, p_card.hp, p_card.shield, p_card.movement, p_card.movement, p_card.range, p_card.range)
		if p_card.ap_bonus != 0:
			sheet.stats.append(InfoSheet.Stat.new(InfoSheet.AP, "%s/turn" % _signed(p_card.ap_bonus), InfoSheet.GOOD_COLOR, "AP for you at the start of each turn"))
	else:
		sheet.lines.append_array(spell_effect_lines(p_card))

	_add_keyword_rows(sheet, p_card, p_card.keywords, p_card.level)
	_add_legend_row(sheet, p_card)
	_add_trigger_rows(sheet, p_card, false)
	if not unit and p_card.tile_effect != TileEffectType.NONE:
		sheet.rows.append(_tile_row(p_card.tile_effect, ""))
	if not unit and p_card.grant_status != StatusEffectType.NONE:
		sheet.rows.append(_status_row(p_card.grant_status, ""))
	return sheet


## Everything about a piece on the board, seen by player 'viewer'.
static func piece(p: Piece, state: GameState, viewer: int) -> InfoSheet:
	var sheet := InfoSheet.new()
	if p == null or state == null:
		return sheet
	var mine: bool = p.owner_index == viewer
	sheet.title = p.source.name if p.source != null else "Piece"
	sheet.title_color = InfoSheet.TEXT_COLOR if mine else HudStyle.ENEMY_RED.lightened(0.1)
	sheet.tag = "Yours" if mine else "Enemy"
	sheet.tag_color = HudStyle.PLAYER_BLUE.lightened(0.2) if mine else HudStyle.ENEMY_RED
	# The header shows the card's clan (like the card tooltip); ownership is the tag and the title colour.
	var clan: int = p.source.clan if p.source != null else Clan.NONE
	sheet.accent = ClanInfo.get_color(clan) if clan != Clan.NONE else HudStyle.GOLD_DARK

	if p.is_building:
		sheet.subtitle = "Building"
		_add_health(sheet, p)
		sheet.lines.append(BuildingInfo.get_description(p.building))
		if p.under_construction:
			var left: int = maxi(1, (p.complete_turn - state.turn_number + 1) / 2)
			sheet.notes.append("[color=%s]Under construction[/color] - ready in %d turn%s. Collapses if its builder dies." % [InfoSheet.HEX_BAD, left, "s" if left > 1 else ""])
		return sheet

	sheet.subtitle = (ClassInfo.class_or_role(p.source) if p.source != null else UnitRole.name_of(p.role)) \
		+ ((" · %s" % ClanInfo.display_name(p.source.clan)) if p.source != null and p.source.clan != Clan.NONE else "")
	_add_unit_stats(sheet, p.effective_attack, p.base_stats.attack, p.current_hp, p.max_hp, p.base_stats.hp, p.total_shield,
		p.effective_movement, p.base_stats.movement, p.effective_range, p.base_stats.range)
	if p.ap_bonus != 0:
		sheet.stats.append(InfoSheet.Stat.new(InfoSheet.AP, "%s/turn" % _signed(p.ap_bonus), InfoSheet.GOOD_COLOR, "AP for its owner each turn"))

	_add_keyword_rows(sheet, p.source, p.keywords, p.source.level if p.source != null else 0)
	_add_legend_row(sheet, p.source)
	_add_trigger_rows(sheet, p.source, p.was_hit)
	if p.bonus_attack > 0:
		sheet.rows.append(InfoSheet.Row.new(FxIconShape.BURST, Color(1.0, 0.82, 0.45), TRIGGER_BG, "Enraged", InfoSheet.GOOD_COLOR,
			"+%d Attack for the rest of the game." % p.bonus_attack))
	for s: ActiveSpell in p.active_spells:
		var parts: Array[String] = []
		_add_delta(parts, s.effect.attack_delta, "Atk")
		_add_delta(parts, s.effect.hp_delta, "HP")
		if s.remaining_shield > 0:
			parts.append("[color=%s]%d Shield[/color]" % [InfoSheet.HEX_GOOD, s.remaining_shield])
		_add_delta(parts, s.effect.movement_delta, "Move")
		_add_delta(parts, s.effect.range_delta, "Range")
		var friendly: bool = s.caster_index == p.owner_index
		var effect: String = ", ".join(PackedStringArray(parts)) if parts.size() > 0 else "no stat change"
		sheet.rows.append(InfoSheet.Row.new(FxIconShape.PLUS if friendly else FxIconShape.CROSS,
			Color(0.6, 1.0, 0.55) if friendly else Color(0.9, 0.7, 1.0), BUFF_BG if friendly else DEBUFF_BG,
			_esc(s.source.name if s.source != null else "Spell"), InfoSheet.GOOD_COLOR if friendly else InfoSheet.MAGIC_COLOR,
			"%s [color=%s](%s)[/color]" % [effect, InfoSheet.HEX_MUTED, _turns_left(s.expiry_turn, state.turn_number)]))
	for s: StatusEffect in p.status_effects:
		sheet.rows.append(_status_row(s.type, " [color=%s](%s)[/color]" % [InfoSheet.HEX_MUTED, _turns_left(s.expiry_turn, state.turn_number)]))

	if p.is_summoning_sick(state.turn_number):
		sheet.notes.append("[color=%s]Summoning sick - acts next turn.[/color]" % InfoSheet.HEX_MUTED)
	elif mine and p.has_acted(state.turn_number):
		sheet.notes.append("[color=%s]Already acted this turn.[/color]" % InfoSheet.HEX_MINE)
	if p.constructing_id >= 0:
		sheet.notes.append("Busy building - cannot move and scores no VP until the building is finished.")
	if not p.can_score:
		if state.board.is_in_scoring_zone(p.position) and p.has_keyword(Keyword.PLANTED):
			sheet.notes.append("[color=%s]Planted - scores no VP here.[/color]" % InfoSheet.HEX_MUTED)
	elif state.board.is_in_hot_zone(p.position):
		sheet.notes.append("[color=%s]Crown field: +%d VP[/color] each owner's turn." % [InfoSheet.HEX_GOOD, state.board.hot_zone_points])
	elif state.board.is_in_scoring_zone(p.position):
		sheet.notes.append("[color=%s]Scoring zone: +1 VP[/color] each owner's turn." % InfoSheet.HEX_GOOD)
	if state.board.get_terrain(p.position) == TerrainType.WATER:
		sheet.notes.append("[color=%s]Wading[/color] - every water tile costs %d movement." % [InfoSheet.HEX_MINE, state.board.water_move_cost])
	var tile: TileEffect = state.board.get_tile_effect(p.position)
	if tile != null:
		sheet.notes.append("On [b][color=%s]%s[/color][/b] " % [_tile_hex(tile.type), KeywordInfo.get_tile_effect_name(tile.type)]
			+ "(%s): %s" % [_turns_left(tile.expiry_turn, state.turn_number), KeywordInfo.get_tile_effect_description(tile.type)])
	return sheet


## Info about a tile effect on an (empty) tile, the crown field, or an empty sheet.
static func tile(pos: Vector2i, state: GameState, viewer: int) -> InfoSheet:
	var sheet := InfoSheet.new()
	var trap: Trap = state.board.get_trap(pos) if state != null else null
	if trap != null and trap.owner_index == viewer:
		sheet.title = TrapInfo.display_name(trap.type)
		sheet.subtitle = "Your hidden trap"
		sheet.accent = TrapInfo.get_color(trap.type).darkened(0.35)
		sheet.rows.append(InfoSheet.Row.new(FxIconShape.TRAP, TrapInfo.get_color(trap.type), Color(0.12, 0.1, 0.08, 0.97),
			"Springs", InfoSheet.HEADING_COLOR, "An enemy stepping here is stopped and takes %s" % TrapInfo.describe(trap.type)))
		return sheet
	var tile_effect: TileEffect = state.board.get_tile_effect(pos) if state != null else null
	var terrain: int = state.board.get_terrain(pos) if state != null else TerrainType.NONE
	if tile_effect == null and terrain != TerrainType.NONE:
		_add_terrain(sheet, terrain, pos, state)
		return sheet
	if tile_effect == null:
		if state != null and state.board.is_in_hot_zone(pos):
			sheet.title = "Crown field"
			sheet.subtitle = "Centre of the scoring zone"
			sheet.accent = HudStyle.GOLD.darkened(0.2)
			sheet.rows.append(InfoSheet.Row.new(FxIconShape.SUN, Color(1.0, 0.92, 0.55), Color(0.4, 0.32, 0.08, 0.97),
				"+%d VP" % state.board.hot_zone_points, InfoSheet.GOOD_COLOR, "per piece here at the start of its owner's turn (1 VP elsewhere in the zone)."))
		return sheet
	sheet.title = KeywordInfo.get_tile_effect_name(tile_effect.type)
	var creator: String = "neutral" if tile_effect.creator_index < 0 else ("yours" if tile_effect.creator_index == viewer else "enemy")
	var source: String = "" if tile_effect.source_name.is_empty() else "%s · " % tile_effect.source_name
	sheet.subtitle = "Tile effect · %s%s" % [source, creator]
	sheet.tag = "Permanent" if tile_effect.is_permanent else _turns_left(tile_effect.expiry_turn, state.turn_number)
	sheet.tag_color = InfoSheet.MUTED_COLOR.lightened(0.2)
	sheet.accent = _tile_color(tile_effect.type)
	sheet.rows.append(_tile_row(tile_effect.type, ""))
	if state.board.is_in_scoring_zone(pos):
		sheet.notes.append("[color=%s]Scoring zone tile.[/color]" % InfoSheet.HEX_GOOD)
	return sheet


## Header and rule row of a terrain tile (water, bridge, rock).
static func _add_terrain(sheet: InfoSheet, terrain: int, pos: Vector2i, state: GameState) -> void:
	match terrain:
		TerrainType.WATER:
			sheet.title = "River"
			sheet.subtitle = "Terrain"
			sheet.accent = Color(0.2, 0.45, 0.65)
			sheet.rows.append(InfoSheet.Row.new(FxIconShape.CHEVRONS, Color(0.7, 0.9, 1.0), Color(0.1, 0.25, 0.45, 0.97),
				"Slow", Color(0.6, 0.85, 1.0), "Entering costs %d movement instead of 1." % state.board.water_move_cost))
		TerrainType.BRIDGE:
			sheet.title = "Bridge"
			sheet.subtitle = "Terrain"
			sheet.accent = Color(0.45, 0.3, 0.16)
			sheet.lines.append("Crosses the river at normal speed.")
		TerrainType.ROCK:
			sheet.title = "Rock wall"
			sheet.subtitle = "Terrain"
			sheet.tag = "%d/%d HP" % [state.board.get_terrain_hp(pos), state.config.rock_hp]
			sheet.tag_color = InfoSheet.BAD_COLOR
			sheet.accent = Color(0.45, 0.42, 0.38)
			sheet.rows.append(InfoSheet.Row.new(FxIconShape.BRICKS, Color(0.88, 0.82, 0.72), Color(0.3, 0.27, 0.24, 0.97),
				"Breakable", InfoSheet.HEADING_COLOR, "Blocks movement. Attack it (or hit it with damage spells) to break it."))
	if state.board.is_in_scoring_zone(pos):
		sheet.notes.append("[color=%s]Scoring zone tile.[/color]" % InfoSheet.HEX_GOOD)


## Deck description and card list (units and spells with counts).
static func deck(p_deck: DeckData) -> InfoSheet:
	var sheet := InfoSheet.new()
	if p_deck == null:
		return sheet
	sheet.title = p_deck.name
	sheet.subtitle = "%d cards" % p_deck.cards.size()
	sheet.accent = p_deck.accent_color
	# Entries are {"card": CardData, "count": int}.
	var units: Array[Dictionary] = []
	var spells: Array[Dictionary] = []
	for c: CardData in p_deck.cards:
		if c == null:
			continue
		var list: Array[Dictionary] = units if c.card_type == CardType.UNIT else spells
		var index: int = -1
		for i in range(list.size()):
			if list[i].card == c:
				index = i
				break
		if index >= 0:
			list[index] = {"card": c, "count": int(list[index].count) + 1}
		else:
			list.append({"card": c, "count": 1})
	_append_card_list(sheet, "Units", units)
	_append_card_list(sheet, "Spells", spells)
	return sheet


## Short spell effect lines (BBCode, dark-panel colours).
static func spell_effect_lines(p_card: CardData) -> Array[String]:
	var lines: Array[String] = []
	if p_card.targets_tile:
		var effects: Array[String] = []
		if p_card.spell_damage > 0:
			effects.append("[color=%s]%d damage[/color] to enemies" % [InfoSheet.HEX_BAD, p_card.spell_damage])
		if p_card.spell_heal > 0:
			effects.append("[color=%s]heals %d[/color] your pieces" % [InfoSheet.HEX_GOOD, p_card.spell_heal])
		if p_card.spell_push:
			effects.append("pushes every piece 1 tile outward")
		if p_card.tile_effect != TileEffectType.NONE:
			effects.append("leaves [color=%s]%s[/color] for %d turns" % [_tile_hex(p_card.tile_effect), KeywordInfo.get_tile_effect_name(p_card.tile_effect), p_card.tile_effect_duration])
		if p_card.ap_gain > 0:
			effects.append("[color=%s]you gain %d AP[/color]" % [InfoSheet.HEX_MINE, p_card.ap_gain])
		lines.append("[b]%s:[/b] %s." % [_capitalize(_area_text(p_card)), "; ".join(PackedStringArray(effects))])
		return lines
	var parts: Array[String] = []
	_add_delta(parts, p_card.attack_delta, "Attack")
	_add_delta(parts, p_card.hp_delta, "HP")
	_add_delta(parts, p_card.shield_delta, "Shield")
	_add_delta(parts, p_card.movement_delta, "Move")
	_add_delta(parts, p_card.range_delta, "Range")
	if parts.size() > 0:
		lines.append("[b]Any piece:[/b] %s until the end of your next turn." % ", ".join(PackedStringArray(parts)))
	elif p_card.ap_gain <= 0:
		lines.append("[b]Any piece.[/b]")
	if p_card.ap_gain > 0:
		lines.append("[color=%s]You gain %d AP.[/color]" % [InfoSheet.HEX_MINE, p_card.ap_gain])
	return lines


static func _add_unit_stats(sheet: InfoSheet, _atk: int, _base_atk: int, _hp: int, _max_hp: int, _base_hp: int, shield: int,
		move: int, base_move: int, p_range: int, base_range: int) -> void:
	# Attack and health are printed on the card / piece badges; the panel shows what they do not.
	if shield > 0:
		sheet.stats.append(InfoSheet.Stat.new(InfoSheet.SHIELD, str(shield), InfoSheet.TEXT_COLOR, "Shield (absorbs damage first)"))
	sheet.stats.append(InfoSheet.Stat.new(InfoSheet.MOVE, str(move), _stat_color(move, base_move), "Movement"))
	sheet.stats.append(InfoSheet.Stat.new(InfoSheet.RANGE, str(p_range), _stat_color(p_range, base_range), "Attack range"))


static func _add_health(sheet: InfoSheet, p: Piece) -> void:
	if p.total_shield > 0:
		sheet.stats.append(InfoSheet.Stat.new(InfoSheet.SHIELD, str(p.total_shield), InfoSheet.TEXT_COLOR, "Shield"))
	if p.effective_attack > 0:
		sheet.stats.append(InfoSheet.Stat.new(InfoSheet.RANGE, str(p.effective_range), InfoSheet.TEXT_COLOR, "Range"))


static func _add_keyword_rows(sheet: InfoSheet, p_card: CardData, keywords: int, level: int) -> void:
	for k: int in KeywordInfo.split(keywords):
		var kw_name: String = KeywordInfo.display_name(k)
		if k == Keyword.UNDYING and level > 0:
			kw_name += " +%d" % level
		var fg: Color = KeywordVisuals.get_foreground(k)
		var bg: Color = KeywordVisuals.get_background(k)
		if k == Keyword.AURA and p_card != null:
			fg = ClanInfo.get_color(p_card.clan).lightened(0.35)
			bg = ClanInfo.get_color(p_card.clan).darkened(0.65)
		var text: String = KeywordInfo.get_description(k)
		if k == Keyword.BUILDER and p_card != null:
			var b: int = BuildingInfo.for_class(p_card.class_)
			if b != BuildingType.NONE:
				text = "Builds a [b]%s[/b] next to it (%d AP, %d turn%s): " % [BuildingInfo.display_name(b), BuildingInfo.get_cost(b), BuildingInfo.get_build_turns(b), "s" if BuildingInfo.get_build_turns(b) > 1 else ""] \
					+ "%s [color=%s]Cannot move while building.[/color]" % [BuildingInfo.get_description(b), InfoSheet.HEX_MUTED]
		elif k == Keyword.TRAPPER and p_card != null:
			var trap: int = TrapInfo.for_clan(p_card.clan)
			text = "Instead of attacking (also after moving), hides a [b]%s[/b] on a free tile next to it " % TrapInfo.display_name(trap) \
				+ "(1 AP). An enemy stepping on it is stopped and takes %s " % TrapInfo.describe(trap) \
				+ "[color=%s]Hidden from the enemy, up to 2 at once.[/color]" % InfoSheet.HEX_MUTED
		elif k == Keyword.AURA and p_card != null:
			kw_name = TriggerInfo.aura_name(p_card.clan)
			text = "Each of your turns it %s" % TriggerInfo.aura_text(p_card.clan)
		sheet.rows.append(InfoSheet.Row.new(KeywordVisuals.get_shape(k), fg, bg, kw_name, fg.lerp(InfoSheet.HEADING_COLOR, 0.5), text))


static func _add_legend_row(sheet: InfoSheet, p_card: CardData) -> void:
	if p_card == null or p_card.legend == LegendEffect.NONE:
		return
	sheet.rows.append(InfoSheet.Row.new(LegendInfo.get_shape(p_card.legend), LegendInfo.get_color(p_card.legend), LegendInfo.EMBLEM_BACKGROUND,
		"Legendary: %s" % LegendInfo.display_name(p_card.legend), CardEconomy.rarity_color(CardRarity.LEGENDARY).lightened(0.2), LegendInfo.describe(p_card.legend)))


static func _add_trigger_rows(sheet: InfoSheet, p_card: CardData, first_hit_used: bool) -> void:
	if p_card == null or p_card.card_type != CardType.UNIT:
		return
	if p_card.on_first_hit != FirstHitType.NONE:
		var used: String = " [color=%s](used)[/color]" % InfoSheet.HEX_MUTED if first_hit_used else ""
		sheet.rows.append(InfoSheet.Row.new(FxIconShape.BURST, Color(1.0, 0.82, 0.45), TRIGGER_BG,
			"First hit: %s" % TriggerInfo.get_first_hit_name(p_card.on_first_hit), InfoSheet.HEADING_COLOR,
			"%s%s" % [_capitalize(TriggerInfo.describe_first_hit(p_card.on_first_hit, maxi(1, p_card.on_first_hit_amount))), used]))
	if p_card.deathrattle != DeathrattleType.NONE:
		sheet.rows.append(InfoSheet.Row.new(FxIconShape.TOMB, Color(0.85, 0.85, 0.95), DEATH_BG,
			"Deathrattle: %s" % TriggerInfo.display_name(p_card.deathrattle), Color(0.82, 0.8, 1.0),
			_capitalize(TriggerInfo.describe(p_card.deathrattle, maxi(1, p_card.deathrattle_amount)))))


static func _status_row(status: int, suffix: String) -> InfoSheet.Row:
	var frost: bool = status == StatusEffectType.FROZEN
	return InfoSheet.Row.new(FxIconShape.SNOWFLAKE if frost else FxIconShape.BOLT,
		Color(0.88, 0.97, 1.0) if frost else Color(1.0, 0.93, 0.4),
		Color(0.14, 0.38, 0.72, 0.97) if frost else Color(0.42, 0.3, 0.04, 0.97),
		KeywordInfo.get_status_name(status), InfoSheet.MAGIC_COLOR, KeywordInfo.get_status_description(status) + suffix)


static func _tile_row(type: int, suffix: String) -> InfoSheet.Row:
	var icon: int
	match type:
		TileEffectType.LAVA:
			icon = FxIconShape.FLAME
		TileEffectType.HEALING:
			icon = FxIconShape.PLUS
		TileEffectType.ICE:
			icon = FxIconShape.SNOWFLAKE
		TileEffectType.STORM:
			icon = FxIconShape.BOLT
		TileEffectType.MUD:
			icon = FxIconShape.CHEVRONS
		TileEffectType.WALL:
			icon = FxIconShape.BRICKS
		_:
			icon = FxIconShape.BRICKS
	var color: Color = _tile_color(type)
	return InfoSheet.Row.new(icon, color.lightened(0.35), Color(color.darkened(0.6), 0.97),
		KeywordInfo.get_tile_effect_name(type), color.lightened(0.25), KeywordInfo.get_tile_effect_description(type) + suffix)


static func _append_card_list(sheet: InfoSheet, title: String, list: Array[Dictionary]) -> void:
	if list.size() == 0:
		return
	var total: int = 0
	for e: Dictionary in list:
		total += int(e.count)
	var entries: Array[String] = []
	for e: Dictionary in list:
		var c: CardData = e.card
		entries.append("[color=%s]%dx[/color] %s" % [InfoSheet.HEX_HEADING, int(e.count), _esc(c.name)])
	sheet.lines.append("[b][color=%s]%s (%d)[/color][/b]\n%s" % [InfoSheet.HEX_HEADING, title, total, "\n".join(PackedStringArray(entries))])


static func _area_text(p_card: CardData) -> String:
	if p_card.spell_target == SpellTargetType.TILE:
		return "one tile"
	match p_card.area_shape:
		AreaShape.PLUS:
			return "cross of 5 tiles"
		AreaShape.ROW3:
			return "row of 3 tiles"
		AreaShape.COLUMN3:
			return "column of 3 tiles"
		AreaShape.SQUARE2:
			return "2x2 square"
		_:
			return "one tile"


static func _turns_left(expiry_turn: int, current_turn: int) -> String:
	if expiry_turn >= TileEffect.PERMANENT:
		return "permanent"
	var left: int = maxi(0, expiry_turn - current_turn + 1)
	return "ends this turn" if left <= 1 else "%d turns left" % left


static func _tile_color(type: int) -> Color:
	match type:
		TileEffectType.LAVA:
			return Color(0.95, 0.38, 0.1)
		TileEffectType.HEALING:
			return Color(0.35, 0.8, 0.3)
		TileEffectType.WALL:
			return Color(0.6, 0.55, 0.48)
		TileEffectType.ICE:
			return Color(0.55, 0.82, 1.0)
		TileEffectType.STORM:
			return Color(0.65, 0.45, 1.0)
		TileEffectType.MUD:
			return Color(0.55, 0.4, 0.22)
		_:
			return Color(0.55, 0.48, 0.42)


static func _tile_hex(type: int) -> String:
	return "#" + _tile_color(type).lightened(0.25).to_html(false)


static func _stat_color(value: int, base_value: int) -> Color:
	return InfoSheet.GOOD_COLOR if value > base_value else (InfoSheet.BAD_COLOR if value < base_value else InfoSheet.TEXT_COLOR)


static func _add_delta(parts: Array[String], value: int, label: String) -> void:
	if value != 0:
		parts.append("[color=%s]%s %s[/color]" % [InfoSheet.HEX_GOOD if value > 0 else InfoSheet.HEX_BAD, _signed(value), label])


static func _signed(value: int) -> String:
	return "+%d" % value if value > 0 else str(value)


static func _capitalize(text: String) -> String:
	return "" if text.is_empty() else text[0].to_upper() + text.substr(1)


static func _esc(text: String) -> String:
	return text.replace("[", "[lb]")

