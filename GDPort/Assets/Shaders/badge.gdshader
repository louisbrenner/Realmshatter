// Camera-facing stat badge drawn with SDFs (always on top).
// shape: 0 = attack (bronze diamond crest), 1 = health (red diamond crest), 2 = shield, 3 = order coin,
//        4 = damage splat, 5 = gem, 6 = soft glow disc,
//        7 = token attack crest, 8 = token health crest, 9 = token shield (7-9 fill the quad).
shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled;

#include "res://Assets/Shaders/common.gdshaderinc"

uniform int shape = 0;
uniform vec4 fill_color : source_color = vec4(1.0, 0.8, 0.2, 1.0);
uniform vec4 rim_color : source_color = vec4(0.18, 0.1, 0.03, 1.0);
uniform float alpha = 1.0;
uniform bool billboard = true;

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

void fragment() {
	vec2 p = vec2(UV.x - 0.5, 0.5 - UV.y) * 2.0;
	float hl = clamp(1.0 - length(p - vec2(-0.25, 0.3)) * 0.85, 0.0, 1.0);
	vec3 fill = fill_color.rgb * (0.62 + 0.62 * hl);
	float d;
	float outline = 0.08;
	if (shape == 0 || shape == 7) {
		// Bevelled diamond crest with a faintly engraved sword behind the number.
		float k = shape == 7 ? 0.9 : 1.0;
		d = pc_sd_crest(p * k) / k;
		float inner = pc_sd_crest(p * k * 1.28) / (k * 1.28);
		fill = fill_color.rgb * (0.62 + 0.55 * hl);
		fill *= mix(1.12, 0.78, smoothstep(-0.02, 0.02, inner));
		float sw = pc_sd_sword(pc_rot(0.785398) * p * k * 1.35) / 1.35;
		fill = mix(fill, fill * 0.74, (1.0 - smoothstep(-0.01, 0.02, sw)) * 0.55);
		outline = shape == 7 ? 0.1 : outline;
	} else if (shape == 1 || shape == 8) {
		// The attack crest in red, with a faintly engraved heart behind the number.
		float k = shape == 8 ? 0.9 : 1.0;
		d = pc_sd_crest(p * k) / k;
		float inner = pc_sd_crest(p * k * 1.28) / (k * 1.28);
		fill = fill_color.rgb * (0.62 + 0.55 * hl);
		fill *= mix(1.12, 0.78, smoothstep(-0.02, 0.02, inner));
		float heart = pc_sd_heart(p * k * 1.9) / 1.9;
		fill = mix(fill, fill * 0.74, (1.0 - smoothstep(-0.01, 0.02, heart)) * 0.55);
		outline = shape == 8 ? 0.1 : outline;
	} else if (shape == 2) {
		d = pc_sd_shield(p * 1.12 - vec2(0.0, -0.1)) / 1.12;
		fill *= 1.0 - smoothstep(-0.14, 0.0, d) * 0.3;
	} else if (shape == 3) {
		float r = length(p);
		d = r - 0.72;
		vec3 gold = vec3(1.0, 0.78, 0.34) * (0.6 + 0.6 * hl);
		fill = mix(fill_color.rgb * (0.5 + 0.6 * hl), gold, smoothstep(0.5, 0.53, r));
	} else if (shape == 4) {
		float a = atan(p.y, p.x);
		float r = length(p);
		d = r - (0.7 + 0.13 * sin(a * 9.0) + 0.05 * sin(a * 23.0 + 1.0));
		fill *= 1.0 - smoothstep(-0.2, 0.0, d) * 0.3;
	} else if (shape == 5) {
		d = (abs(p.x) * 1.05 + abs(p.y) * 0.8) - 0.72;
		float facet = step(0.0, p.y) * 0.25 + step(0.0, p.x) * 0.12;
		fill *= 0.8 + facet;
	} else if (shape == 9) {
		// Token shield badge: steel shield filling the quad.
		d = pc_sd_shield(p * 1.12 - vec2(0.0, -0.1)) / 1.12;
		fill *= 1.0 - smoothstep(-0.16, 0.0, d) * 0.3;
		outline = 0.1;
	} else {
		d = 0.0;
	}
	float aa = max(fwidth(d) * 0.75, 0.012);
	float shape_mask = 1.0 - smoothstep(-aa, aa, d);
	float outer_mask = 1.0 - smoothstep(outline - aa, outline + aa, d);
	vec3 c = mix(rim_color.rgb, fill, shape_mask);
	if (shape == 6) {
		float r = length(p);
		c = fill_color.rgb * 2.0;
		outer_mask = exp(-r * r * 3.0) * (1.0 - smoothstep(0.85, 1.0, r)) * fill_color.a;
	}
	ALBEDO = c;
	ALPHA = clamp(outer_mask * alpha, 0.0, 1.0);
}
