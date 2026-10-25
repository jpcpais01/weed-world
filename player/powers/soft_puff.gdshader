// A soft billboard puff of smoke or cloud (alpha blended), rounded by noise,
// lighter on top. COLOR is the tint and opacity, INSTANCE_CUSTOM.y spins it
// and .z picks a patch of the noise.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;

varying vec4 v_color;
varying vec4 v_custom;

void vertex() {
	v_color = COLOR;
	v_custom = INSTANCE_CUSTOM;
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float c = cos(v_custom.y);
	float sn = sin(v_custom.y);
	vec2 q = vec2(c * p.x - sn * p.y, sn * p.x + c * p.y);
	float n = texture(noise, q * 0.33 + vec2(v_custom.z, v_custom.z * 0.7)).r;
	float n2 = texture(noise, q * 0.8 + vec2(v_custom.z * 1.3, 0.2)).r;
	float d = length(p) + (n - 0.5) * 0.7 + (n2 - 0.5) * 0.25;
	float a = smoothstep(1.0, 0.25, d);
	ALBEDO = v_color.rgb * (0.82 + 0.22 * (1.0 - UV.y) + 0.12 * n);
	ALPHA = a * v_color.a;
}
