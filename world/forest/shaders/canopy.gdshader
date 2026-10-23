// Stylised tree foliage: soft "cloud" lighting from spherised normals, a
// height/depth colour gradient, sunlight glowing through the leaves, wind
// sway shared with the bark, and per-instance colour so no two trees match.
shader_type spatial;
render_mode world_vertex_coords, cull_disabled, depth_draw_opaque, diffuse_lambert_wrap;

#include "wind.gdshaderinc"

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 color_low : source_color = vec3(0.10, 0.28, 0.12);
uniform vec3 color_high : source_color = vec3(0.55, 0.78, 0.22);
uniform vec3 alt_low : source_color = vec3(0.45, 0.14, 0.38);
uniform vec3 alt_high : source_color = vec3(1.0, 0.62, 0.78);
uniform vec3 canopy_center = vec3(0.0, 4.0, 0.0);
uniform float canopy_radius = 3.0;
uniform float normal_sphere : hint_range(0.0, 1.0) = 0.8;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.42;
uniform float translucency : hint_range(0.0, 2.0) = 0.75;
uniform float hue_variation : hint_range(0.0, 0.5) = 0.06;
uniform float stiffness = 1.0;
uniform float flutter = 0.05;

varying vec4 v_custom;
varying float v_shape;

vec3 hue_shift(vec3 c, float h) {
	const vec3 k = vec3(0.57735);
	float ca = cos(h * 6.2831853);
	return c * ca + cross(k, c) * sin(h * 6.2831853) + k * dot(k, c) * (1.0 - ca);
}

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[1].xyz);
	vec3 center = (MODEL_MATRIX * vec4(canopy_center, 1.0)).xyz;
	vec3 rel = VERTEX - center;
	float rad = canopy_radius * s;
	// 0 deep inside / under the crown, 1 at the sunny outer top.
	float outer = clamp(length(rel) / rad, 0.0, 1.0);
	float up = clamp(rel.y / rad * 0.5 + 0.5, 0.0, 1.0);
	v_shape = clamp(outer * 0.6 + up * 0.55 - 0.1, 0.0, 1.0);
	NORMAL = normalize(mix(NORMAL, normalize(rel + vec3(0.0, rad * 0.35, 0.0)), normal_sphere));

	float phase = v_custom.b * 6.2831853;
	VERTEX += tree_sway(VERTEX, origin, phase, stiffness);
	float t = TIME * wind_speed;
	float g = wind_gust(origin.xz, t);
	VERTEX += NORMAL * sin(t * 4.7 + dot(VERTEX, vec3(1.9, 1.3, 2.3))) * flutter * wind_strength * (0.3 + g);
}

void fragment() {
	vec4 tex = texture(leaf_tex, UV);
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ALPHA_ANTIALIASING_EDGE = 0.25;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(leaf_tex, 0));
	float magic = v_custom.a;
	vec3 lo = mix(color_low, alt_low, magic);
	vec3 hi = mix(color_high, alt_high, magic);
	vec3 col = mix(lo, hi, smoothstep(0.05, 0.95, v_shape));
	col = hue_shift(col, (v_custom.r - 0.5) * hue_variation);
	col *= 0.86 + v_custom.g * 0.28;
	ALBEDO = col;
	ROUGHNESS = 0.82;
	SPECULAR = 0.2;
	BACKLIGHT = col * translucency * (0.5 + 0.5 * v_shape);
	AO = mix(0.3, 1.0, v_shape);
	AO_LIGHT_AFFECT = 0.25;
}
