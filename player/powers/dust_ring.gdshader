// A soft ring of dust or smoke rolling out over the ground (Moon Jump
// landings, the Bloom Burst wave). Noise breaks the edge into puffs.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
instance uniform vec4 color : source_color = vec4(0.8, 0.85, 1.0, 1.0);
instance uniform float age = 0.0;      // 0..1 over its life
instance uniform float strength = 1.0;
instance uniform float width = 0.12;   // band width, fraction of the radius
instance uniform float seed = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float grow = 1.0 - pow(1.0 - age, 2.2);
	float radius = 0.08 + grow * 0.86;
	float n = texture(noise, vec2(a * 0.48 + seed, r * 0.6 - age * 0.4)).r;
	float n2 = texture(noise, vec2(a * 1.6 - seed, r * 1.7 + age * 0.3)).r;
	float w = width * (0.6 + grow * 0.8) * (0.7 + 0.6 * n);
	float band = smoothstep(w, 0.0, abs(r - radius + (n2 - 0.5) * w * 0.8));
	float inner = smoothstep(radius, 0.0, r) * 0.18 * (1.0 - age);
	float fade = pow(1.0 - age, 1.6) * strength;
	float puffs = 0.55 + 0.6 * n2;
	ALBEDO = color.rgb * (band * puffs + inner) * fade * step(r, 1.0) * 1.3;
}
