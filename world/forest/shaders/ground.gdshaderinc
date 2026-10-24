// The forest floor's colour, shared by the terrain, the grass and everything
// that stands on the ground. Grass blades start exactly the colour of the
// ground they grow from, and rocks, trunks and logs fade into the very same
// soil, moss and path dirt at their feet, so nothing looks pasted on.
uniform sampler2D ground_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 grass_a : source_color = vec3(0.30, 0.50, 0.15);
uniform vec3 grass_b : source_color = vec3(0.47, 0.62, 0.19);
uniform vec3 grass_dry : source_color = vec3(0.70, 0.64, 0.30);
uniform vec3 grass_shade : source_color = vec3(0.13, 0.27, 0.16);
uniform vec3 grass_wet : source_color = vec3(0.15, 0.33, 0.19);
uniform vec3 dirt_a : source_color = vec3(0.45, 0.33, 0.20);
uniform vec3 dirt_b : source_color = vec3(0.62, 0.50, 0.33);
uniform vec3 pebble : source_color = vec3(0.70, 0.66, 0.58);
uniform vec3 litter : source_color = vec3(0.36, 0.26, 0.14);
uniform vec3 mud : source_color = vec3(0.20, 0.16, 0.11);
uniform vec3 soil_dark : source_color = vec3(0.24, 0.17, 0.10);
uniform vec3 moss_ground : source_color = vec3(0.27, 0.45, 0.10);
uniform vec3 sand : source_color = vec3(0.62, 0.55, 0.40);
uniform vec3 algae : source_color = vec3(0.22, 0.34, 0.12);

// Baked by ForestGround (forest_ground.gd) and declared in project.godot.
// ground_blend is 0 until a forest has published its ground.
global uniform sampler2D ground_height;
global uniform sampler2D ground_mask;
global uniform sampler2D ground_detail;
global uniform vec4 ground_grid;
global uniform float ground_blend;

// Roughly towards the sun across the floor: little stones catch light on this
// side and throw a shadow on the other.
const vec2 GROUND_SUN = vec2(-0.905, 0.425);

vec3 ground_grass(vec2 p, float shade, float wet) {
	vec4 n1 = textureLod(ground_noise, p * 0.013, 0.0);
	vec4 n2 = textureLod(ground_noise, p * 0.057 + vec2(0.37, 0.11), 0.0);
	vec3 c = mix(grass_a, grass_b, smoothstep(0.3, 0.72, n1.r));
	c = mix(c, grass_dry, smoothstep(0.6, 0.85, n1.g) * 0.6 * (1.0 - shade));
	c *= 0.88 + 0.24 * n2.b;
	c = mix(c, grass_wet, wet * 0.65);
	c = mix(c, grass_shade, shade * 0.72);
	return c;
}

// 1 inside the baked grid (and once a forest has published it), else 0.
float ground_inside(vec2 p) {
	float half_size = (ground_grid.w - 1.0) * ground_grid.z * 0.5;
	vec2 d = abs(p - ground_grid.xy - half_size);
	return ground_blend * step(max(d.x, d.y), half_size - 0.3);
}

vec2 ground_grid_uv(vec2 p) {
	vec2 t = (p - ground_grid.xy) / ground_grid.z + 0.5;
	return clamp(t, vec2(0.5), vec2(ground_grid.w - 0.5)) / ground_grid.w;
}

float ground_height_at(vec2 p) {
	return textureLod(ground_height, ground_grid_uv(p), 0.0).r;
}

// Terrain masks: x worn path, y bare rock, z wet bank, w canopy shade.
vec4 ground_mask_at(vec2 p) {
	return textureLod(ground_mask, ground_grid_uv(p), 0.0);
}

// Detail: r bare soil, g moss, b path edge (0.5 on the edge, 1 inside),
// a contact shade. Masked to zero outside the grid.
vec2 ground_detail_uv(vec2 p) {
	return clamp((p - ground_grid.xy) / ((ground_grid.w - 1.0) * ground_grid.z), 0.0, 1.0);
}

vec4 ground_detail_lod(vec2 p, float lod) {
	return textureLod(ground_detail, ground_detail_uv(p), lod) * ground_inside(p);
}

// Small stones on the path: x stone, y sunlit rim, z shadow it throws.
vec3 ground_stones(vec2 p, float density) {
	float lo = 0.91 - density * 0.03;
	vec2 q = p * 0.83 + vec2(0.13, 0.61);
	float s = smoothstep(lo, lo + 0.025, texture(ground_noise, q).a);
	float t = smoothstep(lo, lo + 0.025, texture(ground_noise, q + GROUND_SUN * 0.035).a);
	return vec3(s, s * (1.0 - t), (1.0 - s) * t);
}

// The colour of the floor at p. m: terrain masks, det: detail sample,
// rock: colour of bare rock here, under: how far under water (0..1), fine: 1
// for the floor itself, 0 for props blending into it (their flanks would
// smear grit and stones into streaks). Also returns how muddy it is and how
// deep in contact shade.
vec3 ground_albedo(vec2 p, vec4 m, vec4 det, vec3 rock, float under, float fine, out float mudm, out float contact) {
	float shade = m.a;
	float wet = m.b;
	vec4 n = texture(ground_noise, p * 0.21);
	vec4 nf = texture(ground_noise, p * 1.1);
	vec4 ng = vec4(0.5);
	if (fine > 0.0) {
		ng = mix(ng, texture(ground_noise, p * 3.7 + vec2(0.31, 0.77)), fine);
	}

	vec3 c = ground_grass(p, shade, wet);
	// fine mottling so close-up ground never looks flat
	c *= 0.9 + 0.2 * nf.g;
	// Steep ground where the blades give up shows short turf and earth.
	float bare = smoothstep(0.05, 0.45, m.g + (n.g - 0.5) * 0.3);
	c = mix(c, mix(soil_dark * 1.2, c * 0.75, smoothstep(0.35, 0.65, ng.r)), bare * 0.55);

	// leaf litter pools under heavy canopy
	float lit = smoothstep(0.45, 0.85, shade + (n.b - 0.5) * 0.5);
	c = mix(c, litter * (0.8 + 0.4 * nf.r), lit * 0.55);

	// Trampled verge: flattened, sun-bleached grass with flecks of bare soil,
	// fading out over a metre and a half from the path's edge.
	float e = det.b;
	float verge = smoothstep(0.03, 0.5, e) * (1.0 - lit * 0.6);
	c = mix(c, mix(c, grass_dry * 0.9, 0.4), verge * 0.55);
	float fleck = smoothstep(0.58, 0.8, nf.b + verge * 0.2 + (ng.g - 0.5) * 0.15) * verge;
	c = mix(c, mix(dirt_a, c, 0.3) * (0.85 + 0.25 * nf.r), fleck * 0.6);

	// The path itself: a crisp but wandering edge with a damp dark lip, a
	// paler trodden middle, grit and small stones with a sunny top.
	float pm = smoothstep(0.485, 0.515, e + (ng.r - 0.5) * 0.05);
	if (pm > 0.0) {
		vec3 dirt = mix(dirt_a, dirt_b, smoothstep(0.2, 0.8, n.g)) * (0.85 + 0.3 * nf.b);
		dirt = mix(dirt, dirt_b * 1.06, smoothstep(0.62, 0.92, e + (n.r - 0.5) * 0.12) * 0.4);
		float lip = smoothstep(0.5, 0.53, e) * (1.0 - smoothstep(0.53, 0.62, e));
		dirt *= 1.0 - lip * 0.25;
		dirt = mix(dirt, mix(dirt_b, pebble, 0.5) * (0.8 + 0.3 * ng.b), smoothstep(0.74, 0.84, ng.a) * 0.18 * fine);
		if (fine > 0.0) {
			vec3 st = ground_stones(p, lip * 1.5 + smoothstep(0.3, 0.8, n.b));
			dirt = mix(dirt, mix(pebble, dirt_b, 0.55) * (0.7 + 0.35 * nf.r), st.x);
			dirt *= 1.0 + st.y * 0.22 - st.z * 0.3;
		}
		dirt = mix(dirt, dirt * 0.75, shade * 0.6);
		c = mix(c, dirt, pm);
	}

	// Bare soil and moss where trunks, boulders and logs meet the floor.
	float a = det.a;
	float soil = det.r * smoothstep(0.03, 0.4, a + (n.g - 0.5) * 0.25);
	vec3 sc = soil_dark * (0.8 + 0.45 * nf.r);
	sc = mix(sc, litter * 1.1, smoothstep(0.55, 0.8, ng.b) * 0.55);
	c = mix(c, sc, soil * 0.85);
	float moss = det.g * smoothstep(0.02, 0.3, a + (nf.b - 0.5) * 0.35) * clamp(0.5 + shade * 0.6 + wet * 0.4, 0.0, 1.0);
	c = mix(c, moss_ground * (0.72 + 0.55 * ng.g), smoothstep(0.22, 0.55, moss));
	contact = smoothstep(0.4, 0.95, a);

	// dark wet mud along water
	mudm = smoothstep(0.55, 0.95, wet + (n.g - 0.5) * 0.4);
	c = mix(c, mud * (0.8 + 0.4 * nf.b), mudm * 0.85);

	// Under water: pale sand and pebbles in the shallows, weed-green deeper.
	if (under > 0.0) {
		float pebs = smoothstep(0.55, 0.8, nf.a) * (0.7 + 0.3 * n.r);
		vec3 bed = mix(sand * (0.85 + 0.25 * nf.r), pebble * (0.6 + 0.5 * nf.b), pebs * 0.8);
		float weed = smoothstep(0.25, 0.9, under * 0.8 + (n.g - 0.5) * 0.8);
		bed = mix(bed, algae * (0.7 + 0.6 * nf.g), weed * 0.75);
		c = mix(c, bed, under);
		mudm *= 1.0 - under;
	}

	// Rock breaks through steep ground where its own relief is highest, with
	// a fringe of soil and moss around every outcrop instead of a smear.
	float rr = m.g + (n.r - 0.5) * 0.5;
	if (rr > 0.12) {
		float lum = dot(rock, vec3(0.333));
		float rm = smoothstep(0.44, 0.56, rr + (lum - 0.3) * 0.6);
		float fringe = smoothstep(0.12, 0.42, rr) * (1.0 - rm);
		c = mix(c, mix(soil_dark, moss_ground * 0.8, n.b), fringe * 0.5);
		c = mix(c, rock, rm);
	}
	c *= 1.0 - contact * 0.45;
	return c;
}

// How much of the floor here is meadow that real grass blades cover.
float ground_grassy(vec4 m, vec4 det, float mudm, float contact) {
	float onpath = smoothstep(0.42, 0.5, det.b);
	return (1.0 - onpath) * (1.0 - smoothstep(0.1, 0.4, m.g)) * (1.0 - mudm) * (1.0 - contact) * (1.0 - m.a * 0.72);
}
