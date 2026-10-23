shader_type spatial;
// World-space prototype grid: soft checker every `major_every` cells with
// anti-aliased minor/major lines. Triplanar so ramps and walls read clearly.

uniform vec3 base_color : source_color = vec3(0.36, 0.47, 0.33);
uniform vec3 alt_color : source_color = vec3(0.32, 0.43, 0.30);
uniform vec3 line_color : source_color = vec3(0.86, 0.96, 0.78);
uniform float cell = 1.0;
uniform float major_every = 5.0;
uniform float minor_strength = 0.16;
uniform float major_strength = 0.42;
uniform float roughness_value = 0.92;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float grid_line(vec2 p, float width) {
	vec2 d = fwidth(p);
	vec2 g = abs(fract(p - 0.5) - 0.5) / max(d, vec2(1e-4));
	float line = 1.0 - min(min(g.x, g.y) / width, 1.0);
	// Fade lines out where they would alias into noise in the distance.
	float fade = 1.0 - smoothstep(0.15, 0.6, max(d.x, d.y));
	return line * fade;
}

void fragment() {
	vec3 n = abs(world_normal);
	vec2 p = world_pos.xz;
	if (n.x > n.y && n.x > n.z) {
		p = world_pos.zy;
	} else if (n.z > n.y) {
		p = world_pos.xy;
	}
	float minor = grid_line(p / cell, 1.0);
	float major = grid_line(p / (cell * major_every), 1.5);
	vec2 c = floor(p / (cell * major_every));
	float checker = mod(c.x + c.y, 2.0);
	vec3 col = mix(base_color, alt_color, checker);
	col = mix(col, line_color, clamp(minor * minor_strength + major * major_strength, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.3;
}
