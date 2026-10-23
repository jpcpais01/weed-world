// Golden-hour sky: warm horizon to deep blue zenith, a soft sun halo, a crisp
// sun disk and painted cloud banks that catch the low sun.
shader_type sky;

uniform vec3 zenith : source_color = vec3(0.20, 0.38, 0.70);
uniform vec3 mid_sky : source_color = vec3(0.52, 0.66, 0.86);
uniform vec3 horizon : source_color = vec3(1.0, 0.80, 0.58);
uniform vec3 below : source_color = vec3(0.30, 0.33, 0.30);
uniform vec3 sun_halo : source_color = vec3(1.0, 0.62, 0.30);
uniform float sun_size = 0.035;
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.86, 0.70);
uniform vec3 cloud_shade : source_color = vec3(0.58, 0.55, 0.70);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.5;
uniform vec2 cloud_offset = vec2(0.13, 0.41);

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 sun = LIGHT0_ENABLED ? LIGHT0_DIRECTION : normalize(vec3(-0.6, 0.35, 0.7));
	float sd = max(dot(d, sun), 0.0);

	float up = clamp(h, 0.0, 1.0);
	vec3 col = mix(horizon, mid_sky, smoothstep(0.0, 0.28, up));
	col = mix(col, zenith, smoothstep(0.25, 0.95, up));
	// warmer horizon on the sun's side
	float sun_side = pow(max(dot(normalize(d.xz + 1e-4), normalize(sun.xz + 1e-4)), 0.0), 3.0);
	col = mix(col, sun_halo, (1.0 - smoothstep(0.0, 0.35, up)) * sun_side * 0.55);
	col += sun_halo * (pow(sd, 10.0) * 0.55 + pow(sd, 90.0) * 0.9);

	if (h > -0.02) {
		vec2 cuv = d.xz / (max(h, 0.0) + 0.12) * 0.22 + cloud_offset;
		float c1 = texture(cloud_noise, cuv).r;
		float c2 = texture(cloud_noise, cuv * 2.6 + 0.3).g;
		float c3 = texture(cloud_noise, cuv * 7.0).b;
		float c = c1 * 0.62 + c2 * 0.28 + c3 * 0.1;
		float cover = smoothstep(1.0 - cloud_cover * 0.75, 1.08 - cloud_cover * 0.5, c);
		cover *= smoothstep(-0.02, 0.18, h);
		float lit = clamp(0.35 + pow(sd, 3.0) * 0.9 + (c - 0.5) * 0.6, 0.0, 1.0);
		vec3 cc = mix(cloud_shade, cloud_lit, lit);
		cc += sun_halo * pow(sd, 6.0) * 0.6 * (1.0 - cover * 0.5);
		col = mix(col, cc, cover * 0.88);
	}

	if (!AT_CUBEMAP_PASS && LIGHT0_ENABLED) {
		float disk = smoothstep(cos(sun_size), cos(sun_size * 0.7), dot(d, sun));
		col += LIGHT0_COLOR * disk * 6.0;
	}

	col = mix(col, below, smoothstep(0.0, -0.18, h));
	COLOR = col;
}
