// The spirit owl of Owl Flight (GiftOwl): João's Meshy owl, made of smoke
// and moonlight. tools/owl_asset.py bakes its anatomy into the mesh, so no
// skeleton is needed:
//   COLOR  r wing plate, g tail plume (0 root .. 1 tip), b head, a eyes
//   UV2    x out along the wing (0 shoulder .. 1 tip), y across it
//          (0 leading edge .. 1 trailing edge)
// The vertex stage flaps the wings about the shoulder and the wrist (the
// script mirrors the same maths for the wingtip trails, see GiftOwl.flap_point),
// sweeps them back for a dive, streams the tail plumes and turns the head.
// The fragment stage is the ghost: a faint glassy body you can see the forest
// through, a bright moonlit rim, smoke flowing through it from beak to tail,
// feather edges and plume tips fraying into wisps, glowing eyes, and a
// burning seam where it gathers out of smoke (form 0..1) or melts back in.
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;

// Wing beat (GiftOwl keeps these in step with its own copy of the maths).
uniform float flap_phase = 0.0;
uniform float flap_amp = 0.0;      // radians at the shoulder
uniform float wrist_amp = 0.0;     // radians at the wrist
uniform float dihedral = 0.06;     // wings held a little up when gliding
uniform float fold = 0.0;          // 0 spread .. 1 swept back for a dive
uniform vec3 shoulder = vec3(0.9, -0.333, 0.312);
uniform float wrist_x = 2.7;
uniform float head_yaw = 0.0;
uniform float head_tilt = 0.0;
uniform float plume_droop = 0.9;

// Look.
uniform float form = 1.0;          // 0 smoke .. 1 whole owl
uniform vec3 form_origin = vec3(0.0, -0.6, 0.4);
uniform float intensity = 1.0;
uniform vec3 deep_color : source_color = vec3(0.08, 0.24, 0.95);
uniform vec3 pale_color : source_color = vec3(0.45, 0.76, 1.0);
uniform vec3 rim_color : source_color = vec3(0.6, 0.88, 1.0);
uniform vec3 eye_color : source_color = vec3(0.45, 1.0, 0.95);

varying vec3 v_pos;
varying vec4 v_parts;
varying vec2 v_wing;

vec2 rot(vec2 p, float a) {
	float c = cos(a), s = sin(a);
	return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

void vertex() {
	v_pos = VERTEX;
	v_parts = COLOR;
	v_wing = UV2;
	float wing = COLOR.r;
	float tail = COLOR.g;
	float head = COLOR.b;
	float span = UV2.x;
	float chord = UV2.y;
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	float side = v.x < 0.0 ? -1.0 : 1.0;
	float ax = abs(v.x);

	if (wing > 0.001) {
		float a1 = (sin(flap_phase) * flap_amp + dihedral) * (1.0 - fold * 0.7);
		float a2 = sin(flap_phase - 0.9) * wrist_amp + fold * 0.25;
		// Wrist first (outer wing), then the shoulder carries it all.
		float ww = wing * smoothstep(wrist_x - 0.6, wrist_x + 0.7, ax);
		vec2 p = rot(vec2(ax - wrist_x, v.y - shoulder.y), a2 * ww);
		vec2 pn = rot(vec2(n.x * side, n.y), a2 * ww);
		ax = p.x + wrist_x;
		v.y = p.y + shoulder.y;
		float ws = wing * smoothstep(shoulder.x - 0.25, shoulder.x + 0.7, abs(VERTEX.x));
		p = rot(vec2(ax - shoulder.x, v.y - shoulder.y), a1 * ws);
		pn = rot(pn, a1 * ws);
		ax = p.x + shoulder.x;
		v.y = p.y + shoulder.y;
		// The trailing feathers lag the stroke and shiver in the wind.
		v.y += -cos(flap_phase) * flap_amp * 0.55 * chord * (0.3 + span) * wing;
		v.y += sin(TIME * 17.0 + ax * 2.3 + chord * 5.0) * 0.035 * chord * (0.4 + span) * wing;
		// Dive: sweep the wings back from the shoulder.
		vec2 q = rot(vec2(ax - shoulder.x, v.z - shoulder.z), -fold * 0.95 * ws);
		ax = q.x + shoulder.x;
		v.z = q.y + shoulder.z;
		n = vec3(pn.x * side, pn.y, n.z);
	}
	v.x = side * ax;

	// Tail plumes stream out behind and ripple like ribbons.
	float t2 = tail * tail;
	v.y -= tail * plume_droop;
	v.y += sin(TIME * 2.6 - tail * 3.2 + side * 0.8) * 0.32 * t2;
	v.x += sin(TIME * 1.9 - tail * 2.6 + side) * 0.2 * t2;

	// Head turns into the turn and tilts, owl-like.
	if (head > 0.001) {
		vec3 piv = vec3(0.0, -0.55, 1.15);
		vec3 h = v - piv;
		h.xz = rot(h.xz, -head_yaw * head);
		h.xy = rot(h.xy, head_tilt * head);
		v = piv + h;
		n.xz = rot(n.xz, -head_yaw * head);
	}
	// Breathing.
	v += NORMAL * sin(TIME * 2.2) * 0.012 * (1.0 - wing);

	VERTEX = v;
	NORMAL = normalize(n);
}

void fragment() {
	vec3 alb = texture(albedo_tex, UV).rgb;
	float lum = dot(alb, vec3(0.3, 0.5, 0.2));
	float wing = v_parts.r;
	float tail = v_parts.g;
	float eye = v_parts.a;
	float nd = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float fres = pow(1.0 - nd, 2.0);

	// Smoke flowing through the body, beak to tail.
	vec2 fuv = vec2(v_pos.x * 0.16, v_pos.z * 0.11 + TIME * 0.21);
	vec2 warp = texture(noise, fuv).rg - 0.5;
	float flow = texture(noise, fuv * 1.7 + warp * 0.35 + vec2(0.0, TIME * 0.12)).r;
	float wisp = texture(noise, vec2(v_pos.x * 0.32, v_pos.z * 0.19 + TIME * 0.45) + warp * 0.5).g;

	// Feather edges and plume tips fray into smoke streaming behind.
	float edge = smoothstep(0.55, 1.0, v_wing.y) * wing * (0.35 + 0.65 * v_wing.x);
	edge = max(edge, smoothstep(0.35, 1.0, tail) * 0.95);
	edge = max(edge, smoothstep(0.82, 1.0, v_wing.x) * wing * 0.8);
	float dens = wisp * 0.8 + flow * 0.45;
	float erode = edge * 0.95 + fres * 0.18;
	float cut = smoothstep(erode - 0.06, erode + 0.3, dens);

	// Gathering out of smoke: the seam runs out from the chest to the tips.
	float reach = length(v_pos - form_origin) / 6.0 + (flow - 0.5) * 0.35;
	float front = form * 1.35 - 0.12;
	if (reach > front + 0.04) {
		discard;
	}
	float seam = smoothstep(front - 0.16, front + 0.04, reach) * step(form, 0.999);

	// A ghost: mostly see-through, its shape drawn by a moonlit rim and
	// faint smoke inside, deep blue where it's thin, pale where it's dense.
	float body = 0.03 + 0.08 * lum * lum + 0.1 * smoothstep(0.55, 0.85, flow);
	float rim = fres * (0.55 + 0.45 * wisp);
	float a = clamp((body + rim * 0.6) * cut, 0.0, 1.0) * intensity;
	vec3 inner = mix(deep_color, pale_color, clamp(lum * 0.55 + flow * 0.3, 0.0, 1.0));
	vec3 glow = inner * body * 2.2 * cut + rim_color * rim * cut * 0.7;
	// Faint veins of light in the smoke.
	glow += pale_color * smoothstep(0.66, 0.74, wisp) * (1.0 - edge) * 0.16 * cut;
	glow *= intensity;
	// The eyes burn steady through it all (the albedo's cyan on the face).
	float eyes = max(eye, smoothstep(0.08, 0.25, min(alb.g, alb.b) - alb.r - 0.1) * v_parts.b);
	float pulse = 0.85 + 0.15 * sin(TIME * 3.1);
	glow += eye_color * eyes * 2.2 * pulse * intensity;
	a = max(a, eyes * 0.6 * intensity);
	// The seam glows white-blue while it forms or melts.
	glow += mix(eye_color, vec3(1.0), 0.5) * seam * 1.2 * intensity;
	a = max(a, seam * 0.35 * intensity);
	if (a < 0.003 && dot(glow, glow) < 0.0001) {
		discard;
	}
	ALBEDO = glow;
	ALPHA = a;
}
