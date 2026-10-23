// Leaves tumbling down through the canopy. A fixed pool of leaves wraps
// around the camera, so there are always some drifting past wherever you
// walk, and they only appear where the shade map says trees overhead.
// INSTANCE_CUSTOM: r = phase, g = fall speed, b = spin, a = colour pick.
shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, diffuse_lambert_wrap;

uniform sampler2D shade_map : filter_linear, repeat_disable;
uniform float map_extent = 60.0;
uniform float box = 26.0;
uniform float fall_height = 11.0;
uniform vec3 wind_direction = vec3(0.86, 0.0, 0.5);
uniform float wind_strength = 0.45;
uniform vec3 green : source_color = vec3(0.45, 0.62, 0.16);
uniform vec3 gold : source_color = vec3(0.95, 0.68, 0.18);
uniform vec3 rust : source_color = vec3(0.72, 0.26, 0.08);

varying vec4 v_custom;
varying vec2 v_uv;

mat3 rot(vec3 axis, float a) {
	float s = sin(a);
	float c = cos(a);
	float oc = 1.0 - c;
	return mat3(
		vec3(oc * axis.x * axis.x + c, oc * axis.x * axis.y + axis.z * s, oc * axis.z * axis.x - axis.y * s),
		vec3(oc * axis.x * axis.y - axis.z * s, oc * axis.y * axis.y + c, oc * axis.y * axis.z + axis.x * s),
		vec3(oc * axis.z * axis.x + axis.y * s, oc * axis.y * axis.z - axis.x * s, oc * axis.z * axis.z + c));
}

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_uv = UV;
	vec3 seed = MODEL_MATRIX[3].xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float t = TIME;
	float ph = v_custom.r * 6.2831853;
	float speed = 0.3 + v_custom.g * 0.35;
	float h = fract(seed.y / fall_height - t * speed / fall_height);
	vec2 wind = normalize(wind_direction.xz) * wind_strength * 0.7;
	vec2 xz = seed.xz + wind * t + vec2(sin(t * 1.3 + ph), cos(t * 1.07 + ph * 1.3)) * 0.45;
	vec2 rel = (fract((xz - cam.xz) / box + 0.5) - 0.5) * box;
	xz = cam.xz + rel;
	float y = cam.y - 3.5 + h * fall_height;

	vec2 muv = clamp((xz + map_extent) / (2.0 * map_extent), 0.0, 1.0);
	float shade = textureLod(shade_map, muv, 0.0).r;
	float vis = smoothstep(0.18, 0.45, shade);
	vis *= smoothstep(0.0, 0.08, h) * smoothstep(1.0, 0.9, h);
	vis *= 1.0 - smoothstep(0.38, 0.5, max(abs(rel.x), abs(rel.y)) / box);

	float spin = 1.4 + v_custom.b * 2.2;
	mat3 r = rot(normalize(vec3(sin(ph), 0.6, cos(ph))), t * spin + ph) * rot(vec3(0.0, 1.0, 0.0), ph * 3.0);
	vec3 world = vec3(xz.x, y, xz.y) + r * VERTEX * vis;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(r * NORMAL, 0.0)).xyz);
}

void fragment() {
	// A pointed leaf with a midrib.
	vec2 u = v_uv * 2.0 - 1.0;
	float w = (1.0 - u.y * u.y) * (0.55 - u.y * 0.15);
	if (abs(u.x) > w) discard;
	float pick = v_custom.a;
	vec3 col = pick < 0.4 ? mix(green, gold, pick / 0.4) : mix(gold, rust, (pick - 0.4) / 0.6);
	col *= 0.85 + 0.15 * smoothstep(0.0, 0.08, abs(u.x));
	ALBEDO = col;
	ROUGHNESS = 0.75;
	SPECULAR = 0.2;
	BACKLIGHT = col * 0.7;
}
