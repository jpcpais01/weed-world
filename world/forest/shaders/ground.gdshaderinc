// The meadow colour, shared by the terrain and the grass so that each blade
// starts exactly the colour of the ground it grows from.
uniform sampler2D ground_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 grass_a : source_color = vec3(0.30, 0.50, 0.15);
uniform vec3 grass_b : source_color = vec3(0.47, 0.62, 0.19);
uniform vec3 grass_dry : source_color = vec3(0.70, 0.64, 0.30);
uniform vec3 grass_shade : source_color = vec3(0.13, 0.27, 0.16);
uniform vec3 grass_wet : source_color = vec3(0.15, 0.33, 0.19);

vec3 ground_grass(vec2 p, float shade, float wet) {
	vec4 n1 = textureLod(ground_noise, p * 0.013, 0.0);
	vec4 n2 = textureLod(ground_noise, p * 0.057 + vec2(0.37, 0.11), 0.0);
	vec3 c = mix(grass_a, grass_b, smoothstep(0.3, 0.72, n1.r));
	c = mix(c, grass_dry, smoothstep(0.6, 0.85, n1.g) * 0.6 * (1.0 - shade));
	c *= 0.88 + 0.24 * n2.b;
	c = mix(c, grass_wet, wet * 0.65);
	c = mix(c, grass_shade, shade * 0.72);
	return c;
}
