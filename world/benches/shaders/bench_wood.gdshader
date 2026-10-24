// Bench timber: planed boards with flowing grain, or rough bark for the
// living bench, with soft moss creeping over the sunny tops. Vertex colour
// carries the paint/wood tone (rgb) and baked occlusion (a).
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D bark_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D bark_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float bark = 0.0;
uniform float grain = 1.0;
uniform float moss_amount : hint_range(0.0, 1.0) = 0.3;
uniform vec3 moss_color : source_color = vec3(0.30, 0.46, 0.13);
uniform float roughness = 0.8;

varying vec3 v_wp;
varying vec3 v_wn;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float n = texture(noise_tex, v_wp.xz * 0.6 + v_wp.y * 0.4).g;
	vec3 alb = COLOR.rgb;
	if (bark > 0.5) {
		alb *= texture(bark_tex, UV).rgb * 1.35;
		NORMAL_MAP = texture(bark_normal, UV).rgb;
	} else {
		// Growth rings swept along the board, wobbling with the noise, and
		// fine streaks for the open grain.
		float wobble = texture(noise_tex, vec2(UV.x * 0.07, UV.y * 0.5)).r;
		float rings = sin(UV.y * 70.0 + wobble * 11.0);
		float streak = texture(noise_tex, vec2(UV.x * 0.35, UV.y * 6.0)).b;
		alb *= 0.88 + 0.09 * rings * rings * grain + 0.16 * (streak - 0.5) * grain;
	}
	float top = smoothstep(0.55, 0.95, v_wn.y + (n - 0.5) * 0.7);
	float moss = clamp(top * moss_amount * (0.5 + n) * smoothstep(0.32, 0.6, n), 0.0, 1.0);
	alb = mix(alb, moss_color * (0.7 + 0.5 * n), moss);
	ALBEDO = alb;
	ROUGHNESS = roughness;
	SPECULAR = 0.3;
	AO = COLOR.a;
	AO_LIGHT_AFFECT = 0.35;
}
