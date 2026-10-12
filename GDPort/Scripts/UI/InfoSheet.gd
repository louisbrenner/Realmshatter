class_name InfoSheet
extends RefCounted
## Structured content of a hover info panel (InfoPanel): a coloured header (title, type line, owner tag, AP cost),
## a row of stat chips with icons, rule rows with an emblem icon each (keywords, triggers, statuses, tile effects),
## and short coloured notes. Built by InfoText; texts may contain BBCode using the HEX_* colours below, which are
## tuned for the dark panel.

## Kind of a stat chip (decides its icon) (C# InfoSheet.StatKind).
enum { ATTACK = 0, HEALTH = 1, SHIELD = 2, MOVE = 3, RANGE = 4, AP = 5, TURNS = 6 }
const STAT_KIND_NAMES := { ATTACK: "Attack", HEALTH: "Health", SHIELD: "Shield", MOVE: "Move", RANGE: "Range", AP: "Ap", TURNS: "Turns" }


## One stat chip: icon kind, value text and value colour.
class Stat:
	extends RefCounted
	var kind: int
	var value: String
	var color: Color
	var tooltip: String

	func _init(p_kind: int = 0, p_value: String = "", p_color: Color = Color.WHITE, p_tooltip: String = "") -> void:
		kind = p_kind
		value = p_value
		color = p_color
		tooltip = p_tooltip

	func copy() -> Stat:
		return Stat.new(kind, value, color, tooltip)


## One rule row: emblem (glyph + colours), coloured title and a short BBCode text.
class Row:
	extends RefCounted
	var icon: int
	var icon_fg: Color
	var icon_bg: Color
	var title: String
	var title_color: Color
	var text: String

	func _init(p_icon: int = 0, p_icon_fg: Color = Color.WHITE, p_icon_bg: Color = Color.BLACK, p_title: String = "",
			p_title_color: Color = Color.WHITE, p_text: String = "") -> void:
		icon = p_icon
		icon_fg = p_icon_fg
		icon_bg = p_icon_bg
		title = p_title
		title_color = p_title_color
		text = p_text

	func copy() -> Row:
		return Row.new(icon, icon_fg, icon_bg, title, title_color, text)


const TEXT_COLOR := Color(1.0, 0.93, 0.8)
const MUTED_COLOR := Color(0.78, 0.66, 0.5)
const GOOD_COLOR := Color(0.55, 0.95, 0.45)
const BAD_COLOR := Color(1.0, 0.48, 0.4)
const HEADING_COLOR := Color(1.0, 0.8, 0.42)
const MAGIC_COLOR := Color(0.8, 0.62, 1.0)

static var HEX_MUTED: String = "#" + MUTED_COLOR.to_html(false)
static var HEX_GOOD: String = "#" + GOOD_COLOR.to_html(false)
static var HEX_BAD: String = "#" + BAD_COLOR.to_html(false)
static var HEX_HEADING: String = "#" + HEADING_COLOR.to_html(false)
static var HEX_MAGIC: String = "#" + MAGIC_COLOR.to_html(false)
static var HEX_MINE: String = "#" + HudStyle.PLAYER_BLUE.lightened(0.15).to_html(false)
static var HEX_ENEMY: String = "#" + HudStyle.ENEMY_RED.to_html(false)

var title: String = ""
## Colour of the title (enemy pieces: red).
var title_color: Color = TEXT_COLOR
## Muted line under the title (type, class, clan).
var subtitle: String = ""
## Small tag on the right of the header, e.g. "Yours" / "Enemy" / rarity.
var tag: String = ""
var tag_color: Color = HudStyle.GOLD
## Colour of the header strip (clan, owner or tile effect).
var accent: Color = HudStyle.GOLD_DARK
## AP cost shown as a mana gem in the header (-1 = none).
var ap_cost: int = -1
## Short italic card text.
var flavor: String = ""
var stats: Array[Stat] = []
## Free BBCode lines below the stats (spell effects, building rules, deck lists).
var lines: Array[String] = []
var rows: Array[Row] = []
## Short BBCode notes at the bottom (state of a piece, scoring, tile under it).
var notes: Array[String] = []

## True if the sheet has no content.
var is_empty: bool:
	get:
		return title.is_empty() and lines.size() == 0 and rows.size() == 0 and notes.size() == 0


## Equivalent of C# StatKind.ToString().
static func stat_kind_name(value: int) -> String:
	return STAT_KIND_NAMES.get(value, str(value))


## Content signature, used to skip rebuilding an identical panel.
func key() -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append(title + str(title_color) + "|" + subtitle + "|" + tag + "|" + str(accent) + "|"
		+ str(ap_cost) + "|" + flavor + "|")
	for s in stats:
		parts.append(stat_kind_name(s.kind) + s.value + str(s.color) + ";")
	for l in lines:
		parts.append(l + ";")
	for r in rows:
		parts.append(str(r.icon) + r.title + r.text + ";")
	for n in notes:
		parts.append(n + ";")
	return "".join(parts)
