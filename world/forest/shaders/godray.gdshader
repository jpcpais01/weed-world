// Fake volumetric light shafts: soft camera-facing ribbons aligned with the
// sunlight, fading near the camera and when seen end-on. One draw call for
// every shaft in the forest.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform, fog_disabled;

uniform vec3 light_dir = vec3(0.6, -0.45, -0.66);
uniform vec3 color : source_color = vec3(1.0, 0.78, 0.48);
uniform float intensity = 0.35;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying float v_face;
varying float v_dist;
varying vec4 v_custom;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	vec3 top = MODEL_MATRIX[3].xyz;
	vec3 axis = normalize(light_dir);
	float width = INSTANCE_CUSTOM.r * 4.0;
	float len = INSTANCE_CUSTOM.g * 30.0;
	vec3 to_cam = CAMERA_POSITION_WORLD - top;
	vec3 side = cross(axis, to_cam);
	side = length(side) < 1e-3 ? vec3(1.0, 0.0, 0.0) : normalize(side);
	float along = 0.5 - VERTEX.y;
	vec3 world = top + side * VERTEX.x * width * mix(0.7, 1.5, along) + axis * along * len;
	v_face = 1.0 - abs(dot(axis, normalize(CAMERA_POSITION_WORLD - world)));
	vec4 view = VIEW_MATRIX * vec4(world, 1.0);
	v_dist = -view.z;
	VERTEX = view.xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(cross(side, axis), 0.0)).xyz);
}

void fragment() {
	float across = sin(UV.x * 3.14159);
	across *= across;
	float along = smoothstep(0.0, 0.3, UV.y) * (1.0 - smoothstep(0.5, 1.0, UV.y));
	float drift = texture(noise_tex, vec2(UV.x * 0.5 + v_custom.b * 3.0, UV.y * 0.15 + TIME * 0.015)).r;
	float breathe = 0.7 + 0.3 * sin(TIME * 0.35 + v_custom.b * 20.0);
	float near = smoothstep(2.0, 9.0, v_dist);
	float face = smoothstep(0.05, 0.6, v_face);
	ALBEDO = color;
	ALPHA = clamp(across * along * (0.45 + 0.75 * drift) * breathe * near * face * intensity * v_custom.a, 0.0, 1.0);
}
