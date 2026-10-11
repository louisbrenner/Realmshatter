class_name VfxAssets
extends RefCounted
## Lazily loaded, shared shaders, meshes and fonts for the procedural visuals and VFX.

const SHADER_DIR := "res://Assets/Shaders/"
const CARD_FONT_PATH := "res://Resources/UI/CardFont.tres"

static var _shaders: Dictionary = {}
static var _font: Font
static var _glow_material: ShaderMaterial
static var _sparkle_material: ShaderMaterial
static var _smoke_material: ShaderMaterial
static var _glow_quad: QuadMesh
static var _sparkle_quad: QuadMesh
static var _smoke_quad: QuadMesh
static var _ring_material: ShaderMaterial
static var _ring_quad: QuadMesh


## Loads (once) a shader from Assets/Shaders by file name without extension.
static func get_shader(name: String) -> Shader:
	var shader: Shader = _shaders.get(name, null)
	if shader != null:
		return shader
	shader = load(SHADER_DIR + name + ".gdshader") as Shader
	_shaders[name] = shader
	return shader


## Creates a new (unshared) ShaderMaterial using the named shader.
static func create_material(shader_name: String, render_priority: int = 0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = get_shader(shader_name)
	mat.render_priority = render_priority
	return mat


## The bold serif font used for cards, badges and popups.
static var card_font: Font:
	get:
		if _font == null:
			_font = load(CARD_FONT_PATH) as Font
		return _font

## Regular serif for card body text and info panels (MSDF: stays sharp when cards are scaled).
static var card_text_font: Font:
	get:
		if _text_font == null:
			_text_font = _create_sharp_font(400)
		return _text_font

## Bold serif for card titles, badges and keyword names (MSDF).
static var card_text_bold_font: Font:
	get:
		if _text_bold_font == null:
			_text_bold_font = _create_sharp_font(700)
		return _text_bold_font

static var _text_font: Font
static var _text_bold_font: Font


static func _create_sharp_font(weight: int) -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Georgia", "Palatino Linotype", "Book Antiqua", "Times New Roman", "Serif"])
	font.font_weight = weight
	font.multichannel_signed_distance_field = true
	font.msdf_pixel_range = 16
	font.msdf_size = 48
	font.generate_mipmaps = true
	return font


## Billboard quad with an additive soft glow dot (shared material, tint via instance uniform).
static var glow_quad: QuadMesh:
	get:
		if _glow_quad == null:
			_glow_material = create_material("vfx_particle", 4)
			_glow_material.set_shader_parameter("shape", 0)
			_glow_quad = QuadMesh.new()
			_glow_quad.size = Vector2(1.0, 1.0)
			_glow_quad.material = _glow_material
		return _glow_quad

## Billboard quad with an additive four-point star sparkle.
static var sparkle_quad: QuadMesh:
	get:
		if _sparkle_quad == null:
			_sparkle_material = create_material("vfx_particle", 4)
			_sparkle_material.set_shader_parameter("shape", 1)
			_sparkle_material.set_shader_parameter("energy", 4.0)
			_sparkle_quad = QuadMesh.new()
			_sparkle_quad.size = Vector2(1.0, 1.0)
			_sparkle_quad.material = _sparkle_material
		return _sparkle_quad

## Billboard quad with an alpha-blended smoke puff.
static var smoke_quad: QuadMesh:
	get:
		if _smoke_quad == null:
			_smoke_material = create_material("vfx_smoke", 2)
			_smoke_quad = QuadMesh.new()
			_smoke_quad.size = Vector2(1.0, 1.0)
			_smoke_quad.material = _smoke_material
		return _smoke_quad

## Billboard quad with an additive thin ring (bubbles, ripples).
static var ring_quad: QuadMesh:
	get:
		if _ring_quad == null:
			_ring_material = create_material("vfx_particle", 4)
			_ring_material.set_shader_parameter("shape", 2)
			_ring_quad = QuadMesh.new()
			_ring_quad.size = Vector2(1.0, 1.0)
			_ring_quad.material = _ring_material
		return _ring_quad


## Creates an SDF icon sprite (see fx_icon.gdshader for shapes), camera facing and always on top.
static func create_icon(shape: int, size: float, fg: Color, bg: Color, background: bool = true, priority: int = 30) -> MeshInstance3D:
	var mat: ShaderMaterial = create_material("fx_icon", priority)
	mat.set_shader_parameter("shape", shape)
	mat.set_shader_parameter("fg_color", fg)
	mat.set_shader_parameter("bg_color", bg)
	mat.set_shader_parameter("background", background)
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Creates a gold metal material (used for rims, trims, coins).
static func create_gold_material(emission: float = 0.08) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.77, 0.36)
	mat.metallic = 0.85
	mat.roughness = 0.3
	mat.metallic_specular = 0.7
	mat.emission_enabled = emission > 0.0
	mat.emission = Color(1.0, 0.7, 0.3)
	mat.emission_energy_multiplier = emission
	return mat


## Creates a camera-facing Label3D in the card font.
static func create_label(text: String, font_size: int, pixel_size: float, color: Color, outline: int = 14, priority: int = 30) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = card_font
	label.font_size = font_size
	label.outline_size = outline
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_modulate = Color(0.05, 0.03, 0.02)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.shaded = false
	label.render_priority = priority
	label.outline_render_priority = priority - 1
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return label


## Creates a billboard badge quad (see badge.gdshader for shapes).
static func create_badge(shape: int, size: float, fill: Color, priority: int = 28) -> MeshInstance3D:
	var mat: ShaderMaterial = create_material("badge", priority)
	mat.set_shader_parameter("shape", shape)
	mat.set_shader_parameter("fill_color", fill)
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
