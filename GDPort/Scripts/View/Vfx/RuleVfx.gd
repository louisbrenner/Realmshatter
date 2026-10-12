class_name RuleVfx
extends RefCounted
## One-shot effects for the v3 rules (keywords, tile effects, statuses, card returns). Like Vfx, every
## effect parents itself to the given node, positions itself in world space and frees itself.

const FIRE_COLOR := Color(1.0, 0.45, 0.08)
const ICE_COLOR := Color(0.55, 0.85, 1.0)
const CHARGE_COLOR := Color(0.75, 0.6, 1.0)
const HEAL_COLOR := Color(0.45, 1.0, 0.5)
const HEAL_GOLD := Color(1.0, 0.86, 0.42)
const SOUL_COLOR := Color(0.55, 1.0, 0.9)
const STONE_COLOR := Color(0.55, 0.5, 0.44)

static var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
static var _ice_material: StandardMaterial3D
static var _stone_material: StandardMaterial3D
static var _rock_material: StandardMaterial3D


static func _get_ice_material() -> StandardMaterial3D:
	if _ice_material == null:
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.75, 0.93, 1.0, 0.8)
		m.metallic = 0.2
		m.roughness = 0.08
		m.emission_enabled = true
		m.emission = Color(0.35, 0.7, 1.0)
		m.emission_energy_multiplier = 1.3
		m.rim_enabled = true
		m.rim = 0.8
		_ice_material = m
	return _ice_material


static func _get_stone_material() -> StandardMaterial3D:
	if _stone_material == null:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.albedo_color = STONE_COLOR
		m.roughness = 0.95
		_stone_material = m
	return _stone_material


static func _get_rock_material() -> StandardMaterial3D:
	if _rock_material == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.16, 0.09, 0.06)
		m.roughness = 0.8
		m.emission_enabled = true
		m.emission = Color(1.0, 0.35, 0.05)
		m.emission_energy_multiplier = 1.6
		_rock_material = m
	return _rock_material


static func _burst(parent: Node3D, pos: Vector3, mesh: Mesh, amount: int, lifetime: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.amount = maxi(1, amount)
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	return p


static func _fire(p: CPUParticles3D) -> void:
	p.emitting = true
	Vfx.auto_free(p, float(p.lifetime) + 0.6)


## Licking flames bursting upward (Burning hits).
static func fire_burst(parent: Node3D, pos: Vector3, power: float = 1.0) -> void:
	if parent == null:
		return
	var p: CPUParticles3D = _burst(parent, pos, VfxAssets.get_glow_quad(), int(34 * power), 0.55)
	p.explosiveness = 0.8
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.25
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 1.2 * power
	p.initial_velocity_max = 2.6 * power
	p.gravity = Vector3(0, 1.5, 0)
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.5
	p.scale_amount_curve = Vfx.linear_curve(0.6, 0.0, 1.0)
	p.color_ramp = Vfx.ramp(Color(1.0, 0.95, 0.6, 1.0), FIRE_COLOR, Color(0.7, 0.08, 0.02, 0.6), Color(0.2, 0.02, 0.0, 0.0))
	_fire(p)
	Vfx.glow_flash(parent, pos + Vector3(0, 0.2, 0), FIRE_COLOR, 1.6 * power, 0.3)
	Vfx.smoke_puff(parent, pos + Vector3(0, 0.4, 0), Color(0.2, 0.15, 0.12), 6, 0.6)
	Vfx.light_flash(parent, pos + Vector3(0, 0.6, 0), FIRE_COLOR, 3.5 * power, 2.6, 0.4)


## Lava eruption on a tile (turn-start lava damage): flames, molten blobs and smoke.
static func lava_eruption(parent: Node3D, pos: Vector3) -> void:
	if parent == null:
		return
	fire_burst(parent, pos, 1.2)
	var blobs: CPUParticles3D = _burst(parent, pos + Vector3(0, 0.05, 0), VfxAssets.get_glow_quad(), 16, 0.75)
	blobs.direction = Vector3.UP
	blobs.spread = 35.0
	blobs.initial_velocity_min = 2.2
	blobs.initial_velocity_max = 3.8
	blobs.gravity = Vector3(0, -11.0, 0)
	blobs.scale_amount_min = 0.12
	blobs.scale_amount_max = 0.24
	blobs.scale_amount_curve = Vfx.linear_curve(1.0, 0.3)
	blobs.color_ramp = Vfx.ramp(Color(1.0, 0.85, 0.4), Color(1.0, 0.35, 0.05), Color(0.5, 0.05, 0.0, 0.0))
	_fire(blobs)
	Vfx.shockwave(parent, pos + Vector3(0, 0.04, 0), FIRE_COLOR, 1.1, 0.35, 0.14)


## Ice shatter with crystals sprouting around the base and cold mist (Frozen applied).
static func ice_burst(parent: Node3D, pos: Vector3) -> void:
	if parent == null:
		return
	var shard := PrismMesh.new()
	shard.size = Vector3(0.09, 0.2, 0.06)
	shard.material = _get_ice_material()
	var p: CPUParticles3D = _burst(parent, pos + Vector3(0, 0.3, 0), shard, 18, 0.7)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.25
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.2
	p.gravity = Vector3(0, -9.0, 0)
	p.particle_flag_rotate_y = true
	p.angular_velocity_min = -600.0
	p.angular_velocity_max = 600.0
	p.scale_amount_curve = Vfx.linear_curve(1.0, 0.0, 1.0)
	_fire(p)
	ice_crystals(parent, pos, 7, 0.36, 0.75)
	Vfx.sparkle(parent, pos + Vector3(0, 0.35, 0), ICE_COLOR, 18, 0.8, 0.45)
	Vfx.smoke_puff(parent, pos + Vector3(0, 0.15, 0), Color(0.8, 0.92, 1.0), 10, 0.7)
	Vfx.shockwave(parent, pos + Vector3(0, 0.04, 0), ICE_COLOR, 1.3, 0.4, 0.12)
	Vfx.glow_flash(parent, pos + Vector3(0, 0.35, 0), ICE_COLOR, 1.8, 0.3)
	Vfx.light_flash(parent, pos + Vector3(0, 0.7, 0), ICE_COLOR, 3.0, 3.0, 0.45)


## A ring of ice crystals that grow out of the ground, hold and shrink away.
static func ice_crystals(parent: Node3D, pos: Vector3, count: int, radius: float, hold: float) -> void:
	if parent == null:
		return
	for i in range(count):
		var ang: float = TAU * i / count + _rng.randf_range(-0.2, 0.2)
		var h: float = _rng.randf_range(0.22, 0.42)
		var prism := PrismMesh.new()
		prism.size = Vector3(0.11, h, 0.09)
		var crystal := MeshInstance3D.new()
		crystal.mesh = prism
		crystal.material_override = _get_ice_material()
		crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(crystal)
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		crystal.global_position = pos + dir * radius + Vector3(0, h * 0.4, 0)
		crystal.look_at(crystal.global_position + dir, Vector3.UP)
		crystal.rotate_object_local(Vector3.RIGHT, -0.45)
		crystal.scale = Vector3(1.0, 0.01, 1.0)
		var tween: Tween = crystal.create_tween()
		tween.tween_property(crystal, "scale", Vector3.ONE, 0.14 + 0.02 * i).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_interval(hold)
		tween.tween_property(crystal, "scale", Vector3(0.3, 0.01, 0.3), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_callback(crystal.queue_free)


## Small icy crack when Frozen wears off.
static func thaw(parent: Node3D, pos: Vector3) -> void:
	if parent == null:
		return
	var shard := PrismMesh.new()
	shard.size = Vector3(0.06, 0.12, 0.05)
	shard.material = _get_ice_material()
	var p: CPUParticles3D = _burst(parent, pos + Vector3(0, 0.2, 0), shard, 10, 0.5)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.8
	p.gravity = Vector3(0, -8.0, 0)
	p.scale_amount_curve = Vfx.linear_curve(1.0, 0.0)
	_fire(p)
	Vfx.smoke_puff(parent, pos + Vector3(0, 0.15, 0), Color(0.8, 0.92, 1.0), 6, 0.5)


## Electric crackle around a point: short lightning arcs radiating out plus a glow.
static func charge_crackle(parent: Node3D, pos: Vector3, color: Color, arcs: int = 5, radius: float = 0.65, duration: float = 0.35) -> void:
	if parent == null:
		return
	var offset: float = _rng.randf() * TAU
	for i in range(arcs):
		var ang: float = offset + TAU * i / arcs
		var end: Vector3 = pos + Vector3(cos(ang) * radius, _rng.randf_range(-0.1, 0.35), sin(ang) * radius)
		var arc := LightningArc.new()
		arc.name = "Crackle"
		arc.setup(pos, end, color, duration * _rng.randf_range(0.7, 1.1))
		parent.add_child(arc)
	Vfx.glow_flash(parent, pos, color, 2.0, 0.3)
	Vfx.sparkle(parent, pos, color, 14, 0.5, radius * 0.6)
	Vfx.light_flash(parent, pos + Vector3(0, 0.4, 0), color, 4.0, 3.0, duration + 0.1)


## Soft green-gold heal: rising sparkles, a glowing ring and a "+" glyph flash.
static func heal_burst(parent: Node3D, pos: Vector3) -> void:
	if parent == null:
		return
	Vfx.sparkle(parent, pos + Vector3(0, 0.25, 0), HEAL_COLOR, 18, 0.9, 0.4)
	Vfx.sparkle(parent, pos + Vector3(0, 0.4, 0), HEAL_GOLD, 10, 1.0, 0.3)
	Vfx.shockwave(parent, pos + Vector3(0, 0.05, 0), HEAL_COLOR, 1.1, 0.5, 0.1)
	Vfx.glow_flash(parent, pos + Vector3(0, 0.3, 0), HEAL_COLOR, 1.5, 0.35)
	Vfx.light_flash(parent, pos + Vector3(0, 0.6, 0), HEAL_COLOR, 2.5, 2.5, 0.45)


## Straight piercing beam between two world points.
static func beam(parent: Node3D, from: Vector3, to: Vector3, color: Color, duration: float = 0.4, width: float = 0.24) -> void:
	if parent == null:
		return
	var main_beam := BeamEffect.new()
	main_beam.name = "Beam"
	main_beam.setup(from, to, color, duration, width)
	parent.add_child(main_beam)
	var core := BeamEffect.new()
	core.name = "BeamCore"
	core.setup(from, to, Color(1.0, 1.0, 0.95), duration * 0.8, width * 0.35)
	parent.add_child(core)
	Vfx.glow_flash(parent, from, color, 1.2, 0.2)
	Vfx.light_flash(parent, (from + to) * 0.5 + Vector3(0, 0.4, 0), color, 3.0, 4.0, duration)


## Echo: two expanding brass rings and a chime sparkle.
static func echo_ring(parent: Node3D, pos: Vector3, color: Color) -> void:
	if parent == null:
		return
	Vfx.shockwave(parent, pos + Vector3(0, 0.05, 0), color, 1.6, 0.45, 0.08)
	Vfx.shockwave(parent, pos + Vector3(0, 0.07, 0), color.lightened(0.3), 2.4, 0.65, 0.06)
	var p: CPUParticles3D = _burst(parent, pos + Vector3(0, 0.35, 0), VfxAssets.get_ring_quad(), 3, 0.55)
	p.explosiveness = 0.6
	p.gravity = Vector3.ZERO
	p.initial_velocity_max = 0.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 0.8
	p.scale_amount_curve = Vfx.linear_curve(0.3, 2.2)
	p.color_ramp = Vfx.ramp(Color(color.r, color.g, color.b, 0.9), Color(color.r, color.g, color.b, 0.0))
	_fire(p)
	Vfx.sparkle(parent, pos + Vector3(0, 0.4, 0), color, 10, 0.6, 0.4)


## Stone chunks and dust (walls rising or crumbling).
static func rubble_burst(parent: Node3D, pos: Vector3, power: float = 1.0) -> void:
	if parent == null:
		return
	var chunk := BoxMesh.new()
	chunk.size = Vector3(0.09, 0.07, 0.08)
	chunk.material = _get_stone_material()
	var p: CPUParticles3D = _burst(parent, pos + Vector3(0, 0.15, 0), chunk, int(14 * power), 0.8)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.4, 0.15, 0.4)
	p.direction = Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = 1.2 * power
	p.initial_velocity_max = 2.6 * power
	p.gravity = Vector3(0, -12.0, 0)
	p.particle_flag_rotate_y = true
	p.angular_velocity_min = -500.0
	p.angular_velocity_max = 500.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.scale_amount_curve = Vfx.linear_curve(1.0, 0.2, 1.0)
	p.color_ramp = Vfx.ramp(STONE_COLOR.lightened(0.15), STONE_COLOR.darkened(0.35))
	_fire(p)
	Vfx.dust_ring(parent, pos, Color(0.62, 0.55, 0.46), 0.5, int(18 * power))
	Vfx.smoke_puff(parent, pos + Vector3(0, 0.2, 0), Color(0.55, 0.5, 0.43), int(8 * power), 0.8)


## Arcane circle flash on the ground (generic tile spell cast).
static func magic_circle(parent: Node3D, pos: Vector3, color: Color) -> void:
	if parent == null:
		return
	Vfx.shockwave(parent, pos + Vector3(0, 0.05, 0), color, 2.2, 0.5, 0.06)
	Vfx.shockwave(parent, pos + Vector3(0, 0.06, 0), color.lightened(0.4), 1.2, 0.35, 0.1)
	Vfx.glow_flash(parent, pos + Vector3(0, 0.3, 0), color, 2.2, 0.35)
	Vfx.sparkle(parent, pos + Vector3(0, 0.3, 0), color, 16, 0.7, 0.6)


## A flaming rock falling from the sky onto 'to'. Completes on impact (coroutine; caller adds the explosion).
static func meteor(parent: Node3D, from: Vector3, to: Vector3, duration: float) -> void:
	if parent == null:
		return
	var root := Node3D.new()
	root.name = "Meteor"
	parent.add_child(root)
	root.global_position = from
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.36
	sphere.radial_segments = 10
	sphere.rings = 6
	var rock := MeshInstance3D.new()
	rock.mesh = sphere
	rock.material_override = _get_rock_material()
	root.add_child(rock)
	var glow := MeshInstance3D.new()
	glow.mesh = VfxAssets.get_glow_quad()
	glow.scale = Vector3.ONE * 1.2
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.set_instance_shader_parameter("tint", FIRE_COLOR)
	root.add_child(glow)
	var light := OmniLight3D.new()
	light.light_color = FIRE_COLOR
	light.light_energy = 4.0
	light.omni_range = 4.0
	root.add_child(light)
	var trail := CPUParticles3D.new()
	trail.mesh = VfxAssets.get_glow_quad()
	trail.amount = 70
	trail.lifetime = 0.4
	trail.local_coords = false
	trail.spread = 180.0
	trail.initial_velocity_min = 0.1
	trail.initial_velocity_max = 0.5
	trail.gravity = Vector3(0, 0.5, 0)
	trail.scale_amount_min = 0.35
	trail.scale_amount_max = 0.7
	trail.scale_amount_curve = Vfx.linear_curve(1.0, 0.0)
	trail.color_ramp = Vfx.ramp(Color(1.0, 0.9, 0.5), FIRE_COLOR, Color(0.3, 0.05, 0.02, 0.0))
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(trail)
	trail.emitting = true
	var tween: Tween = root.create_tween()
	tween.tween_property(root, "global_position", to, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
	if not is_instance_valid(root):
		return
	trail.emitting = false
	rock.visible = false
	glow.visible = false
	light.visible = false
	Vfx.auto_free(root, 0.5)


## Undying: a pale soul wisp rises from 'from' and flies off in an arc toward 'to' (the owner's deck).
## Completes when it arrives (coroutine).
static func soul_wisp(parent: Node3D, from: Vector3, to: Vector3, duration: float) -> void:
	if parent == null:
		return
	var root := Node3D.new()
	root.name = "SoulWisp"
	parent.add_child(root)
	root.global_position = from
	var glow := MeshInstance3D.new()
	glow.mesh = VfxAssets.get_glow_quad()
	glow.scale = Vector3.ONE * 0.9
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.set_instance_shader_parameter("tint", SOUL_COLOR)
	root.add_child(glow)
	var skull: MeshInstance3D = VfxAssets.create_icon(FxIconShape.SKULL, 0.36, Color(0.85, 1.0, 0.95), Color(0.0, 0.0, 0.0, 0.0), false, 34)
	root.add_child(skull)
	var light := OmniLight3D.new()
	light.light_color = SOUL_COLOR
	light.light_energy = 2.5
	light.omni_range = 2.5
	root.add_child(light)
	var trail := CPUParticles3D.new()
	trail.mesh = VfxAssets.get_glow_quad()
	trail.amount = 50
	trail.lifetime = 0.5
	trail.local_coords = false
	trail.spread = 180.0
	trail.initial_velocity_min = 0.05
	trail.initial_velocity_max = 0.35
	trail.gravity = Vector3(0, 0.6, 0)
	trail.scale_amount_min = 0.2
	trail.scale_amount_max = 0.45
	trail.scale_amount_curve = Vfx.linear_curve(1.0, 0.0)
	trail.color_ramp = Vfx.ramp(Color(1.0, 1.0, 1.0, 0.9), SOUL_COLOR, Color(0.2, 0.6, 0.7, 0.0))
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(trail)
	trail.emitting = true

	var p1: Vector3 = from + Vector3(0, 1.8, 0)
	var p2: Vector3 = to + Vector3(0, 1.4, 0)
	var tween: Tween = root.create_tween()
	tween.tween_method(func(t: float) -> void:
		if not is_instance_valid(root):
			return
		var u: float = 1.0 - t
		root.global_position = from * (u * u * u) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + to * (t * t * t) \
			+ Vector3(sin(t * 18.0) * 0.08, 0.0, 0.0)
		root.scale = Vector3.ONE * (1.0 - 0.45 * t)
	, 0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	if not is_instance_valid(root):
		return
	Vfx.glow_flash(parent, to, SOUL_COLOR, 1.4, 0.3)
	trail.emitting = false
	glow.visible = false
	skull.visible = false
	light.visible = false
	Vfx.auto_free(root, 0.6)


## A small card back flips out of 'from' and flies in an arc to 'to' (card returns to the deck; coroutine).
static func card_to_deck(parent: Node3D, from: Vector3, to: Vector3, owner_color: Color, duration: float) -> void:
	if parent == null:
		return
	var root := Node3D.new()
	root.name = "CardToDeck"
	parent.add_child(root)
	root.global_position = from
	var back := StandardMaterial3D.new()
	back.albedo_color = Color(0.14, 0.12, 0.3).lerp(owner_color, 0.25)
	back.roughness = 0.5
	back.emission_enabled = true
	back.emission = owner_color
	back.emission_energy_multiplier = 0.35
	var rim_box := BoxMesh.new()
	rim_box.size = Vector3(0.42, 0.012, 0.58)
	var rim := MeshInstance3D.new()
	rim.mesh = rim_box
	rim.material_override = VfxAssets.create_gold_material(0.5)
	root.add_child(rim)
	var back_box := BoxMesh.new()
	back_box.size = Vector3(0.36, 0.02, 0.52)
	var back_mesh := MeshInstance3D.new()
	back_mesh.mesh = back_box
	back_mesh.material_override = back
	root.add_child(back_mesh)
	var trail := CPUParticles3D.new()
	trail.mesh = VfxAssets.get_sparkle_quad()
	trail.amount = 20
	trail.lifetime = 0.4
	trail.local_coords = false
	trail.spread = 180.0
	trail.initial_velocity_min = 0.05
	trail.initial_velocity_max = 0.3
	trail.gravity = Vector3.ZERO
	trail.scale_amount_min = 0.1
	trail.scale_amount_max = 0.2
	trail.scale_amount_curve = Vfx.linear_curve(1.0, 0.0)
	trail.color_ramp = Vfx.ramp(Color(1.0, 0.9, 0.6), Color(owner_color.r, owner_color.g, owner_color.b, 0.0))
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(trail)
	trail.emitting = true
	root.scale = Vector3.ONE * 0.2

	var height: float = 1.1 + 0.08 * from.distance_to(to)
	var tween: Tween = root.create_tween()
	tween.tween_method(func(t: float) -> void:
		if not is_instance_valid(root):
			return
		root.global_position = from.lerp(to, t) + Vector3(0, height * 4.0 * t * (1.0 - t) + 0.4 * t, 0)
		var s: float = lerpf(0.2, 1.0, t / 0.15) if t < 0.15 else lerpf(1.0, 0.55, (t - 0.15) / 0.85)
		root.scale = Vector3.ONE * s
		root.rotation = Vector3(sin(t * PI) * 0.9, t * TAU * 1.5, 0.0)
	, 0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	if not is_instance_valid(root):
		return
	Vfx.glow_flash(parent, root.global_position, owner_color.lightened(0.4), 1.0, 0.25)
	root.queue_free()
