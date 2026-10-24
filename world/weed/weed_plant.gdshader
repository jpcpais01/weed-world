// Wild weed plants. They ride the forest's shared gust fronts, lean away from
// Kelings brushing past, give a springy shudder when a bud is plucked, and can
// shine with an inner light (ripe buds under Spirit Sight, a Bloom Trail
// ripening them).
shader_type spatial;
render_mode world_vertex_coords, cull_disabled, diffuse_lambert_wrap;

#include "res://world/forest/shaders/wind.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float height = 1.0;           // plant height in metres, for the bend
uniform vec3 glow_color : source_color = vec3(0.6, 1.0, 0.4);
uniform float translucency : hint_range(0.0, 2.0) = 0.6;
uniform vec4 interactor_0 = vec4(0.0, -1000.0, 0.0, 0.9);
uniform vec4 interactor_1 = vec4(0.0, -1000.0, 0.0, 0.9);
uniform vec4 interactor_2 = vec4(0.0, -1000.0, 0.0, 0.9);
uniform vec4 interactor_3 = vec4(0.0, -1000.0, 0.0, 0.9);

instance uniform float shake = 0.0;    // 1 right after a pick, decays to 0
instance uniform float glow = 0.0;     // inner light, 0..1
instance uniform float phase = 0.0;

varying float v_h;

float press_from(vec4 it, vec3 v) {
	float near = 1.0 - smoothstep(it.w * 0.2, it.w * 0.9, distance(v.xz, it.xz));
	return near * (1.0 - smoothstep(0.8, 2.0, abs(v.y - it.y)));
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 local = VERTEX - origin;
	float h = clamp(local.y / max(height, 0.01), 0.0, 1.2);
	v_h = h;
	float t = TIME * wind_speed;
	float gust = wind_gust(origin.xz, t);
	vec2 dir = normalize(wind_direction.xz);
	vec2 flick = vec2(sin(t * 2.1 + phase * 6.0 + local.y * 3.0), cos(t * 1.7 + phase * 4.0)) * 0.12;
	vec2 sway = (dir * (gust * 0.7 + 0.08) + flick) * wind_strength * h * h * 0.16;

	// Lean away from any Keling pushing through, tipping about the root.
	vec2 push = vec2(0.0);
	push += normalize(origin.xz - interactor_0.xz + vec2(0.001)) * press_from(interactor_0, VERTEX);
	push += normalize(origin.xz - interactor_1.xz + vec2(0.001)) * press_from(interactor_1, VERTEX);
	push += normalize(origin.xz - interactor_2.xz + vec2(0.001)) * press_from(interactor_2, VERTEX);
	push += normalize(origin.xz - interactor_3.xz + vec2(0.001)) * press_from(interactor_3, VERTEX);
	float bow = min(length(push), 1.0) * 0.55;
	vec2 lean = length(push) > 0.0001 ? normalize(push) : vec2(0.0);

	// A plucked plant springs back and forth a few times.
	float s = shake * sin(TIME * 22.0 + phase * 3.0) * 0.09 * h;
	vec2 shiver = vec2(s, shake * cos(TIME * 17.0) * 0.05 * h);

	float up = max(local.y, 0.0);
	local.xz += sway + shiver + lean * up * sin(bow);
	local.y -= up * (1.0 - cos(bow));
	VERTEX = origin + local;
}

void fragment() {
	vec3 col = texture(albedo_tex, UV).rgb;
	// Darker and mossier at the root, sunlit at the crown.
	col *= mix(0.62, 1.08, smoothstep(0.0, 0.7, v_h));
	ALBEDO = col;
	ROUGHNESS = 0.72;
	SPECULAR = 0.25;
	BACKLIGHT = col * translucency;
	AO = mix(0.45, 1.0, smoothstep(0.0, 0.5, v_h));
	AO_LIGHT_AFFECT = 0.4;
	float pulse = 0.75 + 0.25 * sin(TIME * 2.4 + phase * 9.0);
	EMISSION = glow_color * glow * pulse * (0.25 + 0.75 * smoothstep(0.3, 0.9, v_h)) * (0.4 + dot(col, vec3(0.6)));
}
