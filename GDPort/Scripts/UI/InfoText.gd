class_name InfoText
extends RefCounted
## Builds the BBCode texts of the hover info panels (InfoPanel): full card rules, pieces on the board (stats,
## keywords, active spells, statuses, order), tile effects and deck lists. Colors are chosen for dark ink on
## the parchment panel.

const MUTED := "#6b4a2a"
const GOOD := "#2f7a22"
const BAD := "#a3261b"
const MINE := "#1f5fa8"
const ENEMY := "#b02a1e"
const HEADING := "#5a3208"
const FIRE := "#c0430c"
const HEAL := "#2f7a22"
const STONE := "#5d5246"
const MAGIC := "#6a35a8"


## Full rules of a card: type line, card text, stats and every keyword / effect explained.
static func card(card_data: CardData, ap_cost: int) -> String:
	if card_data == null:
		return ""
	var sb := ""
	sb += "[font_size=18][b]%s[/b][/font_size]\n" % _esc(card_data.name)
	var unit: bool = card_data.card_type == CardType.UNIT
	var type_text: String = ("%s unit" % UnitRole.name_of(card_data.role)) if unit else ("Area spell" if card_data.targets_tile else "Spell")
	sb += "[color=%s]%s  ·  %d AP[/color]\n" % [MUTED, type_text, ap_cost]
	if not card_data.description.strip_edges().is_empty():
		sb += "[i]%s[/i]\n" % _esc(card_data.description.strip_edges())

	if unit:
		sb += "\n[b]Attack[/b] %d   [b]HP[/b] %d   [b]Move[/b] %d   [b]Range[/b] %d" % [card_data.attack, card_data.hp, card_data.movement, card_data.range]
		if card_data.shield > 0:
			sb += "   [b]Shield[/b] %d" % card_data.shield
		sb += "\n"
		if card_data.ap_bonus != 0:
			sb += "[color=%s]%s AP at the start of each of your turns while alive.[/color]\n" % [GOOD, _signed(card_data.ap_bonus)]
	else:
		sb += "\n"
		for line: String in spell_effect_lines(card_data):
			sb += "• %s\n" % line

	sb += _append_keyword_rules(card_data.keywords, card_data.level)
	if not unit and card_data.tile_effect != TileEffectType.NONE:
		sb += "\n[b][color=%s]%s[/color][/b]: " % [_tile_color(card_data.tile_effect), KeywordInfo.get_tile_effect_name(card_data.tile_effect)] \
			+ KeywordInfo.get_tile_effect_description(card_data.tile_effect)
	if not unit and card_data.grant_status != StatusEffectType.NONE:
		sb += "\n[b][color=%s]%s[/color][/b]: " % [MAGIC, KeywordInfo.get_status_name(card_data.grant_status)] \
			+ KeywordInfo.get_status_description(card_data.grant_status)
	return sb.rstrip("\n")


## Everything about a piece on the board, seen by player 'viewer'.
static func piece(p: Piece, state: GameState, viewer: int) -> String:
	if p == null or state == null:
		return ""
	var sb := ""
	var mine: bool = p.owner_index == viewer
	sb += "[font_size=18][b]%s[/b][/font_size]  " % _esc(p.source.name if p.source != null else "Piece")
	sb += ("[color=%s]Yours[/color]\n" % MINE) if mine else ("[color=%s]Enemy[/color]\n" % ENEMY)
	sb += "[color=%s]%s unit[/color]\n\n" % [MUTED, UnitRole.name_of(p.role)]

	sb += "[b]HP[/b] %s/%s" % [_colored(p.current_hp, p.max_hp, true), _colored(p.max_hp, p.base_stats.hp)]
	if p.total_shield > 0:
		sb += "   [b]Shield[/b] %d" % p.total_shield
	sb += "\n[b]Attack[/b] %s   " % _colored(p.effective_attack, p.base_stats.attack) \
		+ "[b]Move[/b] %s   " % _colored(p.effective_movement, p.base_stats.movement) \
		+ "[b]Range[/b] %s\n" % _colored(p.effective_range, p.base_stats.range)
	if p.ap_bonus != 0:
		sb += "[color=%s]%s AP per turn for its owner.[/color]\n" % [GOOD, _signed(p.ap_bonus)]

	sb += _append_keyword_rules(p.keywords, p.source.level if p.source != null else 0)

	if p.active_spells.size() > 0:
		sb += "\n[b][color=%s]Active spells[/color][/b]" % HEADING
		for s: ActiveSpell in p.active_spells:
			var parts: Array[String] = []
			_add_delta(parts, s.effect.attack_delta, "Attack")
			_add_delta(parts, s.effect.hp_delta, "HP")
			if s.remaining_shield > 0:
				parts.append("%d Shield" % s.remaining_shield)
			_add_delta(parts, s.effect.movement_delta, "Move")
			_add_delta(parts, s.effect.range_delta, "Range")
			var effect: String = ", ".join(PackedStringArray(parts)) if parts.size() > 0 else "no stat change"
			var by: String = "your" if s.caster_index == viewer else "enemy"
			sb += "\n• [b]%s[/b] (%s): %s - %s" % [_esc(s.source.name if s.source != null else "Spell"), by, effect, _turns_left(s.expiry_turn, state.turn_number)]
		sb += "\n"

	if p.status_effects.size() > 0:
		sb += "\n[b][color=%s]Status[/color][/b]" % HEADING
		for s: StatusEffect in p.status_effects:
			var from_text: String = "" if s.source_name.is_empty() else " (from %s)" % _esc(s.source_name)
			sb += "\n• [b][color=%s]%s[/color][/b]%s: " % [MAGIC, KeywordInfo.get_status_name(s.type), from_text] \
				+ "%s - %s" % [KeywordInfo.get_status_description(s.type), _turns_left(s.expiry_turn, state.turn_number)]
		sb += "\n"

	var notes: Array[String] = []
	if p.is_summoning_sick(state.turn_number):
		notes.append("Summoning sick: can receive orders next turn.")
	if mine and p.order != null:
		notes.append(_describe_order(p, state))
	if state.board.is_in_scoring_zone(p.position):
		notes.append("[color=%s]In the scoring zone: +1 VP at the start of its owner's turn.[/color]" % GOOD)
	var tile_fx: TileEffect = state.board.get_tile_effect(p.position)
	if tile_fx != null:
		notes.append("Standing on [b][color=%s]%s[/color][/b] " % [_tile_color(tile_fx.type), KeywordInfo.get_tile_effect_name(tile_fx.type)]
			+ "(%s): %s" % [_turns_left(tile_fx.expiry_turn, state.turn_number), KeywordInfo.get_tile_effect_description(tile_fx.type)])
	if notes.size() > 0:
		sb += "\n"
		for n: String in notes:
			sb += "%s\n" % n
	return sb.rstrip("\n")


## Info about a tile effect on an (empty) tile, or "" if there is none.
static func tile(pos: Vector2i, state: GameState, viewer: int) -> String:
	var tile_fx: TileEffect = state.board.get_tile_effect(pos) if state != null else null
	if tile_fx == null:
		return ""
	var sb := ""
	sb += "[font_size=18][b][color=%s]%s[/color][/b][/font_size]\n" % [_tile_color(tile_fx.type), KeywordInfo.get_tile_effect_name(tile_fx.type)]
	var creator: String = "neutral" if tile_fx.creator_index < 0 else ("yours" if tile_fx.creator_index == viewer else "enemy")
	var source: String = "" if tile_fx.source_name.is_empty() else "%s, " % _esc(tile_fx.source_name)
	sb += "[color=%s]Tile effect (%s%s)[/color]\n\n" % [MUTED, source, creator]
	sb += KeywordInfo.get_tile_effect_description(tile_fx.type)
	sb += "\n[b]%s[/b]" % _turns_left(tile_fx.expiry_turn, state.turn_number)
	if state.board.is_in_scoring_zone(pos):
		sb += "\n\n[color=%s]Scoring zone tile.[/color]" % GOOD
	return sb


## Deck description and card list (units and spells with counts).
static func deck(deck_data: DeckData) -> String:
	if deck_data == null:
		return ""
	var sb := ""
	sb += "[font_size=18][b]%s[/b][/font_size]\n" % _esc(deck_data.name)
	# Entries are [CardData, count] pairs.
	var units: Array = []
	var spells: Array = []
	for c: CardData in deck_data.cards:
		if c == null:
			continue
		var list: Array = units if c.card_type == CardType.UNIT else spells
		var index: int = -1
		for i in range(list.size()):
			if list[i][0] == c:
				index = i
				break
		if index >= 0:
			list[index] = [c, int(list[index][1]) + 1]
		else:
			list.append([c, 1])
	sb += _append_card_list("Units", units)
	sb += _append_card_list("Spells", spells)
	return sb.rstrip("\n")


## Short spell effect lines (shared by the info panel and the card face).
static func spell_effect_lines(card_data: CardData) -> Array[String]:
	var lines: Array[String] = []
	if card_data.targets_tile:
		lines.append("Target: %s." % _area_text(card_data))
		if card_data.spell_damage > 0:
			lines.append("[color=%s]%d damage[/color] to every enemy there." % [BAD, card_data.spell_damage])
		if card_data.spell_heal > 0:
			lines.append("[color=%s]Heals %d HP[/color] to each of your pieces there." % [GOOD, card_data.spell_heal])
		if card_data.tile_effect != TileEffectType.NONE:
			var free: String = " free" if card_data.tile_effect == TileEffectType.WALL else ""
			lines.append("Turns the%s tiles into [color=%s]%s[/color] " % [free, _tile_color(card_data.tile_effect), KeywordInfo.get_tile_effect_name(card_data.tile_effect)]
				+ "for %d turns." % card_data.tile_effect_duration)
		return lines
	var parts: Array[String] = []
	_add_delta(parts, card_data.attack_delta, "Attack")
	_add_delta(parts, card_data.hp_delta, "HP")
	_add_delta(parts, card_data.shield_delta, "Shield")
	_add_delta(parts, card_data.movement_delta, "Move")
	_add_delta(parts, card_data.range_delta, "Range")
	lines.append("Target: any piece.")
	if parts.size() > 0:
		lines.append("%s until the end of your next turn." % ", ".join(PackedStringArray(parts)))
	if card_data.grant_status != StatusEffectType.NONE:
		lines.append("Makes it [color=%s]%s[/color]." % [MAGIC, KeywordInfo.get_status_name(card_data.grant_status)])
	return lines


static func _append_card_list(title: String, list: Array) -> String:
	if list.size() == 0:
		return ""
	var sb := ""
	var total: int = 0
	for entry: Array in list:
		total += int(entry[1])
	sb += "\n[b][color=%s]%s (%d)[/color][/b]\n" % [HEADING, title, total]
	for entry: Array in list:
		var c: CardData = entry[0]
		var count: int = entry[1]
		var keywords: String = (" [color=%s]- %s[/color]" % [MUTED, KeywordInfo.format(c.keywords)]) if c.keywords != Keyword.NONE else ""
		sb += "%dx %s%s\n" % [count, _esc(c.name), keywords]
	return sb


static func _append_keyword_rules(keywords: int, level: int) -> String:
	var list: Array = KeywordInfo.split(keywords)
	if list.size() == 0:
		return ""
	var sb := "\n"
	for k: int in list:
		var keyword_name: String = KeywordInfo.get_keyword_name(k)
		if k == Keyword.UNDYING and level > 0:
			keyword_name += " +%d" % level
		sb += "[b][color=%s]%s[/color][/b]: %s\n" % [HEADING, keyword_name, KeywordInfo.get_description(k)]
	return sb


static func _describe_order(p: Piece, state: GameState) -> String:
	var parts: Array[String] = []
	if p.order.move_target != null and p.order.move_target != p.position:
		parts.append("move to %s" % str(p.order.move_target))
	if p.order.attack_target != null:
		var target: Piece = state.board.get_piece_at(p.order.attack_target)
		if target != null and target.owner_index == p.owner_index and target != p:
			parts.append("chain via %s" % _esc(target.source.name if target.source != null else "piece"))
		else:
			parts.append("attack %s" % str(p.order.attack_target))
	var text: String = ", ".join(PackedStringArray(parts)) if parts.size() > 0 else "hold position"
	return "[color=%s]Order %d: %s.[/color]" % [MINE, p.order.order_index + 1, text]


static func _area_text(card_data: CardData) -> String:
	if card_data.spell_target == SpellTargetType.TILE:
		return "one tile"
	var shape: int = card_data.area_shape
	if shape == AreaShape.PLUS:
		return "a cross of 5 tiles"
	elif shape == AreaShape.ROW3:
		return "a row of 3 tiles"
	elif shape == AreaShape.COLUMN3:
		return "a column of 3 tiles"
	elif shape == AreaShape.SQUARE2:
		return "a 2x2 square"
	return "one tile"


static func _turns_left(expiry_turn: int, current_turn: int) -> String:
	var left: int = maxi(0, expiry_turn - current_turn + 1)
	return "ends this turn" if left <= 1 else "%d more turns" % left


static func _tile_color(effect_type: int) -> String:
	if effect_type == TileEffectType.LAVA:
		return FIRE
	elif effect_type == TileEffectType.HEALING:
		return HEAL
	elif effect_type == TileEffectType.WALL:
		return STONE
	return MAGIC


static func _colored(value: int, base_value: int, hp: bool = false) -> String:
	if hp:
		return ("[color=%s]%d[/color]" % [BAD, value]) if value < base_value else str(value)
	if value > base_value:
		return "[color=%s]%d[/color]" % [GOOD, value]
	return ("[color=%s]%d[/color]" % [BAD, value]) if value < base_value else str(value)


static func _add_delta(parts: Array[String], value: int, label: String) -> void:
	if value != 0:
		parts.append("[color=%s]%s %s[/color]" % [GOOD if value > 0 else BAD, _signed(value), label])


static func _signed(value: int) -> String:
	return "+%d" % value if value > 0 else str(value)


static func _esc(text: String) -> String:
	return text.replace("[", "[lb]")
