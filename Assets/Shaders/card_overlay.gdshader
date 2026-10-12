// Printed overlay above the full-bleed card art: name bar (top), optional rules panel, the type plate at the
// bottom (its outline shows the card kind, a lighter clan line its edge) and a soft glossy sheen. Everything is drawn with alpha so a real
// artwork texture below stays visible around the panels.
// plate_shape: 0 = unit (notched ribbon), 1 = spell (pill), 2 = area spell (pointed hexagon), 3 = totem (octagon).
shader_type canvas_item;

#include "res://Assets/Shaders/common.gdshaderinc"

uniform vec2 card_size = vec2(150.0, 210.0);
uniform vec4 name_rect = vec4(5.0, 5.0, 140.0, 25.0);
uniform vec4 text_rect = vec4(10.0, 116.0, 130.0, 50.0);
uniform bool has_text = true;
uniform vec4 plate_rect = vec4(36.0, 186.0, 78.0, 20.0);
uniform int plate_shape = 0;
uniform vec3 clan_color : source_color = vec3(0.75, 0.7, 0.62);
uniform vec3 rarity_color : source_color = vec3(0.8, 0.8, 0.8);

float sd_rect(vec2 px, vec4 rect, float r) {
	vec2 c = rect.xy + rect.zw * 0.5;
	return pc_sd_round_box(px - c, rect.zw * 0.5, r);
}

float sd_plate(vec2 px) {
	vec2 c = plate_rect.xy + plate_rect.zw * 0.5;
	vec2 q = abs(px - c);
	vec2 b = vec2(plate_rect.z * 0.5 - 7.0, plate_rect.w * 0.5);
	if (plate_shape == 0) {
		// Ribbon with V-notched tails.
		float body = max(q.x - b.x - 7.0, q.y - b.y);
		float notch = (q.x - b.x - 7.0 * q.y / b.y) * 0.75;
		return max(body, notch);
	} else if (plate_shape == 1) {
		return pc_sd_round_box(px - c, vec2(b.x + 4.0, b.y), b.y);
	} else if (plate_shape == 2) {
		float side = (q.x - b.x - (b.y - q.y) * 0.85) * 0.76;
		return max(q.y - b.y, side);
	}
	float box = max(q.x - b.x - 3.0, q.y - b.y);
	return max(box, (q.x + q.y - (b.x + 3.0 + b.y - 6.0)) * 0.707);
}

// Straight-alpha "source over" compositing of a layer (col, a) onto dst.
vec4 over(vec4 dst, vec3 col, float a) {
	float out_a = a + dst.a * (1.0 - a);
	vec3 rgb = out_a > 0.0001 ? (col * a + dst.rgb * dst.a * (1.0 - a)) / out_a : vec3(0.0);
	return vec4(rgb, out_a);
}

void fragment() {
	vec2 px = UV * card_size;
	vec4 c = vec4(0.0);
	float grain = pc_vnoise(px * 1.6);

	// Name bar: dark, clan-tinted band with a clan-coloured underline.
	float nd = sd_rect(px, name_rect, 4.0);
	float in_name = 1.0 - smoothstep(-0.6, 0.6, nd);
	vec3 bar = mix(vec3(0.07, 0.05, 0.035), clan_color * 0.35, 0.55) * (0.9 + 0.12 * grain);
	c = over(c, bar, in_name * 0.86);
	float underline = (1.0 - smoothstep(0.4, 1.4, abs(px.y - (name_rect.y + name_rect.w)))) * step(name_rect.x, px.x) * step(px.x, name_rect.x + name_rect.z);
	c = over(c, clan_color, underline);

	// Rules panel: printed parchment with a clan rim.
	if (has_text) {
		float td = sd_rect(px, text_rect, 5.0);
		vec3 parch = vec3(0.94, 0.88, 0.75) * (0.9 + 0.12 * pc_fbm(px * 0.08 + vec2(3.0))) * (0.96 + 0.06 * grain);
		c = over(c, vec3(0.0), (1.0 - smoothstep(0.0, 4.0, td)) * step(0.0, td) * 0.35);
		c = over(c, parch, (1.0 - smoothstep(-0.6, 0.6, td)) * 0.93);
		c = over(c, clan_color * 0.7, 1.0 - smoothstep(0.5, 1.4, abs(td + 0.5)));
	}

	// Type plate: kind shown by the outline shape, clan fill, rarity rim.
	float pd = sd_plate(px);
	c = over(c, vec3(0.0), (1.0 - smoothstep(0.0, 3.0, pd)) * step(0.0, pd) * 0.45);
	vec3 fill = clan_color * (0.55 + 0.35 * (1.0 - (px.y - plate_rect.y) / plate_rect.w)) * (0.92 + 0.1 * grain);
	c = over(c, fill, 1.0 - smoothstep(-0.6, 0.6, pd));
	c = over(c, clan_color * 1.25, (1.0 - smoothstep(0.4, 1.3, abs(pd + 1.6))) * 0.6);
	c = over(c, vec3(0.06, 0.04, 0.03), 1.0 - smoothstep(0.3, 1.0, abs(pd)));

	// Gloss: a soft diagonal sheen across the whole card face.
	float diag = (UV.x * 0.8 - UV.y) + 0.35;
	float sheen = exp(-diag * diag * 40.0) * 0.07;
	c = over(c, vec3(1.0, 0.98, 0.92), sheen);
	COLOR = vec4(c.rgb, clamp(c.a, 0.0, 1.0)) * COLOR.a;
}
