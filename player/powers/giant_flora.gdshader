// Bloom Burst's giant flora (GiantFlora builds the meshes). One shader for
// every kind: the mesh carries its own little rig and its paint zones.
//
//   COLOR     r: zone (0 stem, .2 cap top, .4 gills/underside, .6 petal,
//                .8 glowing part, 1 leaf/frond)
//             g: 0 at the base of the part, 1 at its tip
//             b: when the part starts to grow (0..1 of the plant's growth)
//             a: how much the wind sways it
//   CUSTOM0   xyz: the point the part hangs off (its pivot), w: spare
//   CUSTOM1   xyz: hinge axis, w: angle it is folded by while closed
//
// Growing: the stem scales up out of the ground (with a springy overshoot),
// every part scales out from its pivot once its turn comes, and folded parts
// (petals, caps, fern fronds) swing open round their hinges as `open` goes
// to 1. A fern frond's fold grows along its length, so it unrolls like a
// fiddlehead. `wilt` droops and shrinks it all, `squash` is a bounce.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;

instance uniform float grow = 0.0;      // 0..1.6, seconds-ish of growth
instance uniform float open = 0.0;      // 0..1
instance uniform float wilt = 0.0;      // 0..1
instance uniform float squash = 0.0;    // bounce, -1..1
instance uniform float flash = 0.0;     // the pop of light as it bursts out
instance uniform float seed = 0.0;
instance uniform vec4 col_a : source_color = vec4(1.0, 0.4, 0.8, 1.0);
instance uniform vec4 col_b : source_color = vec4(1.0, 0.8, 0.95, 1.0);
instance uniform vec4 glow_col : source_color = vec4(0.4, 1.0, 0.9, 1.0);
instance uniform vec4 stem_col : source_color = vec4(0.82, 0.88, 0.7, 1.0);
uniform float glow_strength = 2.4;

varying vec4 v_paint;
varying vec2 v_uv;
varying float v_open;

float elastic(float t) {
	if (t <= 0.0) return 0.0;
	if (t >= 1.0) return 1.0;
	return pow(2.0, -9.0 * t) * sin((t * 9.0 - 0.75) * 2.0944) + 1.0;
}

vec3 rotate_axis(vec3 v, vec3 axis, float a) {
	float c = cos(a);
	float s = sin(a);
	return v * c + cross(axis, v) * s + axis * dot(axis, v) * (1.0 - c);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	v_paint = COLOR;
	v_uv = UV;
	vec3 anchor = CUSTOM0.xyz;
	vec3 axis = CUSTOM1.xyz;
	float fold = CUSTOM1.w;
	float delay = COLOR.b;
	float g0 = elastic(clamp(grow / 0.75, 0.0, 1.0));
	float gp = elastic(clamp((grow - delay * 0.9) / 0.6, 0.0, 1.0));
	float o = clamp(open, 0.0, 1.0);
	v_open = o;
	vec3 local = VERTEX - anchor;
	if (dot(axis, axis) > 0.01) {
		local = rotate_axis(local, normalize(axis), fold * (1.0 - o));
		NORMAL = rotate_axis(NORMAL, normalize(axis), fold * (1.0 - o));
	}
	// A bounce squashes caps (zones .2 and .4) flat and wide for a moment.
	float cap = step(0.1, COLOR.r) * step(COLOR.r, 0.5);
	local *= mix(vec3(1.0), vec3(1.0 + squash * 0.18, 1.0 - squash * 0.32, 1.0 + squash * 0.18), cap);
	vec3 p = anchor * g0 + local * gp;
	// Wilting: everything sags, curls in and shrinks back down.
	float w = clamp(wilt, 0.0, 1.0);
	p.y *= 1.0 - w * w * 0.85;
	p.xz *= 1.0 - w * 0.5;
	p *= 1.0 - w * w * w;
	// Wind and a lazy breathing sway.
	float sway = COLOR.a;
	float t = TIME * 0.9 + seed * 6.0;
	p.x += sin(t + p.y * 0.35) * sway * 0.09;
	p.z += cos(t * 0.8 + p.y * 0.3) * sway * 0.07;
	VERTEX = p;
}

void fragment() {
	float zone = v_paint.r;
	float along = v_paint.g;
	vec3 albedo;
	vec3 emit = vec3(0.0);
	float rough = 0.6;
	float back = 0.2;
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 3.0);
	if (zone < 0.1) {
		// Stem: pale, faintly ribbed, glowing a touch near the top.
		float rib = 0.92 + 0.08 * sin(v_uv.x * 6.2832 * 9.0);
		albedo = stem_col.rgb * rib * (0.8 + 0.25 * along);
		emit = glow_col.rgb * smoothstep(0.75, 1.0, along) * 0.15;
		back = 0.15;
	} else if (zone < 0.3) {
		// Cap top: a gradient to the rim, scattered glowing spots.
		albedo = mix(col_a.rgb, col_b.rgb, smoothstep(0.35, 1.0, along));
		vec2 g = v_uv * vec2(18.0, 7.0);
		vec2 id = floor(g);
		vec2 f = fract(g) - 0.5;
		float h = hash(id + seed);
		vec2 off = (vec2(hash(id + 1.3), hash(id + 2.7)) - 0.5) * 0.45;
		float spot = smoothstep(0.1 + 0.16 * h, 0.04 + 0.1 * h, length(f - off)) * step(0.42, h) * smoothstep(0.05, 0.2, along);
		albedo = mix(albedo, vec3(1.0, 0.98, 0.92), spot * 0.85);
		emit = glow_col.rgb * spot * 0.55 + col_b.rgb * rim * 0.25;
		rough = 0.45;
	} else if (zone < 0.5) {
		// Gills: fine radial ribs of light.
		float ribs = pow(0.5 + 0.5 * sin(v_uv.x * 6.2832 * 64.0), 4.0);
		albedo = mix(col_a.rgb * 0.5, glow_col.rgb, 0.4);
		emit = glow_col.rgb * (0.35 + 0.85 * ribs) * (0.5 + 0.5 * along);
		back = 0.4;
	} else if (zone < 0.7) {
		// Petal: base colour to tip colour, a fine vein, light shining through.
		albedo = mix(col_a.rgb, col_b.rgb, smoothstep(0.0, 1.0, along));
		float vein = smoothstep(0.035, 0.0, abs(v_uv.y - 0.5)) * 0.25;
		albedo = mix(albedo, col_b.rgb * 1.1, vein);
		emit = glow_col.rgb * (smoothstep(0.35, 0.0, along) * 0.25 + rim * 0.3) + col_b.rgb * rim * 0.15;
		back = 0.75;
		rough = 0.5;
	} else if (zone < 0.9) {
		// The glowing parts: stamens, bell hearts, lotus cores, seed tips.
		albedo = glow_col.rgb;
		emit = glow_col.rgb * (1.1 + 0.5 * along);
		back = 0.5;
	} else {
		// Leaves and fronds: deep green to a lit tip, a midrib.
		albedo = mix(stem_col.rgb * vec3(0.55, 0.85, 0.5), col_b.rgb, smoothstep(0.55, 1.0, along) * 0.6);
		float mid = smoothstep(0.05, 0.0, abs(v_uv.y - 0.5));
		albedo = mix(albedo, albedo * 1.35, mid);
		emit = glow_col.rgb * smoothstep(0.8, 1.0, along) * 0.35 * v_open;
		back = 0.6;
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	BACKLIGHT = albedo * back;
	float pulse = 0.85 + 0.15 * sin(TIME * 1.7 + seed * 9.0 + along * 3.0);
	EMISSION = emit * glow_strength * pulse * (1.0 - wilt * 0.8) + glow_col.rgb * flash * 1.5;
}
