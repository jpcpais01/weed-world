// Rings where Dragon Breath's water lands, for DragonBreath's ring
// MultiMesh: a flat quad on the ground with a ring that runs outwards and
// breaks up into beads of foam, and a wet sheen inside it that dries away.
// INSTANCE_CUSTOM: x age (0..1), y strength, z seed.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec3 color : source_color = vec3(0.55, 0.88, 1.0);

varying vec3 v_custom;

void vertex() {
	v_custom = INSTANCE_CUSTOM.xyz;
}

void fragment() {
	float age = v_custom.x;
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float n = texture(noise, vec2(a * 0.32 + v_custom.z, r * 0.4 - age * 0.3)).r;
	float radius = 0.12 + 0.82 * (1.0 - pow(1.0 - age, 2.2));
	float w = 0.035 + age * 0.07;
	float ring = smoothstep(w, 0.0, abs(r - radius + (n - 0.5) * 0.06)) * smoothstep(0.25, 0.55, n + 0.25 * (1.0 - age));
	float inner = smoothstep(w * 2.2, 0.0, abs(r - radius * 0.55)) * 0.3;
	float sheen = smoothstep(radius, radius * 0.4, r) * 0.12 * (1.0 - age);
	float fade = (1.0 - age) * (1.0 - age) * v_custom.y;
	ALBEDO = color * 1.3;
	ALPHA = clamp((ring + inner + sheen) * fade, 0.0, 1.0) * step(r, 1.0);
}
