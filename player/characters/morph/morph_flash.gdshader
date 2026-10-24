shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// The burst of light at the moment of the reveal: a soft glow with a
// four-pointed twinkle, always facing the camera.

uniform vec4 color : source_color = vec4(1.0, 0.95, 0.8, 1.0);
uniform float intensity = 0.0;
uniform float twist = 0.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float c = cos(twist), s = sin(twist);
	p = mat2(vec2(c, -s), vec2(s, c)) * p;
	float r = length(p);
	float glow = exp(-r * r * 9.0) * 1.4 + exp(-r * 3.5) * 0.35;
	float rays = (exp(-abs(p.x) * 30.0) + exp(-abs(p.y) * 30.0)) * (1.0 - smoothstep(0.0, 1.0, r));
	ALBEDO = color.rgb * (glow + rays * 0.9) * intensity * smoothstep(1.0, 0.8, r);
}
