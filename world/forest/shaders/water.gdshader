// Pond, stream and creek water. Depth and flow come in per vertex from the
// terrain (no depth-buffer reads, so it stays cheap on phones): R = water
// depth in metres, G = turbulence, B = flow speed. UV.y runs downstream.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx;

uniform sampler2D water_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 shallow : source_color = vec3(0.30, 0.62, 0.55);
uniform vec3 deep : source_color = vec3(0.03, 0.17, 0.22);
uniform vec3 foam_color : source_color = vec3(0.95, 0.97, 1.0);
uniform float depth_fade = 1.1;
uniform bool flowing = false;
uniform float normal_strength = 0.35;
uniform float edge_softness = 0.12;

varying vec3 v_wp;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float depth = COLOR.r;
	float turb = COLOR.g;
	float speed = COLOR.b * 3.0;
	float t = TIME;
	vec2 uv1;
	vec2 uv2;
	if (flowing) {
		uv1 = vec2(UV.x * 0.35, UV.y * 0.12 - t * speed * 0.12);
		uv2 = vec2(UV.x * 0.6 + 0.3, UV.y * 0.25 - t * speed * 0.21);
	} else {
		uv1 = v_wp.xz * 0.09 + vec2(t * 0.012, t * 0.007);
		uv2 = v_wp.xz * 0.21 - vec2(t * 0.009, -t * 0.015);
	}
	vec4 a = texture(water_noise, uv1);
	vec4 b = texture(water_noise, uv2);
	vec2 nn = (a.rg + b.rg - 1.0) * (normal_strength + turb * 0.6);
	NORMAL_MAP = normalize(vec3(nn, 1.0)) * 0.5 + 0.5;

	float d = clamp(depth / depth_fade, 0.0, 1.0);
	vec3 col = mix(shallow, deep, smoothstep(0.0, 1.0, d));
	float foam_noise = b.b * 0.6 + a.b * 0.4;
	float edge = 1.0 - smoothstep(0.0, 0.09 + foam_noise * 0.12, depth);
	float rapids = smoothstep(0.35, 0.75, turb * (0.6 + foam_noise * 0.8));
	float foam = clamp(edge * 0.75 + rapids, 0.0, 1.0) * smoothstep(0.35, 0.6, foam_noise + rapids * 0.4);
	col = mix(col, foam_color, foam);
	ALBEDO = col;
	ALPHA = clamp(mix(0.45, 0.93, d) * smoothstep(0.0, edge_softness, depth) + foam * 0.6, 0.0, 0.97);
	ROUGHNESS = mix(0.04, 0.4, foam);
	SPECULAR = 0.6;
	METALLIC = 0.0;
	EMISSION = foam_color * foam * 0.08;
}
