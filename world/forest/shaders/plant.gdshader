// Grass, flowers, ferns and ground plants. Blades take the exact colour of the
// ground at their root (trampled and sun-bleached beside the paths, mossy at
// the feet of trees) and brighten towards the tips, ride the shared gust
// fronts, part around nearby Kelings and melt into the ground with distance.
// Anything growing in the shade of a trunk or boulder darkens to match.
shader_type spatial;
render_mode world_vertex_coords, cull_disabled, diffuse_lambert_wrap;

#include "wind.gdshaderinc"
#include "ground.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform bool ground_tint = false;
uniform bool use_alpha = true;
uniform vec3 tip_color : source_color = vec3(0.78, 0.86, 0.36);
uniform float tip_mix : hint_range(0.0, 1.0) = 0.8;
uniform vec3 tint : source_color = vec3(1.0);
uniform float hue_variation : hint_range(0.0, 0.5) = 0.04;
uniform float stiffness = 1.0;
uniform float bend_height = 1.0;
uniform float translucency : hint_range(0.0, 2.0) = 0.45;
uniform float up_normal : hint_range(0.0, 1.0) = 0.6;
uniform float fade_start = 20.0;
uniform float fade_end = 28.0;
uniform vec4 interactor_0 = vec4(0.0, -1000.0, 0.0, 0.9);
uniform vec4 interactor_1 = vec4(0.0, -1000.0, 0.0, 0.9);
uniform vec4 interactor_2 = vec4(0.0, -1000.0, 0.0, 0.9);
uniform vec4 interactor_3 = vec4(0.0, -1000.0, 0.0, 0.9);
uniform float glow = 0.0;
uniform vec3 glow_color : source_color = vec3(1.0, 0.8, 0.4);

varying vec3 v_ground;
varying float v_w;
varying vec4 v_custom;
varying float v_gust;
varying float v_contact;
varying float v_verge;

vec3 hue_shift(vec3 c, float h) {
	const vec3 k = vec3(0.57735);
	float ca = cos(h * 6.2831853);
	return c * ca + cross(k, c) * sin(h * 6.2831853) + k * dot(k, c) * (1.0 - ca);
}

vec2 push_from(vec4 it, vec3 v, float w) {
	vec2 to = v.xz - it.xz;
	float d = length(to);
	float near = 1.0 - smoothstep(it.w * 0.25, it.w, d);
	near *= 1.0 - smoothstep(0.8, 2.0, abs(v.y - it.y));
	return to / max(d, 0.001) * near * w;
}

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float w = clamp(COLOR.r, 0.0, 1.0);
	v_w = w;
	float h = max(VERTEX.y - origin.y, 0.0) / bend_height;
	float t = TIME * wind_speed;

	float gust = wind_gust(VERTEX.xz, t);
	v_gust = gust * wind_strength;
	vec2 dir = normalize(wind_direction.xz);
	vec2 flick = vec2(sin(t * 2.3 + origin.x * 0.9 + origin.z * 0.4), cos(t * 1.9 + origin.z * 0.8)) * 0.18;
	vec2 sway = (dir * (gust * 0.85 + 0.05) + flick) * wind_strength * w * w * min(h, 1.5) * 0.55 / stiffness;

	vec2 push = push_from(interactor_0, VERTEX, w) + push_from(interactor_1, VERTEX, w)
			+ push_from(interactor_2, VERTEX, w) + push_from(interactor_3, VERTEX, w);
	float pl = min(length(push), 1.0);
	push = push / max(length(push), 0.001) * pl * 0.55 * bend_height;

	float cam_d = distance(origin, CAMERA_POSITION_WORLD);
	float fade = 1.0 - smoothstep(fade_start, fade_end, cam_d);

	vec3 local = VERTEX - origin;
	local.xz += sway + push;
	local.y -= (length(sway) * 0.35 + pl * 0.45) * w * bend_height * 0.6;
	VERTEX = origin + local * fade;

	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), up_normal));
	vec4 det = ground_detail_lod(origin.xz, 0.0);
	v_contact = smoothstep(0.3, 0.9, det.a);
	v_verge = smoothstep(0.03, 0.5, det.b);
	v_ground = vec3(1.0);
	if (ground_tint) {
		v_ground = ground_grass(origin.xz, v_custom.r, v_custom.g);
		v_ground = mix(v_ground, mix(v_ground, grass_dry * 0.85, 0.45), v_verge * 0.6);
		v_ground = mix(v_ground, soil_dark * 1.3, det.r * smoothstep(0.03, 0.4, det.a) * 0.5);
		v_ground = mix(v_ground, moss_ground, det.g * smoothstep(0.02, 0.3, det.a) * 0.4);
	}
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	if (use_alpha) {
		if (tex.a < 0.5) {
			discard;
		}
	}
	vec3 col;
	if (ground_tint) {
		vec3 tip = tip_color * (0.82 + 0.36 * v_custom.b);
		tip = mix(tip, grass_dry * 1.15, v_verge * 0.45);
		tip = mix(tip, v_ground * 1.25, v_custom.r * 0.6);
		col = mix(v_ground, tip, smoothstep(0.0, 1.0, v_w) * tip_mix);
		// Gusts comb the meadow and flash the paler undersides of the blades.
		col = mix(col, col * 1.22 + vec3(0.03, 0.035, 0.0), smoothstep(0.3, 0.75, v_gust) * v_w * 0.7);
	} else {
		col = tex.rgb * tint;
		col = hue_shift(col, (v_custom.b - 0.5) * hue_variation + v_custom.a);
		col = mix(col, col * 0.62, v_custom.r * 0.5);
	}
	col *= 1.0 - v_contact * (0.4 - v_w * 0.2);
	ALBEDO = col;
	ROUGHNESS = 0.88;
	SPECULAR = 0.12;
	BACKLIGHT = col * translucency;
	AO = mix(0.35, 1.0, v_w) * (1.0 - v_contact * 0.4);
	AO_LIGHT_AFFECT = 0.3;
	if (glow > 0.0) {
		EMISSION = glow_color * glow * smoothstep(0.55, 0.95, v_w) * (0.7 + 0.3 * sin(TIME * 1.7 + v_custom.b * 40.0));
	}
}
