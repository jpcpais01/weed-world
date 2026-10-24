// A weed bud: the carved Meshy bud tinted towards its strain, with frosty
// trichome glints that twinkle as the view moves and a soft rim glow that
// breathes while the bud is ripe and ready to pick.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(1.0);
uniform float tint_mix : hint_range(0.0, 1.0) = 0.35;
uniform vec3 glow_color : source_color = vec3(0.6, 1.0, 0.4);
uniform float rim_strength = 0.9;

instance uniform float ripe = 1.0;     // 0 while regrowing, 1 ripe
instance uniform float flash = 0.0;    // brief burst of light (picked, ripened)
instance uniform float phase = 0.0;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb;
	float lum = dot(base, vec3(0.299, 0.587, 0.114));
	vec3 col = mix(base, lum * tint * 1.35, tint_mix);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 1.2;
	ALBEDO = col;
	ROUGHNESS = 0.55;
	SPECULAR = 0.55;
	BACKLIGHT = col * 0.35;

	// Frosty trichomes: tiny glints that twinkle as the bud turns.
	vec3 cell = floor(UV.xyy * vec3(260.0, 260.0, 1.0));
	float g = hash(cell + floor(phase * 13.0));
	float tw = step(0.965, g) * (0.5 + 0.5 * sin(TIME * 5.0 + g * 60.0 + dot(VIEW, vec3(9.0))));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	float breathe = 0.65 + 0.35 * sin(TIME * 2.2 + phase * 6.2831);
	EMISSION = glow_color * (fres * rim_strength * ripe * breathe + flash * 2.5) + vec3(tw) * 0.6 * ripe;
}
