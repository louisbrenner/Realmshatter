// Ground left behind by clan attacks (see TileEffectType): kind 0 = Ice (pale cracked sheet with glints),
// 1 = Storm cell (dark violet with crackling arcs), 2 = Mud (wet brown puddle with slow ripples).
// 'opacity' fades it in / out (also used for ghost previews), 'hatch' adds preview stripes.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

#include "res://Assets/Shaders/common.gdshaderinc"

uniform int kind = 0;
uniform float opacity = 1.0;
uniform float seed = 0.0;
uniform float hatch = 0.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float box = pc_sd_round_box(p, vec2(0.9), 0.3);
	float inside = 1.0 - smoothstep(-0.06, 0.02, box);
	float edge = exp(-abs(box) * 12.0);
	vec2 w = v_world.xz * 3.0 + vec2(seed);
	vec3 col;
	float a;
	if (kind == 0) {
		// Ice: frosted sheet, dark cracks (cellular), sparkling glints.
		float n = pc_fbm(w * 1.2);
		col = mix(vec3(0.62, 0.82, 0.95), vec3(0.88, 0.96, 1.0), n);
		vec2 cell = fract(w * 0.9) - 0.5;
		float crack = 1.0 - smoothstep(0.0, 0.05, min(abs(cell.x + 0.15 * sin(w.y * 3.0)), abs(cell.y + 0.15 * sin(w.x * 3.0))));
		col = mix(col, vec3(0.35, 0.55, 0.75), crack * 0.6);
		float glint = pow(pc_vnoise(w * 4.0 + vec2(TIME * 0.4, 0.0)), 14.0) * 3.0;
		col += vec3(1.0) * glint;
		a = inside * 0.62 + edge * 0.35;
	} else if (kind == 1) {
		// Storm cell: dark violet ground with flickering lightning lines.
		float n = pc_fbm(w * 0.8 + vec2(0.0, TIME * 0.3));
		col = mix(vec3(0.18, 0.1, 0.32), vec3(0.42, 0.26, 0.7), n);
		float flicker = step(0.55, fract(sin(floor(TIME * 9.0 + seed) * 12.9898) * 43758.5453));
		float lines = 1.0 - smoothstep(0.0, 0.035, abs(sin(w.x * 2.3 + pc_fbm(w + TIME) * 3.0) * 0.5 + p.y * 0.4));
		col += vec3(0.85, 0.75, 1.0) * lines * (0.35 + 0.65 * flicker);
		a = inside * 0.6 + edge * 0.4 + lines * 0.3 * inside;
	} else {
		// Mud: wet brown puddle with slow ripples and a darker rim.
		float n = pc_fbm(w * 1.1);
		col = mix(vec3(0.24, 0.16, 0.08), vec3(0.42, 0.3, 0.17), n);
		float ripple = 0.5 + 0.5 * sin(length(p) * 14.0 - TIME * 1.4 + seed);
		col += vec3(0.08, 0.06, 0.04) * ripple * (1.0 - length(p) * 0.6);
		col = mix(col, vec3(0.15, 0.1, 0.05), edge * 0.6);
		a = inside * 0.8 + edge * 0.2;
	}
	if (hatch > 0.0) {
		float stripes = step(0.5, fract((p.x + p.y) * 4.0));
		a *= mix(1.0, 0.55 + 0.45 * stripes, hatch);
	}
	ALBEDO = col;
	ALPHA = clamp(a * opacity, 0.0, 1.0);
}
