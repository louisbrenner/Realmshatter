// Flat ground marker: rotating attack reticle (pattern 0) or move destination ring (pattern 1).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.25, 0.2, 1.0);
uniform float energy = 2.0;
uniform int pattern = 0;
uniform float opacity = 1.0;
uniform float spin = 1.0;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float ang = atan(p.y, p.x) + TIME * spin;
	float pulse = 0.5 + 0.5 * sin(TIME * 5.0);
	float a;
	if (pattern == 0) {
		float ring = 1.0 - smoothstep(0.03, 0.07, abs(r - 0.6));
		ring *= step(0.22, fract(ang / 6.2831853 * 4.0));
		float ring2 = 1.0 - smoothstep(0.02, 0.05, abs(r - (0.86 - 0.08 * pulse)));
		ring2 *= step(0.5, fract(ang / 6.2831853 * 12.0));
		vec2 ap = abs(p);
		float tick = (1.0 - smoothstep(0.03, 0.06, min(ap.x, ap.y))) * step(0.2, max(ap.x, ap.y)) * step(max(ap.x, ap.y), 0.44);
		float dot_c = 1.0 - smoothstep(0.06, 0.1, r);
		a = max(max(ring, ring2 * 0.75), max(tick, dot_c));
	} else {
		float ring = 1.0 - smoothstep(0.035, 0.075, abs(r - (0.56 + 0.05 * pulse)));
		float dashes = step(0.35, fract(ang / 6.2831853 * 10.0));
		float fill = (1.0 - smoothstep(0.3, 0.6, r)) * 0.22;
		a = max(ring * mix(1.0, dashes, 0.5), fill);
	}
	ALBEDO = color.rgb * (1.0 + energy * a);
	ALPHA = clamp(a * opacity * color.a, 0.0, 1.0);
}
