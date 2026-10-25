// The blue breath of Dragon Breath, for DragonBreath's mist MultiMesh: a
// camera-facing quad cut from tileable noise (like the joint smoke), but
// luminous: a glowing core, silver-blue edges, glints of water in it, and
// a swirl that turns as it spreads. It thins into wisps as it ages.
// COLOR: tint. INSTANCE_CUSTOM: x age (0..1), y seed, z spin (radians), w alpha.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert_wrap, specular_disabled, shadows_disabled;

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform float glow = 1.3;

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
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float age = v_custom.x;
	float seed = v_custom.y;
	vec2 o = vec2(fract(seed * 7.13), fract(seed * 3.71));
	vec2 c = UV * 2.0 - 1.0;
	// A slow swirl: the noise is turned more towards the middle.
	float l = length(c);
	float sw = (1.0 - l) * (0.8 + age * 1.6) * (fract(seed * 5.3) > 0.5 ? 1.0 : -1.0);
	vec2 cs = vec2(c.x * cos(sw) - c.y * sin(sw), c.x * sin(sw) + c.y * cos(sw));
	vec2 suv = cs * 0.5 + 0.5;
	vec2 w = texture(noise, suv * 0.5 + o + vec2(age * 0.1, -age * 0.16)).rg - 0.5;
	float shape = smoothstep(1.0, 0.1, length(c + w * (0.4 + 0.8 * age)));
	float billow = texture(noise, suv * 0.6 + o * 1.7 + w * 0.4).r;
	float wisp = texture(noise, suv * 0.9 + o * 2.3 + w * 0.7).g;
	float dens = shape * mix(mix(0.7, billow * 1.15, 0.35 + 0.6 * age), wisp * 1.35, 0.1 + 0.6 * age);
	float erode = mix(0.04, 0.42, age);
	float a = smoothstep(erode, erode + 0.6, dens) * v_custom.w;
	if (a < 0.004) {
		discard;
	}
	float core = smoothstep(0.45, 1.1, dens) * (1.0 - age);
	float glint = smoothstep(0.9, 0.96, texture(noise, suv * 2.1 + o * 3.1 + vec2(0.0, age * 0.5)).b) * (1.0 - age);
	ALBEDO = mix(v_tint, vec3(0.85, 0.95, 1.0), 0.25 * (1.0 - dens));
	NORMAL = normalize(vec3(c * 0.7, 1.0));
	BACKLIGHT = v_tint * 0.5;
	ROUGHNESS = 1.0;
	EMISSION = v_tint * glow * (0.25 + core * 1.1) + vec3(0.8, 1.0, 1.0) * glint * 2.0;
	ALPHA = a;
}
