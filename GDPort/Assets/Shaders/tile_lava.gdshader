// Molten lava tile (opaque, alpha scissor so heat haze can refract it): churning glowing flow with
// cooled crust plates, popping bubbles and a crusted, irregular rim. 'appear' reveals it from the center,
// 'cool' turns it into dark crust (expiry).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, shadows_disabled;

#include "res://Assets/Shaders/common.gdshaderinc"
#include "res://Assets/Shaders/lava_common.gdshaderinc"

uniform float energy = 1.9;
uniform float speed = 1.0;
uniform float appear = 1.0;
uniform float cool = 0.0;
uniform float seed = 0.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float t = TIME * speed;
	vec2 w = v_world.xz;
	float edge_n = pc_fbm(w * 4.0 + vec2(seed));
	float d = pc_sd_round_box(p, vec2(0.93), 0.3) + (edge_n - 0.5) * 0.14;
	float reveal = length(p) - appear * 1.8 + (edge_n - 0.5) * 0.4;
	float shape_d = max(d, reveal);

	float crust;
	float heat = lava_heat(w, t, crust);
	heat += lava_bubbles(w, t, seed) * 0.55;
	float rim = smoothstep(-0.3, 0.0, shape_d);
	heat *= (1.0 - rim * 0.7) * (1.0 - cool);
	crust = max(max(crust, rim * 0.75), cool);

	vec3 hot = lava_ramp(heat);
	vec3 crust_col = vec3(0.075, 0.045, 0.035) * (0.7 + 0.6 * pc_fbm(w * 7.0));
	float crust_mix = crust * 0.85;
	ALBEDO = mix(hot * 0.3, crust_col, crust_mix);
	EMISSION = hot * energy * heat * heat * (1.0 - crust * 0.8) + vec3(0.9, 0.18, 0.02) * 0.1 * (1.0 - cool);
	ROUGHNESS = mix(0.3, 0.95, crust);
	SPECULAR = 0.4;
	ALPHA = 1.0 - step(0.0, shape_d);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
