// Procedural stone masonry for wall blocks (BoxMesh): offset brick courses on the sides, slabs on top,
// mottling, cracks, a little moss and darkened brick edges. 'crumble' (0..1) dissolves the stones.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://Assets/Shaders/common.gdshaderinc"

uniform vec3 stone_light : source_color = vec3(0.66, 0.62, 0.56);
uniform vec3 stone_dark : source_color = vec3(0.3, 0.28, 0.26);
uniform vec3 mortar_color : source_color = vec3(0.12, 0.1, 0.09);
uniform vec3 moss_color : source_color = vec3(0.3, 0.38, 0.16);
uniform float brick_h = 0.16;
uniform float brick_w = 0.3;
uniform float crumble = 0.0;
uniform float seed = 0.0;
uniform vec3 hot_edge : source_color = vec3(0.9, 0.75, 0.5);
// Size (x, z) of this mesh's top face, so each top face is one slab.
instance uniform vec2 top_size = vec2(0.9, 0.9);

varying vec3 v_local;
varying vec3 v_n;

void vertex() {
	v_local = VERTEX;
	v_n = NORMAL;
}

void fragment() {
	vec3 an = abs(v_n);
	vec2 uv;
	bool top = an.y > 0.5;
	if (top) {
		// One solid slab per top face: mortar only along the face border.
		uv = v_local.xz / max(top_size, vec2(0.01)) + vec2(0.5);
	} else if (an.x > 0.5) {
		uv = vec2(v_local.z / brick_w, v_local.y / brick_h);
	} else {
		uv = vec2(v_local.x / brick_w, v_local.y / brick_h);
	}
	if (!top) {
		float row = floor(uv.y);
		uv.x += mod(row, 2.0) * 0.5 + seed * 0.37;
	}
	vec2 cell = floor(uv);
	vec2 f = fract(uv);
	float mx = min(f.x, 1.0 - f.x) * (top ? 1.0 : brick_w / brick_h);
	float my = min(f.y, 1.0 - f.y);
	float edge = min(mx, my);
	float mortar = 1.0 - smoothstep(0.035, 0.075, edge);
	float h = pc_hash21(cell + vec2(seed, 0.37) + floor(v_n.xz * 3.0 + 3.0));
	float n = pc_fbm(uv * 3.0 + cell * 1.7);
	vec3 col = mix(stone_dark, stone_light, 0.3 + 0.55 * h) * (0.78 + 0.38 * n);
	float moss = smoothstep(0.6, 0.78, pc_fbm(v_local.xz * 3.0 + vec2(v_local.y * 2.0 + seed))) * (top ? 0.3 : 0.7);
	col = mix(col, moss_color, moss * 0.55);
	float crack = 1.0 - smoothstep(0.0, 0.025, abs(pc_fbm(uv * 1.6 + vec2(seed * 3.0, 1.0)) - 0.5));
	col *= 1.0 - crack * (0.35 + crumble * 0.5);
	col *= 0.7 + 0.3 * smoothstep(0.0, 0.2, edge);
	col = mix(col, mortar_color, mortar);

	float dn = pc_fbm(uv * 1.3 + vec2(seed, seed * 1.7));
	float cut = crumble * 1.15 - 0.08;
	if (crumble > 0.001 && dn < cut) {
		discard;
	}
	float burn = crumble > 0.001 ? 1.0 - smoothstep(0.0, 0.05, dn - cut) : 0.0;
	ALBEDO = mix(col, hot_edge * 0.6, burn * 0.6);
	EMISSION = hot_edge * burn * 0.4;
	ROUGHNESS = 0.9 - 0.1 * h;
	SPECULAR = 0.25;
}
