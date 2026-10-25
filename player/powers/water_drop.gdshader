// Falling water for Dragon Breath, for DragonBreath's drop MultiMesh: each
// quad is a drop stretched along its own velocity (so fast rain reads as
// streaks and slow spray as beads), turned to face the camera around that
// axis, with a bright highlight on its leading edge.
// INSTANCE_CUSTOM: xyz velocity (m/s), w alpha. COLOR.a: size (m).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(0.62, 0.9, 1.0);

varying float v_alpha;

void vertex() {
	vec3 centre = MODEL_MATRIX[3].xyz;
	vec3 vel = INSTANCE_CUSTOM.xyz;
	float speed = length(vel);
	vec3 dir = speed > 0.01 ? vel / speed : vec3(0.0, -1.0, 0.0);
	vec3 eye = INV_VIEW_MATRIX[3].xyz;
	vec3 side = cross(dir, eye - centre);
	side = length(side) > 1e-5 ? normalize(side) : vec3(1.0, 0.0, 0.0);
	float size = COLOR.a;
	float stretch = size * (1.0 + clamp(speed * 0.045 / max(size, 0.004), 0.0, 9.0));
	VERTEX = side * VERTEX.x * size + dir * VERTEX.y * stretch;
	v_alpha = INSTANCE_CUSTOM.w;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	// A bead: round at the front (UV.y = 0 leads), tapering behind.
	float taper = mix(1.0, 0.35, UV.y);
	float d = length(vec2(p.x / taper, p.y));
	float body = smoothstep(1.0, 0.55, d);
	if (body * v_alpha < 0.01) {
		discard;
	}
	float hi = smoothstep(0.6, 0.0, length(vec2(p.x + 0.25, p.y + 0.45)));
	ALBEDO = mix(color, vec3(1.0), hi * 0.8) * 1.25;
	ALPHA = body * v_alpha * (0.55 + 0.45 * hi);
}
