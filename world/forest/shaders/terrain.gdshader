// Forest floor: meadow grass that shares its colour with the grass blades,
// worn footpaths with a trampled verge and little stones, bare soil and moss
// where trunks and boulders stand, leaf litter under the canopy, dark mud at
// the water's edge and mossy rock breaking through steep slopes.
shader_type spatial;
render_mode diffuse_lambert_wrap;

#include "ground.gdshaderinc"

uniform sampler2D rock_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 rock_tint : source_color = vec3(1.0);
uniform float rock_scale = 0.16;
// Where the grass blades have shrunk away with distance, the meadow keeps
// their sunny colour so the fade never shows.
uniform vec3 blade_tint : source_color = vec3(0.62, 0.72, 0.26);
uniform float blade_fade_start = 17.0;
uniform float blade_fade_end = 30.0;

varying vec3 v_wp;
varying vec3 v_wn;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = v_wp.xz;
	vec4 m = COLOR;
	vec4 det = texture(ground_detail, ground_detail_uv(p)) * ground_inside(p);
	if (ground_blend < 0.5) {
		// No baked ground (e.g. a test scene): fall back to the soft vertex path.
		det.b = m.r * 0.62;
	}

	vec3 rk = vec3(0.0);
	if (m.g > 0.05) {
		vec3 bw = pow(abs(v_wn), vec3(4.0));
		bw /= (bw.x + bw.y + bw.z);
		rk = (texture(rock_tex, v_wp.zy * rock_scale).rgb * bw.x
				+ texture(rock_tex, v_wp.xz * rock_scale).rgb * bw.y
				+ texture(rock_tex, v_wp.xy * rock_scale).rgb * bw.z) * rock_tint;
	}

	float under = smoothstep(0.03, 0.18, UV.x);
	float mudm;
	float contact;
	vec3 c = ground_albedo(p, m, det, rk, under, 1.0, mudm, contact);

	float grassy = ground_grassy(m, det, mudm, contact) * (1.0 - under);
	float far = smoothstep(blade_fade_start, blade_fade_end, length(VERTEX));
	c = mix(c, c * 0.55 + blade_tint * (0.55 - m.a * 0.3), grassy * far * 0.55);

	// A wet, darker film on the bank right at the waterline and on the
	// shallowest bed, so ground and water meet without a hard seam.
	float wetfilm = UV.y * (1.0 - smoothstep(0.1, 0.35, UV.x));
	c *= mix(1.0, 0.6, wetfilm);

	ALBEDO = c;
	ROUGHNESS = mix(mix(0.95, 0.35, mudm), 0.22, wetfilm * 0.8);
	SPECULAR = mix(mix(0.2, 0.45, mudm), 0.5, wetfilm * 0.8);
	AO = (1.0 - m.a * 0.55) * (1.0 - contact * 0.55);
	AO_LIGHT_AFFECT = 0.15 + contact * 0.25;
}
