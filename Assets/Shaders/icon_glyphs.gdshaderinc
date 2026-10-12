// Shared SDF glyphs for the icon shaders (fx_icon.gdshader in 3D, keyword_icon.gdshader in the UI).
// Requires common.gdshaderinc. Coordinates: p in [-1, 1], y up.
// shape: 0 = snowflake, 1 = lightning bolt, 2 = skull, 3 = flame, 4 = plus, 5 = cross (X),
// 7 = fist, 8 = spear, 9 = bell, 10 = tombstone (deathrattle), 11 = burst (first hit), 12 = hammer (builder),
// 13 = sun (aura), 14 = stake (planted), 15 = double chevron (move), 16 = crosshair (range), 17 = brick wall, 18 = mana gem (AP), 19 = trap jaws, 20 = bow and arrow. (6 = frost ring is handled by fx_icon itself.)

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

// Tombstone with a cross (deathrattle).
float pc_sd_tomb(vec2 p) {
	float stone = pc_sd_round_box(p - vec2(0.0, -0.08), vec2(0.36, 0.5), 0.05);
	stone = min(stone, length(p - vec2(0.0, 0.38)) - 0.36);
	stone = max(stone, -(p.y + 0.58));
	float cross = min(pc_sd_box(p - vec2(0.0, 0.08), vec2(0.06, 0.28)), pc_sd_box(p - vec2(0.0, 0.16), vec2(0.2, 0.06)));
	float ground = pc_sd_box(p - vec2(0.0, -0.66), vec2(0.62, 0.08));
	return min(max(stone, -cross), ground);
}

// Eight-pointed impact burst (first hit).
float pc_sd_burst(vec2 p) {
	float a = atan(p.y, p.x);
	float r = length(p);
	float spikes = 0.42 + 0.3 * pow(abs(cos(a * 4.0)), 6.0);
	return r - spikes;
}

// Hammer (builder).
float pc_sd_hammer(vec2 p) {
	vec2 q = pc_rot(0.6) * p;
	float handle = pc_sd_round_box(q - vec2(0.0, -0.2), vec2(0.07, 0.55), 0.04);
	float head = pc_sd_round_box(q - vec2(0.0, 0.42), vec2(0.38, 0.14), 0.04);
	return min(handle, head);
}

// Sun with rays (aura).
float pc_sd_sun(vec2 p) {
	float core = length(p) - 0.3;
	float a = atan(p.y, p.x);
	float ray = abs(fract(a / 6.2831853 * 8.0 + 0.5) - 0.5) * 0.85;
	float rays = max(length(p) - 0.66, ray - 0.12 + (length(p) - 0.36) * 0.0);
	rays = max(rays, 0.4 - length(p));
	return min(core, rays);
}

// Stake driven into the ground (planted): cap, shaft, downward point and the ground on both sides.
float pc_sd_stake(vec2 p) {
	float cap = pc_sd_round_box(p - vec2(0.0, 0.6), vec2(0.26, 0.08), 0.03);
	float shaft = pc_sd_box(p - vec2(0.0, 0.16), vec2(0.12, 0.4));
	float tip = max(p.y + 0.24, (abs(p.x) * 0.35 - (p.y + 0.6) * 0.14) / 0.377);
	tip = max(tip, -(p.y + 0.6));
	float ground = min(pc_sd_box(p - vec2(-0.46, -0.44), vec2(0.18, 0.05)), pc_sd_box(p - vec2(0.46, -0.44), vec2(0.18, 0.05)));
	return min(min(cap, min(shaft, tip)), ground);
}

// Two stacked upward chevrons (movement).
float pc_sd_chevrons(vec2 p) {
	p /= 1.2;
	vec2 q = vec2(abs(p.x), p.y);
	float upper = pc_sd_segment(q, vec2(0.0, 0.5), vec2(0.5, 0.06));
	float lower = pc_sd_segment(q, vec2(0.0, 0.0), vec2(0.5, -0.44));
	return (min(upper, lower) - 0.12) * 1.2;
}

// Ring with four ticks and a centre dot (range / target).
float pc_sd_crosshair(vec2 p) {
	p *= 1.1;
	float ring = abs(length(p) - 0.46) - 0.08;
	vec2 q = abs(p);
	float ticks = min(pc_sd_box(q - vec2(0.0, 0.66), vec2(0.07, 0.16)), pc_sd_box(q - vec2(0.66, 0.0), vec2(0.16, 0.07)));
	float dot_ = length(p) - 0.12;
	return min(min(ring, ticks), dot_) / 1.1;
}

// Three rows of offset bricks (wall).
float pc_sd_bricks(vec2 p) {
	float d = 1e3;
	for (int row = 0; row < 3; row++) {
		float y = 0.42 - float(row) * 0.42;
		float shift = (row == 1) ? 0.0 : 0.3;
		for (int i = -1; i <= 1; i++) {
			float x = float(i) * 0.6 + shift - 0.15;
			if (abs(x) < 0.85) {
				d = min(d, pc_sd_round_box(p - vec2(x, y), vec2(0.25, 0.16), 0.03));
			}
		}
	}
	return max(d, length(p) - 0.76);
}

// Faceted mana gem (AP): hexagon with a carved facet line.
float pc_sd_gem(vec2 p) {
	p /= 1.1;
	vec2 q = abs(p);
	float hex = max(q.x * 0.866 + q.y * 0.5, q.y) - 0.6;
	float facet = abs(p.y - 0.18) - 0.04;
	float edge = max(facet, q.x - 0.42);
	return max(hex, -edge) * 1.1;
}

// Trap jaws: a ring with teeth pointing inward and a trigger plate in the middle.
float pc_sd_trap(vec2 p) {
	float r = length(p);
	float a = atan(p.y, p.x);
	float ring = abs(r - 0.62) - 0.07;
	float tooth = pow(max(cos(a * 7.0), 0.0), 2.0);
	float teeth = max(r - 0.62, (0.62 - 0.26 * tooth) - r);
	teeth = max(teeth, 0.05 - tooth * 0.5);
	float plate = r - 0.16;
	return min(min(ring, teeth), plate);
}

// Bow and arrow (archers), drawn tilted: curved limb, pulled string, arrow with head and fletching.
float pc_sd_bow(vec2 p) {
	p = pc_rot(-0.6) * p;
	vec2 c = vec2(0.5, 0.0);
	float limb = max(abs(length(p - c) - 0.92) - 0.075, abs(p.y) - 0.7);
	limb = max(limb, p.x - 0.0);
	float string_top = pc_sd_segment(p, vec2(-0.07, 0.7), vec2(0.22, 0.0)) - 0.025;
	float string_bottom = pc_sd_segment(p, vec2(-0.07, -0.7), vec2(0.22, 0.0)) - 0.025;
	float shaft = pc_sd_segment(p, vec2(0.3, 0.0), vec2(-0.62, 0.0)) - 0.04;
	float head = pc_sd_round_box(pc_rot(0.785398) * (p - vec2(-0.66, 0.0)), vec2(0.11), 0.01);
	float fletch = min(pc_sd_segment(p, vec2(0.22, 0.0), vec2(0.36, 0.13)), pc_sd_segment(p, vec2(0.22, 0.0), vec2(0.36, -0.13))) - 0.035;
	return min(min(limb, min(string_top, string_bottom)), min(min(shaft, head), fletch));
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
	} else if (shape == 10) {
		return pc_sd_tomb(g);
	} else if (shape == 11) {
		return pc_sd_burst(g);
	} else if (shape == 12) {
		return pc_sd_hammer(g);
	} else if (shape == 13) {
		return pc_sd_sun(g);
	} else if (shape == 14) {
		return pc_sd_stake(g);
	} else if (shape == 15) {
		return pc_sd_chevrons(g);
	} else if (shape == 16) {
		return pc_sd_crosshair(g);
	} else if (shape == 17) {
		return pc_sd_bricks(g);
	} else if (shape == 18) {
		return pc_sd_gem(g);
	} else if (shape == 19) {
		return pc_sd_trap(g);
	} else if (shape == 20) {
		return pc_sd_bow(g);
	}
	return pc_sd_bell(g);
}
