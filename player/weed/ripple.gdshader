// An expanding ring on the ground: water ripples, earth shockwaves.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(0.5, 0.85, 1.0);
instance uniform float age = 0.0;     // 0..1 over the ring's life
instance uniform float strength = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float radius = 0.15 + age * 0.8;
	float w = 0.06 + age * 0.08;
	float ring = smoothstep(w, 0.0, abs(r - radius));
	float inner = smoothstep(w * 2.5, 0.0, abs(r - radius * 0.6)) * 0.35;
	float fade = (1.0 - age) * (1.0 - age) * strength;
	ALBEDO = color * 1.4;
	ALPHA = clamp((ring + inner) * fade, 0.0, 1.0) * step(r, 1.0);
}
