// The ghost feathers of Owl Flight: a few shed from the wings as the owl
// beats them, and a flurry when it gathers or melts away. Two-sided quads
// that tumble as they fall (GiftOwl turns them), glowing at the quill.
// COLOR: tint. INSTANCE_CUSTOM: x age (0..1), y seed, w alpha.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D feather : source_color, filter_linear_mipmap;

varying vec4 v_custom;
varying vec3 v_tint;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_tint = COLOR.rgb;
	// The vane flutters along its length.
	VERTEX.z += sin(TIME * 9.0 + INSTANCE_CUSTOM.y * 20.0 + VERTEX.y * 6.0) * 0.03 * (VERTEX.y + 0.5);
}

void fragment() {
	vec4 f = texture(feather, UV);
	float age = v_custom.x;
	// Melts from the tip down as it ages.
	float melt = smoothstep(age * 1.3 - 0.2, age * 1.3 + 0.1, 1.0 - UV.y);
	float a = f.a * v_custom.w * melt;
	if (a < 0.003) {
		discard;
	}
	ALBEDO = v_tint * f.rgb * (0.7 + 0.6 * (1.0 - age));
	ALPHA = a;
}
