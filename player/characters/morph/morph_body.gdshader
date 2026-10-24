shader_type spatial;
render_mode cull_disabled;
// A Keling halfway through turning into another. The glowing cut sweeps up
// from the feet: the old Keling shows above it (keep_above = 1), the new one
// below (keep_above = 0), so as it rises one is traded for the other. The
// cut's edge is ragged, flickers and burns bright; a magical rim light and
// glints play over the whole body while the spell is on. Stands in for the
// model's own material (same textures) only for the few seconds it lasts.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo : source_color = vec4(1.0);
uniform bool textured = true;
uniform bool has_normal = true;
uniform bool vertex_color = false;   // the buttercups keep their colour in the vertices
uniform float hue_shift = 0.0;
uniform float saturation = 1.0;
uniform float roughness = 1.0;
uniform float metallic = 0.0;

uniform float base_y = 0.0;          // world height of the feet
uniform float cut = -1.0;            // height of the sweep above the feet
uniform float keep_above = 1.0;
uniform vec4 edge_color : source_color = vec4(1.0, 0.85, 0.4, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 1.0, 0.9, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0);
uniform float rim = 0.0;

varying vec3 world_pos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Ragged, licking edge: slow big wobble plus fine crackle, drifting up.
	float n = noise(world_pos * 8.0 + vec3(0.0, -TIME * 1.7, 0.0)) * 0.1 + noise(world_pos * 29.0 + vec3(TIME * 0.7)) * 0.035;
	float side = (world_pos.y - base_y + n - 0.065 - cut) * (keep_above * 2.0 - 1.0);
	if (side < 0.0) {
		discard;
	}
	float edge = 1.0 - smoothstep(0.0, 0.075, side);

	vec3 col = albedo.rgb;
	if (textured) {
		col *= texture(albedo_tex, UV).rgb;
	}
	if (vertex_color) {
		vec3 hsv = rgb2hsv(COLOR.rgb * col);
		hsv.x = fract(hsv.x + hue_shift);
		hsv.y = clamp(hsv.y * saturation, 0.0, 1.0);
		col = hsv2rgb(hsv);
		BACKLIGHT = col * 0.52;
	}
	ALBEDO = col * (1.0 - edge * 0.7);
	ROUGHNESS = textured ? texture(rough_tex, UV).g * roughness : roughness;
	METALLIC = textured ? texture(rough_tex, UV).b * metallic : metallic;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}

	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.5);
	vec3 glow = mix(edge_color.rgb, core_color.rgb, edge * edge * edge) * edge * edge * 6.0;
	glow += rim_color.rgb * fres * rim * 1.3;
	// Glints winking over the body while the magic is on.
	float glint = step(0.992, hash(floor(world_pos * 55.0) + floor(TIME * 14.0)));
	glow += rim_color.rgb * glint * rim * 3.0;
	EMISSION = glow;
}
