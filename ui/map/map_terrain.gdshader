shader_type canvas_item;
// Paints the Whispering Glade as a storybook map, once, into the map bake
// viewport. Reads the terrain's own fields (packed by MapBaker):
//   r height (m)   g distance to the nearest footpath (m)
//   b water depth (m, negative on dry land)   a canopy shade 0..1
// UV 0..1 spans the world square [-extent, extent] on X (east) and Z (south).

uniform sampler2D data : filter_linear, repeat_disable;
uniform float grid_n = 241.0;
uniform float extent = 60.0;
uniform float grid_step = 0.5;
uniform float play_half = 50.0;
uniform float pixels = 1536.0;

vec4 tap(vec2 w) {
	vec2 g = (w + extent) / grid_step;
	return texture(data, (g + 0.5) / grid_n);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	vec2 w = (UV * 2.0 - 1.0) * extent;
	vec4 d = tap(w);
	float h = d.r;
	float path = d.g;
	float depth = d.b;
	float shade = d.a;

	// Shape of the land from the heightfield.
	float e = grid_step;
	float hx = tap(w + vec2(e, 0.0)).r - tap(w - vec2(e, 0.0)).r;
	float hz = tap(w + vec2(0.0, e)).r - tap(w - vec2(0.0, e)).r;
	vec3 n = normalize(vec3(-hx / (2.0 * e), 1.0, -hz / (2.0 * e)));
	float slope = 1.0 - n.y;
	// Classic cartographer's light from the north-west.
	vec3 sun = normalize(vec3(-0.65, 0.85, -0.75));
	float lit = dot(n, sun);

	float blot = vnoise(w * 0.12) * 0.55 + vnoise(w * 0.45 + 17.0) * 0.3 + vnoise(w * 1.7) * 0.15;
	float hn = smoothstep(-2.0, 11.0, h);

	vec3 meadow = vec3(0.80, 0.87, 0.50);
	vec3 grass = vec3(0.60, 0.77, 0.40);
	vec3 woods = vec3(0.38, 0.58, 0.34);
	vec3 upland = vec3(0.62, 0.70, 0.46);
	vec3 stone = vec3(0.72, 0.68, 0.64);
	vec3 col = mix(meadow, grass, smoothstep(0.02, 0.35, shade + (blot - 0.5) * 0.25));
	col = mix(col, woods, smoothstep(0.35, 0.9, shade));
	col = mix(col, upland, hn * 0.55);
	col = mix(col, stone, smoothstep(0.22, 0.5, slope) * 0.8);
	col *= 0.9 + blot * 0.2;

	// Soft relief, warm on the sunny faces and cool in the hollows.
	float relief = clamp(lit, 0.0, 1.25);
	col *= 0.74 + 0.36 * relief;
	col = mix(col, col * vec3(1.06, 1.02, 0.88), smoothstep(0.85, 1.1, lit) * 0.6);
	col = mix(col, col * vec3(0.86, 0.9, 1.04), smoothstep(0.8, 0.45, lit) * 0.5);

	// Contour lines every metre, a bolder one every five.
	float fw = max(fwidth(h), 1e-4);
	float c1 = abs(fract(h + 0.5) - 0.5) / fw;
	float c5 = abs(fract(h / 5.0 + 0.5) - 0.5) * 5.0 / fw;
	float contour = (1.0 - smoothstep(0.4, 1.3, c1)) * 0.13 + (1.0 - smoothstep(0.6, 1.6, c5)) * 0.2;
	contour *= 1.0 - smoothstep(-0.2, 0.02, depth);
	col = mix(col, col * vec3(0.55, 0.5, 0.42), contour);

	// Footpaths: a warm trodden band with a darker worn edge.
	float wobble = (vnoise(w * 1.3) - 0.5) * 0.35;
	float p_core = 1.0 - smoothstep(0.5, 0.95, path + wobble);
	float p_edge = 1.0 - smoothstep(0.9, 1.55, path + wobble);
	vec3 dirt = vec3(0.95, 0.86, 0.66) * (0.94 + 0.12 * vnoise(w * 3.0));
	col = mix(col, col * vec3(0.72, 0.68, 0.58), p_edge * 0.55);
	col = mix(col, dirt, p_core);

	// Water: wet dark banks, a pale foam line, shallows to deep blue, and
	// painted ripple strokes.
	float bank = smoothstep(-0.3, -0.02, depth) * (1.0 - smoothstep(-0.02, 0.0, depth));
	col = mix(col, col * vec3(0.72, 0.78, 0.66), bank * 0.75);
	float wet = smoothstep(-0.01, 0.025, depth);
	vec3 shallow = vec3(0.56, 0.86, 0.86);
	vec3 deep = vec3(0.23, 0.55, 0.74);
	vec3 water = mix(shallow, deep, smoothstep(0.04, 1.0, depth));
	float strokes = sin(w.x * 2.2 + w.y * 0.9 + vnoise(w * 0.6) * 7.0);
	water += smoothstep(0.93, 1.0, strokes) * 0.09 * smoothstep(0.08, 0.3, depth);
	water = mix(water, vec3(0.93, 0.99, 0.97), (1.0 - smoothstep(0.0, 0.07, depth)) * 0.75);
	col = mix(col, water, wet);

	// Beyond the playable square the hills fade into a soft morning mist.
	float sd = pow(pow(abs(w.x), 4.0) + pow(abs(w.y), 4.0), 0.25);
	float far = smoothstep(play_half - 3.0, extent + 2.0, sd);
	col = mix(col, vec3(0.84, 0.87, 0.78), far * 0.5);
	col = mix(col, col * 0.86, smoothstep(extent - 6.0, extent, sd) * 0.5);

	// Paper grain.
	col *= 0.975 + hash(floor(UV * pixels)) * 0.05;
	COLOR = vec4(col, 1.0);
}
