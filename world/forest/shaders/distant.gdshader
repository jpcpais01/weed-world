// Far ridges beyond the valley, painted in aerial perspective: each range
// fades towards the hazy horizon colour and warms on the side facing the sun.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

uniform vec3 near_col : source_color = vec3(0.36, 0.42, 0.46);
uniform vec3 far_col : source_color = vec3(0.66, 0.68, 0.76);
uniform vec3 haze : source_color = vec3(0.95, 0.80, 0.64);
uniform vec3 sun_towards = vec3(-0.83, 0.40, 0.39);

varying vec3 v_wp;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float d = length(v_wp.xz);
	float layer = smoothstep(170.0, 330.0, d);
	vec3 c = mix(near_col, far_col, layer);
	float toward = max(dot(normalize(v_wp.xz), normalize(sun_towards.xz)), 0.0);
	c = mix(c, haze, pow(toward, 3.0) * (0.35 + 0.35 * layer));
	// Mist pools at the foot of each range.
	float foot = 1.0 - smoothstep(-6.0, 26.0 + layer * 30.0, v_wp.y);
	c = mix(c, mix(far_col, haze, toward * 0.6), foot * 0.55);
	ALBEDO = c;
}
