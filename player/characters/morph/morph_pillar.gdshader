shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// A column of light round a transforming Keling: streaks rising up its
// walls, brightest at the edges, fading towards the top, with a band of
// light riding along with the cut.

uniform vec4 color_a : source_color = vec4(1.0, 0.8, 0.3, 1.0);
uniform vec4 color_b : source_color = vec4(0.6, 1.0, 0.7, 1.0);
uniform float intensity = 0.0;
uniform float cut = -1.0;      // 0..1 up the column
uniform float height = 2.4;

varying float hy;
varying float ang;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	hy = VERTEX.y / height + 0.5;
	ang = atan(VERTEX.z, VERTEX.x);
}

void fragment() {
	float fade = pow(clamp(1.0 - hy, 0.0, 1.0), 1.6) * smoothstep(0.0, 0.06, hy);
	float streak = noise(vec2(ang * 5.0, hy * 2.5 - TIME * 2.2)) * noise(vec2(ang * 11.0 + 3.0, hy * 5.0 - TIME * 3.1));
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.2);
	float band = exp(-pow((hy - cut) * 9.0, 2.0));
	vec3 col = mix(color_a.rgb, color_b.rgb, clamp(hy * 1.4, 0.0, 1.0));
	ALBEDO = col * intensity * (fade * fres * (0.1 + 1.8 * streak * streak * 2.0) + band * 0.9 * fres);
}
