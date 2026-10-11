// Procedural varnished wood (world space): grain along grain_axis, optional planks with seams.
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

#include "res://Assets/Shaders/common.gdshaderinc"

uniform vec3 wood_light : source_color = vec3(0.56, 0.33, 0.17);
uniform vec3 wood_dark : source_color = vec3(0.24, 0.12, 0.06);
uniform vec3 grain_axis = vec3(1.0, 0.0, 0.0);
uniform float grain_scale = 1.0;
uniform float plank_width = 0.0;
uniform float roughness_value = 0.5;
uniform float varnish = 0.45;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 ax = normalize(grain_axis);
	vec3 side = normalize(cross(ax, vec3(0.0, 1.0, 0.0)));
	float a = dot(v_world, ax) * grain_scale;
	float s = dot(v_world, side) * grain_scale;
	float h = v_world.y * grain_scale;
	float plank_id = 0.0;
	float seam = 0.0;
	if (plank_width > 0.0) {
		float ps = s / plank_width;
		plank_id = floor(ps);
		float pf = fract(ps);
		seam = 1.0 - smoothstep(0.0, 0.025, min(pf, 1.0 - pf));
		a += pc_hash11(plank_id) * 13.0;
		float pe = fract(a / 7.0);
		seam = max(seam, (1.0 - smoothstep(0.0, 0.004, min(pe, 1.0 - pe))));
	}
	float warp = pc_fbm(vec2(a * 0.35, s * 2.0 + plank_id * 7.0));
	float rings = fract((s + h) * 6.0 + warp * 3.5);
	float grain = smoothstep(0.0, 0.5, rings) * (1.0 - smoothstep(0.5, 1.0, rings));
	float fine = pc_fbm(vec2(a * 1.5, s * 38.0 + h * 38.0));
	vec3 col = mix(wood_dark, wood_light, grain * 0.55 + fine * 0.45);
	if (plank_width > 0.0) {
		col *= 0.82 + 0.32 * pc_hash11(plank_id + 3.0);
	}
	col = mix(col, wood_dark * 0.3, seam);
	ALBEDO = col;
	ROUGHNESS = clamp(roughness_value + fine * 0.2 + seam * 0.3, 0.0, 1.0);
	SPECULAR = varnish;
}
