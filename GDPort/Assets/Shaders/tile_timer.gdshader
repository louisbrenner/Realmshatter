// Camera-facing duration badge for tile effects: dark coin with a ring of pips (lit = remaining turns).
// The number itself is a Label3D on top.
shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.5, 0.12, 1.0);
uniform vec4 center_color : source_color = vec4(0.08, 0.05, 0.04, 0.92);
uniform int total = 2;
uniform int lit = 2;
uniform float alpha = 1.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 p = vec2(UV.x - 0.5, 0.5 - UV.y) * 2.0;
	float r = length(p);
	float n = float(max(total, 1));
	float ang = fract(atan(p.x, p.y) / 6.2831853 + 1.0);
	float idx = floor(ang * n);
	float u = fract(ang * n);
	float seg_mask = smoothstep(0.03, 0.09, u) * (1.0 - smoothstep(0.91, 0.97, u));
	float band = (1.0 - smoothstep(0.0, 0.035, abs(r - 0.8) - 0.1));
	bool is_lit = idx < float(lit);
	vec3 pip = is_lit ? color.rgb * 1.8 : vec3(0.22, 0.2, 0.19);
	float center = 1.0 - smoothstep(0.62, 0.66, r);
	float outer = 1.0 - smoothstep(0.96, 1.0, r);
	vec3 c = vec3(0.04, 0.03, 0.02);
	c = mix(c, center_color.rgb + color.rgb * 0.12 * (1.0 - r), center);
	c = mix(c, pip, band * seg_mask);
	float a = max(outer * 0.95, center * center_color.a);
	ALBEDO = c;
	ALPHA = clamp(a * alpha, 0.0, 1.0);
}
