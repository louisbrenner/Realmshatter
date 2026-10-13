class_name PieceView
extends Node3D
## Minion-like token for one piece (root of Piece.tscn): oval portrait (card tint + class symbol, see ClassVisuals)
## in a gold rim, owner-colored ring, attack (yellow, bottom-left) and health (red drop, bottom-right)
## badges, a shield badge + golden bubble, a name below the token, a green "can act" glow and a
## "Zzz" exhausted state. Everything fits inside one tile; the badge plates sit at fixed token-local
## spots and are tilted toward the camera (badge_tilt). All play_*/move_to helpers are awaitable.

## How strongly the card tint is blended into the owner color for body_color (0..1).
@export_range(0, 1, 0.05) var tint_blend: float = 0.3
@export var move_duration: float = 0.35
@export var attack_duration: float = 0.3
@export var hop_height: float = 0.28
## Orientation of the stat badges and name: 0 = lying flat on the token (facing up), 1 = facing the
## camera. In between they lie on the token, tilted toward the camera and turned upright on screen.
@export_range(0, 1, 0.05) var badge_tilt: float = 0.5
## Maximum world width of the name label (it shrinks to fit inside the tile).
@export var max_name_width: float = 0.78
## World size of the keyword emblems (left edge of the token).
@export var keyword_icon_size: float = 0.34

@export_group("Colors")
@export var hit_flash_color: Color = Color(1.0, 1.0, 1.0)
@export var selected_color: Color = Color(1.0, 0.82, 0.3)
@export var order_color: Color = Color(0.35, 0.75, 1.0)
@export var can_act_color: Color = Color(0.25, 1.0, 0.35)
@export var attack_badge_color: Color = Color(0.98, 0.66, 0.1)
@export var health_badge_color: Color = Color(0.92, 0.13, 0.1)
@export var shield_badge_color: Color = Color(0.78, 0.8, 0.86)
@export var buffed_color: Color = Color(0.45, 1.0, 0.4)
@export var damaged_color: Color = Color(1.0, 0.3, 0.26)

const ZZZ_CYCLE: float = 2.4
const ZZZ_RISE: float = 0.32

var _visual: Node3D
var _badges: Node3D
var _can_act_glow: MeshInstance3D
var _selection_ring: MeshInstance3D
var _base: MeshInstance3D
var _owner_ring: MeshInstance3D
var _portrait: MeshInstance3D
var _shield_bubble: MeshInstance3D
var _attack_badge: MeshInstance3D
var _health_badge: MeshInstance3D
var _shield_badge: MeshInstance3D
var _order_indicator: MeshInstance3D
var _attack_label: Label3D
var _health_label: Label3D
var _shield_label: Label3D
var _name_label: Label3D
var _zzz_label: Label3D
var _zzz_base: Vector3
## The three drifting "z" letters of the sleep indicator (the first is the scene's ZzzLabel).
var _zzz: Array[Label3D] = []
var _attack_plate: Node3D
var _health_plate: Node3D
var _shield_plate: Node3D
var _order_plate: Node3D
var _name_plate: Node3D
var _plates: Array[Node3D] = []
var _keyword_plates: Array[Node3D] = []
var _shown_source: CardData
var _shown_first_hit_used: bool = false
var _building_model: Node3D
var _scaffold: Node3D
var _under_construction: bool = false
var _shown_keywords: int = Keyword.NONE
var _shown_level: int = -1
var _name_pixel_size: float = 0.0
var _plate_rotation: Quaternion = Quaternion(2.0, 0.0, 0.0, 0.0)

var _portrait_mat: ShaderMaterial
var _can_act_mat: ShaderMaterial
var _select_mat: ShaderMaterial
var _ring_mat: StandardMaterial3D

var _owner_color: Color = Color.GRAY
var _tint: Color = Color.WHITE
var _body_color: Color = Color.GRAY
var _base_attack: int = 0
var _base_hp: int = 0
var _max_hp: int = 0
var _selected: bool = false
var _hovered: bool = false
var _can_act: bool = false
var _exhausted: bool = false
var _time: float = 0.0
var _lift: float = 0.0
var _shake: Vector3 = Vector3.ZERO
var _move_tween: Tween
var _exhaust_tween: Tween

## Id of the core Piece this view represents (-1 before setup).
var piece_id: int = -1

## Owner player index (from setup).
var owner_index: int = 0

## Owner color blended with the card tint (used for fragments etc.).
var body_color: Color:
	get:
		return _body_color

## The card tint.
var tint_color: Color:
	get:
		return _tint

## The owner color passed to setup.
var owner_color: Color:
	get:
		return _owner_color

## True while the green "can act" glow is shown.
var can_act: bool:
	get:
		return _can_act

## True while the piece is shown exhausted (summoning sickness).
var is_exhausted: bool:
	get:
		return _exhausted

## Seconds after the start of play_attack at which the lunge hits.
var impact_time: float:
	get:
		return attack_duration * 0.45


func _ready() -> void:
	_ensure_nodes()


func _process(delta: float) -> void:
	if _visual == null:
		return
	var dt: float = delta
	_time += dt
	var target: float = 0.09 + 0.025 * sin(_time * 3.0) if _selected else (0.05 if _hovered else 0.0)
	_lift = lerpf(_lift, target, 1.0 - exp(-dt * 12.0))
	_visual.position = Vector3(_shake.x, _lift + _shake.y, _shake.z)
	_badges.position = Vector3(_shake.x, _lift, _shake.z)
	_orient_plates()
	if _exhausted and _zzz.size() > 0:
		_animate_zzz()


## Initializes portrait, colors, name and badges from a core piece.
func setup(piece: Piece, owner_color_value: Color) -> void:
	_ensure_nodes()
	piece_id = piece.id
	owner_index = piece.owner_index
	name = "Piece_%d" % piece.id
	_owner_color = owner_color_value
	_tint = piece.source.tint if piece.source != null else Color.WHITE
	_tint = Color(_tint.r, _tint.g, _tint.b)
	_body_color = owner_color_value.lerp(_tint, tint_blend)

	var role: int
	match piece.role:
		UnitRole.ATTACK: role = 0
		UnitRole.UTILITY: role = 1
		_: role = 2
	_portrait_mat.set_shader_parameter("tint", _tint)
	_portrait_mat.set_shader_parameter("role", role)
	_portrait_mat.set_shader_parameter("glyph", ClassVisuals.art_glyph(piece.source))
	_portrait_mat.set_shader_parameter("seed", piece.id * 0.37)
	# Area attackers: outward marks in the area's shape around the attack crest.
	(_attack_badge.material_override as ShaderMaterial).set_shader_parameter("area", piece.attack_area)
	_ring_mat.albedo_color = owner_color_value
	_ring_mat.emission = owner_color_value
	_name_label.text = piece.source.name if piece.source != null else "#%d" % piece.id
	_name_label.modulate = owner_color_value.lerp(Color.WHITE, 0.55)
	_fit_name()

	_max_hp = 0
	refresh(piece)


## Updates attack/health/shield badges and the order indicator from the core piece.
func refresh(piece: Piece) -> void:
	if piece == null:
		return
	_ensure_nodes()
	_base_attack = piece.base_stats.attack
	_base_hp = piece.base_stats.hp
	_max_hp = piece.max_hp
	set_attack(piece.effective_attack)
	set_stats(piece.current_hp, piece.total_shield)
	set_keywords(piece.keywords, piece.source.level if piece.source != null else 0, piece.source, piece.was_hit)
	if piece.is_building:
		_ensure_building_model(piece)
		set_under_construction(piece.under_construction)


## Grows the building out of its scaffold when finished (or shrinks it back while under construction).
func set_under_construction(under_construction: bool) -> void:
	if _building_model == null or _under_construction == under_construction:
		return
	_under_construction = under_construction
	_scaffold.visible = true
	var tween: Tween = create_tween()
	tween.tween_property(_building_model, "scale", Vector3(1.0, 0.35 if under_construction else 1.0, 1.0), 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void: _scaffold.visible = _under_construction)


func _ensure_building_model(piece: Piece) -> void:
	if _building_model != null:
		return
	for z in _zzz:
		z.visible = false
	_portrait.visible = false
	_building_model = BuildingModels.create(piece.building, piece.source.tint if piece.source != null else Color.GRAY, _owner_color)
	_building_model.position = Vector3(0, 0.1, 0)
	_building_model.scale = Vector3(1.0, 0.35, 1.0)
	_visual.add_child(_building_model)
	_scaffold = BuildingModels.create_scaffold()
	_scaffold.position = Vector3(0, 0.1, 0)
	_visual.add_child(_scaffold)
	_under_construction = true


## Shows one small emblem plate per keyword along the left edge of the token (flame = Burning,
## snowflake = Frost, fist = Push, spear = Pierce, cross = Mending, bolt = Arc, bell = Echo,
## skull = Undying; an Undying level is shown as "+N" beside the skull). The first-hit burst disappears once
## it has fired (first_hit_used).
func set_keywords(keywords: int, level: int = 0, source: CardData = null, first_hit_used: bool = false) -> void:
	_ensure_nodes()
	if keywords == _shown_keywords and level == _shown_level and source == _shown_source and first_hit_used == _shown_first_hit_used:
		return
	_shown_source = source
	_shown_first_hit_used = first_hit_used
	_shown_keywords = keywords
	_shown_level = level
	for plate in _keyword_plates:
		if is_instance_valid(plate):
			plate.queue_free()
	_keyword_plates.clear()

	var list: Array = KeywordInfo.split(keywords)
	var icons: Array[Dictionary] = []
	if source != null:
		icons = KeywordVisuals.icons_for(source, first_hit_used)
	else:
		for k: int in list:
			icons.append({"shape": KeywordVisuals.get_shape(k), "fg": KeywordVisuals.get_foreground(k), "bg": KeywordVisuals.get_background(k)})
	var step: float = keyword_icon_size * 0.92
	for i in range(icons.size()):
		var k: int = list[i] if i < list.size() else Keyword.NONE
		var plate := Node3D.new()
		plate.name = "Icon_%d" % i
		plate.position = Vector3(-0.36, 0.21, -0.2 - i * step)
		_badges.add_child(plate)
		var icon: MeshInstance3D = VfxAssets.create_icon(icons[i].shape, keyword_icon_size, icons[i].fg, icons[i].bg, true, 31)
		var mat := icon.material_override as ShaderMaterial
		mat.set_shader_parameter("billboard", false)
		mat.set_shader_parameter("rim_color", Color(0.86, 0.66, 0.3))
		mat.set_shader_parameter("energy", 1.15)
		plate.add_child(icon)
		if k == Keyword.UNDYING and level > 0:
			var lv: Label3D = VfxAssets.create_label("+%d" % level, 40, 0.0034, Color(0.7, 1.0, 0.9), 10, 33)
			lv.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			lv.position = Vector3(0.1, -0.1, 0.001)
			plate.add_child(lv)
		_keyword_plates.append(plate)
	var all: Array[Node3D] = [_attack_plate, _health_plate, _shield_plate, _order_plate, _name_plate]
	all.append_array(_keyword_plates)
	_plates = all
	_plate_rotation = Quaternion(2.0, 0.0, 0.0, 0.0)


## Updates the health and shield badges (health turns red when damaged, green when buffed).
func set_stats(hp: int, shield: int) -> void:
	_ensure_nodes()
	if _max_hp <= 0:
		_max_hp = hp
		_base_hp = hp
	_health_label.text = str(hp)
	_health_label.modulate = damaged_color if hp < _max_hp else (buffed_color if _max_hp > _base_hp else Color.WHITE)
	var has_shield: bool = shield > 0
	_shield_plate.visible = has_shield
	_shield_label.text = str(shield)
	_shield_bubble.visible = has_shield


## Updates the attack badge (green when above the base attack, red when below).
func set_attack(attack: int) -> void:
	_ensure_nodes()
	_attack_label.text = str(attack)
	_attack_label.modulate = buffed_color if attack > _base_attack else (damaged_color if attack < _base_attack else Color.WHITE)


## Shows or hides the golden selection glow and lifts the token.
func set_selected(selected: bool) -> void:
	_ensure_nodes()
	_selected = selected
	_selection_ring.visible = selected


## Slightly lifts the token while the mouse is over it (optional).
func set_hovered(hovered: bool) -> void:
	_hovered = hovered


## Shows or hides the small "has order" gem.
func set_has_order(has_order: bool) -> void:
	_ensure_nodes()
	_order_plate.visible = has_order


## Green pulsing outline like a playable Hearthstone minion.
func set_can_act(can_act_value: bool) -> void:
	_ensure_nodes()
	_can_act = can_act_value
	_can_act_glow.visible = can_act_value


## Sleep indicator: three small z's rise one after another from the top of the token, growing, drifting
## sideways and fading out, then start again.
func _animate_zzz() -> void:
	for i in range(_zzz.size()):
		var phase: float = fposmod(_time / ZZZ_CYCLE + i / float(_zzz.size()), 1.0)
		var sway: float = 0.035 * sin(phase * TAU + i)
		_zzz[i].position = _zzz_base + Vector3(phase * 0.1 + sway, phase * ZZZ_RISE, 0.0)
		_zzz[i].scale = Vector3.ONE * (0.55 + 0.6 * phase)
		var alpha: float = sin(phase * PI)
		_zzz[i].modulate = Color(0.78, 0.88, 1.0, alpha)


## Exhausted look (desaturated portrait + drifting z's): summoning sick, busy building, or already acted this
## turn.
func set_exhausted(exhausted: bool) -> void:
	_ensure_nodes()
	if _building_model != null:
		exhausted = false
	if _exhausted == exhausted:
		return
	_exhausted = exhausted
	for z in _zzz:
		z.visible = exhausted
	if _exhaust_tween != null:
		_exhaust_tween.kill()
	_exhaust_tween = create_tween()
	_exhaust_tween.tween_method(_set_desaturation,
		0.0 if exhausted else 0.75, 0.75 if exhausted else 0.0, 0.3)


## Places the view immediately (no animation), cancelling a running move.
func snap_to(target: Vector3) -> void:
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	global_position = target


## Hops to a world position with a landing squash. Await to wait for arrival.
func move_to(target: Vector3) -> void:
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	var start: Vector3 = global_position
	var hop: float = hop_height * minf(1.0, start.distance_to(target))
	_move_tween = create_tween()
	_move_tween.tween_method(func(t: float) -> void:
		global_position = start.lerp(target, t) + Vector3.UP * hop * 4.0 * t * (1.0 - t)
	, 0.0, 1.0, move_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _move_tween.finished
	play_squash(0.6)


## Winds up, lunges toward a world position and returns. The hit lands at impact_time.
func play_attack(target_world: Vector3) -> void:
	var start: Vector3 = global_position
	var flat := Vector3(target_world.x, start.y, target_world.z)
	var dir: Vector3 = flat - start
	dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	var windup: Vector3 = start - dir * 0.14 + Vector3(0, 0.06, 0)
	var lunge: Vector3 = start.lerp(flat, 0.58) + Vector3(0, 0.12, 0)
	var tween: Tween = create_tween()
	tween.tween_property(self, "global_position", windup, attack_duration * 0.25) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", lunge, attack_duration * 0.2) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "global_position", start, attack_duration * 0.55) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tween.finished


## Small recoil away from a target (ranged shot).
func play_recoil(target_world: Vector3) -> void:
	var start: Vector3 = global_position
	var dir := Vector3(target_world.x - start.x, 0.0, target_world.z - start.z)
	dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	var tween: Tween = create_tween()
	tween.tween_property(self, "global_position", start - dir * 0.1 + Vector3(0, 0.04, 0), 0.06)
	tween.tween_property(self, "global_position", start, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tween.finished


## Short nudge toward a world position and back (e.g. blocked move).
func play_bump(toward_world: Vector3) -> void:
	var start: Vector3 = global_position
	var dir := Vector3(toward_world.x - start.x, 0.0, toward_world.z - start.z)
	dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	var tween: Tween = create_tween()
	tween.tween_property(self, "global_position", start + dir * 0.2, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", start, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished


## Flashes the portrait white, shakes and squashes the token.
func play_hit() -> void:
	_ensure_nodes()
	_portrait_mat.set_shader_parameter("flash_color", hit_flash_color)
	var flash: Tween = create_tween()
	flash.tween_method(_set_flash, 1.0, 0.0, 0.3)
	var shake: Tween = create_tween()
	shake.tween_method(func(t: float) -> void:
		_shake = Vector3(sin(t * 42.0), 0.0, cos(t * 33.0) * 0.6) * 0.09 * (1.0 - t)
	, 0.0, 1.0, 0.26)
	shake.tween_callback(func() -> void: _shake = Vector3.ZERO)
	var punch: Tween = create_tween()
	punch.tween_property(_visual, "scale", Vector3(1.14, 0.82, 1.14), 0.05)
	punch.tween_property(_visual, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	await flash.finished


## Briefly tints the portrait with a color (e.g. chain trigger) and pulses its scale.
func play_flash(color: Color, duration: float = 0.35) -> void:
	_ensure_nodes()
	_portrait_mat.set_shader_parameter("flash_color", color)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_method(_set_flash, 0.85, 0.0, duration)
	tween.tween_property(_visual, "scale", Vector3.ONE * 1.18, duration * 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(_visual, "scale", Vector3.ONE, duration * 0.6)
	await tween.finished


## Squash-and-stretch bounce of the token (landing).
func play_squash(amount: float = 1.0) -> void:
	_ensure_nodes()
	var tween: Tween = create_tween()
	tween.tween_property(_visual, "scale", Vector3(1.0 + 0.25 * amount, 1.0 - 0.35 * amount, 1.0 + 0.25 * amount), 0.06)
	tween.tween_property(_visual, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	await tween.finished


## Drops the token from above onto its current position. Completes on impact.
func play_drop(height: float = 2.2, duration: float = 0.22) -> void:
	_ensure_nodes()
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	var rest: Vector3 = global_position
	global_position = rest + Vector3.UP * height
	_visual.scale = Vector3(0.82, 1.3, 0.82)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", rest, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_visual, "scale", Vector3(0.92, 1.12, 0.92), duration)
	await tween.finished


## Collapses the token quickly (the animator adds the shatter VFX) and frees it.
func play_death() -> void:
	_ensure_nodes()
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_badges.visible = false
	_can_act_glow.visible = false
	_selection_ring.visible = false
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_visual, "scale", Vector3(0.01, 0.01, 0.01), 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(_visual, "rotation:y", _visual.rotation.y + PI, 0.18)
	await tween.finished
	queue_free()


func _set_flash(value: float) -> void:
	if _portrait_mat != null:
		_portrait_mat.set_shader_parameter("flash", value)


func _set_desaturation(value: float) -> void:
	if _portrait_mat != null:
		_portrait_mat.set_shader_parameter("desaturate", value)
		_portrait_mat.set_shader_parameter("brightness", 1.0 - value * 0.3)


func _ensure_nodes() -> void:
	if _visual != null:
		return
	_visual = get_node("Visual") as Node3D
	_badges = get_node("Badges") as Node3D
	_can_act_glow = get_node("Visual/CanActGlow") as MeshInstance3D
	_selection_ring = get_node("Visual/SelectionRing") as MeshInstance3D
	_base = get_node("Visual/Token/Base") as MeshInstance3D
	_owner_ring = get_node("Visual/Token/OwnerRing") as MeshInstance3D
	_portrait = get_node("Visual/Token/Portrait") as MeshInstance3D
	_shield_bubble = get_node("Visual/ShieldBubble") as MeshInstance3D
	_attack_plate = get_node("Badges/AttackPlate") as Node3D
	_health_plate = get_node("Badges/HealthPlate") as Node3D
	_shield_plate = get_node("Badges/ShieldPlate") as Node3D
	_order_plate = get_node("Badges/OrderPlate") as Node3D
	_name_plate = get_node("Badges/NamePlate") as Node3D
	_plates = [_attack_plate, _health_plate, _shield_plate, _order_plate, _name_plate]
	_attack_badge = get_node("Badges/AttackPlate/Badge") as MeshInstance3D
	_health_badge = get_node("Badges/HealthPlate/Badge") as MeshInstance3D
	_shield_badge = get_node("Badges/ShieldPlate/Badge") as MeshInstance3D
	_order_indicator = get_node("Badges/OrderPlate/Badge") as MeshInstance3D
	_attack_label = get_node("Badges/AttackPlate/Label") as Label3D
	_health_label = get_node("Badges/HealthPlate/Label") as Label3D
	_shield_label = get_node("Badges/ShieldPlate/Label") as Label3D
	_name_label = get_node("Badges/NamePlate/Label") as Label3D
	_zzz_label = get_node("Badges/ZzzLabel") as Label3D
	# Badge numbers: lining figures, centred on their badge.
	for number: Label3D in [_attack_label, _health_label, _shield_label]:
		number.font = VfxAssets.get_number_font()
		number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		# Label3D offsets point up: lift the digits by how far their ink sits below the line centre.
		number.offset = Vector2(0.0, VfxAssets.digit_drop(number.font_size))
	_name_pixel_size = _name_label.pixel_size
	# Sleep indicator: start just above the token's top edge and build three single "z" letters.
	_zzz_base = Vector3(0.08, 0.42, -0.12)
	_zzz_label.text = "z"
	_zzz_label.visible = false
	var letters: Array[Label3D] = [_zzz_label]
	for i in range(1, 3):
		var copy := _zzz_label.duplicate() as Label3D
		copy.name = "ZzzLabel%d" % (i + 1)
		_zzz_label.get_parent().add_child(copy)
		letters.append(copy)
	_zzz = letters

	_base.material_override = VfxAssets.create_gold_material(0.06)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = _owner_color
	_ring_mat.metallic = 0.3
	_ring_mat.roughness = 0.3
	_ring_mat.emission_enabled = true
	_ring_mat.emission = _owner_color
	_ring_mat.emission_energy_multiplier = 0.9
	_owner_ring.material_override = _ring_mat

	_portrait_mat = VfxAssets.create_material("piece_portrait")
	_portrait.material_override = _portrait_mat

	_can_act_mat = VfxAssets.create_material("aura", 2)
	_can_act_mat.set_shader_parameter("color", can_act_color)
	_can_act_mat.set_shader_parameter("inner", 0.6)
	_can_act_mat.set_shader_parameter("width", 0.22)
	_can_act_mat.set_shader_parameter("energy", 2.6)
	_can_act_glow.material_override = _can_act_mat

	_select_mat = VfxAssets.create_material("aura", 3)
	_select_mat.set_shader_parameter("color", selected_color)
	_select_mat.set_shader_parameter("inner", 0.55)
	_select_mat.set_shader_parameter("width", 0.3)
	_select_mat.set_shader_parameter("energy", 3.2)
	_select_mat.set_shader_parameter("pulse_speed", 5.0)
	_selection_ring.material_override = _select_mat

	_shield_bubble.material_override = VfxAssets.create_material("shield_bubble", 5)

	_attack_badge.material_override = _create_badge_material(7, attack_badge_color)
	_health_badge.material_override = _create_badge_material(8, health_badge_color)
	_shield_badge.material_override = _create_badge_material(9, shield_badge_color)
	_order_indicator.material_override = _create_badge_material(5, order_color)


static func _create_badge_material(shape: int, fill: Color) -> ShaderMaterial:
	var mat: ShaderMaterial = VfxAssets.create_material("badge", 28)
	mat.set_shader_parameter("shape", shape)
	mat.set_shader_parameter("fill_color", fill)
	mat.set_shader_parameter("billboard", false)
	return mat


## Orients all badge plates: blend between lying flat (turned so the text is upright on screen)
## and facing the camera by badge_tilt. Positions stay token-local, so badges never drift off the tile.
func _orient_plates() -> void:
	var viewport: Viewport = get_viewport()
	var camera: Camera3D = viewport.get_camera_3d() if viewport != null else null
	if camera == null or _plates.is_empty():
		return
	var cam_basis: Basis = camera.global_basis.orthonormalized()
	var right := Vector3(cam_basis.x.x, 0.0, cam_basis.x.z)
	right = right.normalized() if right.length_squared() > 1e-5 else Vector3.RIGHT
	var normal: Vector3 = Vector3.UP
	var flat := Basis(right, normal.cross(right), normal)
	var q: Quaternion = flat.get_rotation_quaternion().slerp(cam_basis.get_rotation_quaternion(), clampf(badge_tilt, 0.0, 1.0))
	if q.is_equal_approx(_plate_rotation):
		return
	_plate_rotation = q
	var plate_basis := Basis(q)
	for plate in _plates:
		plate.global_basis = plate_basis


## Shrinks the name label so it fits inside the tile.
func _fit_name() -> void:
	var font: Font = _name_label.font if _name_label.font != null else VfxAssets.get_card_font()
	_name_label.pixel_size = _name_pixel_size
	if font == null:
		return
	var width: float = font.get_string_size(_name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _name_label.font_size).x * _name_pixel_size
	if width > max_name_width and width > 0.0:
		_name_label.pixel_size = _name_pixel_size * max_name_width / width
