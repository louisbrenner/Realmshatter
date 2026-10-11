// Translucent hologram-like preview for boxes (predicted walls): fresnel rim, glowing edges, rising scanlines.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 color : source_color = vec4(0.8, 0.74, 0.62, 1.0);
uniform float opacity = 0.7;
uniform float energy = 1.6;
uniform vec3 half_size = vec3(0.43, 0.3, 0.43);

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float scan = step(0.6, fract(v_local.y * 14.0 - TIME * 1.5));
	float pulse = 0.5 + 0.5 * sin(TIME * 4.0);
	vec3 q = abs(v_local) / max(half_size, vec3(0.001));
	float e1 = step(0.93, q.x) * step(0.93, q.y);
	float e2 = step(0.93, q.y) * step(0.93, q.z);
	float e3 = step(0.93, q.x) * step(0.93, q.z);
	float edge = clamp(e1 + e2 + e3, 0.0, 1.0);
	ALBEDO = color.rgb * energy * (1.0 + fres + edge * 1.5);
	float a = (0.16 + 0.45 * fres + 0.12 * scan + 0.7 * edge) * (0.75 + 0.25 * pulse);
	ALPHA = clamp(a * opacity, 0.0, 1.0);
}
