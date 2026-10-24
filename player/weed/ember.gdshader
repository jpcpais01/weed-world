// The lit end of a joint: grey ash with glowing cracks. `energy` is how hard
// it's burning: resting it smoulders in a few dull red cracks, on a draw the
// cracks spread and blaze orange right across the end.
shader_type spatial;
render_mode specular_disabled;

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform float energy = 0.0;

varying vec3 v_pos;

void vertex() {
	v_pos = VERTEX;
}

void fragment() {
	vec2 q = v_pos.yz * 55.0 + vec2(v_pos.x * 35.0, TIME * 0.04);
	float n = texture(noise, q).r;
	float cracks = texture(noise, q * 1.7 + vec2(0.3, TIME * 0.07)).g;
	// The very end burns hottest; round the sides it's mostly ash.
	float front = smoothstep(-0.004, 0.012, v_pos.x);
	float heat = clamp(energy / 3.0, 0.0, 1.6);
	float glow = smoothstep(0.62 - 0.38 * heat, 0.92, cracks * (0.65 + 0.55 * front)) * (0.3 + 0.7 * front);
	vec3 ash = mix(vec3(0.2, 0.19, 0.18), vec3(0.56, 0.55, 0.53), n);
	ALBEDO = mix(ash, vec3(0.08, 0.02, 0.01), glow);
	EMISSION = vec3(1.0, 0.36, 0.08) * glow * (0.5 + energy) * 1.8 + vec3(1.0, 0.45, 0.12) * heat * heat * 0.25 * front;
	ROUGHNESS = 0.95;
}
