// Moon Jump's pale daytime moon: a crescent with soft craters, a faint
// earthshine on its dark side and a halo, added over the sky.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.86, 0.9, 1.0);
instance uniform float alpha = 0.0;

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) / 0.5;
	float r = length(p);
	float disc = smoothstep(1.0, 0.975, r);
	// The shadowed part is a second disc pushed to one side.
	float lit = disc * smoothstep(0.93, 1.02, length(p - vec2(0.46, -0.14)));
	float n = texture(noise, p * 0.32 + vec2(0.31, 0.57)).r;
	float n2 = texture(noise, p * 0.9 + vec2(0.7, 0.2)).r;
	float maria = smoothstep(0.42, 0.7, n) * 0.35 + smoothstep(0.55, 0.8, n2) * 0.15;
	float limb = 0.75 + 0.25 * sqrt(max(1.0 - r * r, 0.0));
	float halo = exp(-max(r - 1.0, 0.0) * 2.6) * (1.0 - disc) * 0.22 + exp(-max(r - 1.0, 0.0) * 9.0) * (1.0 - disc) * 0.25;
	vec3 c = tint * (lit * (1.0 - maria) * limb * 1.15 + disc * 0.05 + halo);
	ALBEDO = c * alpha;
}
