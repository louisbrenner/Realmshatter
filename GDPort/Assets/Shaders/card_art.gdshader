// Card art window: the card's Art texture, or a procedural painting (tinted glow + role emblem),
// masked to an oval (frame_shape 0) or rounded rect (1) with a gold rim, or full-bleed (2): fills the whole card
// face with a thin printed edge; 'focus' moves the painting's centre (pixels, y down) above the text panel.
shader_type canvas_item;

#include "res://Assets/Shaders/common.gdshaderinc"
#include "res://Assets/Shaders/icon_glyphs.gdshaderinc"

uniform sampler2D art_texture : source_color, filter_linear;
uniform bool has_art = false;
uniform vec4 tint : source_color = vec4(0.9, 0.3, 0.25, 1.0);
uniform int emblem = 0;
uniform int frame_shape = 0;
uniform vec2 rect_size = vec2(100.0, 94.0);
uniform float seed = 0.0;
uniform vec2 focus = vec2(0.0, 0.0);
// Subject of the procedural painting: >= 0 = glyph from icon_glyphs (class / spell symbol), -1 = role emblem.
uniform int glyph = -1;
// Only rare cards shimmer; common painted art is still.
uniform bool animate = false;

void fragment() {
	vec4 tint_in = COLOR;
	vec2 p = (UV - 0.5) * 2.0;
	p.y = -p.y;
	// Pixel-true coordinates: the unit window is a perfect circle (diameter = the shorter side), and the painting
	// uses the same unit circle so nothing is stretched.
	vec2 px = (UV - 0.5) * rect_size - focus;
	px.y = -px.y;
	float radius = frame_shape == 2 ? rect_size.x * 0.44 : min(rect_size.x, rect_size.y) * 0.5;
	vec2 q = px / radius;
	float d;
	if (frame_shape == 0) {
		d = length(px) - radius;
	} else if (frame_shape == 1) {
		d = pc_sd_round_box((UV - 0.5) * rect_size, rect_size * 0.5, 12.0);
	} else {
		d = pc_sd_round_box((UV - 0.5) * rect_size, rect_size * 0.5, 6.0);
	}
	vec3 col;
	if (has_art && frame_shape == 2) {
		// Cover-fit a square texture into the tall card (crop the sides, no stretching).
		vec2 tuv = vec2(0.5 + (UV.x - 0.5) * rect_size.x / rect_size.y, UV.y);
		col = texture(art_texture, tuv).rgb;
	} else if (has_art) {
		// Cover-fit a square texture into the wide window (crop top/bottom, no stretching).
		vec2 tuv = vec2(0.5) + vec2(q.x, -q.y) * 0.5;
		col = texture(art_texture, tuv).rgb;
	} else {
		float t = animate ? TIME : 0.0;
		float light = 1.0 - clamp(length(q - vec2(-0.3, 0.45)) * 0.6, 0.0, 1.0);
		col = mix(tint.rgb * 0.16, mix(tint.rgb, vec3(1.0, 0.95, 0.82), 0.35), light);
		col *= 0.8 + 0.35 * pc_fbm(q * 2.5 + vec2(seed, t * 0.05));
		float ang = atan(q.y, q.x);
		col += tint.rgb * 0.2 * smoothstep(0.5, 1.0, sin(ang * 9.0 + t * 0.5 + seed)) * max(1.0 - length(q) * 0.7, 0.0);
		float e;
		float es;
		if (glyph >= 0) {
			e = pc_icon_glyph(q / 0.62, glyph, t) * 0.62;
			es = pc_icon_glyph((q - vec2(0.05, -0.06)) / 0.62, glyph, t) * 0.62;
		} else {
			e = pc_emblem(q / 0.72, emblem) * 0.72;
			es = pc_emblem((q - vec2(0.05, -0.06)) / 0.72, emblem) * 0.72;
		}
		col = mix(col, col * 0.3, (1.0 - smoothstep(0.0, 0.08, es)) * 0.7);
		vec3 emb_col = vec3(1.0, 0.9, 0.66) * (0.75 + 0.45 * light);
		col = mix(col, emb_col, 1.0 - smoothstep(-0.01, 0.01, e));
		col = mix(col, vec3(0.12, 0.07, 0.03), (1.0 - smoothstep(0.0, 0.035, abs(e))) * 0.8);
		if (animate) {
			float motes = pow(pc_vnoise(q * 9.0 + vec2(0.0, -t * 0.6)), 12.0) * 3.0;
			col += vec3(1.0, 0.9, 0.6) * motes;
		}
	}
	if (frame_shape == 2) {
		// Printed edge: the picture darkens slightly towards the border, then a fine ink line.
		col *= 0.76 + 0.24 * smoothstep(0.0, 14.0, -d);
		col = mix(col, vec3(0.05, 0.035, 0.02), 1.0 - smoothstep(0.0, 1.2, abs(d + 0.8)));
	} else {
		float rim = smoothstep(-4.2, -3.2, d);
		vec3 gold = vec3(1.0, 0.78, 0.35) * (0.55 + 0.6 * (1.0 - UV.y));
		col = mix(col, gold, rim);
		col = mix(col, vec3(0.06, 0.04, 0.02), 1.0 - smoothstep(0.0, 1.0, abs(d + 4.2)));
	}
	float aa = 1.0 - smoothstep(-0.6, 0.6, d);
	COLOR = vec4(col, aa) * tint_in;
}
