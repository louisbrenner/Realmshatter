// Soft, pulsing tile highlight overlay (move / attack / deploy / spell / selected / hover).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

#include "res://Assets/Shaders/common.gdshaderinc"

uniform vec4 color : source_color = vec4(0.3, 0.75, 1.0, 0.6);
uniform float energy = 2.0;
uniform float pulse_speed = 3.0;
// 0 = fill + rim, 1 = attack (inward rings), 2 = hover (rim only), 3 = selected (strong rim)
uniform int pattern = 0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float d = pc_sd_round_box(p, vec2(0.84), 0.24);
	float phase = TIME * pulse_speed + (v_world.x + v_world.z) * 0.6;
	float pulse = 0.5 + 0.5 * sin(phase);
	float rim = exp(-abs(d) * 16.0);
	float inside = 1.0 - smoothstep(-0.02, 0.02, d);
	float fill = inside * (0.16 + 0.12 * pulse) * (0.55 + 0.45 * smoothstep(-0.9, 0.0, d));
	float a;
	if (pattern == 1) {
		float rings = fract(-d * 2.2 + TIME * 1.3);
		float ring = smoothstep(0.0, 0.15, rings) * (1.0 - smoothstep(0.15, 0.5, rings)) * inside;
		a = fill + rim * (0.7 + 0.3 * pulse) + ring * 0.3;
	} else if (pattern == 2) {
		a = rim * 0.75 + inside * 0.07;
	} else if (pattern == 3) {
		a = rim * (0.9 + 0.3 * pulse) + fill * 1.3;
	} else {
		a = fill + rim * (0.6 + 0.4 * pulse);
	}
	ALBEDO = color.rgb * (1.0 + rim * energy);
	ALPHA = clamp(a * color.a * 1.6, 0.0, 1.0);
}
