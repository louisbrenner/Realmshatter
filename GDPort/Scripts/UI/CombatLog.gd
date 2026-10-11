class_name CombatLog
extends PanelContainer
## Collapsible combat log (root of the HUD's LogPanel): a header button toggles the body, lines are
## colored by who they are about (you = blue, AI = red, turn separators = gold). Keeps the last max_lines.

@export var max_lines: int = 40
@export var start_collapsed: bool = false

var _header: Button
var _body: RichTextLabel
var _lines: Array[String] = []
var _collapsed: bool = false
var _unread: int = 0

## True while only the header is shown.
var collapsed: bool:
	get:
		return _collapsed


func _ready() -> void:
	_header = get_node("VBox/Header") as Button
	_body = get_node("VBox/Body") as RichTextLabel
	_body.bbcode_enabled = true
	_body.scroll_following = true
	_body.text = ""
	_header.pressed.connect(func() -> void: set_collapsed(not _collapsed))
	add_theme_stylebox_override("panel", HudStyle.wood_panel(null, 8))
	var header_style: StyleBoxFlat = HudStyle.box(Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.0), 6, 0, 0)
	var header_hover: StyleBoxFlat = HudStyle.box(Color(1.0, 0.85, 0.5, 0.08), Color(0.0, 0.0, 0.0, 0.0), 6, 0, 0)
	_header.add_theme_stylebox_override("normal", header_style)
	_header.add_theme_stylebox_override("hover", header_hover)
	_header.add_theme_stylebox_override("pressed", header_hover)
	_header.add_theme_color_override("font_color", HudStyle.GOLD)
	_header.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.6))
	_header.add_theme_font_size_override("font_size", 15)
	_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_header.focus_mode = Control.FOCUS_NONE
	var body_style: StyleBoxFlat = HudStyle.box(Color(0.05, 0.03, 0.015, 0.55), Color(HudStyle.GOLD_DARK, 0.5), 6, 1, 0)
	body_style.set_content_margin_all(6)
	_body.add_theme_stylebox_override("normal", body_style)
	set_collapsed(start_collapsed)
	_rebuild()


## Appends a line (plain text; colored automatically).
func add_line(line: String) -> void:
	_lines.append(_format(line))
	while _lines.size() > max_lines:
		_lines.pop_front()
	if _collapsed:
		_unread += 1
		_update_header()
	_rebuild()


## Removes all lines.
func clear() -> void:
	_lines.clear()
	_unread = 0
	_rebuild()
	_update_header()


## Collapses (header only) or expands the log.
func set_collapsed(p_collapsed: bool) -> void:
	_collapsed = p_collapsed
	if _body == null:
		return
	_body.visible = not p_collapsed
	if not p_collapsed:
		_unread = 0
	_update_header()
	size = Vector2(size.x, 0.0)


func _update_header() -> void:
	if _header == null:
		return
	var arrow: String = "+" if _collapsed else "-"
	_header.text = ("%s  Combat Log  (%d new)" % [arrow, _unread]) if _collapsed and _unread > 0 else ("%s  Combat Log" % arrow)


func _rebuild() -> void:
	if _body == null:
		return
	_body.text = "[color=#a08c70][i]Nothing has happened yet.[/i][/color]" if _lines.size() == 0 else "\n".join(PackedStringArray(_lines))


static func _format(line: String) -> String:
	var text: String = line.replace("[", "[lb]")
	if line.begins_with("---"):
		return "[center][color=#f5c860]~ %s ~[/color][/center]" % _trim_dashes(text)
	var lower: String = line.to_lower()
	if lower.contains("wins"):
		return "[color=#ffd76a]%s[/color]" % text
	if lower.contains("scored"):
		return "[color=#f0d080]%s[/color]" % text
	if line.begins_with("You") or lower.begins_with("your "):
		return "[color=#8cc4ff]%s[/color]" % text
	if line.begins_with("AI"):
		return "[color=#ff9a8c]%s[/color]" % text
	if lower.contains("dies"):
		return "[color=#e0a0a0]%s[/color]" % text
	return "[color=#eadcc0]%s[/color]" % text


## Equivalent of C# Trim('-', ' ').
static func _trim_dashes(text: String) -> String:
	var start: int = 0
	var end: int = text.length()
	while start < end and (text[start] == "-" or text[start] == " "):
		start += 1
	while end > start and (text[end - 1] == "-" or text[end - 1] == " "):
		end -= 1
	return text.substr(start, end - start)
