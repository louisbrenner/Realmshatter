// Card art window: the card's Art texture, or a procedural painting (tinted glow + role emblem),
// masked to an oval (units) or rounded rect (spells) with a gold rim.
shader_type canvas_item;

#include "res://Assets/Shaders/common.gdshaderinc"

uniform sampler2D art_texture : source_color, filter_linear;
uniform bool has_art = false;
uniform vec4 tint : source_color = vec4(0.9, 0.3, 0.25, 1.0);
uniform int emblem = 0;
uniform int frame_shape = 0;
uniform vec2 rect_size = vec2(100.0, 94.0);
uniform float seed = 0.0;

void fragment() {
	vec4 tint_in = COLOR;
	vec2 p = (UV - 0.5) * 2.0;
	p.y = -p.y;
	float d;
	if (frame_shape == 0) {
		d = (length(p) - 1.0) * min(rect_size.x, rect_size.y) * 0.5;
	} else {
		d = pc_sd_round_box((UV - 0.5) * rect_size, rect_size * 0.5, 12.0);
	}
	vec3 col;
	if (has_art) {
		col = texture(art_texture, UV).rgb;
	} else {
		float light = 1.0 - clamp(length(p - vec2(-0.3, 0.45)) * 0.6, 0.0, 1.0);
		col = mix(tint.rgb * 0.16, mix(tint.rgb, vec3(1.0, 0.95, 0.82), 0.35), light);
		col *= 0.8 + 0.35 * pc_fbm(p * 2.5 + vec2(seed, TIME * 0.05));
		float ang = atan(p.y, p.x);
		col += tint.rgb * 0.2 * smoothstep(0.5, 1.0, sin(ang * 9.0 + TIME * 0.5 + seed)) * max(1.0 - length(p) * 0.7, 0.0);
		float hill = p.y + 0.62 + 0.1 * sin(p.x * 3.0 + seed * 2.0);
		col *= mix(0.45, 1.0, smoothstep(-0.02, 0.02, hill));
		float e = pc_emblem(p / 0.72, emblem) * 0.72;
		float es = pc_emblem((p - vec2(0.05, -0.06)) / 0.72, emblem) * 0.72;
		col = mix(col, col * 0.3, (1.0 - smoothstep(0.0, 0.08, es)) * 0.7);
		vec3 emb_col = vec3(1.0, 0.9, 0.66) * (0.75 + 0.45 * light);
		col = mix(col, emb_col, 1.0 - smoothstep(-0.01, 0.01, e));
		col = mix(col, vec3(0.12, 0.07, 0.03), (1.0 - smoothstep(0.0, 0.035, abs(e))) * 0.8);
		float motes = pow(pc_vnoise(p * 9.0 + vec2(0.0, -TIME * 0.6)), 12.0) * 3.0;
		col += vec3(1.0, 0.9, 0.6) * motes;
	}
	float rim = smoothstep(-4.2, -3.2, d);
	vec3 gold = vec3(1.0, 0.78, 0.35) * (0.55 + 0.6 * (1.0 - UV.y));
	col = mix(col, gold, rim);
	col = mix(col, vec3(0.06, 0.04, 0.02), 1.0 - smoothstep(0.0, 1.0, abs(d + 4.2)));
	float aa = 1.0 - smoothstep(-0.6, 0.6, d);
	COLOR = vec4(col, aa) * tint_in;
}
