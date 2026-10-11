// Full-screen warm vignette (ColorRect on a CanvasLayer below the HUD).
shader_type canvas_item;

uniform float strength = 0.6;
uniform float radius = 1.05;
uniform float softness = 0.7;
uniform vec3 tint : source_color = vec3(0.06, 0.03, 0.01);

void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.0, 0.9) * 1.4142;
	float v = smoothstep(radius - softness, radius, length(d));
	COLOR = vec4(tint, v * strength);
}
