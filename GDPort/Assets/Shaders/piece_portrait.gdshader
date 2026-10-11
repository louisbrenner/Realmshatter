// Oval minion portrait on a quad: painted radial background in the card tint, role emblem,
// gold rim. Supports desaturation (exhausted) and a hit/flash overlay.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, shadows_disabled;

#include "res://Assets/Shaders/common.gdshaderinc"

uniform vec3 tint : source_color = vec3(0.9, 0.3, 0.25);
uniform int role = 0;
uniform float desaturate = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0);
uniform float flash = 0.0;
uniform float brightness = 1.0;
uniform float seed = 0.0;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	p.y = -p.y;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	// Light from the top-left of the screen.
	float light = 1.0 - clamp(length(p - vec2(-0.35, 0.4)) * 0.62, 0.0, 1.0);
	vec3 bg_dark = tint * 0.22;
	vec3 bg_light = mix(tint, vec3(1.0, 0.95, 0.85), 0.3);
	vec3 col = mix(bg_dark, bg_light, light);
	col *= 0.82 + 0.32 * pc_fbm(p * 2.6 + vec2(seed * 3.1, seed * 1.7));
	float ang = atan(p.y, p.x);
	col += tint * 0.14 * smoothstep(0.55, 1.0, sin(ang * 7.0 + TIME * 0.4 + seed)) * (1.0 - r);

	vec2 ep = p / 0.78;
	float e = pc_emblem(ep, role) * 0.78;
	float es = pc_emblem((p - vec2(0.05, -0.06)) / 0.78, role) * 0.78;
	float shadow = 1.0 - smoothstep(0.0, 0.08, es);
	col = mix(col, col * 0.35, shadow * 0.65);
	float emb = 1.0 - smoothstep(-0.01, 0.01, e);
	float emb_edge = 1.0 - smoothstep(0.0, 0.035, abs(e));
	vec3 emb_col = vec3(1.0, 0.9, 0.66) * (0.72 + 0.45 * light);
	emb_col = mix(emb_col, emb_col * 0.75, smoothstep(-0.12, 0.0, e));
	col = mix(col, emb_col, emb);
	col = mix(col, vec3(0.14, 0.08, 0.04), emb_edge * 0.75);

	col *= 1.0 - smoothstep(0.66, 0.86, r) * 0.6;

	// Gold rim with a fake bevel.
	float rim = smoothstep(0.855, 0.875, r);
	vec2 n = p / max(r, 0.001);
	float rim_shade = clamp(0.55 + 0.6 * dot(n, normalize(vec2(-0.5, 0.75))), 0.0, 1.3);
	float band = clamp((r - 0.865) / 0.135, 0.0, 1.0);
	vec3 gold = vec3(1.0, 0.76, 0.33) * (0.45 + 0.7 * rim_shade) * (0.7 + 0.5 * sin(band * 3.14159));
	gold += vec3(1.0, 0.95, 0.75) * pow(max(rim_shade - 0.9, 0.0) * 2.5, 2.0) * 0.6;
	float dark_line = 1.0 - smoothstep(0.0, 0.018, abs(r - 0.862));
	col = mix(col, gold, rim);
	col = mix(col, vec3(0.08, 0.05, 0.02), dark_line * 0.8);

	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum) * 0.7, desaturate);
	col = mix(col, flash_color.rgb * 1.8, clamp(flash, 0.0, 1.0));
	ALBEDO = col * brightness;
}
