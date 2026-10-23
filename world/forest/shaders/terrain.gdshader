// Forest floor: meadow grass that shares its colour with the grass blades,
// worn footpaths with pebbles, leaf litter under the canopy, dark mud at the
// water's edge and biplanar mossy rock on steep slopes.
shader_type spatial;
render_mode diffuse_lambert_wrap;

#include "ground.gdshaderinc"

uniform sampler2D rock_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 dirt_a : source_color = vec3(0.45, 0.33, 0.20);
uniform vec3 dirt_b : source_color = vec3(0.62, 0.50, 0.33);
uniform vec3 pebble : source_color = vec3(0.70, 0.66, 0.58);
uniform vec3 litter : source_color = vec3(0.36, 0.26, 0.14);
uniform vec3 mud : source_color = vec3(0.20, 0.16, 0.11);
uniform vec3 sand : source_color = vec3(0.62, 0.55, 0.40);
uniform vec3 algae : source_color = vec3(0.22, 0.34, 0.12);
uniform vec3 rock_tint : source_color = vec3(1.0);
uniform float rock_scale = 0.16;

varying vec3 v_wp;
varying vec3 v_wn;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = v_wp.xz;
	float shade = COLOR.a;
	float wet = COLOR.b;
	vec4 n = texture(ground_noise, p * 0.21);
	vec4 nf = texture(ground_noise, p * 1.1);

	vec3 c = ground_grass(p, shade, wet);
	// fine mottling so close-up ground never looks flat
	c *= 0.9 + 0.2 * nf.g;

	// leaf litter pools under heavy canopy
	float lit = smoothstep(0.45, 0.85, shade + (n.b - 0.5) * 0.5);
	c = mix(c, litter * (0.8 + 0.4 * nf.r), lit * 0.55);

	// worn footpath with scattered pebbles
	float pm = smoothstep(0.38, 0.62, COLOR.r + (n.r - 0.5) * 0.55);
	vec3 dirt = mix(dirt_a, dirt_b, smoothstep(0.2, 0.8, n.g)) * (0.85 + 0.3 * nf.b);
	float peb = smoothstep(0.82, 0.9, nf.a) * smoothstep(0.3, 0.8, n.b);
	dirt = mix(dirt, pebble * (0.8 + 0.3 * nf.r), peb);
	dirt = mix(dirt, dirt * 0.75, shade * 0.6);
	c = mix(c, dirt, pm);

	// dark wet mud along water
	float mudm = smoothstep(0.55, 0.95, wet + (n.g - 0.5) * 0.4);
	c = mix(c, mud * (0.8 + 0.4 * nf.b), mudm * 0.85);

	// Under water: pale sand and pebbles in the shallows, weed-green deeper.
	float under = smoothstep(0.03, 0.18, UV.x);
	if (under > 0.0) {
		float pebs = smoothstep(0.55, 0.8, nf.a) * (0.7 + 0.3 * n.r);
		vec3 bed = mix(sand * (0.85 + 0.25 * nf.r), pebble * (0.6 + 0.5 * nf.b), pebs * 0.8);
		float weed = smoothstep(0.25, 0.9, UV.x * 0.8 + (n.g - 0.5) * 0.8);
		bed = mix(bed, algae * (0.7 + 0.6 * nf.g), weed * 0.75);
		c = mix(c, bed, under);
		mudm *= 1.0 - under;
	}

	// rock on steep ground
	float rm = smoothstep(0.3, 0.7, COLOR.g + (n.r - 0.5) * 0.5);
	if (rm > 0.001) {
		vec3 bw = pow(abs(v_wn), vec3(4.0));
		bw /= (bw.x + bw.y + bw.z);
		vec3 rk = texture(rock_tex, v_wp.zy * rock_scale).rgb * bw.x
				+ texture(rock_tex, v_wp.xz * rock_scale).rgb * bw.y
				+ texture(rock_tex, v_wp.xy * rock_scale).rgb * bw.z;
		c = mix(c, rk * rock_tint, rm);
	}

	ALBEDO = c;
	ROUGHNESS = mix(0.95, 0.35, mudm);
	SPECULAR = mix(0.2, 0.45, mudm);
	AO = 1.0 - shade * 0.55;
	AO_LIGHT_AFFECT = 0.15;
}
