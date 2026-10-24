shader_type canvas_item;
// The paused forest behind the menu: softly blurred, a touch darker and
// greener towards the edges so the cards read on top of it.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.02, 0.06, 0.035, 1.0);

void fragment() {
	float lod = amount * 3.0;
	vec2 px = SCREEN_PIXEL_SIZE * (1.0 + amount * 5.0);
	vec3 c = textureLod(screen_tex, SCREEN_UV, lod).rgb * 0.36;
	c += textureLod(screen_tex, SCREEN_UV + vec2(px.x, px.y), lod).rgb * 0.16;
	c += textureLod(screen_tex, SCREEN_UV + vec2(-px.x, px.y), lod).rgb * 0.16;
	c += textureLod(screen_tex, SCREEN_UV + vec2(px.x, -px.y), lod).rgb * 0.16;
	c += textureLod(screen_tex, SCREEN_UV + vec2(-px.x, -px.y), lod).rgb * 0.16;
	vec2 d = (UV - vec2(0.5)) * vec2(1.25, 1.0);
	float edge = smoothstep(0.2, 0.85, length(d));
	// Left side darker too: the menu lives there.
	float side = smoothstep(0.55, 0.0, UV.x) * 0.35;
	c = mix(c, tint.rgb, clamp(0.28 + 0.4 * edge + side, 0.0, 0.85) * amount);
	c *= 1.0 - 0.12 * amount;
	COLOR = vec4(c, amount);
}
