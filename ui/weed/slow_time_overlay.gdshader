// Slow Time on the caster's screen: the colour drains towards a moonlit
// blue at the edges, the picture ripples slowly outwards from the Keling
// like a stone dropped in still water, a faint ring of clock ticks turns
// round the edge, and a shock ring bends the view when time stops or starts.
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float intensity = 0.0;
uniform float shock = -1.0;        // shock ring radius (screen heights), < 0 for none
uniform vec2 center = vec2(0.5, 0.6);
uniform float aspect = 1.7778;
uniform vec4 tint : source_color = vec4(0.55, 0.72, 1.0, 1.0);
uniform float time_s = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = (uv - center) * vec2(aspect, 1.0);
	float r = length(d);
	vec2 dir = r > 0.0001 ? d / r : vec2(0.0);
	float sh = 0.0;
	if (shock >= 0.0) {
		sh = exp(-pow((r - shock) * 8.0, 2.0)) * (1.0 - clamp(shock / 1.8, 0.0, 1.0));
	}
	float edge = smoothstep(0.3, 1.15, r);
	float rip = sin(r * 24.0 - time_s * 1.3);
	vec2 to_uv = dir / vec2(aspect, 1.0);
	vec2 off = to_uv * (sh * 0.04 + rip * edge * 0.0022 * intensity);
	vec2 ca = to_uv * edge * 0.0045 * intensity;
	vec3 col;
	col.r = textureLod(screen, uv - off + ca, 0.0).r;
	col.g = textureLod(screen, uv - off, 0.0).g;
	col.b = textureLod(screen, uv - off - ca, 0.0).b;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum) * tint.rgb * 1.2, intensity * (0.22 + 0.45 * edge));
	col *= 1.0 - edge * edge * 0.45 * intensity;
	col += tint.rgb * sh * 0.3;
	// A ring of faint clock ticks turning slowly round the edge.
	float ang = atan(d.y, d.x);
	float ring_r = 0.8 + 0.015 * sin(time_s * 0.6);
	float tick = smoothstep(0.86, 1.0, cos(ang * 60.0 + time_s * 0.08)) * 0.6 + smoothstep(0.985, 1.0, cos(ang * 12.0 + time_s * 0.08));
	tick *= smoothstep(0.018, 0.0, abs(r - ring_r));
	col += tint.rgb * tick * 0.22 * intensity;
	COLOR = vec4(col, 1.0);
}
