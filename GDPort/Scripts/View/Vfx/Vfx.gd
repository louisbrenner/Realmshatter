class_name Vfx
extends RefCounted
## Factory for one-shot procedural effects (particles, flashes, popups, projectiles).
## Every effect parents itself to the given node, positions in world space and frees itself.

static var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
static var _coin_material: StandardMaterial3D
static var _coin_mesh: CylinderMesh


## Frees a node after the given (scaled) time, if it still exists.
static func auto_free(node: Node, seconds: float) -> void:
	if node == null or not node.is_inside_tree():
		if node != null:
			node.queue_free()
		return
	var timer: SceneTreeTimer = node.get_tree().create_timer(seconds)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(node):
			node.queue_free()
	)


## Creates a gradient from a list of colors spread evenly over 0..1.
## C# params Color[]: call as Vfx.ramp(c1, c2, c3); a single Array argument (Vfx.ramp([c1, c2])) also works.
static func ramp(...colors: Array) -> Gradient:
	var list: Array = colors
	if list.size() == 1 and (list[0] is Array or list[0] is PackedColorArray):
		list = Array(list[0])
	var packed_colors := PackedColorArray()
	var offsets := PackedFloat32Array()
	for i in range(list.size()):
		packed_colors.append(list[i])
		offsets.append(float(i) / (list.size() - 1) if list.size() > 1 else 0.0)
	var gradient := Gradient.new()
	gradient.colors = packed_colors
	gradient.offsets = offsets
	return gradient


## Creates a linear curve from start to end value over the particle lifetime.
static func linear_curve(start: float, end: float, mid: float = -1.0) -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, start))
	if mid >= 0.0:
		curve.add_point(Vector2(0.3, mid))
	curve.add_point(Vector2(1.0, end))
	return curve


static func _create_burst(parent: Node3D, pos: Vector3, mesh: Mesh, amount: int, lifetime: float) -> CPUParticles3D:
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
	auto_free(p, float(p.lifetime) + 0.6)


## Hot sparks flying out of an impact point plus a short flare.
static func impact_sparks(parent: Node3D, pos: Vector3, color: Color, amount: int = 40, power: float = 1.0) -> void:
	if parent == null:
		return
	var p: CPUParticles3D = _create_burst(parent, pos, VfxAssets.get_glow_quad(), amount, 0.5)
	p.direction = Vector3.UP
	p.spread = 85.0
	p.initial_velocity_min = 2.5 * power
	p.initial_velocity_max = 5.5 * power
	p.gravity = Vector3(0, -9.0, 0)
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.scale_amount_min = 0.14
	p.scale_amount_max = 0.34
	p.scale_amount_curve = linear_curve(1.0, 0.0)
	p.color_ramp = ramp(Color(1.0, 1.0, 0.9, 1.0), color, Color(color.r, color.g * 0.5, color.b * 0.3, 0.0))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.08
	_fire(p)
	glow_flash(parent, pos, color, 1.6 * power, 0.2)
	shockwave(parent, Vector3(pos.x, 0.04, pos.z), color, 1.2 * power, 0.32, 0.12)


## A big billboard glow that shrinks and fades quickly.
static func glow_flash(parent: Node3D, pos: Vector3, color: Color, size: float, duration: float) -> void:
	if parent == null:
		return
	var flash := MeshInstance3D.new()
	flash.mesh = VfxAssets.get_glow_quad()
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(flash)
	flash.global_position = pos
	flash.scale = Vector3.ONE * size * 0.4
	flash.set_instance_shader_parameter("tint", color)
	var tween: Tween = flash.create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * size, duration * 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(c: Color) -> void: flash.set_instance_shader_parameter("tint", c),
		color, Color(color.r, color.g, color.b, 0.0), duration)
	tween.chain().tween_callback(flash.queue_free)


## Soft rising smoke or dust.
static func smoke_puff(parent: Node3D, pos: Vector3, color: Color, amount: int = 10, size: float = 0.6) -> void:
	if parent == null:
		return
	var p: CPUParticles3D = _create_burst(parent, pos, VfxAssets.get_smoke_quad(), amount, 0.95)
	p.explosiveness = 0.85
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.3
	p.gravity = Vector3(0, 0.7, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = 0.5 * size
	p.scale_amount_max = 1.0 * size
	p.scale_amount_curve = linear_curve(0.5, 1.3)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.2
	p.color_ramp = ramp(Color(color.r, color.g, color.b, 0.6), Color(color.r, color.g, color.b, 0.35), Color(color.r, color.g, color.b, 0.0))
	_fire(p)


## A ring of dust rolling outwards along the ground.
static func dust_ring(parent: Node3D, pos: Vector3, color: Color, radius: float = 0.45, amount: int = 18) -> void:
	if parent == null:
		return
	var p: CPUParticles3D = _create_burst(parent, pos + Vector3(0, 0.08, 0), VfxAssets.get_smoke_quad(), amount, 0.7)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = radius
	p.emission_ring_inner_radius = radius * 0.85
	p.emission_ring_height = 0.02
	p.direction = Vector3(1, 0, 0)
	p.spread = 180.0
	p.flatness = 1.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.8
	p.radial_accel_min = 2.5
	p.radial_accel_max = 4.0
	p.damping_min = 2.0
	p.damping_max = 3.0
	p.gravity = Vector3(0, 0.3, 0)
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.45
	p.scale_amount_curve = linear_curve(0.6, 1.4)
	p.color_ramp = ramp(Color(color.r, color.g, color.b, 0.65), Color(color.r, color.g, color.b, 0.0))
	_fire(p)


## Breaks a token into tumbling fragments with a flash and a puff of smoke.
static func shatter(parent: Node3D, pos: Vector3, body_color: Color, accent_color: Color) -> void:
	if parent == null:
		return
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.4
	mat.emission_enabled = true
	mat.emission = accent_color * 0.4
	var shard := PrismMesh.new()
	shard.size = Vector3(0.16, 0.1, 0.12)
	shard.material = mat
	var p: CPUParticles3D = _create_burst(parent, pos, shard, 22, 0.85)
	p.direction = Vector3.UP
	p.spread = 75.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -13.0, 0)
	p.particle_flag_rotate_y = true
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.scale_amount_curve = linear_curve(1.0, 0.0, 1.0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3
	p.color_ramp = ramp(body_color.lightened(0.2), accent_color, body_color.darkened(0.4))
	_fire(p)

	var gold_shard := BoxMesh.new()
	gold_shard.size = Vector3(0.09, 0.03, 0.05)
	gold_shard.material = VfxAssets.create_gold_material(0.6)
	var g: CPUParticles3D = _create_burst(parent, pos, gold_shard, 12, 0.8)
	g.direction = Vector3.UP
	g.spread = 90.0
	g.initial_velocity_min = 2.0
	g.initial_velocity_max = 4.5
	g.gravity = Vector3(0, -12.0, 0)
	g.particle_flag_rotate_y = true
	g.angular_velocity_min = -900.0
	g.angular_velocity_max = 900.0
	g.scale_amount_curve = linear_curve(1.0, 0.0, 1.0)
	g.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	g.emission_ring_axis = Vector3.UP
	g.emission_ring_radius = 0.42
	g.emission_ring_inner_radius = 0.36
	g.emission_ring_height = 0.05
	_fire(g)

	impact_sparks(parent, pos + Vector3(0, 0.15, 0), accent_color.lightened(0.3), 24, 0.8)
	smoke_puff(parent, pos, Color(0.25, 0.22, 0.2), 12, 0.9)
	glow_flash(parent, pos + Vector3(0, 0.3, 0), Color(1.0, 0.6, 0.3), 1.9, 0.3)


## Golden shards and a ring when a shield is broken.
static func shield_shatter(parent: Node3D, pos: Vector3) -> void:
	if parent == null:
		return
	var gold := Color(1.0, 0.82, 0.35)
	var shard := PrismMesh.new()
	shard.size = Vector3(0.12, 0.04, 0.1)
	shard.material = VfxAssets.create_gold_material(1.5)
	var p: CPUParticles3D = _create_burst(parent, pos, shard, 26, 0.7)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.5
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0, -8.0, 0)
	p.particle_flag_rotate_y = true
	p.angular_velocity_min = -800.0
	p.angular_velocity_max = 800.0
	p.scale_amount_curve = linear_curve(1.0, 0.0, 1.0)
	_fire(p)
	sparkle(parent, pos, gold, 18, 0.6)
	shockwave(parent, Vector3(pos.x, 0.05, pos.z), gold, 1.3, 0.4, 0.1)
	glow_flash(parent, pos, gold, 1.8, 0.25)
	light_flash(parent, pos + Vector3(0, 0.5, 0), gold, 3.0, 3.0, 0.3)


## Small golden ripple when a shield absorbs damage but holds.
static func shield_block(parent: Node3D, pos: Vector3) -> void:
	var gold := Color(1.0, 0.85, 0.4)
	shockwave(parent, Vector3(pos.x, 0.05, pos.z), gold, 1.0, 0.3, 0.08)
	sparkle(parent, pos, gold, 8, 0.45)


## Twinkling star sparkles drifting upwards.
static func sparkle(parent: Node3D, pos: Vector3, color: Color, amount: int = 16, lifetime: float = 0.8, radius: float = 0.45) -> void:
	if parent == null:
		return
	var p: CPUParticles3D = _create_burst(parent, pos, VfxAssets.get_sparkle_quad(), amount, lifetime)
	p.explosiveness = 0.55
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3.UP
	p.spread = 40.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.8
	p.gravity = Vector3(0, 0.6, 0)
	p.scale_amount_min = 0.22
	p.scale_amount_max = 0.45
	p.scale_amount_curve = linear_curve(0.0, 0.0, 1.0)
	p.color_ramp = ramp(Color(1.0, 1.0, 1.0, 1.0), color, Color(color.r, color.g, color.b, 0.0))
	_fire(p)


## Gold coins popping out of a tile plus sparkles.
static func coin_fountain(parent: Node3D, pos: Vector3, coins: int = 6) -> void:
	if parent == null:
		return
	if _coin_material == null:
		_coin_material = VfxAssets.create_gold_material(0.9)
	if _coin_mesh == null:
		_coin_mesh = CylinderMesh.new()
		_coin_mesh.top_radius = 0.075
		_coin_mesh.bottom_radius = 0.075
		_coin_mesh.height = 0.02
		_coin_mesh.radial_segments = 12
		_coin_mesh.rings = 1
		_coin_mesh.material = _coin_material
	var p: CPUParticles3D = _create_burst(parent, pos + Vector3(0, 0.1, 0), _coin_mesh, coins, 0.95)
	p.explosiveness = 0.8
	p.direction = Vector3.UP
	p.spread = 28.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 4.3
	p.gravity = Vector3(0, -8.0, 0)
	p.particle_flag_rotate_y = true
	p.angular_velocity_min = 300.0
	p.angular_velocity_max = 700.0
	p.scale_amount_curve = linear_curve(1.0, 0.2, 1.0)
	_fire(p)
	sparkle(parent, pos + Vector3(0, 0.3, 0), Color(1.0, 0.85, 0.35), 12, 0.8, 0.4)


## Expanding ground ring.
static func shockwave(parent: Node3D, pos: Vector3, color: Color, radius: float, duration: float, thickness: float = 0.12) -> void:
	if parent == null:
		return
	var mat: ShaderMaterial = VfxAssets.create_material("shockwave", 3)
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("thickness", thickness)
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 2.0, radius * 2.0)
	var ring := MeshInstance3D.new()
	ring.mesh = plane
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ring)
	ring.global_position = pos
	var tween: Tween = ring.create_tween()
	tween.tween_method(func(v: float) -> void: mat.set_shader_parameter("progress", v), 0.0, 1.0, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_callback(ring.queue_free)


## A short-lived point light flash.
static func light_flash(parent: Node3D, pos: Vector3, color: Color, energy: float, light_range: float, duration: float) -> void:
	if parent == null:
		return
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.shadow_enabled = false
	parent.add_child(light)
	light.global_position = pos
	var tween: Tween = light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(light.queue_free)


## Big punchy damage number on a splat that pops, arcs upward and fades.
static func damage_number(parent: Node3D, pos: Vector3, text: String, splat_color: Color) -> void:
	if parent == null:
		return
	var root := Node3D.new()
	root.name = "DamageNumber"
	parent.add_child(root)
	root.global_position = pos + Vector3(0, 0.75, 0)
	root.scale = Vector3.ONE * 0.2

	var splat: MeshInstance3D = VfxAssets.create_badge(4, 0.95, splat_color, 40)
	root.add_child(splat)
	var label: Label3D = VfxAssets.create_label(text, 104, 0.0042, Color.WHITE, 20, 42)
	root.add_child(label)
	var splat_mat := splat.material_override as ShaderMaterial

	var side: float = _rng.randf_range(-0.25, 0.25)
	var start: Vector3 = root.global_position
	var tween: Tween = root.create_tween()
	tween.tween_property(root, "scale", Vector3.ONE * 1.35, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(root, "scale", Vector3.ONE, 0.08)
	var move: Tween = root.create_tween()
	move.tween_method(func(t: float) -> void:
		if is_instance_valid(root):
			root.global_position = start + Vector3(side * t, 0.55 * sin(t * PI * 0.5), 0)
	, 0.0, 1.0, 0.85)
	var fade: Tween = root.create_tween()
	fade.set_parallel(true)
	fade.tween_method(func(a: float) -> void: splat_mat.set_shader_parameter("alpha", a), 1.0, 0.0, 0.3).set_delay(0.6)
	fade.tween_property(label, "modulate:a", 0.0, 0.3).set_delay(0.6)
	fade.tween_property(label, "outline_modulate:a", 0.0, 0.3).set_delay(0.6)
	fade.chain().tween_callback(root.queue_free)


## Popping, rising text (info, "+1", "Arc!", ...).
static func popup_text(parent: Node3D, pos: Vector3, text: String, color: Color, font_size: int = 64, lift: float = 1.2) -> void:
	if parent == null:
		return
	var label: Label3D = VfxAssets.create_label(text, font_size, 0.004, color, 14, 44)
	parent.add_child(label)
	label.global_position = pos + Vector3(0, lift, 0)
	label.scale = Vector3.ONE * 0.3
	var tween: Tween = label.create_tween()
	tween.tween_property(label, "scale", Vector3.ONE * 1.15, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector3.ONE, 0.08)
	tween.set_parallel(true)
	tween.tween_property(label, "global_position", label.global_position + Vector3(0, 0.55, 0), 0.8) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.35).set_delay(0.45)
	tween.tween_property(label, "outline_modulate:a", 0.0, 0.35).set_delay(0.45)
	tween.chain().tween_callback(label.queue_free)


## Fires a glowing projectile with a trail along an arc. Completes on impact (coroutine: await it).
static func projectile(parent: Node3D, from: Vector3, to: Vector3, color: Color, duration: float) -> void:
	if parent == null:
		return
	var root := Node3D.new()
	root.name = "Projectile"
	parent.add_child(root)
	root.global_position = from

	var head := MeshInstance3D.new()
	head.mesh = VfxAssets.get_glow_quad()
	head.scale = Vector3.ONE * 0.7
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.set_instance_shader_parameter("tint", color)
	root.add_child(head)
	var core := MeshInstance3D.new()
	core.mesh = VfxAssets.get_glow_quad()
	core.scale = Vector3.ONE * 0.22
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.set_instance_shader_parameter("tint", Color(1.0, 1.0, 0.95))
	root.add_child(core)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 2.5
	light.omni_range = 2.2
	root.add_child(light)

	var trail := CPUParticles3D.new()
	trail.mesh = VfxAssets.get_glow_quad()
	trail.amount = 48
	trail.lifetime = 0.32
	trail.local_coords = false
	trail.explosiveness = 0.0
	trail.spread = 180.0
	trail.initial_velocity_min = 0.05
	trail.initial_velocity_max = 0.3
	trail.gravity = Vector3.ZERO
	trail.scale_amount_min = 0.25
	trail.scale_amount_max = 0.42
	trail.scale_amount_curve = linear_curve(1.0, 0.0)
	trail.color_ramp = ramp(Color(1.0, 1.0, 0.9, 0.9), color, Color(color.r, color.g, color.b, 0.0))
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(trail)
	trail.emitting = true

	var dist: float = from.distance_to(to)
	var height: float = 0.25 + 0.14 * dist
	var tween: Tween = root.create_tween()
	tween.tween_method(func(t: float) -> void:
		if is_instance_valid(root):
			root.global_position = from.lerp(to, t) + Vector3(0, height * 4.0 * t * (1.0 - t), 0)
	, 0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tween.finished
	if not is_instance_valid(root):
		return
	trail.emitting = false
	head.visible = false
	core.visible = false
	light.visible = false
	auto_free(root, 0.45)


## Crackling lightning arc between two world points.
static func lightning(parent: Node3D, from: Vector3, to: Vector3, color: Color, duration: float) -> void:
	if parent == null:
		return
	var arc := LightningArc.new()
	arc.name = "Lightning"
	arc.setup(from, to, color, duration)
	parent.add_child(arc)
	glow_flash(parent, from, color, 1.0, 0.2)
	glow_flash(parent, to, color, 1.4, 0.25)
	light_flash(parent, (from + to) * 0.5 + Vector3(0, 0.5, 0), color, 3.0, 4.0, duration)


## Glowing motes spiralling into a piece, ending in a burst.
static func spell_swirl(parent: Node3D, pos: Vector3, primary: Color, secondary: Color, duration: float) -> SwirlEffect:
	if parent == null:
		return null
	var swirl := SwirlEffect.new()
	swirl.name = "SpellSwirl"
	swirl.setup(primary, secondary, duration)
	parent.add_child(swirl)
	swirl.global_position = pos
	return swirl
