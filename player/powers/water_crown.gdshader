// The crown of a Dragon Breath splash, on an open cylinder DragonBreath
// scales up and out: a thin wall of water thrown up round the hole, glassy
// (the forest bent through it), streaming back down, its top torn into
// spikes of white foam that break up as it falls back.
// Instance uniforms: age (0..1), seed.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec3 water : source_color = vec3(0.3, 0.72, 0.98);
uniform vec3 foam : source_color = vec3(0.88, 0.97, 1.0);
instance uniform float age = 0.0;
instance uniform float seed = 0.0;

varying float v_h;
varying float v_ang;

void vertex() {
	v_h = VERTEX.y + 0.5;
	v_ang = atan(VERTEX.z, VERTEX.x) / 6.2831853;
	// The rim flares out more as it goes up, and wobbles.
	float wob = sin(v_ang * 6.2831853 * 5.0 + seed * 20.0) * 0.06;
	VERTEX.xz *= 1.0 + v_h * v_h * (0.35 + 0.5 * age) + wob * v_h;
}

void fragment() {
	float a = v_ang + seed;
	// A torn top edge: spikes, which split into beads as it falls back.
	float spikes = texture(noise, vec2(a * 3.0, seed + age * 0.2)).r;
	spikes = pow(spikes, 1.6);
	float edge = 1.0 - 0.55 * (1.0 - spikes) - 0.25 * age;
	float holes = texture(noise, vec2(a * 6.0, v_h * 0.9 - age * 0.6) + seed).g;
	if (v_h > edge || holes < age * 0.75 - 0.05) {
		discard;
	}
	float rim = smoothstep(edge - 0.22, edge, v_h);
	float streak = texture(noise, vec2(a * 9.0, v_h * 0.7 + age * 1.4)).b;
	float facing = abs(dot(NORMAL, VIEW));
	vec2 bend = NORMAL.xy * 0.05 + (streak - 0.5) * 0.03;
	vec3 behind = textureLod(screen_tex, SCREEN_UV + bend, 1.0).rgb;
	vec3 col = mix(behind * mix(vec3(1.0), water * 1.3, 0.55), foam, rim * 0.85 + smoothstep(0.62, 0.8, streak) * 0.35);
	col += water * (1.0 - facing) * 0.35;
	ALBEDO = col;
	float fade = (1.0 - age) * smoothstep(0.0, 0.12, v_h);
	ALPHA = clamp((0.45 + rim * 0.5 + (1.0 - facing) * 0.35) * fade, 0.0, 1.0);
}
