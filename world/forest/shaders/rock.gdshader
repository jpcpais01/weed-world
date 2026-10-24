// Boulders, pebbles and stepping stones with moss on their sunny tops. Where
// they meet the floor soil and moss creep up their flanks, a damp contact
// shadow hugs the ground line and the stone fades into the exact colour of the
// ground beneath, so each one sits in the earth instead of on it.
shader_type spatial;
render_mode diffuse_lambert_wrap;

#include "ground.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 moss_color : source_color = vec3(0.30, 0.46, 0.13);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.55;
// Fallback darkening above the model origin when no ground is baked.
uniform float sink_height = 0.25;

varying vec3 v_wn;
varying vec3 v_wp;
varying float v_base;
varying vec4 v_custom;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_base = v_wp.y - MODEL_MATRIX[3].y;
}

void fragment() {
	// The kit's stone atlas is very dark; lift it towards a warm grey so
	// boulders read as stone in the meadow rather than holes in it.
	vec3 alb = (texture(albedo_tex, UV).rgb * 1.3 + vec3(0.03, 0.028, 0.022)) * tint * (0.85 + 0.3 * v_custom.g);
	float n = texture(noise_tex, v_wp.xz * 0.4 + v_wp.y * 0.2).g;
	float moss = smoothstep(0.35, 0.85, v_wn.y + (n - 0.5) * 0.8) * moss_amount * (0.5 + v_custom.r);
	alb = mix(alb, moss_color * (0.7 + 0.5 * n), clamp(moss, 0.0, 1.0));
	float ao;
	if (ground_inside(v_wp.xz) > 0.5) {
		// INSTANCE_CUSTOM.b: how tall the blend band is, sized to the stone.
		float band = max(v_custom.b, 0.03);
		float hg = v_wp.y - ground_height_at(v_wp.xz);
		vec4 gm = ground_mask_at(v_wp.xz);
		float creep = 1.0 - smoothstep(0.0, band * 3.5, hg + (n - 0.5) * band * 2.5);
		vec3 grime = mix(soil_dark * 1.35, moss_color * 0.85, smoothstep(0.35, 0.7, n) * (0.35 + gm.a * 0.65));
		alb = mix(alb, grime, creep * 0.5);
		float b = 1.0 - smoothstep(0.0, band, hg + (n - 0.5) * band * 1.2);
		if (b > 0.001) {
			float mudm;
			float contact;
			vec4 det = texture(ground_detail, ground_detail_uv(v_wp.xz));
			alb = mix(alb, ground_albedo(v_wp.xz, gm, det, alb, 0.0, 0.0, mudm, contact), b);
			NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz, b * 0.75));
		}
		float c = 1.0 - smoothstep(0.0, band * 2.0 + 0.08, hg);
		alb *= 1.0 - c * 0.22;
		ao = 1.0 - c * 0.5;
	} else {
		float sink = 1.0 - smoothstep(0.0, sink_height, v_base);
		alb *= 1.0 - sink * 0.45;
		ao = 1.0 - sink * 0.5;
	}
	ALBEDO = alb;
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
	AO = ao;
}
