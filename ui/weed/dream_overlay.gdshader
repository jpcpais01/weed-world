// The high at the edges of your vision: a soft, slowly swirling glow that
// creeps in from the corners, rainbow for the Glade Glow, the power's own
// colour on a bench. Nothing is read from the screen, so it costs a single
// blended quad.
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tint : source_color = vec3(0.8, 0.6, 1.0);
uniform float rainbow : hint_range(0.0, 1.0) = 0.0;
uniform float aspect = 1.78;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.x *= mix(1.0, aspect, 0.55);
	float r = length(p);
	float ang = atan(p.y, p.x);
	float t = TIME;
	float swirl = 0.5 + 0.5 * sin(ang * 3.0 + t * 0.5 + r * 5.0) * sin(ang * 5.0 - t * 0.35 + r * 2.0);
	float breathe = 0.85 + 0.15 * sin(t * 0.9);
	float edge = smoothstep(0.7, 1.75, r * breathe);
	vec3 rb = 0.62 + 0.38 * cos(6.2831853 * (vec3(0.0, 0.33, 0.67) + ang / 6.2831853 + t * 0.04 + r * 0.25));
	vec3 col = mix(tint, rb, rainbow);
	float a = edge * (0.45 + 0.55 * swirl) * intensity * 0.5;
	COLOR = vec4(col, a);
}
