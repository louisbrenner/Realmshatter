// Molten lava pattern shared by tile_lava (opaque) and tile_lava_ghost (preview).
// Requires common.gdshaderinc to be included first. Time is passed in as a parameter.

vec3 lava_ramp(float h) {
	vec3 c0 = vec3(0.06, 0.012, 0.006);
	vec3 c1 = vec3(0.6, 0.06, 0.012);
	vec3 c2 = vec3(1.0, 0.36, 0.03);
	vec3 c3 = vec3(1.0, 0.72, 0.25);
	h = clamp(h, 0.0, 1.0);
	if (h < 0.4) {
		return mix(c0, c1, h / 0.4);
	}
	if (h < 0.75) {
		return mix(c1, c2, (h - 0.4) / 0.35);
	}
	return mix(c2, c3, (h - 0.75) / 0.25);
}

// Heat 0..1 (0 = cold, 1 = white hot) of slowly churning lava at world xz 'w'. 'crust' = cooled plates 0..1.
float lava_heat(vec2 w, float t, out float crust) {
	vec2 flow = vec2(pc_fbm(w * 1.1 + vec2(t * 0.12, 0.0)), pc_fbm(w * 1.1 + vec2(5.2, 1.3) - vec2(0.0, t * 0.1)));
	float n = pc_fbm(w * 2.2 + flow * 1.8 + vec2(t * 0.08, -t * 0.05));
	float ridge = 1.0 - abs(pc_fbm(w * 3.4 + flow * 2.4 - vec2(t * 0.04)) * 2.0 - 1.0);
	ridge = pow(clamp(ridge, 0.0, 1.0), 5.0);
	crust = smoothstep(0.56, 0.38, n) * (1.0 - ridge);
	return clamp(smoothstep(0.35, 0.85, n) * 0.7 + ridge * 0.85, 0.0, 1.0);
}

// Bright rings of bubbles that swell and pop.
float lava_bubbles(vec2 w, float t, float seed) {
	vec2 bc = w * 2.6;
	vec2 bi = floor(bc);
	vec2 bf = fract(bc) - 0.5;
	float h = pc_hash21(bi + vec2(seed, 3.1));
	float ph = fract(t * (0.35 + 0.5 * h) + h * 7.0);
	vec2 c = (vec2(pc_hash21(bi + vec2(1.3, seed)), pc_hash21(bi + vec2(seed, 2.7))) - 0.5) * 0.45;
	float rad = 0.05 + ph * 0.2;
	float d = length(bf - c);
	float ring = 1.0 - smoothstep(0.0, 0.035, abs(d - rad));
	float dome = (1.0 - smoothstep(rad - 0.05, rad, d)) * 0.45;
	return (ring + dome) * step(0.45, h) * smoothstep(1.0, 0.75, ph) * smoothstep(0.0, 0.1, ph);
}
