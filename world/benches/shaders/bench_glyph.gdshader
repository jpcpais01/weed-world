// The carved view emblem on each bench. It breathes faintly at rest and
// wakes up, glowing and shimmering, while someone sits and takes in the view.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 glow_color : source_color = vec3(0.4, 0.8, 1.0);
uniform vec3 inlay_color : source_color = vec3(0.9, 0.85, 0.7);
uniform float active : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_lp;

void vertex() {
	v_lp = VERTEX;
}

void fragment() {
	float breathe = 0.5 + 0.5 * sin(TIME * 1.3);
	// A shimmer runs across the glyph while it is awake.
	float sweep = 0.5 + 0.5 * sin(TIME * 2.6 - (v_lp.x + v_lp.y) * 18.0);
	float e = mix(0.25 + 0.2 * breathe, 1.4 + 0.6 * breathe + 0.8 * sweep, active);
	ALBEDO = mix(inlay_color, glow_color, 0.55);
	EMISSION = glow_color * e;
	ROUGHNESS = 0.35;
	SPECULAR = 0.5;
}
