// Additive glowing ribbon (lightning arcs). UV.y = across (0..1).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.6, 0.8, 1.0, 1.0);
uniform float energy = 4.0;
uniform float opacity = 1.0;

void fragment() {
	float e = abs(UV.y - 0.5) * 2.0;
	float core = exp(-e * e * 14.0);
	float glow = exp(-e * 3.0) * 0.45;
	ALBEDO = mix(color.rgb, vec3(1.0), core * 0.75) * energy;
	ALPHA = clamp((core + glow) * opacity, 0.0, 1.0);
}
