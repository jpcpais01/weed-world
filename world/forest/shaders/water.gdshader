// Pond, stream and creek water. Looks into the scene behind the surface for
// real depth: light is absorbed along the path through the water (reds go
// first, so deep pools turn teal), the bed shows through with refraction and
// dancing caustics, foam gathers wherever water meets rock or bank, and a
// short screen-space march reflects the trees and the sky.
//
// Per vertex: COLOR.r = water depth (m), COLOR.g = turbulence, COLOR.b = flow
// speed, UV2 = flow direction * speed in world XZ.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx, diffuse_lambert;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D water_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D caustic_tex : filter_linear_mipmap, repeat_enable;

uniform vec3 absorption = vec3(0.34, 0.11, 0.085);   // per metre: reds vanish first
uniform vec3 scatter_color : source_color = vec3(0.1, 0.36, 0.34);
uniform vec3 foam_color : source_color = vec3(0.93, 0.96, 0.98);
uniform vec3 caustic_color : source_color = vec3(1.0, 0.88, 0.66);
uniform float caustic_strength = 1.6;
uniform vec3 light_dir = vec3(0.83, -0.40, -0.39);    // direction the sunlight travels
uniform vec3 sun_color : source_color = vec3(1.0, 0.78, 0.52);
uniform bool flowing = false;
uniform bool ripples = false;
uniform float refraction = 0.045;
uniform float normal_strength = 0.3;
uniform int ssr_steps = 10;
uniform vec4 interactor_0 = vec4(0.0, -1000.0, 0.0, 0.0);
uniform vec4 interactor_1 = vec4(0.0, -1000.0, 0.0, 0.0);
uniform vec4 interactor_2 = vec4(0.0, -1000.0, 0.0, 0.0);
uniform vec4 interactor_3 = vec4(0.0, -1000.0, 0.0, 0.0);
// Splash ripples (WaterFX): x, z, age in seconds, strength (0 = free slot).
uniform vec4 splashes[10];
// Kelings in the water: x, surface y, z, strength / velocity x, z, swimming.
uniform vec4 wake_pos[4];
uniform vec4 wake_vel[4];

varying vec3 v_wp;
varying vec2 v_flow;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_flow = UV2;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Gradient of an expanding ring of ripples centred on c.
vec2 ring_grad(vec2 p, vec2 c, float radius, float amp) {
	vec2 to = p - c;
	float d = length(to);
	float x = d - radius;
	float env = exp(-x * x * 18.0) * amp;
	return to / max(d, 0.001) * cos(x * 26.0) * env;
}

// Insects and falling seeds touching the pond: rings that bloom and fade at
// random spots, a few at a time.
vec2 drop_ripples(vec2 p, float t) {
	vec2 g = vec2(0.0);
	vec2 cell = floor(p / 2.6);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = cell + vec2(float(x), float(y));
			float h = hash12(c);
			if (h > 0.45) continue;
			float period = 5.0 + h * 14.0;
			float age = mod(t + h * 97.0, period);
			if (age > 2.4) continue;
			vec2 centre = (c + vec2(hash12(c + 7.1), hash12(c + 3.7)) * 0.8 + 0.1) * 2.6;
			float fade = (1.0 - age / 2.4) * smoothstep(0.0, 0.2, age);
			g += ring_grad(p, centre, age * 0.55, 0.22 * fade * fade);
		}
	}
	return g;
}

// Little rings running out from a Keling standing in the water.
vec2 wake(vec4 it, vec2 p, float surface, float t) {
	float wading = 1.0 - smoothstep(0.1, 0.9, abs(it.y - surface + 0.3));
	if (wading <= 0.0) return vec2(0.0);
	vec2 to = p - it.xz;
	float d = length(to);
	float env = exp(-d * 1.4) * smoothstep(0.15, 0.35, d) * wading;
	return to / max(d, 0.001) * cos(d * 16.0 - t * 7.0) * env * 0.35;
}

// A splash: a train of rings running out from where something hit the water,
// with a puff of foam at its heart that breaks up as it spreads.
vec3 splash_ring(vec2 p, vec4 s, float fn) {
	if (s.w <= 0.0) return vec3(0.0);
	vec2 to = p - s.xy;
	float d = length(to);
	float age = s.z;
	float big = min(s.w, 1.0);
	float radius = 0.08 + age * (0.42 + 0.3 * big);
	if (d > radius + 0.7) return vec3(0.0);
	vec2 dir = to / max(d, 0.001);
	float x = d - radius;
	// A leading crest with smaller ones trailing inside it.
	float env = exp(-x * x * 22.0) + 0.55 * exp(-(x + 0.24) * (x + 0.24) * 30.0) * smoothstep(0.12, 0.35, radius);
	vec2 g = dir * cos(x * 30.0) * env * s.w * 0.6;
	// Foam churned up at the heart and flung out on the first crest.
	float young = exp(-age * 2.2);
	float heart = exp(-d * d / (0.03 + 0.22 * big)) * young;
	float crest = exp(-x * x * 70.0) * exp(-age * 1.7);
	float foam = (heart * 1.3 + crest * 0.75) * min(s.w * 1.8, 1.0) * smoothstep(0.25, 0.62, fn + young * 0.35);
	return vec3(g, foam);
}

// The V of little waves fanning out behind a swimming (or wading) Keling,
// pinned to it like a boat's wake, with a churn of foam at its chest.
vec3 kelvin_wake(vec2 p, float surface, vec4 pos, vec4 vel, float fn) {
	if (pos.w <= 0.0 || abs(surface - pos.y) > 0.35) return vec3(0.0);
	vec2 to = p - pos.xz;
	float d2 = dot(to, to);
	if (d2 > 49.0) return vec3(0.0);
	float speed = length(vel.xy);
	vec2 fwd = speed > 0.05 ? vel.xy / speed : vec2(0.0, 1.0);
	vec2 side = vec2(-fwd.y, fwd.x);
	float s = -dot(to, fwd);
	float l = dot(to, side);
	float behind = max(s, 0.0);
	float move = smoothstep(0.08, 0.6, speed);
	// Two arms at the Kelvin angle (~19.5 degrees) with crests along them,
	// and softer transverse waves rolling between them.
	float arm = abs(l) - behind * 0.36 - 0.2;
	vec2 out_dir = normalize(side * (l < 0.0 ? -1.0 : 1.0) - fwd * 0.36);
	float reach = exp(-behind * (0.95 - 0.3 * min(speed, 1.5))) * smoothstep(-0.35, 0.15, s);
	float arms = exp(-arm * arm * 16.0) * cos(arm * 26.0 - behind * 3.0);
	float inside = smoothstep(0.1, -0.15, arm) * smoothstep(-0.2, 0.3, s);
	float trans = sin(behind * 15.0) * inside * 0.35;
	vec2 g = (out_dir * arms + fwd * trans) * reach * move * pos.w * min(speed, 1.4) * 0.6;
	// Froth at the chest and a short trail of it behind.
	float chest = exp(-d2 * 9.0) * (0.35 + 0.65 * vel.z);
	float trail = exp(-l * l * 14.0) * exp(-behind * 1.3) * smoothstep(-0.1, 0.2, s) * move;
	float foam = (chest * 0.6 + trail * 0.6) * pos.w * smoothstep(0.35, 0.75, fn + 0.15 * move);
	return vec3(g, foam);
}

vec3 view_from_depth(vec2 uv, float raw, mat4 inv_proj) {
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, raw, 1.0);
	return v.xyz / v.w;
}

void fragment() {
	float t = TIME;
	vec2 wp = v_wp.xz;
	float turb = COLOR.g;

	// Surface normal: two noise layers advected along the flow and cross-faded
	// (a flow map), so the water visibly runs downstream without stretching.
	vec2 flow = v_flow * 1.6;
	// Each layer jumps back to its start once per cycle, so it must be
	// invisible at that moment: a layer's weight peaks mid-cycle and falls to
	// zero exactly when it wraps. A slow noise staggers the cycle across the
	// surface so the whole river never pulses in step.
	vec2 base = wp * 0.16;
	float stagger = texture(water_noise, wp * 0.015).b * 0.6;
	float ph0 = fract(t * 0.35 + stagger);
	float ph1 = fract(ph0 + 0.5);
	float w0 = 1.0 - abs(1.0 - 2.0 * ph0);
	float w1 = 1.0 - w0;
	// Averaging two unrelated noises flattens them; restore the contrast.
	float keep = inversesqrt(w0 * w0 + w1 * w1);
	vec2 drift = vec2(t * 0.011, t * 0.007);
	vec4 n0 = texture(water_noise, base - flow * ph0 + drift);
	vec4 n1 = texture(water_noise, base - flow * ph1 + vec2(0.37, 0.61) + drift);
	vec4 n = vec4(((n0.rg - 0.5) * w0 + (n1.rg - 0.5) * w1) * keep + 0.5, n0.ba * w0 + n1.ba * w1);
	vec2 fdrift = vec2(-t * 0.02, t * 0.017);
	vec4 fine0 = texture(water_noise, wp * 0.43 - flow * ph0 * 1.7 + fdrift);
	vec4 fine1 = texture(water_noise, wp * 0.43 - flow * ph1 * 1.7 + vec2(0.5) + fdrift);
	vec4 fine = vec4(((fine0.rg - 0.5) * w0 + (fine1.rg - 0.5) * w1) * keep + 0.5, fine0.ba * w0 + fine1.ba * w1);
	vec2 grad = (n.rg - 0.5) * (normal_strength + turb * 0.9) + (fine.rg - 0.5) * (0.16 + turb * 0.5);
	if (ripples) {
		grad += drop_ripples(wp, t);
	}
	grad += wake(interactor_0, wp, v_wp.y, t) + wake(interactor_1, wp, v_wp.y, t)
			+ wake(interactor_2, wp, v_wp.y, t) + wake(interactor_3, wp, v_wp.y, t);
	// Splashes and swimmers' wakes; their foam joins the rest further down.
	float fx_noise = fine.b * 0.6 + n.b * 0.4;
	vec3 fx = vec3(0.0);
	for (int i = 0; i < 10; i++) {
		fx += splash_ring(wp, splashes[i], fx_noise);
	}
	for (int i = 0; i < 4; i++) {
		fx += kelvin_wake(wp, v_wp.y, wake_pos[i], wake_vel[i], fx_noise);
	}
	grad += fx.xy;
	vec3 n_world = normalize(vec3(-grad.x, 1.0, -grad.y));
	vec3 nv = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	NORMAL = nv;

	// How much water lies behind this pixel.
	float surf_z = -VERTEX.z;
	vec3 scene0 = view_from_depth(SCREEN_UV, texture(depth_tex, SCREEN_UV).r, INV_PROJECTION_MATRIX);
	float thick0 = max(-scene0.z - surf_z, 0.0);

	// Refraction: bend the view by the surface normal, unless that would pick
	// up something standing in front of the water.
	vec2 off = (nv.xy) * refraction * clamp(thick0 * 1.5, 0.0, 1.0);
	vec2 ruv = clamp(SCREEN_UV + off, vec2(0.002), vec2(0.998));
	float rraw = texture(depth_tex, ruv).r;
	vec3 scene = view_from_depth(ruv, rraw, INV_PROJECTION_MATRIX);
	if (-scene.z < surf_z) {
		ruv = SCREEN_UV;
		scene = scene0;
	}
	vec3 bed = (INV_VIEW_MATRIX * vec4(scene, 1.0)).xyz;
	float path = max(length(scene - VERTEX), 0.0);
	float vdepth = max(v_wp.y - bed.y, 0.0);
	float vdepth0 = max(v_wp.y - (INV_VIEW_MATRIX * vec4(scene0, 1.0)).y, 0.0);
	// The mesh also knows the depth at each vertex (0 where its rim runs up
	// under the bank), which keeps the shore soft even where the depth buffer
	// is coarse or unavailable.
	float shallow = min(vdepth0, COLOR.r);

	vec3 behind = textureLod(screen_tex, ruv, 0.0).rgb;

	// Caustics: two drifting webs of light focused onto the bed.
	vec2 cuv = bed.xz * 0.24 + grad * 0.12;
	float c1 = texture(caustic_tex, cuv + vec2(t * 0.031, t * 0.017)).r;
	float c2 = texture(caustic_tex, cuv * 1.37 + vec2(-t * 0.023, t * 0.029)).g;
	float web = 1.0 - min(c1, c2);
	float caustic = smoothstep(0.78, 0.98, web) + smoothstep(0.9, 1.0, web) * 0.8;
	float sun_up = clamp(-light_dir.y, 0.0, 1.0);
	caustic *= caustic_strength * smoothstep(0.02, 0.2, vdepth) * exp(-vdepth * 0.9) * (0.4 + sun_up);
	behind *= 1.0 + caustic * caustic_color;

	// Beer-Lambert absorption plus light scattered back out of the water body.
	vec3 trans = exp(-absorption * path * 1.3);
	vec3 body = scatter_color * (0.55 + 0.45 * sun_up) * sun_color * 1.2;
	vec3 water = behind * trans + body * (1.0 - trans);

	// Shoreline. The water thins away over its last few centimetres so the
	// edge never traces the ground's polygons, and the shore foam is only a
	// soft, broken line that laps slowly in and out (on gentle banks a wide
	// depth band would paint a broad white strip). Rapids and the stones in
	// running water still churn up proper foam.
	float fn = texture(water_noise, wp * 0.7 - v_flow * t * 0.9).b * 0.6
			+ texture(water_noise, wp * 1.6 + vec2(t * 0.05, -t * 0.04)).b * 0.4;
	float soft = texture(water_noise, wp * 0.23 + vec2(t * 0.013, -t * 0.009)).b;
	float edge = smoothstep(0.0, 0.14 + soft * 0.08, shallow);
	float lap = 0.5 + 0.5 * sin(t * 0.85 + soft * 9.0);
	float line_depth = 0.02 + lap * 0.035;
	float lap_line = exp(-pow((shallow - line_depth) / (0.012 + soft * 0.01), 2.0));
	float shore = lap_line * smoothstep(0.3, 0.75, fn * 0.7 + soft * 0.5) * (flowing ? 0.7 : 0.42);
	float stones = flowing ? (1.0 - smoothstep(0.0, 0.05 + fn * 0.1, vdepth0)) * smoothstep(0.35, 0.65, fn) * 0.6 : 0.0;
	float rapids = smoothstep(0.3, 0.8, turb * (0.55 + fn * 0.9));
	float foam = clamp(max(max(shore, stones), max(rapids * smoothstep(0.3, 0.62, fn + rapids * 0.35), fx.z)), 0.0, 1.0);

	// Screen-space reflection of whatever stands above the water.
	float fres = 0.02 + 0.98 * pow(1.0 - clamp(dot(nv, VIEW), 0.0, 1.0), 5.0);
	vec3 rd = reflect(-VIEW, nv);
	vec3 p = VERTEX;
	float stride = 0.3 + surf_z * 0.02;
	float hit = 0.0;
	vec3 refl = vec3(0.0);
	for (int i = 0; i < ssr_steps; i++) {
		p += rd * stride;
		stride *= 1.5;
		vec4 clip = PROJECTION_MATRIX * vec4(p, 1.0);
		vec2 suv = clip.xy / clip.w * 0.5 + 0.5;
		if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0 || clip.w <= 0.0) break;
		vec3 sp = view_from_depth(suv, texture(depth_tex, suv).r, INV_PROJECTION_MATRIX);
		float diff = -p.z - (-sp.z);
		if (diff > 0.0 && diff < stride * 2.0 + 0.4) {
			vec2 e = smoothstep(vec2(0.0), vec2(0.12), suv) * smoothstep(vec2(0.0), vec2(0.12), 1.0 - suv);
			hit = e.x * e.y * (1.0 - float(i) / float(ssr_steps));
			refl = textureLod(screen_tex, suv, 1.5).rgb;
			break;
		}
	}

	// Sun glitter: sparks where facets catch the low sun.
	float facing = max(dot(reflect(light_dir, n_world), normalize(CAMERA_POSITION_WORLD - v_wp)), 0.0);
	float sparkle = smoothstep(0.82, 1.0, fine.b) * pow(facing, 60.0) * 6.0;

	// Reflections and glints fade with the edge too, or the thinning water
	// would still draw a bright outline.
	hit *= edge;
	sparkle *= edge;
	vec3 col = water * (1.0 - fres * hit) + refl * fres * hit;
	vec3 froth = mix(water, foam_color, 0.75);
	ALBEDO = froth * foam;
	EMISSION = col * (1.0 - foam) + sun_color * sparkle * (1.0 - foam);
	ROUGHNESS = mix(0.04, 0.55, foam);
	METALLIC = 0.0;
	SPECULAR = mix(0.5, 0.0, max(hit, foam)) * edge;
	ALPHA = clamp(edge + foam * 0.85, 0.0, 1.0);
}
