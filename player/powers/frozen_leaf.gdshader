// Leaves, petals and seeds caught in the air by Slow Time. A leaf shape cut
// out of a quad (discard: alpha scissor turns black on Mobile), tinted per
// instance, lit from both sides with a warm glow where the sun shines
// through. INSTANCE_CUSTOM.x fades it in/out, .y picks the shape.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_lambert_wrap, specular_disabled;

varying vec4 v_color;
varying vec4 v_custom;

void vertex() {
	v_color = COLOR;
	v_custom = INSTANCE_CUSTOM;
	// A gentle cup along the leaf.
	VERTEX.z += (VERTEX.x * VERTEX.x) * 6.0 - 0.004;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float shape;
	if (v_custom.y < 0.33) {
		// Leaf: pointed oval.
		shape = (1.0 - abs(p.x) / (0.62 * (1.0 - p.y * p.y))) ;
	} else if (v_custom.y < 0.66) {
		// Petal: rounded teardrop.
		float w = 0.75 * sqrt(max(0.0, (1.0 - p.y) * 0.5)) * (1.0 + p.y * 0.4);
		shape = 1.0 - abs(p.x) / max(w, 0.001);
	} else {
		// Seed fluff: a soft star.
		float a = atan(p.y, p.x);
		shape = 1.0 - length(p) / (0.55 + 0.35 * abs(cos(a * 3.0)));
	}
	if (shape < 0.0 || v_custom.x < 0.02) {
		discard;
	}
	float vein = smoothstep(0.06, 0.0, abs(p.x)) * step(v_custom.y, 0.33) * 0.25;
	vec3 c = v_color.rgb * (0.82 + 0.25 * shape) - vein * 0.2;
	ALBEDO = c;
	ROUGHNESS = 0.7;
	BACKLIGHT = c * 0.6;
	EMISSION = c * 0.12 * v_custom.x;
}
