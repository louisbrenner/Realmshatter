// Translucent golden "divine shield" bubble: fresnel rim plus a slow shimmer.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.8, 0.35, 1.0);
uniform float energy = 1.6;
uniform float intensity = 1.0;

void fragment() {
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.2);
	vec2 uv = UV * vec2(14.0, 7.0);
	float shimmer = 0.5 + 0.5 * sin(uv.x * 2.0 + TIME * 2.2) * sin(uv.y * 3.0 - TIME * 1.6);
	float sweep = pow(0.5 + 0.5 * sin(UV.x * 6.2831853 + UV.y * 3.0 - TIME * 2.5), 8.0);
	float a = (0.08 + fres * 0.85 + shimmer * 0.06 + sweep * 0.18) * intensity;
	ALBEDO = mix(color.rgb, vec3(1.0, 0.97, 0.85), fres * 0.4) * energy;
	ALPHA = clamp(a, 0.0, 1.0);
}
