// The carpet of little glowing flowers Bloom Burst leaves round the giants.
// The mesh is WeedHigh's five-petal flower (COLOR r: heart -> tip, g: heart,
// b: stem); INSTANCE_CUSTOM is the petal colour and how much it glows.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

varying vec4 v_zone;
varying vec4 v_custom;

void vertex() {
	v_zone = COLOR;
	v_custom = INSTANCE_CUSTOM;
	VERTEX.x += sin(TIME * 1.3 + MODEL_MATRIX[3].x * 0.7) * VERTEX.y * 0.25;
}

void fragment() {
	vec3 petal = v_custom.rgb;
	vec3 c = mix(petal * 1.05, mix(petal, vec3(1.0), 0.45), v_zone.r);
	c = mix(c, vec3(1.0, 0.86, 0.35), v_zone.g);
	c = mix(c, vec3(0.32, 0.6, 0.25), v_zone.b);
	ALBEDO = c;
	ROUGHNESS = 0.6;
	BACKLIGHT = c * 0.5;
	EMISSION = (petal * (0.3 + 0.7 * v_zone.r) * (1.0 - v_zone.b) + vec3(1.0, 0.85, 0.4) * v_zone.g) * v_custom.a * 1.4;
}
