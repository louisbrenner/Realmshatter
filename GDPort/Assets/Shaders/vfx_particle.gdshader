// Additive, camera-facing glow sprite for particles and motes. Particle COLOR * tint, HDR energy for bloom.
// shape: 0 = soft dot, 1 = star sparkle, 2 = ring.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float energy = 2.2;
uniform int shape = 0;
instance uniform vec4 tint = vec4(1.0);

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a;
	if (shape == 1) {
		vec2 ap = abs(p);
		float rays = (1.0 - smoothstep(0.0, 0.1, min(ap.x, ap.y))) * max(1.0 - r, 0.0);
		a = max(rays * 1.6, exp(-r * 7.0));
	} else if (shape == 2) {
		a = 1.0 - smoothstep(0.0, 0.18, abs(r - 0.7));
	} else {
		a = exp(-r * r * 4.0) * (1.0 - smoothstep(0.8, 1.0, r));
	}
	vec4 c = COLOR * tint;
	float core = exp(-r * r * 18.0);
	ALBEDO = (c.rgb + vec3(core) * 0.3) * energy;
	ALPHA = clamp(a * c.a, 0.0, 1.0);
}
