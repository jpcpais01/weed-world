// The little flowers a Bloom Trail leaves behind: petals tinted per flower,
// a sunny heart, and a soft glow while they are fresh.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap;

instance uniform vec3 petal : source_color = vec3(1.0, 0.6, 0.8);
instance uniform float fresh = 1.0;

void fragment() {
	// COLOR.r: 0 at the heart, 1 at the petal tips; COLOR.g marks the heart,
	// COLOR.b the stem.
	vec3 heart = vec3(1.0, 0.85, 0.3);
	vec3 col = mix(petal * mix(0.75, 1.15, COLOR.r), heart, COLOR.g);
	col = mix(col, vec3(0.3, 0.58, 0.2), COLOR.b);
	ALBEDO = col;
	ROUGHNESS = 0.7;
	BACKLIGHT = col * 0.6;
	EMISSION = col * 0.35 * fresh;
}
