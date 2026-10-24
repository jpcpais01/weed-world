// Rolling paper. The sheet runs along X; across it (Z) it bends by curvature,
// integrated from the middle out, so one shader covers every stage:
//   fold    0 flat .. 1 a deep U (a taco round the filling)
//   wrap_a  the near edge tucks over the filling and wraps right round it
//   wrap_b  the far edge (with the gum strip) rolls over the top and seals
// The filling log sits on the pivot; the flat sheet lies `radius` below it.
// `fill` scatters crumbs over the open sheet, `wet` shines up the licked gum.
shader_type spatial;
render_mode cull_disabled;

uniform float fold : hint_range(0.0, 1.0) = 0.0;
uniform float wrap_a : hint_range(0.0, 1.0) = 0.0;
uniform float wrap_b : hint_range(0.0, 1.0) = 0.0;
uniform float fill : hint_range(0.0, 1.0) = 0.0;
uniform float wet : hint_range(0.0, 1.0) = 0.0;
uniform float width = 0.085;
uniform float radius = 0.0095;
uniform vec3 fill_color : source_color = vec3(0.45, 0.7, 0.3);
uniform vec3 paper_color : source_color = vec3(0.98, 0.95, 0.88);
uniform vec3 gum_color : source_color = vec3(0.93, 0.86, 0.66);

varying float v_across;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float curvature(float d) {
	float half_w = width * 0.5;
	// A U over the whole sheet at fold 1 (about 75 degrees up each side).
	float k_fold = fold * 2.6 / width;
	if (d < 0.0) {
		float front = wrap_a * half_w;
		return (-d < front) ? 1.0 / radius : k_fold * (1.0 - 0.8 * wrap_a);
	}
	float front_b = wrap_b * half_w;
	return (d < front_b) ? 1.0 / (radius + 0.0013) : k_fold * (1.0 - 0.8 * wrap_b);
}

void vertex() {
	v_across = UV.x;
	float d = (UV.x - 0.5) * width;
	// March from the middle of the sheet to this vertex, bending as we go.
	const int STEPS = 20;
	float h = d / float(STEPS);
	float th = 0.0;
	vec2 p = vec2(0.0); // (z, y)
	for (int i = 0; i < STEPS; i++) {
		float m = (float(i) + 0.5) * h;
		float k = curvature(m);
		float th_mid = th + k * h * 0.5;
		p += vec2(cos(th_mid), sin(th_mid)) * h;
		th += k * h;
	}
	VERTEX.z = p.x;
	VERTEX.y = p.y - radius;
	NORMAL = vec3(0.0, cos(th), -sin(th));
}

void fragment() {
	// Soft paper fibres.
	float fib = hash(floor(UV * vec2(9.0, 160.0))) * 0.05 + hash(floor(UV * vec2(40.0, 40.0))) * 0.03;
	vec3 col = paper_color * (0.96 + fib);
	float rough = 0.85;
	// The gum strip along the far edge, glossy once it has been licked.
	if (v_across > 0.9) {
		col = mix(col, gum_color, 0.55);
		col *= 1.0 - 0.12 * wet;
		rough = mix(0.7, 0.18, wet);
	}
	// Ground bud scattered along the middle of the open sheet.
	float d = abs(v_across - 0.5);
	float n = hash(floor(UV * vec2(70.0, 40.0)));
	float band = fill * 0.2 * (0.6 + 0.8 * n);
	if (FRONT_FACING && d < band && n > 0.35) {
		col = fill_color * (0.5 + 0.7 * n);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.3 + 0.4 * wet;
	BACKLIGHT = paper_color * 0.45;
}
