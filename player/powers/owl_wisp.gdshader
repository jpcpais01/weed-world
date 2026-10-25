// Spirit smoke for Owl Flight (GiftOwl's wisps MultiMesh): the breath that
// spirals up and gathers into the owl, the smoke streaming off its feathers
// as it flies, and the cloud it melts back into. A camera-facing quad cut
// from the tileable smoke noise like the joint smoke, but moonlit: it glows
// from within and thins into strands as it ages.
// COLOR: tint. INSTANCE_CUSTOM: x age (0..1), y seed, z spin (radians), w alpha.
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;

varying vec4 v_custom;
varying vec3 v_tint;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_tint = COLOR.rgb;
	float a = INSTANCE_CUSTOM.z;
	vec2 r = vec2(cos(a), sin(a));
	VERTEX.xy = vec2(VERTEX.x * r.x - VERTEX.y * r.y, VERTEX.x * r.y + VERTEX.y * r.x);
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
}

void fragment() {
	float age = v_custom.x;
	float seed = v_custom.y;
	vec2 o = vec2(fract(seed * 7.13), fract(seed * 3.71));
	vec2 c = UV * 2.0 - 1.0;
	float l = length(c);
	float sw = (1.0 - l) * (0.9 + age * 1.8) * (fract(seed * 5.3) > 0.5 ? 1.0 : -1.0);
	vec2 cs = vec2(c.x * cos(sw) - c.y * sin(sw), c.x * sin(sw) + c.y * cos(sw));
	vec2 suv = cs * 0.5 + 0.5;
	vec2 w = texture(noise, suv * 0.5 + o + vec2(age * 0.1, -age * 0.16)).rg - 0.5;
	float shape = smoothstep(1.0, 0.1, length(c + w * (0.5 + 0.8 * age)));
	float billow = texture(noise, suv * 0.6 + o * 1.7 + w * 0.4).r;
	float wisp = texture(noise, suv * 0.9 + o * 2.3 + w * 0.7).g;
	float dens = shape * mix(billow * 1.1, wisp * 1.4, 0.3 + 0.6 * age);
	float erode = mix(0.08, 0.45, age);
	float a = smoothstep(erode, erode + 0.5, dens) * v_custom.w;
	if (a < 0.003) {
		discard;
	}
	float core = smoothstep(0.5, 1.1, dens) * (1.0 - age);
	vec3 col = mix(v_tint, vec3(0.9, 0.98, 1.0), core * 0.6);
	ALBEDO = col * a * (0.8 + core);
	ALPHA = a * 0.45;
}
