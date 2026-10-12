class_name VfxAssets
extends RefCounted
## Lazily loaded, shared shaders, meshes and fonts for the procedural visuals and VFX.
## C# static properties with getters are exposed as static funcs (get_card_font(), get_glow_quad(), ...);
## the same values are also reachable via property syntax (VfxAssets.card_font, VfxAssets.glow_quad, ...).

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
static func get_card_font() -> Font:
	if _font == null:
		_font = load(CARD_FONT_PATH) as Font
	return _font


## Regular serif for card body text and info panels (MSDF: stays sharp when cards are scaled).
static func get_card_text_font() -> Font:
	if _text_font == null:
		_text_font = _create_sharp_font(400)
	return _text_font


## Bold serif for card titles, badges and keyword names (MSDF).
static func get_card_text_bold_font() -> Font:
	if _text_bold_font == null:
		_text_bold_font = _create_sharp_font(700)
	return _text_bold_font


static var _text_font: Font
static var _text_bold_font: Font
static var _number_font: Font


## Bold serif for the numbers on badges (MSDF, lining figures): every digit has the same height and sits on
## the baseline, so numbers stay centred in their badge (Georgia's old-style 3, 4, 5, 7, 9 hang below it).
static func get_number_font() -> Font:
	if _number_font == null:
		var base := SystemFont.new()
		base.font_names = PackedStringArray(["Palatino Linotype", "Book Antiqua", "Times New Roman", "Serif"])
		base.font_weight = 700
		base.multichannel_signed_distance_field = true
		base.msdf_pixel_range = 16
		base.msdf_size = 48
		base.generate_mipmaps = true
		var variation := FontVariation.new()
		variation.base_font = base
		var features := {}
		features[TextServerManager.get_primary_interface().name_to_tag("lnum")] = 1
		variation.opentype_features = features
		_number_font = variation
	return _number_font


static var _digit_drops: Dictionary = {}


## How far (font pixels, positive = lower) the visual centre of NumberFont's digits sits below the centre of
## a vertically centred text line. Shift the text up by this value to centre the ink inside a badge.
## Measured from the real glyph boxes, so it also holds for whatever fallback font the platform picks.
static func digit_drop(font_size: int) -> float:
	if _digit_drops.has(font_size):
		return _digit_drops[font_size]
	var font: Font = get_number_font()
	var ts: TextServer = TextServerManager.get_primary_interface()
	var shaped: RID = ts.create_shaped_text()
	var sum := 0.0
	var count := 0
	ts.shaped_text_add_string(shaped, "0123456789", font.get_rids(), font_size, font.get_opentype_features())
	for glyph: Dictionary in ts.shaped_text_get_glyphs(shaped):
		var rid: RID = glyph["font_rid"]
		var index: int = int(glyph["index"])
		var size := Vector2i(font_size, 0)
		var box: Vector2 = ts.font_get_glyph_size(rid, size, index)
		if not rid.is_valid() or box.y <= 0.0:
			continue
		# Glyph boxes are padded evenly on both sides, so their middle is the ink middle (relative to the baseline).
		sum += ts.font_get_glyph_offset(rid, size, index).y + box.y * 0.5
		count += 1
	ts.free_rid(shaped)
	var ascent: float = font.get_ascent(font_size)
	var descent: float = font.get_descent(font_size)
	var drop: float = (ascent - descent) * 0.5 + sum / count if count > 0 else 0.0
	_digit_drops[font_size] = drop
	return drop


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
static func get_glow_quad() -> QuadMesh:
	if _glow_quad == null:
		_glow_material = create_material("vfx_particle", 4)
		_glow_material.set_shader_parameter("shape", 0)
		_glow_quad = QuadMesh.new()
		_glow_quad.size = Vector2(1.0, 1.0)
		_glow_quad.material = _glow_material
	return _glow_quad


## Billboard quad with an additive four-point star sparkle.
static func get_sparkle_quad() -> QuadMesh:
	if _sparkle_quad == null:
		_sparkle_material = create_material("vfx_particle", 4)
		_sparkle_material.set_shader_parameter("shape", 1)
		_sparkle_material.set_shader_parameter("energy", 4.0)
		_sparkle_quad = QuadMesh.new()
		_sparkle_quad.size = Vector2(1.0, 1.0)
		_sparkle_quad.material = _sparkle_material
	return _sparkle_quad


## Billboard quad with an alpha-blended smoke puff.
static func get_smoke_quad() -> QuadMesh:
	if _smoke_quad == null:
		_smoke_material = create_material("vfx_smoke", 2)
		_smoke_quad = QuadMesh.new()
		_smoke_quad.size = Vector2(1.0, 1.0)
		_smoke_quad.material = _smoke_material
	return _smoke_quad


## Billboard quad with an additive thin ring (bubbles, ripples).
static func get_ring_quad() -> QuadMesh:
	if _ring_quad == null:
		_ring_material = create_material("vfx_particle", 4)
		_ring_material.set_shader_parameter("shape", 2)
		_ring_quad = QuadMesh.new()
		_ring_quad.size = Vector2(1.0, 1.0)
		_ring_quad.material = _ring_material
	return _ring_quad


# Property-syntax aliases of the getters above (compatibility for callers using VfxAssets.card_font etc.).
static var card_font: Font:
	get:
		return get_card_font()
static var card_text_font: Font:
	get:
		return get_card_text_font()
static var card_text_bold_font: Font:
	get:
		return get_card_text_bold_font()
static var number_font: Font:
	get:
		return get_number_font()
static var glow_quad: QuadMesh:
	get:
		return get_glow_quad()
static var sparkle_quad: QuadMesh:
	get:
		return get_sparkle_quad()
static var smoke_quad: QuadMesh:
	get:
		return get_smoke_quad()
static var ring_quad: QuadMesh:
	get:
		return get_ring_quad()


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
	label.font = get_card_font()
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
