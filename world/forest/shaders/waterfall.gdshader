// A sheet of water pouring over a ledge: glassy at the lip, breaking into
// white streaks as it falls, frothing where it hits the pool.
// UV.x runs across the sheet, UV.y from the lip (0) to the pool (1).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform sampler2D water_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 glass : source_color = vec3(0.32, 0.55, 0.5);
uniform vec3 white : source_color = vec3(0.94, 0.97, 1.0);
uniform float speed = 1.5;

varying float v_seed;

void vertex() {
	v_seed = MODEL_MATRIX[3].x * 0.37 + MODEL_MATRIX[3].z * 0.11;
	float wob = sin(TIME * 9.0 + UV.y * 14.0 + UV.x * 5.0 + v_seed * 10.0) * 0.012 * UV.y;
	VERTEX += NORMAL * wob;
}

void fragment() {
	float t = TIME * speed;
	vec2 uv = vec2(UV.x * 1.6 + v_seed, UV.y * 0.5 - t * 0.9);
	float s1 = texture(water_noise, vec2(uv.x, uv.y)).b;
	float s2 = texture(water_noise, vec2(uv.x * 2.3 + 0.4, uv.y * 1.7 - t * 0.4)).b;
	float streak = smoothstep(0.35, 0.75, s1 * 0.6 + s2 * 0.5);
	float broken = smoothstep(0.05, 0.55, UV.y);
	float froth = smoothstep(0.72, 1.0, UV.y);
	float w = clamp(streak * broken + froth * 0.9, 0.0, 1.0);
	float edge = smoothstep(0.0, 0.14, UV.x) * smoothstep(1.0, 0.86, UV.x);
	vec3 col = mix(glass, white, w);
	ALBEDO = col;
	EMISSION = white * w * 0.12;
	ROUGHNESS = mix(0.05, 0.6, w);
	SPECULAR = 0.5;
	ALPHA = clamp((0.55 + w * 0.45) * edge * (1.0 - smoothstep(0.93, 1.0, UV.y) * 0.6), 0.0, 1.0);
}
