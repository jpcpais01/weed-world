// A fingertip fairy flame: a flickering teardrop, hot white at the core.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 outer : source_color = vec3(1.0, 0.45, 0.1);
uniform vec3 inner : source_color = vec3(1.0, 0.95, 0.7);

void vertex() {
	// Face the camera around the vertical axis.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], MODEL_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y = -p.y;
	float wob = sin(TIME * 23.0 + p.y * 5.0) * 0.08 * (p.y + 1.0);
	p.x += wob;
	// Teardrop: round at the bottom, pointed at the top.
	float w = mix(0.75, 0.05, clamp((p.y + 1.0) * 0.5, 0.0, 1.0));
	float d = length(vec2(p.x / max(w, 0.05), (p.y + 0.35) * 0.9));
	float a = smoothstep(1.0, 0.3, d);
	float core = smoothstep(0.55, 0.0, d);
	float flick = 0.85 + 0.15 * sin(TIME * 41.0);
	ALBEDO = mix(outer, inner, core) * flick * 2.2;
	ALPHA = a;
}
