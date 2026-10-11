// SDF icon sprite for status markers, keyword emblems and previews (always on top).
// shape: 0 = snowflake, 1 = lightning bolt, 2 = skull, 3 = flame, 4 = plus, 5 = cross (X), 6 = frost ring (flat ground decal),
// 7 = fist, 8 = spear, 9 = bell (glyphs in icon_glyphs.gdshaderinc).
// background = round coin behind the glyph; billboard = camera facing (off for ground decals / oriented plates).
shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled;

#include "res://Assets/Shaders/common.gdshaderinc"
#include "res://Assets/Shaders/icon_glyphs.gdshaderinc"

uniform int shape = 0;
uniform vec4 fg_color : source_color = vec4(1.0);
uniform vec4 bg_color : source_color = vec4(0.1, 0.2, 0.4, 0.92);
uniform vec4 rim_color : source_color = vec4(0.05, 0.04, 0.03, 1.0);
uniform bool background = true;
uniform bool billboard = true;
uniform float alpha = 1.0;
uniform float energy = 1.0;
uniform float spin = 0.0;

void vertex() {
	if (billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	}
}

float sd_frost_ring(vec2 p) {
	float r = length(p);
	float a = atan(p.y, p.x);
	float spikes = pow(abs(cos(a * 6.0)), 10.0);
	return abs(r - 0.74) - 0.05 - 0.14 * spikes * smoothstep(0.5, 0.75, r);
}

void fragment() {
	vec2 p = vec2(UV.x - 0.5, 0.5 - UV.y) * 2.0;
	float r = length(p);
	float scale = background ? 1.5 : 1.0;
	vec2 g = pc_rot(TIME * spin) * p * scale;
	float d;
	if (shape == 6) {
		d = sd_frost_ring(p);
	} else {
		d = pc_icon_glyph(g, shape, TIME);
	}
	d /= scale;
	float glyph = 1.0 - smoothstep(-0.008, 0.008, d);
	float glyph_outline = 1.0 - smoothstep(0.03, 0.05, d);
	vec4 c = vec4(rim_color.rgb, 0.0);
	if (background) {
		float disc = 1.0 - smoothstep(0.83, 0.86, r);
		float outer = 1.0 - smoothstep(0.95, 0.99, r);
		float hl = clamp(1.0 - length(p - vec2(-0.3, 0.35)) * 0.9, 0.0, 1.0);
		vec3 bg = bg_color.rgb * (0.65 + 0.6 * hl);
		c = vec4(mix(rim_color.rgb, bg, disc), outer * mix(1.0, bg_color.a, disc));
	}
	if (shape == 6) {
		float glow = exp(-max(d, 0.0) * 22.0) * 0.5;
		vec3 ice = fg_color.rgb * energy;
		ALBEDO = mix(ice, vec3(1.0), glyph * 0.3);
		ALPHA = clamp((glyph * 0.85 + glow) * fg_color.a * alpha, 0.0, 1.0);
	} else {
		c.rgb = mix(c.rgb, rim_color.rgb, glyph_outline * (1.0 - glyph));
		c.a = max(c.a, glyph_outline * 0.92);
		vec3 fg = fg_color.rgb * energy;
		if (shape == 3) {
			fg = mix(vec3(1.0, 0.95, 0.55), fg_color.rgb, smoothstep(-0.22, -0.02, d)) * energy;
		}
		c.rgb = mix(c.rgb, fg, glyph);
		c.a = max(c.a, glyph);
		ALBEDO = c.rgb;
		ALPHA = clamp(c.a * alpha, 0.0, 1.0);
	}
}
