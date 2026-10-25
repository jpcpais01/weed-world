// A firefly: a hot yellow-green core in a soft halo, pulsing the way real
// fireflies do (a quick swell, a slow fade, a dark rest), each on its own
// rhythm. COLOR tints it and carries its fade; INSTANCE_CUSTOM.x is the
// blink phase, .y the blink rate, .z how bright it is at rest.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

varying vec4 v_color;
varying float v_glow;

void vertex() {
	v_color = COLOR;
	float t = TIME * INSTANCE_CUSTOM.y + INSTANCE_CUSTOM.x * 6.2832;
	float pulse = pow(max(sin(t), 0.0), 3.0);
	v_glow = mix(INSTANCE_CUSTOM.z, 1.0, pulse);
	float s = length(MODEL_MATRIX[0].xyz) * (0.75 + 0.45 * v_glow);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d2 = dot(p, p);
	float core = exp(-d2 * 60.0);
	float halo = exp(-d2 * 7.0) * 0.45 + exp(-d2 * 2.2) * 0.12;
	vec3 c = mix(v_color.rgb, vec3(1.0, 1.0, 0.85), core * 0.8);
	ALBEDO = c * (core * 2.2 + halo) * v_glow * v_color.a;
}
