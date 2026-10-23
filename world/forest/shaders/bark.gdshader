// Bark with a normal map, mossy tops and a damp mossy foot, swaying in step
// with its canopy.
shader_type spatial;
render_mode world_vertex_coords;

#include "wind.gdshaderinc"

uniform sampler2D bark_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D bark_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 alt_tint : source_color = vec3(0.92, 0.88, 0.95);
uniform vec3 moss_color : source_color = vec3(0.26, 0.42, 0.12);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.6;
uniform float normal_strength = 1.0;
uniform float stiffness = 1.0;
uniform float uv_scale = 1.0;
uniform float birch : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_wn;
varying vec3 v_wp;
varying float v_base;
varying vec4 v_custom;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	vec3 origin = MODEL_MATRIX[3].xyz;
	v_base = VERTEX.y - origin.y;
	VERTEX += tree_sway(VERTEX, origin, v_custom.b * 6.2831853, stiffness);
	v_wn = NORMAL;
	v_wp = VERTEX;
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 alb = texture(bark_tex, uv).rgb * mix(tint, alt_tint, clamp(v_custom.a, 0.0, 1.0));
	float n = texture(noise_tex, v_wp.xz * 0.35 + v_wp.y * 0.11).g;
	if (birch > 0.0) {
		// Chalk-white birch bark with dark horizontal lenticels and a rough,
		// darker foot.
		float lum = dot(alb, vec3(0.33));
		alb = mix(alb, vec3(0.9, 0.88, 0.83) * (0.75 + lum * 0.5), birch);
		float d = texture(noise_tex, vec2(UV.x * 0.9, v_wp.y * 2.6)).r;
		float dash = smoothstep(0.64, 0.72, d) * (0.6 + 0.4 * n);
		float base = 1.0 - smoothstep(0.2, 1.4 + n, v_base);
		alb = mix(alb, vec3(0.1, 0.09, 0.08), clamp(dash + base * 0.7, 0.0, 1.0) * birch);
	}
	float top = smoothstep(0.25, 0.85, v_wn.y + (n - 0.5) * 0.7);
	float foot = 1.0 - smoothstep(0.0, 1.1 + n, v_base);
	float moss = clamp((top * 0.9 + foot * 0.75) * moss_amount, 0.0, 1.0);
	alb = mix(alb, moss_color * (0.75 + 0.5 * n), moss);
	ALBEDO = alb;
	NORMAL_MAP = texture(bark_normal, uv).rgb;
	NORMAL_MAP_DEPTH = normal_strength * (1.0 - moss * 0.7);
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
	AO = mix(0.45, 1.0, COLOR.r);
	AO_LIGHT_AFFECT = 0.35;
}
