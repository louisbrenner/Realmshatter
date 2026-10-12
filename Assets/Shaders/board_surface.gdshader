// Whole board top surface on one plane: stone tiles with grout + fake bevel, parchment scoring zone
// with an animated glowing rune border, and subtly tinted deploy rows per player.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

#include "res://Assets/Shaders/common.gdshaderinc"

uniform vec2 board_size = vec2(10.0, 8.0);
uniform float tile_size = 1.0;
uniform float grout_width = 0.06;
uniform float bevel_width = 0.1;
uniform float bevel_strength = 0.05;
uniform vec4 scoring_rect = vec4(2.0, 3.0, 6.0, 2.0);
uniform vec4 hot_rect = vec4(-10.0, -10.0, 0.0, 0.0);
uniform vec3 hot_color : source_color = vec3(1.0, 0.5, 0.1);
uniform float deploy_rows = 2.0;
uniform vec3 stone_color : source_color = vec3(0.47, 0.44, 0.40);
uniform vec3 stone_dark : source_color = vec3(0.26, 0.24, 0.22);
uniform vec3 parchment_color : source_color = vec3(0.86, 0.72, 0.46);
uniform vec3 p0_tint : source_color = vec3(0.25, 0.45, 0.9);
uniform vec3 p1_tint : source_color = vec3(0.9, 0.3, 0.22);
uniform float tint_strength = 0.2;
uniform vec3 grout_color : source_color = vec3(0.07, 0.05, 0.04);
uniform vec3 rune_color : source_color = vec3(1.0, 0.7, 0.25);
uniform float rune_energy = 3.2;
uniform float zone_glow = 0.12;
uniform float checker = 0.05;

varying vec3 v_local;
varying vec3 v_normal;

void vertex() {
	v_local = VERTEX;
	v_normal = NORMAL;
}

float tile_height(vec2 g) {
	vec2 f = fract(g);
	float e = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float hg = grout_width * 0.5;
	float bev = smoothstep(hg, hg + bevel_width, e);
	float n = pc_fbm(g * 4.0 + floor(g) * 3.7);
	return bev * 0.6 + n * 0.1 * bev;
}

void fragment() {
	vec2 g = vec2(v_local.x / tile_size + board_size.x * 0.5, v_local.z / tile_size + board_size.y * 0.5);
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float e = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float hg = grout_width * 0.5;
	float groove = 1.0 - smoothstep(hg - 0.008, hg + 0.008, e);
	float bev = smoothstep(hg, hg + bevel_width, e);
	float cell_rand = pc_hash21(cell + vec2(0.5));

	// Stone base with mottling, speckles and fine cracks.
	float n1 = pc_fbm(g * 2.3 + cell * 1.7);
	float n2 = pc_fbm(g * 9.0 + vec2(3.1));
	vec3 col = mix(stone_dark, stone_color, smoothstep(0.25, 0.75, n1));
	col *= 0.86 + 0.26 * n2;
	col *= 0.9 + 0.18 * cell_rand;
	float cn = abs(pc_fbm(g * 3.0 + cell * 5.0) - 0.5);
	float crack = 1.0 - smoothstep(0.0, 0.022, cn);
	col *= 1.0 - crack * 0.4;

	bool in_zone = cell.x >= scoring_rect.x && cell.x < scoring_rect.x + scoring_rect.z
		&& cell.y >= scoring_rect.y && cell.y < scoring_rect.y + scoring_rect.w;
	vec3 emission = vec3(0.0);
	float rough = 0.72 + 0.2 * n2;
	if (in_zone) {
		vec3 parch = parchment_color * (0.82 + 0.3 * pc_fbm(g * 5.0 + vec2(11.0)));
		parch *= 0.82 + 0.18 * smoothstep(0.0, 0.45, e);
		col = mix(col, parch * 0.9, 0.8);
		float pulse = 0.5 + 0.5 * sin(TIME * 1.6 + (cell.x + cell.y) * 0.7);
		emission += rune_color * zone_glow * (0.35 + 0.65 * pulse) * smoothstep(0.05, 0.5, e) * 0.3;
		rough = 0.85;
		bool in_hot = cell.x >= hot_rect.x && cell.x < hot_rect.x + hot_rect.z
			&& cell.y >= hot_rect.y && cell.y < hot_rect.y + hot_rect.w;
		if (in_hot) {
			// Crown field: polished gold inlay that breathes.
			float hp = 0.5 + 0.5 * sin(TIME * 2.4);
			col = mix(col, hot_color * (0.8 + 0.25 * pc_fbm(g * 6.0)), 0.55);
			emission += hot_color * (0.25 + 0.35 * hp) * smoothstep(0.05, 0.5, e);
			rough = 0.45;
		}
	} else if (cell.y >= board_size.y - deploy_rows) {
		col = mix(col, col * 0.55 + p0_tint * 0.5, tint_strength);
	} else if (cell.y < deploy_rows) {
		col = mix(col, col * 0.55 + p1_tint * 0.5, tint_strength);
	}
	if (mod(cell.x + cell.y, 2.0) > 0.5) {
		col *= 1.0 - checker;
	}

	// Grout and ambient occlusion in the bevel.
	col *= mix(0.62, 1.0, bev);
	// Real geometry: chamfers and block sides are darker (ambient occlusion between the stones).
	float upness = clamp(v_normal.y, 0.0, 1.0);
	col *= mix(0.5, 1.0, upness * upness);
	col = mix(col, grout_color, groove);

	// Animated rune border around the scoring zone (in grid units).
	vec2 rc = scoring_rect.xy + scoring_rect.zw * 0.5;
	vec2 rh = scoring_rect.zw * 0.5;
	vec2 q = abs(g - rc) - rh;
	float sd = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);
	float band_in = -0.05;
	float band_out = -0.22;
	float along = (q.x > q.y) ? g.y : g.x;
	float v = clamp((sd - band_out) / (band_in - band_out), 0.0, 1.0);
	float in_band = step(band_out, sd) * step(sd, band_in);
	float k = floor(along * 3.0);
	float u = fract(along * 3.0);
	float r = pc_hash21(vec2(k, 7.0));
	float stroke = 1.0 - smoothstep(0.05, 0.1, abs(u - 0.5));
	if (r > 0.3) {
		float dir = r > 0.65 ? 1.0 : -1.0;
		stroke = max(stroke, 1.0 - smoothstep(0.05, 0.1, abs((u - 0.5) - (v - 0.5) * 0.6 * dir)));
	}
	if (fract(r * 7.0) > 0.5) {
		stroke = max(stroke, (1.0 - smoothstep(0.08, 0.16, abs(v - 0.5))) * step(abs(u - 0.5), 0.28));
	}
	stroke *= step(abs(u - 0.5), 0.34) * in_band;
	stroke *= smoothstep(0.0, 0.18, v) * (1.0 - smoothstep(0.82, 1.0, v));
	float line_outer = 1.0 - smoothstep(0.0, 0.022, abs(sd + 0.015));
	float line_inner = 1.0 - smoothstep(0.0, 0.016, abs(sd + 0.255));
	float wave = 0.5 + 0.5 * sin(along * 1.3 - TIME * 2.2);
	float glow = (stroke + line_outer * 0.9 + line_inner * 0.55) * (0.35 + 0.65 * wave);
	float halo = exp(-abs(sd + 0.12) * 10.0) * 0.22 * (0.4 + 0.6 * wave);
	emission += rune_color * (rune_energy * glow + halo);
	col = mix(col, rune_color * 0.7, clamp(glow, 0.0, 1.0) * 0.65);

	// Glowing double frame around the crown field.
	if (hot_rect.z > 0.0) {
		vec2 hc = hot_rect.xy + hot_rect.zw * 0.5;
		vec2 hq = abs(g - hc) - hot_rect.zw * 0.5;
		float hsd = length(max(hq, vec2(0.0))) + min(max(hq.x, hq.y), 0.0);
		float hline = (1.0 - smoothstep(0.0, 0.03, abs(hsd + 0.03))) + 0.6 * (1.0 - smoothstep(0.0, 0.02, abs(hsd + 0.13)));
		float hwave = 0.6 + 0.4 * sin(TIME * 3.0 + (g.x + g.y) * 2.0);
		emission += hot_color * 3.0 * hline * hwave;
		col = mix(col, hot_color, clamp(hline, 0.0, 1.0) * 0.7);
	}

	// Normal from the procedural height field.
	float eps = 0.01;
	float hx = tile_height(g + vec2(eps, 0.0)) - tile_height(g - vec2(eps, 0.0));
	float hy = tile_height(g + vec2(0.0, eps)) - tile_height(g - vec2(0.0, eps));
	vec3 n_local = normalize(vec3(-hx / (2.0 * eps) * bevel_strength, 1.0, -hy / (2.0 * eps) * bevel_strength));
	if (v_normal.y > 0.95) {
		// Fine surface relief only on the block tops; chamfers and sides keep their geometric normals.
		NORMAL = normalize((VIEW_MATRIX * (MODEL_MATRIX * vec4(n_local, 0.0))).xyz);
	}

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
	EMISSION = emission;
}
