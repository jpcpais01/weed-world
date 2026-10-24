// Ground bud: a crumbly green log with darker flecks, orange hairs and a
// faint frosty twinkle of trichomes.
shader_type spatial;

uniform vec3 tint : source_color = vec3(0.45, 0.7, 0.3);

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

varying vec3 v_pos;

void vertex() {
	v_pos = VERTEX;
	// Lumpy: push the surface in and out a little.
	float n = hash(floor(VERTEX * 260.0));
	VERTEX += NORMAL * (n - 0.5) * 0.0028;
}

void fragment() {
	vec3 cell = floor(v_pos * 520.0);
	float n = hash(cell);
	float m = hash(cell + 7.3);
	vec3 col = tint * (0.55 + 0.6 * n);
	col = mix(col, vec3(0.16, 0.24, 0.1), step(0.82, m));         // dark flecks
	col = mix(col, vec3(0.95, 0.5, 0.18), step(0.93, hash(cell + 3.1)) * 0.8); // pistils
	float frost = step(0.9, hash(cell + 11.0)) * (0.5 + 0.5 * sin(TIME * 3.0 + n * 20.0));
	ALBEDO = col + vec3(frost * 0.25);
	ROUGHNESS = 0.8 - frost * 0.4;
}
