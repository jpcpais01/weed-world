// Distant trees as camera-facing cards (see forest_impostors.gd). Each tree
// type (the instance colour's red) has FRAMES photos taken round it; the card
// shows the two nearest the view, blended, lit with the baked normals and coloured with the same
// palette maths as canopy.gdshader so a crown keeps its colour when it swaps.
// In the shadow pass the card turns to the sun and steps back behind the
// crown, so the impostor never shadows itself.
shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, depth_draw_opaque, diffuse_lambert_wrap;

#include "wind.gdshaderinc"

uniform sampler2D albedo_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_atlas : filter_linear_mipmap, repeat_disable;
// Per type (row): frame strip uv rect, card (width, height, foot, radius),
// then color_low, color_high, alt_low, alt_high (a: wind stiffness).
uniform sampler2D type_table : filter_nearest;
uniform float frames = 8.0;
uniform vec3 autumn_low : source_color = vec3(0.34, 0.09, 0.03);
uniform vec3 autumn_high : source_color = vec3(1.0, 0.58, 0.14);
uniform float hue_variation = 0.06;
uniform float translucency = 0.75;
// A real crown shades itself; the flat card can't, so it is dimmed to match.
uniform float self_shadow = 0.88;

varying vec4 v_custom;
varying vec2 v_uv0;
varying vec2 v_uv1;
varying float v_blend;
varying vec3 v_ox;
varying vec3 v_oz;
varying flat int v_type;

vec3 hue_shift(vec3 c, float h) {
	const vec3 k = vec3(0.57735);
	float ca = cos(h * 6.2831853);
	return c * ca + cross(k, c) * sin(h * 6.2831853) + k * dot(k, c) * (1.0 - ca);
}

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	int type = int(COLOR.r + 0.5);
	v_type = type;
	vec4 rect = texelFetch(type_table, ivec2(0, type), 0);
	vec4 card = texelFetch(type_table, ivec2(1, type), 0);
	float stiffness = texelFetch(type_table, ivec2(2, type), 0).a;

	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 bx = MODEL_MATRIX[0].xyz;
	vec3 by = MODEL_MATRIX[1].xyz;
	vec3 bz = MODEL_MATRIX[2].xyz;
	float sx = length(bx);
	float sy = length(by);
	v_ox = normalize(vec3(bx.x, 0.0, bx.z));
	v_oz = normalize(vec3(bz.x, 0.0, bz.z));

	// Towards the viewer: the camera, or the sun when drawing shadows.
	bool shadow_pass = PROJECTION_MATRIX[3][3] != 0.0;
	vec3 to_eye = shadow_pass ? -CAMERA_DIRECTION_WORLD : CAMERA_POSITION_WORLD - origin;
	to_eye.y = 0.0;
	to_eye = length(to_eye) > 0.0001 ? normalize(to_eye) : v_oz;

	// Which photos: frame k was taken from angle k / frames of a turn.
	float ang = atan(dot(to_eye, v_ox), dot(to_eye, v_oz));
	float f = fract(ang / 6.2831853 + 1.0) * frames;
	float f0 = floor(f);
	v_blend = f - f0;
	float f1 = mod(f0 + 1.0, frames);
	v_uv0 = rect.xy + vec2((f0 + UV.x) * rect.z, UV.y * rect.w);
	v_uv1 = rect.xy + vec2((f1 + UV.x) * rect.z, UV.y * rect.w);

	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_eye));
	vec3 world = origin + right * VERTEX.x * card.x * sx + vec3(0.0, card.z * sy + VERTEX.y * card.y * sy, 0.0);
	world += tree_sway(world, origin, v_custom.b * 6.2831853, stiffness);
	if (shadow_pass) {
		world -= to_eye * card.w * sx;
	}
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = (VIEW_MATRIX * vec4(to_eye, 0.0)).xyz;
}

void fragment() {
	vec4 a0 = texture(albedo_atlas, v_uv0);
	vec4 a1 = texture(albedo_atlas, v_uv1);
	float w0 = a0.a * (1.0 - v_blend);
	float w1 = a1.a * v_blend;
	float cover = w0 + w1;
	if (cover < 0.5) {
		discard;
	}
	vec4 n0 = texture(normal_atlas, v_uv0);
	vec4 n1 = texture(normal_atlas, v_uv1);
	vec4 a = (a0 * w0 + a1 * w1) / cover;
	vec4 nb = (n0 * w0 + n1 * w1) / cover;

	// Octahedral normal in the tree's own space.
	vec2 e = nb.xy * 2.0 - 1.0;
	vec3 n = vec3(e.x, 1.0 - abs(e.x) - abs(e.y), e.y);
	if (n.y < 0.0) {
		n.xz = (1.0 - abs(n.zx)) * sign(n.xz);
	}
	n = normalize(n);
	vec3 wn = normalize(v_ox * n.x + vec3(0.0, n.y, 0.0) + v_oz * n.z);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	float crown = smoothstep(0.3, 0.7, nb.z);
	vec3 col = a.rgb;
	if (crown > 0.0) {
		// a.r holds the crown's light-to-dark blend; recolour it like the canopy.
		vec3 lo = texelFetch(type_table, ivec2(2, v_type), 0).rgb;
		vec3 hi = texelFetch(type_table, ivec2(3, v_type), 0).rgb;
		vec3 alo = texelFetch(type_table, ivec2(4, v_type), 0).rgb;
		vec3 ahi = texelFetch(type_table, ivec2(5, v_type), 0).rgb;
		float magic = clamp(v_custom.a, 0.0, 1.0);
		float autumn = clamp(-v_custom.a, 0.0, 1.0);
		lo = mix(mix(lo, alo, magic), autumn_low, autumn);
		hi = mix(mix(hi, ahi, magic), autumn_high, autumn);
		vec3 leaf = mix(lo, hi, a.r);
		leaf = hue_shift(leaf, (v_custom.r - 0.5) * (hue_variation + autumn * 0.1));
		leaf *= (0.86 + v_custom.g * 0.28) * self_shadow;
		col = mix(col, leaf, crown);
		BACKLIGHT = leaf * translucency * (0.5 + 0.5 * a.r) * crown;
	}
	ALBEDO = col;
	ROUGHNESS = mix(0.92, 0.82, crown);
	SPECULAR = 0.2;
	AO = mix(0.85, mix(0.3, 1.0, a.r), crown);
	AO_LIGHT_AFFECT = 0.25;
}
