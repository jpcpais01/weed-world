// The open mouth end of a joint's crutch: a strip of card rolled into a
// tight spiral round a little W fold, inside a ring of paper.
shader_type spatial;

uniform vec3 card_color : source_color = vec3(0.9, 0.87, 0.8);
uniform vec3 paper_color : source_color = vec3(0.82, 0.7, 0.5);
uniform float radius = 0.012;

varying vec3 v_pos;

void vertex() {
	v_pos = VERTEX;
}

void fragment() {
	// The cap disc lies across the cylinder's Y axis.
	vec2 p = v_pos.xz / radius;
	float r = length(p);
	float a = atan(p.y, p.x) / 6.2832;
	// Three turns of card, each a dark gap then the card's cut edge.
	float turns = 3.2;
	float s = fract(r * turns - a);
	float gap = 1.0 - smoothstep(0.08, 0.24, s);
	vec3 col = mix(card_color, card_color * 0.35, gap * 0.8);
	// The W fold in the middle.
	float w = abs(p.x) < 0.38 ? 1.0 - smoothstep(0.03, 0.08, abs(p.y - 0.12 * cos(p.x * 16.0))) : 0.0;
	col = mix(col, card_color * 0.45, w * 0.8);
	// The paper wrapped round the outside.
	col = mix(col, paper_color, smoothstep(0.86, 0.93, r));
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
