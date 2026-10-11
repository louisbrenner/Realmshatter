// Additive elliptical glow ring around a token (playable = green, selected = gold).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.3, 1.0, 0.4, 1.0);
uniform float energy = 2.5;
uniform float inner = 0.62;
uniform float width = 0.2;
uniform float pulse_speed = 3.0;
uniform float intensity = 1.0;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float d = max(r - inner, 0.0);
	float glow = exp(-d / max(width, 0.001) * 2.5) * smoothstep(inner - 0.1, inner, r);
	float edge = 1.0 - smoothstep(0.86, 1.0, r);
	float ring = exp(-abs(r - inner - 0.02) * 40.0) * 0.6;
	float pulse = 0.72 + 0.28 * sin(TIME * pulse_speed);
	ALBEDO = color.rgb * energy;
	ALPHA = clamp((glow + ring) * edge * pulse * intensity, 0.0, 1.0);
}
