class_name TileEffectVisual
extends Node3D
## Visual of one tile effect: molten lava (embers, bubbles, heat shimmer, glow), a raised stone wall
## with rubble, or a glowing healing rune circle with rising sparkles; plus a small duration badge.
## Ghost mode is a translucent preview without particles/lights/badge (spell and attack previews).
## Created by TileEffectLayer and OrderOverlay; the node origin is the tile's top center.

const LAVA_TIMER_COLOR := Color(1.0, 0.5, 0.12)
const WALL_TIMER_COLOR := Color(0.85, 0.78, 0.62)
const HEAL_TIMER_COLOR := Color(0.45, 1.0, 0.55)

var _emitters: Array[CPUParticles3D] = []
var _surface_mat: ShaderMaterial
var _haze_mat: ShaderMaterial
var _wall_mats: Array[ShaderMaterial] = []
var _ghost_mat: ShaderMaterial
var _wall_root: Node3D
var _light: OmniLight3D
var _light_base: float = 0.0
var _timer: Node3D
var _timer_mat: ShaderMaterial
var _timer_label: Label3D
var _tile_size: float = 1.0
var _seed: float = 0.0
var _time: float = 0.0
var _remaining: int = -1
var _appear_light: float = 1.0
var _timer_color: Color = Color.WHITE
var _tween: Tween

## Remaining turns shown on the badge (-1 = none).
var remaining: int:
	get:
		return _remaining

## The kind of effect shown.
var type: int = TileEffectType.NONE

## True for translucent previews.
var is_ghost: bool = false

## Turn in which the shown effect expires (for diffing), or -1.
var expiry_turn: int = -1

## True once play_vanish started (the node frees itself afterwards).
var is_vanishing: bool = false


## Builds the visual. Call once, before or right after adding it to the tree.
func setup(p_type: int, tile_size: float, ghost: bool, p_seed: float) -> void:
	type = p_type
	is_ghost = ghost
	_tile_size = maxf(0.1, tile_size)
	_seed = p_seed
	name = "%s%s" % [TileEffectType.name_of(p_type), "Ghost" if ghost else ""]
	match p_type:
		TileEffectType.LAVA:
			_build_lava()
		TileEffectType.WALL:
			_build_wall()
		TileEffectType.HEALING:
			_build_healing()
		_:
			_build_generic()
	if not ghost:
		_build_timer()


## Updates the duration badge: number and lit pips (hidden when turns is below 1).
func set_remaining(turns: int, total: int = -1) -> void:
	_remaining = turns
	if _timer == null:
		return
	_timer.visible = turns > 0
	_timer_label.text = str(turns)
	var all: int = clampi(maxi(total, turns) if total > 0 else turns, 1, 6)
	_timer_mat.set_shader_parameter("total", all)
	_timer_mat.set_shader_parameter("lit", clampi(turns, 0, 6))


## Shows the effect fully formed without animation.
func show_instant() -> void:
	if _tween != null:
		_tween.kill()
	_set_appear(1.0)


## Animated appearance: lava spreads with a splash, the wall rises with dust, runes bloom.
func play_appear() -> void:
	if _tween != null:
		_tween.kill()
	_set_appear(0.0)
	var parent := get_parent() as Node3D
	var pos: Vector3 = global_position
	var duration: float = 0.32 if type == TileEffectType.WALL else 0.38
	if not is_ghost and parent != null:
		match type:
			TileEffectType.LAVA:
				RuleVfx.fire_burst(parent, pos, 0.8)
				Vfx.shockwave(parent, pos + Vector3(0, 0.04, 0), RuleVfx.FIRE_COLOR, 1.1, 0.35, 0.14)
			TileEffectType.WALL:
				Vfx.dust_ring(parent, pos, Color(0.62, 0.55, 0.46), 0.5, 16)
			TileEffectType.HEALING:
				Vfx.sparkle(parent, pos + Vector3(0, 0.2, 0), RuleVfx.HEAL_GOLD, 14, 0.8, 0.4)
				Vfx.glow_flash(parent, pos + Vector3(0, 0.15, 0), RuleVfx.HEAL_COLOR, 1.4, 0.35)
	_tween = create_tween()
	var trans: Tween.TransitionType = Tween.TRANS_BACK if type == TileEffectType.WALL else Tween.TRANS_CUBIC
	_tween.tween_method(_set_appear, 0.0, 1.0, duration).set_trans(trans).set_ease(Tween.EASE_OUT)
	if type == TileEffectType.WALL and not is_ghost:
		_tween.tween_callback(func() -> void:
			var p := get_parent() as Node3D
			if p != null:
				RuleVfx.rubble_burst(p, global_position, 0.6)
		)
	await _tween.finished


## Animated removal (lava cools to crust, the wall crumbles and sinks, runes fade); frees the node.
func play_vanish() -> void:
	if is_vanishing:
		return
	is_vanishing = true
	if _tween != null:
		_tween.kill()
	for e in _emitters:
		e.emitting = false
	if _timer != null:
		_timer.visible = false
	var parent := get_parent() as Node3D
	var pos: Vector3 = global_position
	if not is_ghost and parent != null:
		match type:
			TileEffectType.LAVA:
				Vfx.smoke_puff(parent, pos + Vector3(0, 0.1, 0), Color(0.3, 0.27, 0.25), 10, 0.7)
			TileEffectType.WALL:
				RuleVfx.rubble_burst(parent, pos, 1.1)
			TileEffectType.HEALING:
				Vfx.sparkle(parent, pos + Vector3(0, 0.2, 0), RuleVfx.HEAL_COLOR, 10, 0.7, 0.4)
	_tween = create_tween()
	_tween.tween_method(_set_vanish, 0.0, 1.0, 0.12 if is_ghost else 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _tween.finished
	queue_free()


## Short pulse to re-draw attention (effect refreshed on an already active tile).
func pulse() -> void:
	var t: Tween = create_tween()
	t.tween_property(self, "scale", Vector3(1.08, 1.08, 1.08), 0.08)
	t.tween_property(self, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_time += delta
	if _light != null and not is_vanishing:
		var flicker: float
		if type == TileEffectType.LAVA:
			flicker = 0.8 + 0.2 * sin(_time * 7.3 + _seed) + 0.12 * sin(_time * 17.1)
		else:
			flicker = 0.85 + 0.15 * sin(_time * 2.2 + _seed)
		_light.light_energy = _light_base * flicker * _appear_light
	if _timer != null and _timer.visible:
		var s: float = 1.0 + 0.05 * sin(_time * 3.0 + _seed)
		_timer.scale = Vector3.ONE * s


func _set_appear(t: float) -> void:
	_appear_light = t
	match type:
		TileEffectType.LAVA:
			if _surface_mat != null:
				_surface_mat.set_shader_parameter("opacity" if is_ghost else "appear", t)
			if _haze_mat != null:
				_haze_mat.set_shader_parameter("strength", t)
		TileEffectType.HEALING:
			if _surface_mat != null:
				_surface_mat.set_shader_parameter("appear", t)
		TileEffectType.WALL:
			if _wall_root != null:
				var h: float = 0.62
				_wall_root.position = Vector3(0.0, -h * (1.0 - t), 0.0)
				_wall_root.scale = Vector3(1.0, maxf(0.05, t), 1.0)
		_:
			if _surface_mat != null:
				_surface_mat.set_shader_parameter("opacity", t)
	if _timer != null:
		_timer_mat.set_shader_parameter("alpha", t)
		_timer_label.modulate = Color(_timer_color.r, _timer_color.g, _timer_color.b, t)
		_timer_label.outline_modulate = Color(0.05, 0.03, 0.02, t)


func _set_vanish(t: float) -> void:
	_appear_light = 1.0 - t
	match type:
		TileEffectType.LAVA:
			if is_ghost:
				if _surface_mat != null:
					_surface_mat.set_shader_parameter("opacity", 1.0 - t)
			else:
				if _surface_mat != null:
					_surface_mat.set_shader_parameter("cool", clampf(t * 1.6, 0.0, 1.0))
					_surface_mat.set_shader_parameter("appear", 1.0 - clampf((t - 0.45) / 0.55, 0.0, 1.0))
			if _haze_mat != null:
				_haze_mat.set_shader_parameter("strength", 1.0 - t)
		TileEffectType.HEALING:
			if _surface_mat != null:
				_surface_mat.set_shader_parameter("opacity", 1.0 - t)
				_surface_mat.set_shader_parameter("appear", 1.0 + t * 0.3)
		TileEffectType.WALL:
			for m in _wall_mats:
				m.set_shader_parameter("crumble", t)
			if _ghost_mat != null:
				_ghost_mat.set_shader_parameter("opacity", 1.0 - t)
			if _wall_root != null:
				_wall_root.position = Vector3(0.0, -0.45 * t * t, 0.0)
		_:
			if _surface_mat != null:
				_surface_mat.set_shader_parameter("opacity", 1.0 - t)


# ------------------------------------------------------------------ builders

func _build_lava() -> void:
	var s: float = _tile_size * 0.97
	_surface_mat = VfxAssets.create_material("tile_lava_ghost" if is_ghost else "tile_lava", 6 if is_ghost else 0)
	if not is_ghost:
		_surface_mat.set_shader_parameter("seed", _seed)
	var surface := MeshInstance3D.new()
	surface.name = "LavaSurface"
	var surface_mesh := PlaneMesh.new()
	surface_mesh.size = Vector2(s, s)
	surface.mesh = surface_mesh
	surface.material_override = _surface_mat
	surface.position = Vector3(0, 0.03 if is_ghost else 0.006, 0)
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface)
	if is_ghost:
		return

	_haze_mat = VfxAssets.create_material("heat_haze", 1)
	var haze := MeshInstance3D.new()
	haze.name = "HeatHaze"
	var haze_mesh := PlaneMesh.new()
	haze_mesh.size = Vector2(s * 0.95, s * 0.95)
	haze.mesh = haze_mesh
	haze.material_override = _haze_mat
	haze.position = Vector3(0, 0.32, 0)
	haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(haze)

	var embers := CPUParticles3D.new()
	embers.name = "Embers"
	embers.mesh = VfxAssets.glow_quad
	embers.amount = 9
	embers.lifetime = 1.5
	embers.local_coords = false
	embers.randomness = 0.6
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	embers.emission_box_extents = Vector3(s * 0.38, 0.02, s * 0.38)
	embers.direction = Vector3.UP
	embers.spread = 22.0
	embers.initial_velocity_min = 0.35
	embers.initial_velocity_max = 0.85
	embers.gravity = Vector3(0, 0.12, 0)
	embers.damping_min = 0.2
	embers.damping_max = 0.5
	embers.scale_amount_min = 0.05
	embers.scale_amount_max = 0.12
	embers.scale_amount_curve = Vfx.linear_curve(1.0, 0.0, 1.0)
	embers.color_ramp = Vfx.ramp([Color(1.0, 0.9, 0.5, 1.0), Color(1.0, 0.45, 0.08, 0.9), Color(0.6, 0.08, 0.02, 0.0)])
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	embers.position = Vector3(0, 0.05, 0)
	_add_emitter(embers)

	var bubbles := CPUParticles3D.new()
	bubbles.name = "Bubbles"
	bubbles.mesh = VfxAssets.ring_quad
	bubbles.amount = 3
	bubbles.lifetime = 0.8
	bubbles.local_coords = false
	bubbles.randomness = 0.8
	bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	bubbles.emission_box_extents = Vector3(s * 0.3, 0.0, s * 0.3)
	bubbles.direction = Vector3.UP
	bubbles.spread = 0.0
	bubbles.initial_velocity_min = 0.02
	bubbles.initial_velocity_max = 0.08
	bubbles.gravity = Vector3.ZERO
	bubbles.scale_amount_min = 0.12
	bubbles.scale_amount_max = 0.22
	bubbles.scale_amount_curve = Vfx.linear_curve(0.2, 1.2)
	bubbles.color_ramp = Vfx.ramp([Color(1.0, 0.75, 0.3, 0.9), Color(1.0, 0.4, 0.05, 0.0)])
	bubbles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bubbles.position = Vector3(0, 0.04, 0)
	_add_emitter(bubbles)

	_light = OmniLight3D.new()
	_light.name = "Glow"
	_light.light_color = Color(1.0, 0.45, 0.12)
	_light.omni_range = 1.3 * _tile_size
	_light.omni_attenuation = 1.8
	_light.shadow_enabled = false
	_light.position = Vector3(0, 0.12, 0)
	_light_base = 0.55
	add_child(_light)


func _build_wall() -> void:
	_wall_root = Node3D.new()
	_wall_root.name = "Block"
	add_child(_wall_root)
	var ts: float = _tile_size
	if is_ghost:
		_ghost_mat = VfxAssets.create_material("ghost_preview", 6)
		_ghost_mat.set_shader_parameter("half_size", Vector3(0.43 * ts, 0.31, 0.43 * ts))
		var ghost := MeshInstance3D.new()
		var ghost_mesh := BoxMesh.new()
		ghost_mesh.size = Vector3(0.86 * ts, 0.62, 0.86 * ts)
		ghost.mesh = ghost_mesh
		ghost.material_override = _ghost_mat
		ghost.position = Vector3(0, 0.31, 0)
		ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_wall_root.add_child(ghost)
		return

	var main: ShaderMaterial = _create_wall_material(0.0)
	var cap: ShaderMaterial = _create_wall_material(1.7)
	var rubble: ShaderMaterial = _create_wall_material(3.1)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.84 * ts, 0.5, 0.84 * ts)
	body.mesh = body_mesh
	body.material_override = main
	body.position = Vector3(0, 0.25, 0)
	_wall_root.add_child(body)
	var cap_node := MeshInstance3D.new()
	cap_node.name = "Cap"
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = Vector3(0.9 * ts, 0.12, 0.9 * ts)
	cap_node.mesh = cap_mesh
	cap_node.material_override = cap
	cap_node.position = Vector3(0, 0.55, 0)
	cap_node.rotation = Vector3(0, 0.05 + 0.04 * sin(_seed), 0)
	_wall_root.add_child(cap_node)
	# Crenellations on top.
	var merlon := BoxMesh.new()
	merlon.size = Vector3(0.22 * ts, 0.12, 0.22 * ts)
	for i in range(4):
		var sx: float = -1.0 if (i % 2 == 0) else 1.0
		var sz: float = -1.0 if (i < 2) else 1.0
		var m := MeshInstance3D.new()
		m.mesh = merlon
		m.material_override = cap
		m.position = Vector3(sx * 0.3 * ts, 0.67, sz * 0.3 * ts)
		_wall_root.add_child(m)
	# Rubble at the foot.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(_seed) * 1000.0) + 7
	for i in range(5):
		var ang: float = TAU * i / 5.0 + rng.randf_range(-0.4, 0.4)
		var size: float = rng.randf_range(0.08, 0.15)
		var rock := MeshInstance3D.new()
		var rock_mesh := BoxMesh.new()
		rock_mesh.size = Vector3(size * 1.3, size * 0.8, size)
		rock.mesh = rock_mesh
		rock.material_override = rubble
		rock.position = Vector3(cos(ang) * 0.44 * ts, size * 0.35, sin(ang) * 0.44 * ts)
		rock.rotation = Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(0.0, TAU), rng.randf_range(-0.4, 0.4))
		_wall_root.add_child(rock)
	for child in _wall_root.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh is BoxMesh:
				var box := mi.mesh as BoxMesh
				mi.set_instance_shader_parameter("top_size", Vector2(box.size.x, box.size.z))


func _create_wall_material(seed_offset: float) -> ShaderMaterial:
	var m: ShaderMaterial = VfxAssets.create_material("stone_wall")
	m.set_shader_parameter("seed", _seed + seed_offset)
	_wall_mats.append(m)
	return m


func _build_healing() -> void:
	var s: float = _tile_size * 0.97
	_surface_mat = VfxAssets.create_material("tile_healing", 6 if is_ghost else 1)
	_surface_mat.set_shader_parameter("seed", _seed)
	if is_ghost:
		_surface_mat.set_shader_parameter("opacity", 0.75)
		_surface_mat.set_shader_parameter("hatch", 1.0)
	var runes := MeshInstance3D.new()
	runes.name = "Runes"
	var runes_mesh := PlaneMesh.new()
	runes_mesh.size = Vector2(s, s)
	runes.mesh = runes_mesh
	runes.material_override = _surface_mat
	runes.position = Vector3(0, 0.03 if is_ghost else 0.012, 0)
	runes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(runes)
	if is_ghost:
		return
	var sparkles := CPUParticles3D.new()
	sparkles.name = "Sparkles"
	sparkles.mesh = VfxAssets.sparkle_quad
	sparkles.amount = 6
	sparkles.lifetime = 1.6
	sparkles.local_coords = false
	sparkles.randomness = 0.6
	sparkles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sparkles.emission_box_extents = Vector3(s * 0.34, 0.02, s * 0.34)
	sparkles.direction = Vector3.UP
	sparkles.spread = 12.0
	sparkles.initial_velocity_min = 0.25
	sparkles.initial_velocity_max = 0.5
	sparkles.gravity = Vector3(0, 0.05, 0)
	sparkles.scale_amount_min = 0.07
	sparkles.scale_amount_max = 0.15
	sparkles.scale_amount_curve = Vfx.linear_curve(0.0, 0.0, 1.0)
	sparkles.color_ramp = Vfx.ramp([Color(1.0, 1.0, 1.0, 1.0), RuleVfx.HEAL_COLOR, Color(RuleVfx.HEAL_GOLD.r, RuleVfx.HEAL_GOLD.g, RuleVfx.HEAL_GOLD.b, 0.0)])
	sparkles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sparkles.position = Vector3(0, 0.05, 0)
	_add_emitter(sparkles)
	_light = OmniLight3D.new()
	_light.name = "Glow"
	_light.light_color = RuleVfx.HEAL_COLOR
	_light.omni_range = 1.2 * _tile_size
	_light.omni_attenuation = 1.8
	_light.shadow_enabled = false
	_light.position = Vector3(0, 0.3, 0)
	_light_base = 0.45
	add_child(_light)


func _build_generic() -> void:
	var s: float = _tile_size * 0.97
	_surface_mat = VfxAssets.create_material("highlight", 6)
	_surface_mat.set_shader_parameter("color", Color(0.75, 0.35, 1.0, 0.7))
	_surface_mat.set_shader_parameter("pattern", 3)
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(s, s)
	mi.mesh = plane
	mi.material_override = _surface_mat
	mi.position = Vector3(0, 0.03, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_timer() -> void:
	var color: Color
	match type:
		TileEffectType.LAVA:
			color = LAVA_TIMER_COLOR
		TileEffectType.WALL:
			color = WALL_TIMER_COLOR
		TileEffectType.HEALING:
			color = HEAL_TIMER_COLOR
		_:
			color = Color.WHITE
	var pos: Vector3
	if type == TileEffectType.WALL:
		pos = Vector3(0.28 * _tile_size, 0.8, 0.28 * _tile_size)
	else:
		pos = Vector3(0.37 * _tile_size, 0.1, -0.37 * _tile_size)
	_timer = Node3D.new()
	_timer.name = "Timer"
	_timer.position = pos
	add_child(_timer)
	_timer_mat = VfxAssets.create_material("tile_timer", 24)
	_timer_mat.set_shader_parameter("color", color)
	var badge := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.38, 0.38)
	badge.mesh = quad
	badge.material_override = _timer_mat
	badge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_timer.add_child(badge)
	_timer_label = VfxAssets.create_label("", 64, 0.0031, Color.WHITE, 12, 26)
	_timer_color = color.lightened(0.6)
	_timer_label.modulate = _timer_color
	_timer.add_child(_timer_label)
	_timer.visible = false


func _add_emitter(p: CPUParticles3D) -> void:
	add_child(p)
	p.emitting = true
	_emitters.append(p)
