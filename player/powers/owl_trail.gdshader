// Ribbons of light trailing Owl Flight's wingtips and tail plumes (GiftOwl
// rebuilds them each frame as camera-facing strips). UV.x runs from the tip
// (0) to the end of the trail (1), UV.y across it; streaks of smoke noise
// slide down them so they shimmer like thin smoke caught in moonlight.
// COLOR: tint, COLOR.a the trail's strength.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;

void fragment() {
	float along = UV.x;
	float across = abs(UV.y * 2.0 - 1.0);
	float streak = texture(noise, vec2(along * 1.6 - TIME * 0.9, UV.y * 0.35 + COLOR.a * 0.0)).g;
	float fine = texture(noise, vec2(along * 4.0 - TIME * 1.7, UV.y * 0.8)).b;
	float core = 1.0 - smoothstep(0.0, 0.9 - along * 0.5, across);
	float fade = (1.0 - along) * (1.0 - along) * smoothstep(0.0, 0.04, along);
	float a = core * fade * (0.45 + 0.75 * streak) * (0.8 + 0.4 * fine) * COLOR.a;
	if (a < 0.002) {
		discard;
	}
	ALBEDO = mix(COLOR.rgb, vec3(1.0), core * core * (1.0 - along) * 0.5);
	ALPHA = a;
}
