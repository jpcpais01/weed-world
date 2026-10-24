shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// The circle of magic that opens on the ground under a transforming Keling:
// two turning rings, a rose of eight petals drawn in light between them,
// orbiting motes, a soft glowing heart, and a shockwave at the reveal.

uniform vec4 color_a : source_color = vec4(1.0, 0.8, 0.3, 1.0);
uniform vec4 color_b : source_color = vec4(0.5, 1.0, 0.6, 1.0);
uniform float grow = 0.0;        // 0..1 the circle opening
uniform float intensity = 0.0;
uniform float wave = -1.0;       // 0..1 shockwave after the reveal (< 0 off)

float line(float d, float w) {
	return smoothstep(w, 0.0, abs(d));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float R = 0.74 * grow;
	float spin = TIME * 0.8;
	float rings = line(r - R, 0.03) + line(r - R * 0.86, 0.012) * 0.8;
	// Dashes on the outer band, turning the other way.
	float dash = step(0.55, fract((a - spin * 0.7) / TAU * 24.0)) * line(r - R * 0.93, 0.018);
	// The rose: eight petals in light.
	float th = a + spin;
	float rose = R * 0.8 * abs(cos(th * 4.0));
	float petals = line(r - rose, 0.016) * step(r, R * 0.82);
	// Motes orbiting just outside.
	float motes = 0.0;
	for (int i = 0; i < 6; i++) {
		float ang = spin * 1.6 + float(i) * TAU / 6.0;
		vec2 m = vec2(cos(ang), sin(ang)) * R * 1.08;
		motes += smoothstep(0.05, 0.0, length(p - m));
	}
	float heart = (1.0 - smoothstep(0.0, R * 0.9 + 0.001, r)) * 0.4;
	float shade = 0.5 + 0.5 * sin(a * 3.0 + TIME * 2.5);
	vec3 col = mix(color_a.rgb, color_b.rgb, shade);
	vec3 c = col * (rings + dash * 0.7 + petals * 0.8 + motes * 1.2 + heart) * intensity;
	if (wave >= 0.0) {
		c += mix(color_b.rgb, vec3(1.0), 0.4) * line(r - wave * 0.98, 0.05 + 0.05 * wave) * (1.0 - wave) * 2.2;
	}
	ALBEDO = c * smoothstep(1.0, 0.92, r);
}
