// Slow Time's bubble: an iridescent soap-film shell. At the cast it swells
// out over the forest; on a friend's screen a small one shimmers round the
// Keling who has stepped outside time.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
instance uniform float strength = 0.0;
instance uniform float phase = 0.0;

void fragment() {
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(f, 2.6);
	vec3 world_n = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float n = texture(noise, world_n.xz * 0.35 + vec2(phase * 0.05, world_n.y * 0.3)).r;
	float film = f * 5.0 + n * 3.0 + phase * 0.4;
	vec3 iri = 0.5 + 0.5 * cos(6.2832 * (vec3(0.0, 0.33, 0.67) + film));
	vec3 c = mix(vec3(0.55, 0.72, 1.0), iri, 0.55);
	ALBEDO = c * (rim * 0.9 + 0.04) * strength;
}
