// Shared noise and signed-distance helpers for the procedural ProjectClaude shaders.
// Built-ins like TIME are not used here; pass them in as parameters.

float pc_hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float pc_hash11(float x) {
	return fract(sin(x * 127.1 + 311.7) * 43758.5453);
}

float pc_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = pc_hash21(i);
	float b = pc_hash21(i + vec2(1.0, 0.0));
	float c = pc_hash21(i + vec2(0.0, 1.0));
	float d = pc_hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float pc_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * pc_vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

mat2 pc_rot(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

float pc_sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

float pc_sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

float pc_sd_segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// Heater shield, roughly fits [-0.62, 0.62] x [-1.0, 0.75] (y up).
float pc_sd_shield(vec2 p) {
	if (p.y > 0.0) {
		return max(abs(p.x) - 0.62, p.y - 0.75);
	}
	return length(vec2(abs(p.x) + 0.5, p.y)) - 1.12;
}

// Water drop with the tip up, roughly fits [-0.55, 0.55] x [-0.67, 0.8] (y up).
float pc_sd_drop(vec2 p) {
	vec2 c = vec2(0.0, -0.12);
	float r = 0.55;
	float tip = 0.8;
	float d;
	if (p.y < c.y) {
		d = length(p - c) - r;
	} else {
		float k = clamp((p.y - c.y) / (tip - c.y), 0.0, 1.0);
		float w = r * sqrt(max(1.0 - k * k, 0.0)) * (1.0 - 0.35 * k);
		d = abs(p.x) - w;
	}
	return max(d, p.y - tip);
}

// Sword pointing up (+y), blade tip at y = 1.0, pommel near y = -0.95.
float pc_sd_sword(vec2 q) {
	float blade = max(pc_sd_box(q - vec2(0.0, 0.3), vec2(0.1, 0.7)), q.y + abs(q.x) * 2.5 - 1.0);
	float guard = pc_sd_box(q - vec2(0.0, -0.45), vec2(0.3, 0.07));
	float hilt = pc_sd_box(q - vec2(0.0, -0.68), vec2(0.07, 0.18));
	float pommel = length(q - vec2(0.0, -0.9)) - 0.1;
	return min(min(blade, guard), min(hilt, pommel));
}

// Role emblem: 0 = crossed swords, 1 = shield, 2 = gem/coin, 3 = star burst (buff), 4 = cracked skull-ish (debuff).
float pc_emblem(vec2 p, int kind) {
	if (kind == 0) {
		vec2 q1 = pc_rot(0.785398) * p;
		vec2 q2 = pc_rot(-0.785398) * p;
		return min(pc_sd_sword(q1 * 1.35), pc_sd_sword(q2 * 1.35)) / 1.35;
	} else if (kind == 1) {
		vec2 s = p * 1.45 - vec2(0.0, -0.12);
		float outer = pc_sd_shield(s) / 1.45;
		float inner = pc_sd_shield(s * 1.35) / (1.45 * 1.35);
		float cross_v = min(pc_sd_box(p - vec2(0.0, -0.03), vec2(0.04, 0.34)), pc_sd_box(p - vec2(0.0, 0.1), vec2(0.24, 0.04)));
		return min(max(outer, -inner + 0.0), cross_v);
	} else if (kind == 2) {
		float gem = (abs(p.x) * 1.0 + abs(p.y) * 0.75) - 0.42;
		float ring = abs(length(p) - 0.58) - 0.045;
		return min(gem, ring);
	} else if (kind == 3) {
		float a = atan(p.y, p.x);
		float r = length(p);
		float star = r - (0.3 + 0.18 * pow(abs(cos(a * 2.5)), 6.0));
		float hole = length(p) - 0.12;
		return max(star, -hole);
	}
	// 4: debuff, a downward broken arrow / jagged mark
	float a2 = atan(p.y, p.x);
	float r2 = length(p);
	float spiky = r2 - (0.36 + 0.1 * sin(a2 * 7.0));
	float hole = length(p - vec2(0.0, 0.05)) - 0.16;
	return max(spiky, -hole);
}

// Heart (health badge), p in [-1, 1] with y up; fills about [-0.88, 0.88] x [-0.8, 0.82].
float pc_sd_heart(vec2 p) {
	const float k = 0.68;
	vec2 h = vec2(abs(p.x), p.y + 0.8) * k;
	float d;
	if (h.y + h.x > 1.0) {
		d = length(h - vec2(0.25, 0.75)) - 0.35355339;
	} else {
		vec2 a = h - vec2(0.0, 1.0);
		vec2 b = h - 0.5 * max(h.x + h.y, 0.0);
		d = sqrt(min(dot(a, a), dot(b, b))) * sign(h.x - h.y);
	}
	return d / k;
}

// Attack crest: a bevelled diamond, p in [-1, 1] with y up.
float pc_sd_crest(vec2 p) {
	vec2 q = pc_rot(0.785398) * p;
	return pc_sd_round_box(q, vec2(0.5), 0.14);
}

// Area-attack marks around the attack crest: arrowheads beyond its outline pointing outward, one per direction of
// the attack's area. area: 0 = none, 1 = cross (4 tips), 2 = row (left + right), 3 = column (top + bottom),
// 4 = 2x2 square (the 4 diagonal edges). Same frame as pc_sd_crest (p in [-1, 1], y up).
float pc_sd_area_marks(vec2 p, int area) {
	float d = 1e5;
	if (area <= 0) {
		return d;
	}
	for (int i = 0; i < 4; i++) {
		bool on = area == 1 || area == 4 || (area == 2 && (i == 0 || i == 2)) || (area == 3 && (i == 1 || i == 3));
		if (!on) {
			continue;
		}
		float ang = float(i) * 1.5707963 + (area == 4 ? 0.785398 : 0.0);
		vec2 dir = vec2(cos(ang), sin(ang));
		float along = dot(p, dir);
		float across = abs(dot(p, vec2(-dir.y, dir.x)));
		float base = area == 4 ? 0.5 : 0.6;
		float tip = base + 0.27;
		d = min(d, max((across - (tip - along) * 0.6) * 0.86, base - along));
	}
	return d;
}
