// The thin stream of smoke that rises off a lit joint, drawn by WeedSmoke as
// a camera-facing strip. UV.x runs across the strip, UV.y is fixed to the
// smoke itself (when it left the ember), so streaks travel with the air.
// UV2.x is the age (0..1 of its life); COLOR.a the strength.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert_wrap, specular_disabled, shadows_disabled;

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform float seed = 0.0;

void fragment() {
	float x = UV.x * 2.0 - 1.0;
	float age = UV2.x;
	float edge = pow(max(1.0 - x * x, 0.0), 1.6);
	// Fine laminar threads near the ember; ragged streaks once it turns over.
	vec2 q = vec2(UV.x * mix(0.08, 0.35, age) + seed, UV.y * 0.9);
	float streak = texture(noise, q).g;
	float body = texture(noise, q * 0.5 + vec2(0.3, 0.0)).r;
	float a = edge * mix(1.0, streak * 1.5 * (0.6 + body), smoothstep(0.05, 0.5, age)) * COLOR.a;
	if (a < 0.004) {
		discard;
	}
	ALBEDO = COLOR.rgb;
	NORMAL = normalize(vec3(x * 0.6, 0.0, 1.0));
	BACKLIGHT = ALBEDO * 0.4;
	ROUGHNESS = 1.0;
	ALPHA = clamp(a, 0.0, 1.0);
}
