// A little heart for particles (tinted by the particle colour and alpha).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.45, 0.62);

varying vec4 v_color;

void vertex() {
	v_color = COLOR;
	// Billboard, keeping the particle's own scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) * 1.25;
	p.y = -p.y + 0.15;
	// Classic heart curve: (x^2 + y^2 - 1)^3 - x^2 y^3 <= 0
	float x = p.x, y = p.y;
	float h = pow(x * x + y * y - 1.0, 3.0) - x * x * y * y * y;
	float inside = 1.0 - smoothstep(-0.02, 0.02, h);
	if (inside < 0.01) {
		discard;
	}
	vec3 col = color * (1.0 + 0.35 * smoothstep(0.2, 0.9, y));
	ALBEDO = col;
	ALPHA = inside * v_color.a;
}
