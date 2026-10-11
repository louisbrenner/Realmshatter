// Expanding ground ring (summon slam, shield break). Drive "progress" from 0 to 1.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.85, 0.6, 1.0);
uniform float progress = 0.0;
uniform float energy = 2.0;
uniform float thickness = 0.12;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float rad = mix(0.12, 0.92, progress);
	float x = (r - rad) / thickness;
	float ring = exp(-x * x);
	float a = ring * (1.0 - progress) * (1.0 - smoothstep(0.94, 1.0, r));
	ALBEDO = color.rgb * energy;
	ALPHA = clamp(a * color.a, 0.0, 1.0);
}
