// Card stock under the face: a printed border in the clan colour (frame_color) with paper grain, a fine inner
// print line and a light/dark bevel along the edge, so the card reads as a physical, slightly thick card.
// The artwork (card_art, full-bleed) and the overlay (card_overlay) are drawn on top of it.
// show_back = true renders the card back instead (used by the draft flip reveal).
shader_type canvas_item;

#include "res://Assets/Shaders/common.gdshaderinc"

uniform vec2 card_size = vec2(150.0, 210.0);
uniform int style = 0;
uniform bool show_back = false;
uniform vec4 text_rect = vec4(14.0, 128.0, 122.0, 62.0);
uniform vec4 art_rect = vec4(25.0, 10.0, 100.0, 94.0);
uniform vec3 frame_color : source_color = vec3(0.75, 0.7, 0.62);
uniform vec3 accent_color : source_color = vec3(0.9, 0.3, 0.25);
uniform float corner = 9.0;

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
	float grain = pc_vnoise(px * 1.7) * 0.5 + pc_vnoise(px * 0.6 + vec2(11.0)) * 0.5;
	vec3 col;
	if (show_back) {
		vec2 q = (px - card_size * 0.5) / card_size.x;
		vec3 back = vec3(0.24, 0.14, 0.08);
		col = back * (0.82 + 0.3 * pc_fbm(px * 0.05)) * (0.94 + 0.1 * grain);
		float lattice = min(abs(fract((q.x + q.y) * 7.0) - 0.5), abs(fract((q.x - q.y) * 7.0) - 0.5));
		col = mix(col, vec3(0.42, 0.28, 0.15), (1.0 - smoothstep(0.02, 0.05, lattice)) * 0.6);
		float r = length(q * vec2(1.0, 0.75));
		col = mix(col, vec3(0.62, 0.45, 0.24), 1.0 - smoothstep(0.008, 0.02, abs(r - 0.25)));
		float star = pc_emblem(q / 0.18, 3);
		col = mix(col, vec3(0.7, 0.52, 0.28), 1.0 - smoothstep(-0.01, 0.01, star * 0.18));
		float border = 1.0 - smoothstep(5.0, 6.0, edge);
		col = mix(col, vec3(0.86, 0.8, 0.68) * (0.9 + 0.12 * grain), border);
	} else {
		col = frame_color * (0.86 + 0.18 * pc_fbm(px * 0.08)) * (0.93 + 0.1 * grain);
		// Fine printed line inside the border.
		float inner = sd_rect(px, vec4(2.5, 2.5, card_size.x - 5.0, card_size.y - 5.0), corner - 2.5);
		col = mix(col, frame_color * 0.5, (1.0 - smoothstep(0.25, 0.8, abs(inner))) * 0.8);
	}
	// Card thickness: lit top-left edge, shaded bottom-right edge.
	float bevel = 1.0 - smoothstep(0.0, 2.2, edge);
	float side = clamp((UV.x + UV.y) - 1.0, -1.0, 1.0);
	col *= 1.0 + bevel * (side < 0.0 ? 0.28 : -0.32);
	col = mix(vec3(0.08, 0.06, 0.04), col, smoothstep(0.0, 1.0, edge));
	COLOR = vec4(col, aa) * tint_in;
}
