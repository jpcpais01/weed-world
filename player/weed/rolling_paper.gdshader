// Rolling paper: a flat sheet that curls itself into a tube as `roll` goes
// from 0 to 1, with a line of ground bud along its middle while it is open.
shader_type spatial;
render_mode cull_disabled;

uniform float roll : hint_range(0.0, 1.0) = 0.0;
uniform float fill : hint_range(0.0, 1.0) = 0.0;
uniform float width = 0.085;
uniform vec3 fill_color : source_color = vec3(0.45, 0.7, 0.3);
uniform vec3 paper_color : source_color = vec3(0.98, 0.95, 0.88);

varying float v_across;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	v_across = UV.x;
	float s = VERTEX.z;
	float k = max(roll, 0.0001) * 6.2831853 * 0.94 / width;
	float th = s * k;
	VERTEX.y += (1.0 - cos(th)) / k;
	VERTEX.z = sin(th) / k;
	NORMAL = vec3(0.0, cos(th), -sin(th));
}

void fragment() {
	vec3 col = paper_color;
	// Ground bud along the middle of the open sheet.
	float band = fill * 0.32;
	float d = abs(v_across - 0.5);
	float n = hash(floor(UV * vec2(70.0, 40.0)));
	if (FRONT_FACING && d < band * (0.8 + 0.4 * n)) {
		col = fill_color * (0.55 + 0.6 * n);
	}
	ALBEDO = col;
	ROUGHNESS = 0.85;
	BACKLIGHT = paper_color * 0.4;
}
