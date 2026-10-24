// A soft puff of smoke for WeedSmoke's MultiMesh: a camera-facing quad whose
// shape is cut from tileable noise, so no two puffs look alike. As a puff
// ages the noise distorts more and the thin parts erode away first, so it
// swells, tears into wisps and thins out like real smoke instead of fading
// as a blob. A fake sphere normal gives it volume under the sun and sky.
// INSTANCE_CUSTOM: x age (0..1 of its life), y seed, z spin (radians), w alpha.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert_wrap, specular_disabled, shadows_disabled;

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;

varying vec4 v_custom;
varying vec2 v_plane;
varying vec3 v_tint;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_tint = COLOR.rgb;
	float a = INSTANCE_CUSTOM.z;
	vec2 r = vec2(cos(a), sin(a));
	VERTEX.xy = vec2(VERTEX.x * r.x - VERTEX.y * r.y, VERTEX.x * r.y + VERTEX.y * r.x);
	v_plane = VERTEX.xy * 2.0;
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float age = v_custom.x;
	float seed = v_custom.y;
	vec2 o = vec2(fract(seed * 7.13), fract(seed * 3.71));
	vec2 c = UV * 2.0 - 1.0;
	// Warp the outline more as the puff ages and the air churns it.
	vec2 w = texture(noise, UV * 0.45 + o + vec2(age * 0.12, -age * 0.2)).rg - 0.5;
	vec2 cd = c + w * (0.45 + 0.7 * age);
	float shape = smoothstep(1.0, 0.15, length(cd));
	float billow = texture(noise, UV * 0.55 + o * 1.7 + w * 0.35 + vec2(0.0, age * 0.15)).r;
	float wisp = texture(noise, UV * 0.8 + o * 2.3 + w * 0.6).g;
	// Young puffs are smooth and soft; the grain and strands come with age.
	float dens = shape * mix(mix(0.6, billow * 1.1, 0.4 + 0.6 * age), wisp * 1.3, 0.1 + 0.6 * age);
	// Thin parts vanish first, so an old puff breaks into strands.
	float erode = mix(0.05, 0.45, age);
	float a = smoothstep(erode, erode + 0.65, dens) * v_custom.w;
	if (a < 0.004) {
		discard;
	}
	float grain = texture(noise, UV * 1.6 + o).b;
	ALBEDO = v_tint * (0.9 + 0.12 * grain);
	vec2 p = v_plane;
	NORMAL = normalize(vec3(p * 0.75, 1.0));
	BACKLIGHT = ALBEDO * 0.35;
	ROUGHNESS = 1.0;
	ALPHA = a;
}
