shader_type spatial;
render_mode cull_disabled;
// The buttercups in a Keling's leafy crown. Their colour lives in the vertex
// colours; co-op players get their own flower colour by turning the hue (and
// softening the saturation) while keeping each petal's light and shade.

uniform float hue_shift = 0.0;
uniform float saturation = 1.0;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void fragment() {
	vec3 hsv = rgb2hsv(COLOR.rgb);
	hsv.x = fract(hsv.x + hue_shift);
	hsv.y = clamp(hsv.y * saturation, 0.0, 1.0);
	vec3 col = hsv2rgb(hsv);
	ALBEDO = col;
	ROUGHNESS = 0.45;
	// Sunlight glowing through the petals, in the petal's own colour.
	BACKLIGHT = col * 0.52;
}
