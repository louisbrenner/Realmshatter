// UI keyword emblem (canvas_item version of fx_icon): coin with a glyph from icon_glyphs.gdshaderinc.
shader_type canvas_item;

#include "res://Assets/Shaders/common.gdshaderinc"
#include "res://Assets/Shaders/icon_glyphs.gdshaderinc"

uniform int shape = 0;
uniform vec4 fg_color : source_color = vec4(1.0);
uniform vec4 bg_color : source_color = vec4(0.1, 0.2, 0.4, 0.95);
uniform vec4 rim_color : source_color = vec4(0.95, 0.75, 0.35, 1.0);

void fragment() {
	vec2 p = vec2(UV.x - 0.5, 0.5 - UV.y) * 2.0;
	float r = length(p);
	float scale = 1.55;
	float d = pc_icon_glyph(p * scale, shape, TIME) / scale;
	float aa = fwidth(r) * 1.2;
	float glyph = 1.0 - smoothstep(-aa, aa, d);
	float glyph_outline = 1.0 - smoothstep(0.04 - aa, 0.04 + aa, d);
	float disc = 1.0 - smoothstep(0.8 - aa, 0.8 + aa, r);
	float outer = 1.0 - smoothstep(0.97 - aa, 0.97 + aa, r);
	float hl = clamp(1.0 - length(p - vec2(-0.3, 0.35)) * 0.9, 0.0, 1.0);
	vec3 bg = bg_color.rgb * (0.65 + 0.6 * hl);
	vec4 c = vec4(mix(rim_color.rgb * (0.75 + 0.4 * hl), bg, disc), outer);
	c.rgb = mix(c.rgb, vec3(0.05, 0.03, 0.02), glyph_outline * (1.0 - glyph) * disc);
	vec3 fg = fg_color.rgb;
	if (shape == 3) {
		fg = mix(vec3(1.0, 0.95, 0.55), fg_color.rgb, smoothstep(-0.22, -0.02, d));
	}
	c.rgb = mix(c.rgb, fg, glyph * disc);
	COLOR = vec4(c.rgb, c.a * COLOR.a);
}
