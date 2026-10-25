// The water dragon of Dragon Breath. The mesh is the Meshy dragon unbent
// along its spine (tools/dragon_asset.py): -VERTEX.z is how far along the
// body a vertex sits, VERTEX.xy its offset from the spine. Here it is laid
// back along `spine`, the points DragonBreath samples down the trail the head
// has flown, so the whole body follows its head through the air like a real
// serpent. The node stays at the world origin: positions are world space.
//
// The look is water: the forest refracted through a glassy body, deep blue
// inside and bright at the rim, currents and caustic threads streaming from
// head to tail, a few bubbles, glowing eyes. Where the body is still coming
// out of the mist (or has already plunged into the ground) it frays away
// along a bright frothy edge.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx, shadows_disabled;

const int N = 48;

uniform vec4 spine[48];          // xyz: the spine point, head to tail; w: girth swell
uniform vec4 spine_up[48];       // xyz: the body's up there (banked into turns)
uniform float body_len = 6.3;    // the unbent model's spine length (m)
uniform float body_scale = 1.2;
uniform float head_dist = 0.0;   // how far down its path the head has come (m)
uniform float end_dist = 1000.0; // where the path ends in the ground (m)
uniform float swim_phase = 0.0;
uniform float fade = 1.0;
uniform vec3 fallback_fwd = vec3(0.0, 0.0, 1.0);

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

uniform vec3 deep_color : source_color = vec3(0.02, 0.16, 0.4);
uniform vec3 shallow_color : source_color = vec3(0.22, 0.72, 0.95);
uniform vec3 glow_color : source_color = vec3(0.5, 0.95, 1.0);
uniform vec3 foam_color : source_color = vec3(0.85, 0.97, 1.0);

varying float v_s;      // along the body (m, unscaled), 0 just ahead of the snout
varying float v_u;      // where on the path this bit of body is (m)
varying float v_ang;    // around the body, -0.5..0.5
varying float v_rim;    // how far out from the trunk (fins, mane, whiskers)

vec3 cat(vec3 a, vec3 b, vec3 c, vec3 d, float t) {
	float t2 = t * t;
	float t3 = t2 * t;
	return 0.5 * (2.0 * b + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t2 + (-a + 3.0 * b - 3.0 * c + d) * t3);
}

vec3 cat_d(vec3 a, vec3 b, vec3 c, vec3 d, float t) {
	float t2 = t * t;
	return 0.5 * ((-a + c) + 2.0 * (2.0 * a - 5.0 * b + 4.0 * c - d) * t + 3.0 * (-a + 3.0 * b - 3.0 * c + d) * t2);
}

void vertex() {
	float s = clamp(-VERTEX.z, 0.0, body_len);
	float f = s / body_len * float(N - 1);
	int i = clamp(int(floor(f)), 0, N - 2);
	float t = f - float(i);
	vec3 p0 = spine[max(i - 1, 0)].xyz;
	vec3 p1 = spine[i].xyz;
	vec3 p2 = spine[i + 1].xyz;
	vec3 p3 = spine[min(i + 2, N - 1)].xyz;
	vec3 c = cat(p0, p1, p2, p3, t);
	vec3 d = cat_d(p0, p1, p2, p3, t);
	float dl = length(d);
	vec3 fwd = dl > 1e-5 ? -d / dl : fallback_fwd;
	vec3 up0 = mix(spine_up[i].xyz, spine_up[i + 1].xyz, t);
	vec3 left = cross(up0, fwd);
	left = length(left) > 1e-4 ? normalize(left) : vec3(1.0, 0.0, 0.0);
	vec3 up = cross(fwd, left);
	float swell = mix(spine[i].w, spine[i + 1].w, t);

	vec2 off = VERTEX.xy;
	float r = length(off);
	// Fins, mane, whiskers and claws are what sticks out past the trunk.
	float rim = smoothstep(0.17, 0.32, r);
	float ahead = smoothstep(0.55, 1.6, s);
	// A swimming ripple running back down the body, and a flutter of the fins
	// and mane in the rush of air.
	float wave = sin(swim_phase - s * 2.1) * 0.05 * ahead;
	float flutter = sin(swim_phase * 2.6 - s * 5.0 + off.y * 6.0) * 0.045 * rim * smoothstep(0.45, 0.9, s);
	// The legs paddle: whatever hangs below the belly swings fore and aft.
	float leg = smoothstep(0.16, 0.3, -off.y) * ahead;
	float paddle = sin(swim_phase * 1.7 - s * 1.3 + sign(off.x) * 1.6) * 0.09 * leg;
	off *= swell;
	vec3 pos = c + (left * (off.x + wave + flutter * 0.4) + up * (off.y + flutter) + fwd * paddle) * body_scale;
	VERTEX = pos;
	NORMAL = normalize(left * NORMAL.x + up * NORMAL.y + fwd * NORMAL.z);
	TANGENT = normalize(left * TANGENT.x + up * TANGENT.y + fwd * TANGENT.z);
	BINORMAL = normalize(left * BINORMAL.x + up * BINORMAL.y + fwd * BINORMAL.z);

	v_s = s;
	v_u = head_dist - s * body_scale;
	v_ang = atan(off.y, off.x) / 6.2831853;
	v_rim = rim;
}

void fragment() {
	// Coming out of the mist at the start of the path, sinking into the
	// ground at its end: fray away along a noisy edge.
	float edge = min(v_u, end_dist - v_u);
	float n0 = texture(noise, vec2(v_ang * 1.3, v_s * 0.6) + vec2(0.0, TIME * 0.4)).r;
	float cut = edge + (n0 - 0.5) * 1.4;
	if (cut < 0.0 || fade <= 0.001) {
		discard;
	}
	float froth = 1.0 - smoothstep(0.0, 0.55, cut);

	vec3 tex = texture(albedo_tex, UV).rgb;
	float lum = dot(tex, vec3(0.3, 0.59, 0.11));
	// Horns and the inside of the mouth are pink in the model: crystal foam.
	float horn = smoothstep(0.06, 0.2, tex.r - tex.b);
	vec3 body = mix(deep_color, shallow_color, smoothstep(0.2, 0.9, lum));
	body = mix(body, foam_color, horn * 0.65);

	// Currents streaming from head to tail, and caustic threads in them.
	vec2 fuv = vec2(v_ang * 2.0, v_s * 0.42 - TIME * 0.75);
	float n1 = texture(noise, fuv).g;
	float n2 = texture(noise, fuv * vec2(1.6, 1.3) + vec2(0.37, -TIME * 0.35)).b;
	float caustic = pow(clamp(1.0 - abs(n1 + n2 - 1.0) * 2.2, 0.0, 1.0), 4.0);
	float bubbles = smoothstep(0.86, 0.92, texture(noise, vec2(v_ang * 5.0, v_s * 1.6 - TIME * 0.5)).r);

	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 0.7;
	vec3 n = normalize(NORMAL + (vec3(n1, n2, 0.5) - 0.5) * 0.25);
	float facing = clamp(dot(n, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - facing, 3.0);

	// The forest seen through the water, bent by its surface.
	vec2 ruv = SCREEN_UV + n.xy * (0.045 + 0.03 * v_rim) * (1.0 - fres * 0.6);
	vec3 behind = textureLod(screen_tex, ruv, 1.0).rgb;
	vec3 through = behind * mix(shallow_color * 1.25, vec3(1.0), 0.25 + 0.25 * v_rim);

	// Glowing eyes (the darkest bits of the head).
	float eye = (1.0 - smoothstep(0.09, 0.2, lum)) * (1.0 - smoothstep(0.75, 0.95, v_s)) * (1.0 - horn);

	ALBEDO = body * 0.32;
	ROUGHNESS = 0.05;
	METALLIC = 0.0;
	SPECULAR = 0.75;
	EMISSION = through * (1.0 - fres) * 0.9
		+ body * 0.18
		+ glow_color * (caustic * 0.75 + fres * 0.9 + bubbles * 0.8 + v_rim * 0.12)
		+ foam_color * froth * 1.6
		+ vec3(0.7, 1.0, 1.0) * eye * 2.5;
	ALPHA = clamp(mix(0.86, 1.0, fres) * fade * (1.0 - froth * 0.35), 0.0, 1.0);
}
