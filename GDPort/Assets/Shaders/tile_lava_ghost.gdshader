// Translucent, pulsing preview of a lava tile (spell / Burning targeting).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

#include "res://Assets/Shaders/common.gdshaderinc"
#include "res://Assets/Shaders/lava_common.gdshaderinc"

uniform float opacity = 1.0;
uniform float energy = 1.6;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	vec2 w = v_world.xz;
	float pulse = 0.5 + 0.5 * sin(TIME * 4.0);
	float d = pc_sd_round_box(p, vec2(0.9), 0.3);
	float inside = 1.0 - smoothstep(-0.02, 0.02, d);
	float outline = exp(-abs(d) * 18.0);
	float crust;
	float heat = lava_heat(w, TIME, crust);
	float hatch = step(0.55, fract((w.x + w.y) * 3.0 - TIME * 0.8));
	vec3 col = lava_ramp(0.5 + heat * 0.3);
	ALBEDO = col * energy * (1.0 + outline * 1.5);
	float a = inside * (0.3 + 0.25 * heat + 0.12 * hatch) * (0.75 + 0.25 * pulse) + outline * 0.85;
	ALPHA = clamp(a * opacity, 0.0, 1.0);
}
