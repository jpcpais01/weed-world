// Cloud Ride's cloud: lumpy cotton puffs. Each sphere is pushed in and out
// by noise that slowly churns, lit soft (wrap lighting, a glow from inside
// so the shadow side stays pastel), white on top and lavender underneath,
// with a bright silver rim against the sky.
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled, cull_back;

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec3 top_color : source_color = vec3(1.0, 0.99, 0.97);
uniform vec3 under_color : source_color = vec3(0.8, 0.76, 0.96);
uniform vec3 glow_color : source_color = vec3(1.0, 0.9, 0.98);

varying float v_up;
varying float v_n;

void vertex() {
	vec2 uv = NORMAL.xz * 0.32 + vec2(INSTANCE_CUSTOM.x, NORMAL.y * 0.2) + vec2(TIME * 0.025, -TIME * 0.018);
	float n = textureLod(noise, uv, 0.0).r;
	float n2 = textureLod(noise, uv * 2.7 + 0.37, 0.0).r;
	v_n = n;
	VERTEX += NORMAL * ((n - 0.5) * 0.42 + (n2 - 0.5) * 0.14);
	v_up = (MODEL_MATRIX * vec4(NORMAL, 0.0)).y;
}

void fragment() {
	float up = smoothstep(-0.55, 0.75, v_up);
	vec3 base = mix(under_color, top_color, up) * COLOR.rgb;
	ALBEDO = base * (0.9 + 0.12 * v_n);
	ROUGHNESS = 1.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = base * 0.28 + glow_color * rim * 0.4 + glow_color * (1.0 - up) * 0.06 * COLOR.a;
	BACKLIGHT = base * 0.5;
}
