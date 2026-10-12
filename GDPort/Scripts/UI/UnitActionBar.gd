class_name UnitActionBar
extends Control
## Floating row of round ability buttons beside the selected unit (e.g. Build). It follows the unit's screen
## position every frame (a provider returns the placement, null hides the bar) and docks as close to the unit as
## possible without covering any of the tiles the player is choosing from (its move or attack targets): it searches
## the 8 directions in growing rings and takes the nearest free spot on screen.
## Each button shows a glyph, an AP cost badge and a tooltip; unavailable abilities are greyed out with the reason as tooltip.


## One ability shown on the bar.
class Ability:
	var icon: int
	var label: String
	var cost: int
	var enabled: bool
	var tooltip: String
	var on_pressed: Callable

	func _init(p_icon: int = 0, p_label: String = "", p_cost: int = 0, p_enabled: bool = true,
			p_tooltip: String = "", p_on_pressed: Callable = Callable()) -> void:
		icon = p_icon
		label = p_label
		cost = p_cost
		enabled = p_enabled
		tooltip = p_tooltip
		on_pressed = p_on_pressed


## Where to dock, in viewport pixels: the unit's centre, half a tile's on-screen size (gap to the unit) and the
## screen points (tile centres) the bar should not cover.
class Placement:
	var center: Vector2
	var half_tile: float
	var avoid: Array[Vector2]

	func _init(p_center: Vector2 = Vector2.ZERO, p_half_tile: float = 0.0, p_avoid: Array[Vector2] = []) -> void:
		center = p_center
		half_tile = p_half_tile
		avoid = p_avoid


## Docking directions in order of preference: right, left, below, above, then the diagonals.
static var SIDES: Array[Vector2] = [
	Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
	Vector2(1, 1).normalized(), Vector2(-1, 1).normalized(), Vector2(1, -1).normalized(), Vector2(-1, -1).normalized(),
]

const BUTTON_SIZE := 46.0
const SPACING := 8.0

## Callable() -> Placement or null.
var _placement: Callable = Callable()
var _buttons: Array[Button] = []
var _appear: float = 0.0
var _side: int = -1
var _ring: int = -1

## How many rings (one tile apart) the search may move outward from the unit.
const MAX_RINGS := 12
## Width of the caption that hangs out on both sides of the buttons.
const CAPTION_OVERHANG := 20.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## Shows the abilities docked beside the unit described by 'placement' (a Callable returning a Placement or
## null; re-evaluated every frame).
func show_for(placement: Callable, abilities: Array) -> void:
	_clear()
	_placement = placement
	_side = -1
	_ring = -1
	if abilities.is_empty():
		visible = false
		return
	for ability in abilities:
		_buttons.append(_create_button(ability as Ability))
	size = Vector2(abilities.size() * BUTTON_SIZE + (abilities.size() - 1) * SPACING, BUTTON_SIZE + 18.0)
	_appear = 0.0
	visible = true
	_update_position()


## Hides the bar.
func hide_bar() -> void:
	_clear()
	visible = false
	_placement = Callable()


func _process(delta: float) -> void:
	if not visible:
		return
	_appear = minf(1.0, _appear + delta * 7.0)
	var s: float = 0.6 + 0.4 * sin(_appear * PI * 0.5)
	pivot_offset = size * 0.5
	scale = Vector2(s, s)
	modulate = Color(1, 1, 1, _appear)
	_update_position()


func _update_position() -> void:
	var placement: Placement = null
	if _placement.is_valid():
		placement = _placement.call() as Placement
	var parent := get_parent() as Control
	if placement == null or parent == null:
		visible = false
		return
	var to_local: Transform2D = parent.get_global_transform().affine_inverse()
	var center: Vector2 = to_local * placement.center
	var half_tile: float = placement.half_tile * to_local.get_scale().x
	var avoid: Array[Vector2] = []
	for p in placement.avoid:
		avoid.append(to_local * p)

	# Every candidate (8 directions x growing rings) is scored: covering any wanted tile is by far the worst,
	# then leaving the screen, then the distance from the unit, then the direction preference. The current spot
	# gets a small bonus so the bar does not flicker between equally good spots while the camera moves.
	var best_side: int = 0
	var best_ring: int = 0
	var best_score: float = INF
	for ring in range(MAX_RINGS):
		for i in range(SIDES.size()):
			var rect: Rect2 = _rect_for(center, SIDES[i], half_tile, ring)
			# The bar's full footprint (caption included), grown by a tile half: any overlap with a tile counts.
			var footprint: Rect2 = rect.grow(half_tile * 0.95).grow_individual(CAPTION_OVERHANG, 0.0, CAPTION_OVERHANG, 0.0)
			var covered: int = 0
			for p in avoid:
				if footprint.has_point(p):
					covered += 1
			var off_screen: bool = rect.position.x - CAPTION_OVERHANG < 0.0 or rect.position.y < 0.0 \
				or rect.end.x + CAPTION_OVERHANG > parent.size.x or rect.end.y > parent.size.y
			var score: float = covered * 1000.0 + (500.0 if off_screen else 0.0) + ring * 10.0 + i \
				- (4.0 if (i == _side and ring == _ring) else 0.0)
			if score < best_score:
				best_score = score
				best_side = i
				best_ring = ring
	_side = best_side
	_ring = best_ring
	position = _rect_for(center, SIDES[best_side], half_tile, best_ring).position


## Bar rectangle on the given side of the unit: one tile-half plus a small gap away from its centre, pushed
## 'ring' more tiles outward.
func _rect_for(center: Vector2, side: Vector2, half_tile: float, ring: int) -> Rect2:
	var half: Vector2 = size * 0.5
	var reach: float = half_tile * (1.15 + 2.0 * ring) + absf(side.x) * (half.x + CAPTION_OVERHANG) + absf(side.y) * half.y
	var c: Vector2 = center + side * reach
	return Rect2(c - half, size)


func _create_button(ability: Ability) -> Button:
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
	button.size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
	button.position = Vector2(_buttons.size() * (BUTTON_SIZE + SPACING), 0.0)
	button.tooltip_text = ability.tooltip
	button.disabled = not ability.enabled
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if ability.enabled else Control.CURSOR_ARROW
	var icon := ColorRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
	icon.material = _icon_material(ability)
	button.add_child(icon)
	if ability.cost > 0:
		var badge := Label.new()
		badge.text = str(ability.cost)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.position = Vector2(BUTTON_SIZE - 18.0, -4.0)
		badge.size = Vector2(22.0, 22.0)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_font_override("font", VfxAssets.get_card_text_bold_font())
		badge.add_theme_font_size_override("font_size", 14)
		badge.add_theme_color_override("font_color", Color.WHITE)
		badge.add_theme_color_override("font_outline_color", Color(0.02, 0.06, 0.2))
		badge.add_theme_constant_override("outline_size", 5)
		var gem := Panel.new()
		gem.position = badge.position
		gem.size = badge.size
		gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gem.add_theme_stylebox_override("panel", HudStyle.box(HudStyle.MANA_BLUE, HudStyle.MANA_LIGHT, 11, 2, 2))
		button.add_child(gem)
		button.add_child(badge)
	var caption := Label.new()
	caption.text = ability.label
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.position = Vector2(-20.0, BUTTON_SIZE - 2.0)
	caption.size = Vector2(BUTTON_SIZE + 40.0, 18.0)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_font_override("font", VfxAssets.get_card_text_bold_font())
	caption.add_theme_font_size_override("font_size", 12)
	caption.add_theme_color_override("font_color", HudStyle.TEXT_LIGHT if ability.enabled else Color(0.7, 0.65, 0.6))
	caption.add_theme_constant_override("outline_size", 4)
	button.add_child(caption)
	button.mouse_entered.connect(func() -> void:
		if not button.disabled:
			Sfx.play(SfxId.CARD_HOVER)
			icon.scale = Vector2(1.08, 1.08)
	)
	button.mouse_exited.connect(func() -> void: icon.scale = Vector2.ONE)
	icon.pivot_offset = Vector2(BUTTON_SIZE, BUTTON_SIZE) * 0.5
	button.pressed.connect(func() -> void:
		Sfx.play(SfxId.BUTTON_CLICK)
		if ability.on_pressed.is_valid():
			ability.on_pressed.call()
	)
	add_child(button)
	return button


static func _icon_material(ability: Ability) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = VfxAssets.get_shader("keyword_icon")
	mat.set_shader_parameter("shape", ability.icon)
	mat.set_shader_parameter("fg_color", Color(1.0, 0.9, 0.7) if ability.enabled else Color(0.6, 0.58, 0.55))
	mat.set_shader_parameter("bg_color", Color(0.36, 0.22, 0.1, 0.97) if ability.enabled else Color(0.22, 0.2, 0.19, 0.97))
	mat.set_shader_parameter("rim_color", Color(1.0, 0.8, 0.38) if ability.enabled else Color(0.5, 0.47, 0.43))
	return mat


func _clear() -> void:
	for b in _buttons:
		b.queue_free()
	_buttons.clear()
