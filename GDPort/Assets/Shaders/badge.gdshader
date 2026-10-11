// Camera-facing stat badge drawn with SDFs (always on top).
// shape: 0 = attack (yellow disc with sword), 1 = health (red drop), 2 = shield, 3 = order coin,
//        4 = damage splat, 5 = gem, 6 = soft glow disc,
//        7 = token attack disc, 8 = token health drop, 9 = token shield (7-9 fill the quad).
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
	if (shape == 0) {
		float disc = length(p) - 0.58;
		vec2 q = pc_rot(0.785398) * p;
		float sw = pc_sd_sword(q);
		d = min(disc, sw);
		if (disc > 0.0) {
			float blade = max(pc_sd_box(q - vec2(0.0, 0.3), vec2(0.1, 0.7)), q.y + abs(q.x) * 2.5 - 1.0);
			float guard = pc_sd_box(q - vec2(0.0, -0.45), vec2(0.3, 0.07));
			if (blade < 0.0) {
				fill = mix(vec3(0.62, 0.66, 0.72), vec3(0.95, 0.97, 1.0), smoothstep(-0.1, 0.1, q.x));
			} else if (guard < 0.0) {
				fill = vec3(0.85, 0.6, 0.2);
			} else {
				fill = vec3(0.42, 0.22, 0.1);
			}
		} else {
			fill *= mix(0.72, 1.0, smoothstep(0.0, 0.16, -disc));
		}
	} else if (shape == 1) {
		d = pc_sd_drop(p * 1.08) / 1.08;
		fill *= 1.0 - smoothstep(-0.14, 0.0, d) * 0.28;
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
	} else if (shape == 7) {
		// Token attack badge: full gold disc with an embossed sword behind the number.
		float r = length(p);
		d = r - 0.84;
		vec2 q = pc_rot(0.785398) * (p * 1.25);
		float sw = pc_sd_sword(q);
		vec3 gold = fill_color.rgb * (0.62 + 0.45 * hl);
		fill = mix(gold * 0.7, gold, smoothstep(0.0, 0.14, -d));
		fill = mix(fill, gold * 0.72, (1.0 - smoothstep(-0.03, 0.03, sw)) * 0.8);
		fill = mix(fill, vec3(0.45, 0.28, 0.06), (1.0 - smoothstep(0.0, 0.04, abs(r - 0.7))) * 0.5);
		outline = 0.1;
	} else if (shape == 8) {
		// Token health badge: big red drop filling the quad.
		d = pc_sd_drop(p * 0.9) / 0.9;
		fill *= 1.0 - smoothstep(-0.16, 0.0, d) * 0.3;
		outline = 0.1;
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
