// Floating spirit wisps that drift around the Elder tree. Unshaded HDR colour
// so they bloom through the glow pass.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled, cull_back, fog_disabled;

uniform vec3 color_a : source_color = vec3(0.45, 1.0, 0.9);
uniform vec3 color_b : source_color = vec3(1.0, 0.7, 1.0);
uniform float energy = 3.0;

varying vec4 v_custom;
varying float v_rim;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	float t = TIME * (0.3 + v_custom.g * 0.4) + v_custom.b * 40.0;
	vec3 drift = vec3(sin(t), sin(t * 1.31 + 1.0) * 0.6, cos(t * 0.87)) * (0.3 + v_custom.a * 0.6);
	VERTEX += drift / length(MODEL_MATRIX[0].xyz);
	v_rim = 0.0;
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float core = pow(facing, 2.5);
	float twinkle = 0.6 + 0.4 * sin(TIME * (1.5 + v_custom.g * 2.0) + v_custom.b * 17.0);
	vec3 c = mix(color_a, color_b, v_custom.r);
	ALBEDO = c * energy * twinkle;
	ALPHA = core;
}
