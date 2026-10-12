// Card UI ornaments drawn with SDFs on a ColorRect.
// shape: 0 = attack (bronze diamond crest), 1 = health (red diamond crest), 2 = shield, 3 = mana gem,
//        4 = name ribbon, 5 = small plate, 6 = coin.
shader_type canvas_item;

#include "res://Assets/Shaders/common.gdshaderinc"

uniform int shape = 0;
uniform vec4 fill_color : source_color = vec4(1.0, 0.8, 0.2, 1.0);
uniform vec4 rim_color : source_color = vec4(0.12, 0.07, 0.03, 1.0);
uniform vec2 rect_size = vec2(46.0, 46.0);

float sd_hex(vec2 p, float r) {
	const vec3 k = vec3(-0.866025404, 0.5, 0.577350269);
	p = abs(p);
	p -= 2.0 * min(dot(k.xy, p), 0.0) * k.xy;
	p -= vec2(clamp(p.x, -k.z * r, k.z * r), r);
	return length(p) * sign(p.y);
}

void fragment() {
	vec4 tint_in = COLOR;
	vec2 p = vec2(UV.x - 0.5, 0.5 - UV.y) * 2.0;
	float scale = min(rect_size.x, rect_size.y) * 0.5;
	float hl = clamp(1.0 - length(p - vec2(-0.25, 0.3)) * 0.85, 0.0, 1.0);
	vec3 fill = fill_color.rgb * (0.6 + 0.65 * hl);
	float d;
	float outline_px = 2.2;
	if (shape == 0) {
		// Bevelled diamond crest with a faintly engraved sword behind the number.
		d = pc_sd_crest(p) * scale;
		float inner = pc_sd_crest(p * 1.28) / 1.28;
		fill = fill_color.rgb * (0.62 + 0.55 * hl);
		fill *= mix(1.12, 0.78, smoothstep(-0.02, 0.02, inner));
		float sw = pc_sd_sword(pc_rot(0.785398) * p * 1.35) / 1.35;
		fill = mix(fill, fill * 0.74, (1.0 - smoothstep(-0.01, 0.02, sw)) * 0.55);
		fill += vec3(1.0, 0.95, 0.8) * pow(hl, 5.0) * 0.25;
	} else if (shape == 1) {
		// The attack crest in red, with a faintly engraved heart behind the number.
		d = pc_sd_crest(p) * scale;
		float inner = pc_sd_crest(p * 1.28) / 1.28;
		fill = fill_color.rgb * (0.62 + 0.55 * hl);
		fill *= mix(1.12, 0.78, smoothstep(-0.02, 0.02, inner));
		float heart = pc_sd_heart(p * 1.9) / 1.9;
		fill = mix(fill, fill * 0.74, (1.0 - smoothstep(-0.01, 0.02, heart)) * 0.55);
		fill += vec3(1.0, 0.9, 0.85) * pow(hl, 5.0) * 0.25;
	} else if (shape == 2) {
		d = pc_sd_shield(p * 1.12 - vec2(0.0, -0.1)) / 1.12 * scale;
		fill *= 1.0 - smoothstep(-4.0, 0.0, d) * 0.3;
	} else if (shape == 3) {
		d = sd_hex(pc_rot(0.5236) * p, 0.78) * scale;
		float ang = atan(p.y, p.x);
		float sector = floor((ang + 3.14159265) / 1.0471976);
		float sa = sector * 1.0471976 - 3.14159265 + 0.5236;
		float facet = 0.7 + 0.45 * cos(sa - 2.3);
		float inner = sd_hex(pc_rot(0.5236) * p, 0.42);
		fill = fill_color.rgb * mix(facet, 1.25 + 0.3 * hl, 1.0 - smoothstep(-0.02, 0.02, inner));
		fill += vec3(0.8, 0.9, 1.0) * pow(hl, 6.0) * 0.6;
	} else if (shape == 4) {
		vec2 px = (UV - 0.5) * rect_size;
		float hw = rect_size.x * 0.5;
		float bend = 5.0 * (px.x / hw) * (px.x / hw);
		vec2 bp = vec2(px.x, px.y + bend);
		float body = pc_sd_box(bp, vec2(hw - 13.0, rect_size.y * 0.5 - 5.0));
		vec2 tp = vec2(abs(bp.x) - (hw - 9.0), bp.y - 3.0);
		float th = rect_size.y * 0.5 - 7.0;
		float tail = pc_sd_box(tp, vec2(8.5, th));
		float keep = (8.5 - 6.0 * (1.0 - clamp(abs(tp.y) / th, 0.0, 1.0))) - tp.x;
		tail = max(tail, -keep);
		d = min(body, tail);
		float shade = 0.85 + 0.3 * (1.0 - UV.y);
		fill = (body < 0.0 ? fill_color.rgb : fill_color.rgb * 0.62) * shade;
		float stitch = 1.0 - smoothstep(0.4, 1.0, abs(abs(bp.y) - (rect_size.y * 0.5 - 8.0)));
		fill = mix(fill, fill * 1.3, stitch * step(body, 0.0) * 0.5);
	} else if (shape == 5) {
		vec2 px = (UV - 0.5) * rect_size;
		d = pc_sd_round_box(px, rect_size * 0.5 - vec2(2.5), 6.0);
		fill = fill_color.rgb * (0.75 + 0.45 * (1.0 - UV.y));
	} else {
		float r = length(p);
		d = (r - 0.82) * scale;
		vec3 gold = vec3(1.0, 0.78, 0.34) * (0.6 + 0.6 * hl);
		fill = mix(fill_color.rgb * (0.55 + 0.6 * hl), gold, smoothstep(0.6, 0.64, r));
	}
	float shape_mask = 1.0 - smoothstep(-0.6, 0.6, d);
	float outer_mask = 1.0 - smoothstep(outline_px - 0.6, outline_px + 0.6, d);
	vec3 c = mix(rim_color.rgb, fill, shape_mask);
	COLOR = vec4(c, outer_mask * fill_color.a) * tint_in;
}
