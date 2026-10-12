// River / pond water on a board tile: flowing deep-to-shallow blues, soft foam streaks and glints.
// World-space coordinates so neighbouring tiles join seamlessly into one river.
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, specular_schlick_ggx;

#include "res://Assets/Shaders/common.gdshaderinc"

uniform vec4 deep_color : source_color = vec4(0.06, 0.2, 0.36, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.22, 0.52, 0.68, 1.0);
uniform vec4 foam_color : source_color = vec4(0.85, 0.94, 1.0, 1.0);
uniform vec2 flow = vec2(0.22, 0.05);
uniform float opacity = 0.9;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float n1 = pc_fbm(p * 1.6 + flow * TIME * 2.0);
	float n2 = pc_fbm(p * 3.1 - flow.yx * TIME * 3.0 + vec2(5.2, 1.3));
	vec3 col = mix(deep_color.rgb, shallow_color.rgb, smoothstep(0.25, 0.75, n1 * 0.7 + n2 * 0.3));
	float streak = smoothstep(0.62, 0.7, pc_fbm(vec2(p.x * 2.2 - TIME * 0.35, p.y * 7.0)));
	col = mix(col, foam_color.rgb, streak * 0.35);
	float glint = pow(pc_vnoise(p * 9.0 + vec2(TIME * 0.8, -TIME * 0.5)), 10.0) * 2.0;
	col += foam_color.rgb * glint * 0.5;
	ALBEDO = col;
	ROUGHNESS = 0.12;
	SPECULAR = 0.7;
	ALPHA = opacity;
}
