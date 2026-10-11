// Heat shimmer above lava: refracts the opaque scene behind a soft round mask with wobbling offsets.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 1.0;
uniform float amount = 0.006;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float m = (1.0 - smoothstep(0.35, 1.0, length(p))) * strength;
	vec2 off = vec2(sin(v_world.x * 13.0 + TIME * 5.1 + v_world.z * 4.0), cos(v_world.z * 12.0 + TIME * 4.3 - v_world.x * 3.0)) * amount * m;
	vec3 c = textureLod(screen_texture, SCREEN_UV + off, 0.0).rgb;
	ALBEDO = c * (1.0 + 0.05 * m) + vec3(0.06, 0.015, 0.0) * m;
	ALPHA = clamp(m * 1.5, 0.0, 1.0);
}
