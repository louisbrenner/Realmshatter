// Card face background: stone frame with gold trim, shadowed art seat and parchment text box.
// show_back = true renders the card back instead (used by the draft flip reveal).
shader_type canvas_item;

#include "res://Assets/Shaders/common.gdshaderinc"

uniform vec2 card_size = vec2(150.0, 210.0);
uniform int style = 0; // 0 = unit (oval art), 1 = spell (rounded rect art)
uniform bool show_back = false;
uniform vec4 text_rect = vec4(14.0, 128.0, 122.0, 62.0);
uniform vec4 art_rect = vec4(25.0, 10.0, 100.0, 94.0);
uniform vec3 frame_color : source_color = vec3(0.46, 0.4, 0.33);
uniform vec3 accent_color : source_color = vec3(0.9, 0.3, 0.25);
uniform float corner = 12.0;

float sd_rect(vec2 px, vec4 rect, float r) {
	vec2 c = rect.xy + rect.zw * 0.5;
	return pc_sd_round_box(px - c, rect.zw * 0.5, r);
}

void fragment() {
	vec4 tint_in = COLOR;
	vec2 px = UV * card_size;
	float outer = sd_rect(px, vec4(0.0, 0.0, card_size.x, card_size.y), corner);
	float aa = 1.0 - smoothstep(-0.6, 0.6, outer);
	float edge = -outer;
	vec3 col;
	vec3 gold = vec3(1.0, 0.78, 0.36) * (0.62 + 0.55 * (1.0 - UV.y));
	if (show_back) {
		vec2 q = (px - card_size * 0.5) / card_size.x;
		float lattice = min(abs(fract((q.x + q.y) * 7.0) - 0.5), abs(fract((q.x - q.y) * 7.0) - 0.5));
		col = vec3(0.2, 0.11, 0.07) * (0.8 + 0.4 * pc_fbm(px * 0.05));
		col = mix(col, vec3(0.45, 0.28, 0.12), 1.0 - smoothstep(0.02, 0.06, lattice));
		float r = length(q * vec2(1.0, 0.75));
		col = mix(col, vec3(0.1, 0.18, 0.4) * (1.0 + 0.5 * (0.3 - r)), 1.0 - smoothstep(0.24, 0.25, r));
		float ring = 1.0 - smoothstep(0.008, 0.02, abs(r - 0.25));
		col = mix(col, gold, ring);
		float star = pc_emblem(q / 0.18, 3);
		col = mix(col, gold * 1.1, 1.0 - smoothstep(-0.01, 0.01, star * 0.18));
	} else {
		float n = pc_fbm(px * 0.05);
		float n2 = pc_fbm(px * 0.22 + vec2(7.0));
		col = frame_color * (0.72 + 0.42 * n) * (0.9 + 0.2 * n2);
		col = mix(col, col * accent_color * 1.6, 0.1);
		float bevel = 1.0 - smoothstep(0.0, 7.0, edge);
		col *= 1.0 + bevel * (UV.y < 0.5 ? 0.3 : -0.25);

		// Seat shadow around the art window.
		float art_d;
		if (style == 0) {
			vec2 ac = art_rect.xy + art_rect.zw * 0.5;
			vec2 e = (px - ac) / (art_rect.zw * 0.5);
			art_d = (length(e) - 1.0) * min(art_rect.z, art_rect.w) * 0.5;
		} else {
			art_d = sd_rect(px, art_rect, 12.0);
		}
		col *= 1.0 - (1.0 - smoothstep(0.0, 8.0, art_d)) * step(0.0, art_d) * 0.6;

		// Parchment text box.
		float td = sd_rect(px, text_rect, 9.0);
		vec3 parch = vec3(0.92, 0.84, 0.68) * (0.84 + 0.26 * pc_fbm(px * 0.07 + vec2(3.0)));
		parch *= 1.0 - (1.0 - smoothstep(0.0, 9.0, -td)) * 0.28;
		col *= 1.0 - (1.0 - smoothstep(0.0, 5.0, td)) * step(0.0, td) * 0.45;
		col = mix(col, parch, 1.0 - smoothstep(-0.6, 0.6, td));
		col = mix(col, vec3(0.5, 0.34, 0.16), 1.0 - smoothstep(0.5, 1.5, abs(td)));

		// Gold trim and dark outer outline.
		float trim = 1.0 - smoothstep(0.7, 1.5, abs(edge - 5.0));
		col = mix(col, gold, trim);
	}
	col = mix(vec3(0.05, 0.03, 0.02), col, smoothstep(0.0, 1.8, edge));
	COLOR = vec4(col, aa) * tint_in;
}
