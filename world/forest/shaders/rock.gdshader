// Boulders, pebbles and stepping stones with moss on their sunny tops and a
// dark damp line where they sink into the soil.
shader_type spatial;
render_mode diffuse_lambert_wrap;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 moss_color : source_color = vec3(0.30, 0.46, 0.13);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.55;
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
	vec3 alb = texture(albedo_tex, UV).rgb * tint * (0.85 + 0.3 * v_custom.g);
	float n = texture(noise_tex, v_wp.xz * 0.4 + v_wp.y * 0.2).g;
	float moss = smoothstep(0.35, 0.85, v_wn.y + (n - 0.5) * 0.8) * moss_amount * (0.5 + v_custom.r);
	alb = mix(alb, moss_color * (0.7 + 0.5 * n), clamp(moss, 0.0, 1.0));
	float sink = 1.0 - smoothstep(0.0, sink_height, v_base);
	alb *= 1.0 - sink * 0.45;
	ALBEDO = alb;
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
	AO = 1.0 - sink * 0.5;
}
