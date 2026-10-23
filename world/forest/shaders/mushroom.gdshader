// Forest mushrooms. With `glow` set the caps breathe with bioluminescent light
// that blooms in the dusk.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float glow = 0.0;
uniform vec3 glow_a : source_color = vec3(0.35, 0.9, 1.0);
uniform vec3 glow_b : source_color = vec3(0.75, 0.45, 1.0);
uniform float cap_start = 0.18;
uniform float cap_end = 0.42;

varying float v_ly;
varying vec4 v_custom;

void vertex() {
	v_ly = VERTEX.y;
	v_custom = INSTANCE_CUSTOM;
}

void fragment() {
	vec3 alb = texture(albedo_tex, UV).rgb * tint;
	float cap = smoothstep(cap_start, cap_end, v_ly);
	vec3 gc = mix(glow_a, glow_b, v_custom.r);
	if (glow > 0.0) {
		alb = mix(alb, gc * 0.6 + alb * 0.4, cap * 0.8);
		float pulse = 0.65 + 0.35 * sin(TIME * (0.8 + v_custom.g) + v_custom.b * 30.0);
		EMISSION = gc * glow * cap * pulse;
	}
	ALBEDO = alb;
	ROUGHNESS = 0.6;
	SPECULAR = 0.35;
	BACKLIGHT = alb * 0.3;
}
