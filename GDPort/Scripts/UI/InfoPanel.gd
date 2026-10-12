class_name InfoPanel
extends PanelContainer
## Dark hover panel that renders an InfoSheet (built in code, never blocks the mouse): a header strip in the sheet's
## accent colour with title, type line, owner tag and AP gem, stat chips with the card badge icons, rule rows with
## keyword emblems and short coloured notes. It either follows the mouse cursor (board info) or sits beside a target
## control such as a hovered card, flipping sides and clamping so it always stays inside its parent. Fades in softly.

## Width of the content area in pixels (parent space).
@export var text_width: float = 250.0
## Font size of the rule texts (title and notes scale from it).
@export var font_size: int = 13

const CURSOR_OFFSET := 22.0
const GAP := 10.0
const MARGIN := 6.0
const ROW_ICON_SIZE := 22.0
const STAT_ICON_SIZE := 22.0

var _content: VBoxContainer
var _fade: Tween
var _target: Control
var _follow_cursor: bool = false
var _key: String = ""


func _ready() -> void:
	_ensure_built()


## Shows the sheet next to the mouse cursor and keeps following it.
func show_at_cursor(sheet: InfoSheet) -> void:
	_target = null
	_follow_cursor = true
	_show_sheet(sheet)


## Shows the sheet beside the target control (right side preferred) and tracks it while it moves.
func show_beside(target: Control, sheet: InfoSheet) -> void:
	_target = target
	_follow_cursor = false
	_show_sheet(sheet)


## Hides the panel.
func hide_panel() -> void:
	_target = null
	if _fade != null:
		_fade.kill()
	visible = false


func _process(_delta: float) -> void:
	if not visible:
		return
	if not _follow_cursor and (_target == null or not is_instance_valid(_target) or not _target.is_visible_in_tree()):
		hide_panel()
		return
	_place()


func _show_sheet(sheet: InfoSheet) -> void:
	_ensure_built()
	if sheet == null or sheet.is_empty:
		hide_panel()
		return
	var key: String = sheet.key()
	if key != _key:
		_key = key
		_rebuild(sheet)
	if not visible:
		visible = true
		modulate = Color(1.0, 1.0, 1.0, 0.0)
		if _fade != null:
			_fade.kill()
		_fade = create_tween()
		_fade.tween_property(self, "modulate:a", 1.0, 0.12)
	_place()


func _rebuild(sheet: InfoSheet) -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_content.add_child(_build_header(sheet))

	var body := MarginContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("margin_left", 9)
	body.add_theme_constant_override("margin_right", 9)
	body.add_theme_constant_override("margin_top", 2)
	body.add_theme_constant_override("margin_bottom", 8)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 5)
	body.add_child(column)

	if not sheet.flavor.strip_edges().is_empty():
		column.add_child(_rich("[i][color=%s]%s[/color][/i]" % [InfoSheet.HEX_MUTED, sheet.flavor], font_size - 1, text_width))
	if sheet.stats.size() > 0:
		var stats := HFlowContainer.new()
		stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stats.custom_minimum_size = Vector2(text_width, 0.0)
		stats.add_theme_constant_override("h_separation", 10)
		stats.add_theme_constant_override("v_separation", 2)
		for stat in sheet.stats:
			stats.add_child(_build_stat(stat))
		column.add_child(stats)
	for line in sheet.lines:
		column.add_child(_rich(line, font_size, text_width))
	if sheet.rows.size() > 0:
		column.add_child(_divider())
		for row in sheet.rows:
			column.add_child(_build_row(row))
	if sheet.notes.size() > 0:
		column.add_child(_divider())
		for note in sheet.notes:
			column.add_child(_rich("[color=%s]•[/color] %s" % [InfoSheet.HEX_MUTED, note], font_size - 1, text_width))
	_content.add_child(body)
	reset_size()


func _build_header(sheet: InfoSheet) -> Control:
	var header := PanelContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(sheet.accent.darkened(0.45), 0.95)
	style.border_color = sheet.accent.lightened(0.1)
	style.border_width_bottom = 2
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	header.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 7)
	header.add_child(row)

	if sheet.ap_cost >= 0:
		var gem: ColorRect = _badge(3, Color(0.22, 0.5, 1.0), 28.0)
		gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var cost := Label.new()
		cost.text = str(sheet.ap_cost)
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cost.set_anchors_preset(Control.PRESET_FULL_RECT)
		_style_label(cost, 16, Color.WHITE, 5, VfxAssets.get_card_font())
		gem.add_child(cost)
		row.add_child(gem)

	var titles := VBoxContainer.new()
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", -2)
	var title := Label.new()
	title.text = sheet.title
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_label(title, font_size + 5, sheet.title_color, 4, VfxAssets.get_card_font())
	titles.add_child(title)
	if not sheet.subtitle.is_empty():
		var subtitle := Label.new()
		subtitle.text = sheet.subtitle
		subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		subtitle.custom_minimum_size = Vector2(text_width - (90.0 if sheet.ap_cost >= 0 else 60.0), 0.0)
		_style_label(subtitle, font_size - 1, InfoSheet.MUTED_COLOR.lightened(0.15), 0, VfxAssets.get_card_text_font())
		titles.add_child(subtitle)
	row.add_child(titles)

	if not sheet.tag.is_empty():
		var tag := Label.new()
		tag.text = sheet.tag
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_style_label(tag, font_size - 1, sheet.tag_color, 3, VfxAssets.get_card_text_bold_font())
		row.add_child(tag)
	return header


func _build_stat(stat: InfoSheet.Stat) -> Control:
	var chip := HBoxContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.tooltip_text = stat.tooltip
	chip.add_theme_constant_override("separation", 3)
	var icon: ColorRect
	match stat.kind:
		InfoSheet.ATTACK:
			icon = _badge(0, Color(1.0, 0.78, 0.18), STAT_ICON_SIZE)
		InfoSheet.HEALTH:
			icon = _badge(1, Color(0.92, 0.13, 0.1), STAT_ICON_SIZE)
		InfoSheet.SHIELD:
			icon = _badge(2, Color(0.78, 0.8, 0.86), STAT_ICON_SIZE)
		InfoSheet.AP:
			icon = _badge(3, Color(0.22, 0.5, 1.0), STAT_ICON_SIZE)
		InfoSheet.MOVE:
			icon = _emblem(FxIconShape.CHEVRONS, Color(0.75, 1.0, 0.7), Color(0.14, 0.32, 0.16, 0.97), STAT_ICON_SIZE)
		InfoSheet.RANGE:
			icon = _emblem(FxIconShape.CROSSHAIR, Color(1.0, 0.88, 0.65), Color(0.38, 0.22, 0.1, 0.97), STAT_ICON_SIZE)
		_:
			icon = _emblem(FxIconShape.BELL, Color.WHITE, Color(0.25, 0.2, 0.15, 0.97), STAT_ICON_SIZE)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_child(icon)
	var value := Label.new()
	value.text = stat.value
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_style_label(value, font_size + 2, stat.color, 4, VfxAssets.get_card_font())
	chip.add_child(value)
	return chip


func _build_row(row: InfoSheet.Row) -> Control:
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 6)
	var icon: ColorRect = _emblem(row.icon, row.icon_fg, row.icon_bg, ROW_ICON_SIZE)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	line.add_child(icon)
	var head: String = "" if row.title.is_empty() else "[b][color=#%s]%s[/color][/b]  " % [row.title_color.to_html(false), row.title]
	line.add_child(_rich(head + row.text, font_size - 1, text_width - ROW_ICON_SIZE - 6.0))
	return line


func _rich(bbcode: String, p_size: int, width: float) -> RichTextLabel:
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.custom_minimum_size = Vector2(width, 0.0)
	text.text = bbcode
	text.add_theme_font_override("normal_font", VfxAssets.get_card_text_font())
	text.add_theme_font_override("bold_font", VfxAssets.get_card_text_bold_font())
	var italics := FontVariation.new()
	italics.base_font = VfxAssets.get_card_text_font()
	italics.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(0.2, 1.0), Vector2.ZERO)
	text.add_theme_font_override("italics_font", italics)
	text.add_theme_font_size_override("normal_font_size", p_size)
	text.add_theme_font_size_override("bold_font_size", p_size)
	text.add_theme_font_size_override("italics_font_size", p_size)
	text.add_theme_color_override("default_color", InfoSheet.TEXT_COLOR)
	text.add_theme_constant_override("outline_size", 0)
	text.add_theme_constant_override("line_separation", 0)
	return text


static func _divider() -> Control:
	var rect := ColorRect.new()
	rect.color = Color(HudStyle.GOLD_DARK, 0.45)
	rect.custom_minimum_size = Vector2(0.0, 1.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## Card face badge (card_badge.gdshader): 0 attack, 1 health, 2 shield, 3 mana gem.
static func _badge(shape: int, fill: Color, p_size: float) -> ColorRect:
	var rect := ColorRect.new()
	rect.custom_minimum_size = Vector2(p_size, p_size)
	rect.size = Vector2(p_size, p_size)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = VfxAssets.get_shader("card_badge")
	mat.set_shader_parameter("shape", shape)
	mat.set_shader_parameter("fill_color", fill)
	mat.set_shader_parameter("rect_size", Vector2(p_size, p_size))
	rect.material = mat
	return rect


## Round keyword emblem (keyword_icon.gdshader) with a glyph.
static func _emblem(shape: int, fg: Color, bg: Color, p_size: float) -> ColorRect:
	var rect := ColorRect.new()
	rect.custom_minimum_size = Vector2(p_size, p_size)
	rect.size = Vector2(p_size, p_size)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = VfxAssets.get_shader("keyword_icon")
	mat.set_shader_parameter("shape", shape)
	mat.set_shader_parameter("fg_color", fg)
	mat.set_shader_parameter("bg_color", bg)
	mat.set_shader_parameter("rim_color", Color(0.85, 0.66, 0.32))
	rect.material = mat
	return rect


static func _style_label(label: Label, p_size: int, color: Color, outline: int, font: Font) -> void:
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", p_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", HudStyle.OUTLINE)
	label.add_theme_constant_override("outline_size", outline)


func _place() -> void:
	var parent := get_parent() as Control
	if parent == null:
		return
	reset_size()
	var p_size: Vector2 = get_combined_minimum_size()
	var bounds: Vector2 = parent.size
	var pos: Vector2
	if _follow_cursor:
		var mouse: Vector2 = parent.get_local_mouse_position()
		pos = mouse + Vector2(CURSOR_OFFSET, CURSOR_OFFSET)
		if pos.x + p_size.x > bounds.x - MARGIN:
			pos.x = mouse.x - CURSOR_OFFSET - p_size.x
		if pos.y + p_size.y > bounds.y - MARGIN:
			pos.y = mouse.y - CURSOR_OFFSET * 0.5 - p_size.y
	else:
		var to_parent: Transform2D = parent.get_global_transform().affine_inverse()
		var global: Rect2 = _target.get_global_rect()
		var a: Vector2 = to_parent * global.position
		var b: Vector2 = to_parent * global.end
		var rect := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs())
		pos = Vector2(rect.end.x + GAP, rect.position.y + 8.0)
		if pos.x + p_size.x > bounds.x - MARGIN:
			pos.x = rect.position.x - GAP - p_size.x
	pos.x = clampf(pos.x, MARGIN, maxf(MARGIN, bounds.x - p_size.x - MARGIN))
	pos.y = clampf(pos.y, MARGIN, maxf(MARGIN, bounds.y - p_size.y - MARGIN))
	position = pos


func _ensure_built() -> void:
	if _content != null:
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	z_index = 50
	var style: StyleBoxFlat = HudStyle.box(Color(0.1, 0.065, 0.04, 0.96), HudStyle.GOLD_DARK, 8, 2, 12, 0.55)
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	add_theme_stylebox_override("panel", style)
	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_theme_constant_override("separation", 4)
	add_child(_content)
