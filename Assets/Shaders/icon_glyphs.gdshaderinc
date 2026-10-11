// Shared SDF glyphs for the icon shaders (fx_icon.gdshader in 3D, keyword_icon.gdshader in the UI).
// Requires common.gdshaderinc. Coordinates: p in [-1, 1], y up.
// shape: 0 = snowflake, 1 = lightning bolt, 2 = skull, 3 = flame, 4 = plus, 5 = cross (X),
// 7 = fist, 8 = spear, 9 = bell. (6 = frost ring is handled by fx_icon itself.)

float pc_sd_snowflake(vec2 p) {
	float sector = 6.2831853 / 6.0;
	float a = atan(p.x, p.y);
	a = mod(a + sector * 0.5, sector) - sector * 0.5;
	vec2 q = length(p) * vec2(abs(sin(a)), cos(a));
	float d = pc_sd_segment(q, vec2(0.0), vec2(0.0, 0.74));
	d = min(d, pc_sd_segment(q, vec2(0.0, 0.42), vec2(0.21, 0.6)));
	d = min(d, pc_sd_segment(q, vec2(0.0, 0.2), vec2(0.14, 0.33)));
	return d - 0.065;
}

float pc_sd_bolt(vec2 p) {
	// Filled zig-zag bolt from two slanted quads.
	vec2 a = p - vec2(0.08, 0.38);
	float upper = max(abs(a.y) - 0.38, abs(a.x + a.y * 0.55) - 0.15);
	vec2 b = p - vec2(-0.08, -0.38);
	float lower = max(abs(b.y) - 0.38, abs(b.x + b.y * 0.55) - 0.15);
	float bar = pc_sd_box(p - vec2(0.0, 0.0), vec2(0.3, 0.09));
	return min(min(upper, lower), bar);
}

float pc_sd_skull(vec2 p) {
	float head = length(p - vec2(0.0, 0.14)) - 0.54;
	float jaw = pc_sd_round_box(p - vec2(0.0, -0.36), vec2(0.32, 0.22), 0.08);
	float d = min(head, jaw);
	float eyes = min(length(p - vec2(-0.21, 0.1)) - 0.15, length(p - vec2(0.21, 0.1)) - 0.15);
	float nose = max(max(-0.27 - p.y, p.y + 0.09), abs(p.x) - (-0.09 - p.y) * 0.55);
	float teeth = max(abs(fract(p.x * 5.0 + 0.5) - 0.5) / 5.0 - 0.014, abs(p.y + 0.46) - 0.1);
	d = max(d, -eyes);
	d = max(d, -nose);
	d = max(d, -teeth);
	return d;
}

float pc_sd_flame(vec2 p, float t) {
	vec2 q = p;
	q.x += 0.06 * sin(q.y * 7.0 + t * 7.0) * (q.y + 0.7);
	return pc_sd_drop(vec2(q.x * 1.15, q.y + 0.05)) / 1.15;
}

float pc_sd_plus(vec2 p) {
	return min(pc_sd_box(p, vec2(0.15, 0.55)), pc_sd_box(p, vec2(0.55, 0.15)));
}

// Clenched fist seen from the front: four knuckles over a palm block with a thumb across.
float pc_sd_fist(vec2 p) {
	float palm = pc_sd_round_box(p - vec2(0.0, -0.12), vec2(0.42, 0.3), 0.12);
	float fingers = 100000.0;
	for (int i = 0; i < 4; i++) {
		float x = -0.33 + 0.22 * float(i);
		fingers = min(fingers, pc_sd_round_box(p - vec2(x, 0.24), vec2(0.1, 0.2), 0.09));
	}
	float d = min(palm, fingers);
	// Gaps between the fingers (top part only).
	float gaps = 100000.0;
	for (int i = 0; i < 3; i++) {
		float x = -0.22 + 0.22 * float(i);
		gaps = min(gaps, max(abs(p.x - x) - 0.018, abs(p.y - 0.28) - 0.18));
	}
	d = max(d, -gaps);
	// Thumb across the palm (cut a thin outline, then add it back).
	float thumb = pc_sd_round_box(p - vec2(-0.05, -0.05), vec2(0.3, 0.07), 0.07);
	d = max(d, -(abs(thumb) - 0.025));
	float cuff = pc_sd_box(p - vec2(0.0, -0.58), vec2(0.3, 0.12));
	return min(d, cuff);
}

// Spear pointing to the upper right.
float pc_sd_spear(vec2 p) {
	vec2 q = pc_rot(-0.785398) * p;
	float shaft = pc_sd_box(q - vec2(0.0, -0.2), vec2(0.055, 0.62));
	float head = (abs(q.x) * 2.2 + abs(q.y - 0.55)) / 2.42 - 0.13;
	float guard = pc_sd_box(q - vec2(0.0, 0.3), vec2(0.17, 0.035));
	float butt = length(q - vec2(0.0, -0.84)) - 0.08;
	return min(min(shaft, head), min(guard, butt));
}

// Bell with crown, flared rim and clapper.
float pc_sd_bell(vec2 p) {
	float dome = length(p - vec2(0.0, 0.12)) - 0.36;
	float skirt = max(abs(p.x) - (0.36 + (0.12 - p.y) * 0.42), abs(p.y + 0.12) - 0.24);
	float rim = pc_sd_round_box(p - vec2(0.0, -0.4), vec2(0.6, 0.065), 0.05);
	float crown = length(p - vec2(0.0, 0.56)) - 0.1;
	float clapper = length(p - vec2(0.0, -0.6)) - 0.12;
	return min(min(min(dome, skirt), rim), min(crown, clapper));
}

// Distance to the glyph 'shape' at g (already scaled / rotated); t = time for animated glyphs.
float pc_icon_glyph(vec2 g, int shape, float t) {
	if (shape == 0) {
		return pc_sd_snowflake(g);
	} else if (shape == 1) {
		return pc_sd_bolt(g);
	} else if (shape == 2) {
		return pc_sd_skull(g);
	} else if (shape == 3) {
		return pc_sd_flame(g, t);
	} else if (shape == 4) {
		return pc_sd_plus(g);
	} else if (shape == 5) {
		return pc_sd_plus(pc_rot(0.785398) * g);
	} else if (shape == 7) {
		return pc_sd_fist(g);
	} else if (shape == 8) {
		return pc_sd_spear(g);
	}
	return pc_sd_bell(g);
}
