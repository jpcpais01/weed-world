// Butterflies, bees, dragonflies, birds and pond fish. Every creature flies
// (or swims) its own path computed right here on the GPU from its home point
// and a few random numbers, so a whole meadow of life costs one draw call.
//
// Mesh space: the body runs along +Z (forward), wings stretch along +-X and
// carry COLOR.r = 1 where they flap; fins and tails use COLOR.g.
// INSTANCE_CUSTOM: r = phase, g = speed/size jitter, b = path radius, a = hue.
shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, diffuse_lambert_wrap;

uniform int kind = 0;               // 0 butterfly, 1 bee, 2 dragonfly, 3 bird, 4 fish
uniform vec3 color_a : source_color = vec3(1.0, 0.6, 0.15);
uniform vec3 color_b : source_color = vec3(0.1, 0.06, 0.04);
uniform float flap_rate = 9.0;
uniform float flap_angle = 1.1;
uniform float glow = 0.0;

varying vec2 v_uv;
varying float v_wing;
varying vec4 v_custom;

vec3 hash3(float n) {
	return fract(sin(vec3(n, n + 1.7, n + 3.1)) * vec3(43758.5453, 22578.1459, 19642.3490));
}

// Position along the creature's path at time t, relative to its home.
vec3 path(float t, vec4 c) {
	float ph = c.r * 6.2831853;
	float sp = 0.75 + c.g * 0.5;
	float r = c.b;
	if (kind == 0) {
		// Lazy figure-of-eights with a bobbing, fluttering height.
		float u = t * 0.33 * sp + ph;
		return vec3(sin(u) * r, 0.9 + sin(u * 2.3 + ph) * 0.45 + sin(t * 7.0 + ph) * 0.04, sin(u * 2.0 + 1.3) * r * 0.6);
	} else if (kind == 1) {
		// Bees zip between flowers: quick hops with a nervous jitter.
		float seg = floor(t * 0.7 * sp + c.r * 13.0);
		float f = smoothstep(0.55, 1.0, fract(t * 0.7 * sp + c.r * 13.0));
		vec3 a = (hash3(seg + c.r * 91.0) - 0.5) * vec3(2.0 * r, 0.5, 2.0 * r);
		vec3 b = (hash3(seg + 1.0 + c.r * 91.0) - 0.5) * vec3(2.0 * r, 0.5, 2.0 * r);
		vec3 p = mix(a, b, f) + vec3(0.0, 0.45, 0.0);
		p += vec3(sin(t * 23.0 + ph), sin(t * 31.0 + ph * 2.0), cos(t * 27.0 + ph)) * 0.025;
		return p;
	} else if (kind == 2) {
		// Dragonflies hover dead still, then dart somewhere new.
		float seg = floor(t * 0.45 * sp + c.r * 7.0);
		float f = smoothstep(0.82, 1.0, fract(t * 0.45 * sp + c.r * 7.0));
		vec3 a = (hash3(seg + c.r * 57.0) - 0.5) * vec3(2.0 * r, 0.6, 2.0 * r);
		vec3 b = (hash3(seg + 1.0 + c.r * 57.0) - 0.5) * vec3(2.0 * r, 0.6, 2.0 * r);
		return mix(a, b, f) + vec3(0.0, 0.7, 0.0) + vec3(0.0, sin(t * 3.0 + ph) * 0.03, 0.0);
	} else if (kind == 3) {
		// Birds wheel in wide loose circles above the canopy.
		float u = t * 0.12 * sp + ph;
		return vec3(cos(u) * r, sin(u * 0.5 + ph) * 2.5, sin(u) * r * 0.8);
	}
	// Fish cruise slow loops through the pond.
	float u = t * 0.16 * sp + ph;
	return vec3(cos(u) * r, sin(u * 1.7) * 0.08, sin(u) * r * (0.7 + 0.3 * c.g));
}

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_uv = UV;
	v_wing = COLOR.r;
	float t = TIME;
	vec3 home = MODEL_MATRIX[3].xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	vec3 p = path(t, v_custom);
	vec3 vel = path(t + 0.05, v_custom) - p;
	vec3 fwd = length(vel.xz) > 1e-5 ? normalize(vec3(vel.x, vel.y * 0.5, vel.z)) : vec3(0.0, 0.0, 1.0);
	if (kind == 2 && length(vel) < 0.002) {
		fwd = normalize(vec3(sin(v_custom.r * 40.0), 0.0, cos(v_custom.r * 40.0)));
	}
	vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), fwd));
	vec3 up = cross(fwd, side);

	vec3 v = VERTEX;
	vec3 n = NORMAL;
	float ph = v_custom.r * 6.2831853;
	// Wing flap: rotate wing vertices about the body axis.
	if (COLOR.r > 0.0) {
		float rate = flap_rate * (0.85 + v_custom.g * 0.3);
		float beat = sin(t * rate + ph);
		if (kind == 0) {
			// Butterflies flap in bursts and glide with wings raised.
			float burst = smoothstep(-0.2, 0.4, sin(t * 0.9 + ph * 3.0));
			beat = mix(0.55, beat, burst);
		} else if (kind == 3) {
			float glide = smoothstep(-0.3, 0.3, sin(t * 0.35 + ph));
			beat = mix(0.12, beat, glide);
		}
		float a = beat * flap_angle * COLOR.r;
		float s = sign(v.x);
		float x = abs(v.x);
		v = vec3(s * x * cos(a), v.y + x * sin(a), v.z);
		n = normalize(vec3(-s * sin(a) * n.y + n.x * cos(a), n.y * cos(a) + abs(n.x) * sin(a), n.z));
	}
	// Fish bodies and tails swish side to side.
	if (kind == 4) {
		float wag = sin(t * 6.0 * (0.8 + v_custom.g * 0.4) + ph - v.z * 5.0);
		v.x += wag * 0.18 * smoothstep(0.1, -0.5, v.z) * (0.3 + COLOR.g);
	}
	vec3 world = home + p + (side * v.x + up * v.y + fwd * v.z) * size;
	vec3 wn = normalize(side * n.x + up * n.y + fwd * n.z);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}

vec3 hue_shift(vec3 c, float h) {
	const vec3 k = vec3(0.57735);
	float ca = cos(h * 6.2831853);
	return c * ca + cross(k, c) * sin(h * 6.2831853) + k * dot(k, c) * (1.0 - ca);
}

void fragment() {
	vec3 col = color_b;
	if (kind == 0 && v_wing > 0.0) {
		// Wing silhouette: a rounded forewing and a smaller hindwing.
		vec2 u = v_uv;
		float fore = length((u - vec2(0.42, 0.62)) * vec2(1.0, 1.25));
		float hind = length((u - vec2(0.36, 0.25)) * vec2(1.3, 1.35));
		if (fore > 0.5 && hind > 0.36) discard;
		float edge = smoothstep(0.34, 0.48, min(fore, hind + 0.12));
		vec3 base = hue_shift(color_a, v_custom.a);
		col = mix(base, color_b, edge);
		float spot = 1.0 - smoothstep(0.03, 0.06, length(u - vec2(0.6, 0.78)));
		col = mix(col, vec3(0.95), spot * 0.85);
		col = mix(col, color_b, smoothstep(0.08, 0.0, u.x) * 0.8);
	} else if (kind == 1) {
		if (v_wing > 0.0) {
			col = vec3(0.8, 0.85, 0.9);
		} else {
			// Fuzzy gold and black bands.
			col = mix(color_a, color_b, step(0.5, fract(v_uv.y * 3.0)));
		}
	} else if (kind == 2) {
		if (v_wing > 0.0) {
			if (abs(v_uv.y - 0.5) > 0.5 * sqrt(max(1.0 - pow(v_uv.x * 2.0 - 1.0, 2.0), 0.0))) discard;
			col = vec3(0.75, 0.85, 0.9);
		} else {
			col = hue_shift(color_a, v_custom.a);
		}
	} else if (kind == 3) {
		col = mix(color_b, color_a, v_uv.y);
	} else if (kind == 4) {
		// Koi: white bodies splashed with orange and gold.
		float blot = smoothstep(0.45, 0.6, fract(sin(dot(floor(v_uv * vec2(3.0, 5.0)) + v_custom.r * 17.0, vec2(12.9898, 78.233))) * 43758.5453));
		col = mix(vec3(0.95, 0.92, 0.86), hue_shift(color_a, v_custom.a), blot);
	}
	ALBEDO = col;
	ROUGHNESS = kind == 4 ? 0.35 : 0.7;
	SPECULAR = 0.3;
	BACKLIGHT = (kind == 0 || kind == 2) && v_wing > 0.0 ? col * 0.6 : vec3(0.0);
	EMISSION = col * glow;
}
