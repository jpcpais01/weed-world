shader_type canvas_item;
// The minimap disk: a rotating, round window onto the painted world map,
// softly darkened at the rim like looking through a glass lens.

uniform sampler2D map_tex : filter_linear_mipmap, repeat_disable;
uniform bool has_map = false;
uniform vec2 center_uv = vec2(0.5);
uniform float view_uv = 0.2;   // map uv from the centre to the rim
uniform float rot = 0.0;
uniform vec4 mist : source_color = vec4(0.83, 0.87, 0.77, 1.0);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float c = cos(rot);
	float s = sin(rot);
	vec2 q = vec2(c * p.x - s * p.y, s * p.x + c * p.y);
	vec2 uv = center_uv + q * view_uv;
	vec3 col = mist.rgb;
	if (has_map) {
		vec2 inside = step(vec2(0.0), uv) * step(uv, vec2(1.0));
		col = mix(mist.rgb, texture(map_tex, uv).rgb, inside.x * inside.y);
	}
	// Lens: brighter in the middle, a soft vignette and a crisp edge.
	col *= mix(1.04, 0.78, smoothstep(0.55, 1.0, r));
	col += vec3(1.0, 0.97, 0.85) * 0.06 * (1.0 - smoothstep(0.0, 0.7, length(p - vec2(-0.35, -0.45))));
	float aa = fwidth(r) * 1.5;
	COLOR = vec4(col, 1.0 - smoothstep(1.0 - aa, 1.0, r));
}
