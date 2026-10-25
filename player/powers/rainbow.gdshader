// The rainbow over a Dragon Breath splash: an arc of soft spectral bands,
// brightest at the crown, fading into the air at both feet.
// UV.x runs along the arc (0..1), UV.y across it (inside 0 .. outside 1).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float strength = 0.0;

// Red on the outside of the arc (across = 1), violet on the inside.
vec3 spectrum(float across) {
	float h = (1.0 - across) * 0.78;
	vec3 c = clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
	return mix(c, vec3(1.0), 0.15);
}

void fragment() {
	float across = UV.y;
	float bands = smoothstep(0.0, 0.18, across) * smoothstep(1.0, 0.82, across);
	float feet = smoothstep(0.0, 0.3, UV.x) * smoothstep(1.0, 0.7, UV.x);
	float crown = 0.7 + 0.3 * sin(UV.x * 3.14159);
	ALBEDO = spectrum(across) * 1.1;
	ALPHA = bands * feet * crown * strength * 0.5;
}
