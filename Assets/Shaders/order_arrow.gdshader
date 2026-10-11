// Order arrow ribbon with scrolling chevrons. UV.x = distance along the path (world units),
// UV.y = across (0..1). Arrow head triangles have UV2.x = 1 and UV = (across 0..1, along 0..1).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.35, 0.8, 1.0, 1.0);
uniform vec4 outline_color : source_color = vec4(0.02, 0.04, 0.08, 1.0);
uniform float energy = 1.6;
uniform float speed = 1.2;
uniform float density = 2.4;
uniform float opacity = 0.9;
uniform float fade_start = 0.3;
uniform float pulse = 0.0;
// Dashes per world unit along the body (0 = solid). Used for predicted chain shots.
uniform float dash = 0.0;

void fragment() {
	bool head = UV2.x > 0.5;
	if (!head && dash > 0.0 && fract(UV.x * dash - TIME * speed * 0.6) > 0.58) {
		discard;
	}
	float edge_d;
	float chev = 0.0;
	if (head) {
		float half_w = 0.5 * (1.0 - UV.y);
		edge_d = (half_w - abs(UV.x - 0.5)) * 1.2;
		chev = 0.35 + 0.35 * sin(TIME * 6.0);
	} else {
		float e = abs(UV.y - 0.5) * 2.0;
		edge_d = (1.0 - e) * 0.5;
		float c = fract(UV.x * density - TIME * speed - e * 0.35);
		chev = smoothstep(0.0, 0.12, c) * (1.0 - smoothstep(0.32, 0.48, c));
	}
	float outline = 1.0 - smoothstep(0.07, 0.13, edge_d);
	float p = 1.0 + pulse * (0.3 + 0.3 * sin(TIME * 7.0));
	vec3 inner = color.rgb * (0.85 + chev * energy) * p;
	vec3 col = mix(inner, outline_color.rgb, outline * 0.85);
	float a = opacity * (head ? 1.0 : smoothstep(0.0, fade_start, UV.x));
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
}
