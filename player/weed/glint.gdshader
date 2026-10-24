// A four-point star glint, always facing the camera.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.98, 0.9);
instance uniform float strength = 1.0;
instance uniform float spin = 0.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float c = cos(spin), s = sin(spin);
	p = mat2(vec2(c, -s), vec2(s, c)) * p;
	float core = exp(-dot(p, p) * 18.0);
	float rays = exp(-abs(p.x) * 26.0) * exp(-abs(p.y) * 2.6) + exp(-abs(p.y) * 26.0) * exp(-abs(p.x) * 2.6);
	float a = clamp(core * 1.4 + rays * 0.9, 0.0, 1.0) * strength;
	ALBEDO = color * a * 1.6;
}
