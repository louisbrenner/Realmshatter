// Soft camera-facing smoke/dust puff (alpha blended), colored by particle COLOR * tint.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

#include "res://Assets/Shaders/common.gdshaderinc"

instance uniform vec4 tint = vec4(1.0);
varying float v_seed;

void vertex() {
	v_seed = float(INSTANCE_ID) * 1.618;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float n = pc_fbm(p * 2.2 + vec2(v_seed, v_seed * 0.7) + vec2(TIME * 0.3, 0.0));
	float r = length(p) + (n - 0.5) * 0.55;
	float a = 1.0 - smoothstep(0.25, 0.95, r);
	vec4 c = COLOR * tint;
	ALBEDO = c.rgb * (0.8 + 0.4 * n);
	ALPHA = clamp(a * c.a, 0.0, 1.0);
}
