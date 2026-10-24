shader_type spatial;
render_mode cull_disabled;
// Petals, leaves, seeds, florets or spores swirling round a transforming
// Keling (one MultiMesh per kind; each instance's colour and glow come in
// INSTANCE_CUSTOM). Opaque cut-out shapes, lit, with light through them.

uniform int shape = 0;   // 0 leaf, 1 petal, 2 seed, 3 bloom, 4 spore

varying vec4 custom;

void vertex() {
	custom = INSTANCE_CUSTOM;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float m = 0.0;
	float shade = 1.0;
	if (shape == 0) {
		float w = (1.0 - p.y * p.y) * 0.55;
		m = step(abs(p.x), w);
		shade = 0.82 + 0.18 * smoothstep(0.0, 0.08, abs(p.x));
	} else if (shape == 1) {
		vec2 q = p * vec2(1.0 / 0.72, 1.0);
		m = step(length(q), 1.0) * step(0.22, length(p - vec2(0.0, 1.05)));
		shade = 0.85 + 0.15 * (1.0 - length(q));
	} else if (shape == 2) {
		m = step(length(p * vec2(1.0 / 0.3, 1.0)), 1.0);
		shade = 0.8 + 0.2 * smoothstep(0.0, 0.1, abs(p.x));
	} else if (shape == 3) {
		float a = atan(p.y, p.x);
		m = step(length(p), 0.55 + 0.4 * abs(cos(a * 2.0)));
		shade = 0.75 + 0.25 * step(0.25, length(p));
	} else {
		m = step(length(p), 1.0);
		shade = 1.0 - length(p) * 0.4;
	}
	if (m < 0.5) {
		discard;
	}
	vec3 col = custom.rgb * shade;
	ALBEDO = col;
	ROUGHNESS = 0.6;
	BACKLIGHT = col * 0.6;
	EMISSION = col * custom.a * (shape == 4 ? 2.5 : 1.0);
}
