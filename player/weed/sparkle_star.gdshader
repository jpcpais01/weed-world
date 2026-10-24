// A tiny four-point twinkle for sparkle particles, tinted by the particle
// colour (white-hot in the middle) and faded by its alpha.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

varying vec4 v_color;

void vertex() {
	v_color = COLOR;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float core = exp(-dot(p, p) * 30.0);
	float rays = exp(-abs(p.x) * 22.0) * exp(-abs(p.y) * 3.0) + exp(-abs(p.y) * 22.0) * exp(-abs(p.x) * 3.0);
	float a = clamp(core + rays * 0.8, 0.0, 1.0) * v_color.a;
	ALBEDO = mix(v_color.rgb, vec3(1.0), core * 0.7) * a * 1.4;
}
