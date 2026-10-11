// Soft green-gold healing tile: rotating rune circle with glyphs, inner sigil and a glowing core.
// 'appear' (0..1) grows the circle from the center, 'opacity' fades it (also used for ghost previews).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

#include "res://Assets/Shaders/common.gdshaderinc"

uniform vec4 green : source_color = vec4(0.42, 1.0, 0.55, 1.0);
uniform vec4 gold : source_color = vec4(1.0, 0.86, 0.42, 1.0);
uniform float energy = 2.2;
uniform float opacity = 1.0;
uniform float appear = 1.0;
uniform float seed = 0.0;
uniform float hatch = 0.0;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float t = TIME;
	float pulse = 0.5 + 0.5 * sin(t * 2.2 + seed);
	float rot = t * 0.35 + seed;

	float box = pc_sd_round_box(p, vec2(0.92), 0.3);
	float inside = 1.0 - smoothstep(-0.05, 0.02, box);
	float fill = (0.16 + 0.08 * pulse) * (1.0 - 0.45 * smoothstep(0.0, 0.9, r));
	float edge = exp(-abs(box) * 14.0) * 0.5;

	float ring1 = 1.0 - smoothstep(0.015, 0.035, abs(r - 0.79));
	float ring2 = 1.0 - smoothstep(0.012, 0.03, abs(r - 0.58));
	float seg = 12.0;
	float ar = (a + rot) / 6.2831853 * seg;
	float k = floor(ar);
	float u = fract(ar);
	float v = (r - 0.6) / 0.17;
	float h = pc_hash21(vec2(k, 3.0 + seed));
	float glyph = 0.0;
	if (v > 0.08 && v < 0.92) {
		float x = (u - 0.5) * 2.0;
		float y = (v - 0.5) * 2.0;
		float s1 = 1.0 - smoothstep(0.09, 0.17, abs(x - (h - 0.5) * 0.8 * y));
		float s2 = (1.0 - smoothstep(0.1, 0.2, abs(y - (fract(h * 7.0) - 0.5)))) * step(abs(x), 0.55) * step(0.35, h);
		float s3 = (1.0 - smoothstep(0.09, 0.17, abs(abs(x) - 0.5))) * step(0.5, fract(h * 13.0));
		glyph = max(s1, max(s2, s3)) * step(abs(x), 0.7) * step(abs(y), 0.75);
	}

	vec2 q = pc_rot(-rot * 1.5) * p;
	float star = abs(q.x) * abs(q.y);
	float sigil = (1.0 - smoothstep(0.012, 0.03, star)) * (1.0 - smoothstep(0.3, 0.44, r));
	float leaf = 1.0 - smoothstep(0.01, 0.03, abs(r - 0.3));
	float core = exp(-r * r * 9.0) * (0.5 + 0.3 * pulse);
	float lines = max(max(ring1, ring2), glyph * 0.9);
	lines = max(lines, max(sigil * 0.85, leaf * 0.7));

	float reveal = 1.0 - smoothstep(appear * 1.35 - 0.15, appear * 1.35, r);
	float stripes = hatch * step(0.55, fract((p.x + p.y) * 2.5 - TIME * 0.8)) * 0.12;
	vec3 col = mix(green.rgb, gold.rgb, clamp(lines * 0.7 + core, 0.0, 1.0));
	ALBEDO = col * (1.0 + energy * (lines * (0.6 + 0.4 * pulse) + core + edge));
	float alpha_v = (fill + stripes + edge + lines * (0.65 + 0.35 * pulse) + core * 0.6) * inside * reveal;
	ALPHA = clamp(alpha_v * opacity, 0.0, 1.0);
}
