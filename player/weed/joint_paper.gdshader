// The paper of a rolled joint: unbleached hemp, a warm natural tan with
// fibres and streaks, thin enough that the ground bud inside shows through
// in soft green patches, with the glued seam running down one side. The
// mouth end (the crutch section) uses it with `fill` 0: card underneath,
// no bud. UV.x runs round the paper, UV.y along it (CylinderMesh UVs).
shader_type spatial;

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec3 paper_color : source_color = vec3(0.74, 0.6, 0.4);
uniform vec3 fill_color : source_color = vec3(0.36, 0.5, 0.2);
uniform float fill = 1.0;

void fragment() {
	vec2 uv = UV * vec2(1.0, 2.4);
	float grain = texture(noise, uv * vec2(4.0, 8.0)).b;
	float fibre = texture(noise, uv * vec2(3.0, 0.5) + 0.17).g;
	float mott = texture(noise, uv * vec2(2.5, 2.0) + vec2(0.41, 0.0)).r;
	vec3 col = paper_color * (0.9 + 0.16 * grain);
	// Darker hemp fibres running along the paper.
	col *= 1.0 - 0.2 * smoothstep(0.5, 0.95, fibre);
	// The bud inside showing through where the paper is thinnest.
	float through = smoothstep(0.4, 0.75, mott) * fill;
	col = mix(col, col * 0.45 + fill_color * 0.55, through * 0.7);
	// The glued overlap: a slightly darker, smoother line down one side.
	float seam = 1.0 - smoothstep(0.004, 0.018, abs(fract(UV.x + 0.03 * sin(UV.y * 6.0)) - 0.25));
	col *= 1.0 - 0.1 * seam;
	ALBEDO = col;
	ROUGHNESS = mix(0.88, 0.6, seam);
	SPECULAR = 0.25;
	// Light glows through thin paper (and the bud behind it).
	BACKLIGHT = mix(paper_color * 0.35, fill_color * 0.3, fill * 0.6);
}
