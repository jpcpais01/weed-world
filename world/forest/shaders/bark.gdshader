// Bark with a normal map, mossy tops and a damp mossy foot, swaying in step
// with its canopy. Trunks, roots, logs and stumps fade into the colour of the
// soil they grow from, with a contact shadow along the ground line.
shader_type spatial;
render_mode world_vertex_coords;

#include "wind.gdshaderinc"
#include "ground.gdshaderinc"

uniform sampler2D bark_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D bark_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 alt_tint : source_color = vec3(0.92, 0.88, 0.95);
uniform vec3 moss_color : source_color = vec3(0.26, 0.42, 0.12);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.6;
uniform float normal_strength = 1.0;
uniform float stiffness = 1.0;
uniform float uv_scale = 1.0;
uniform float birch : hint_range(0.0, 1.0) = 0.0;
// 1 on the sawn top of a stump: UV is centred on the heart, 0.5 at the rim.
uniform float cut_face : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_wn;
varying vec3 v_wp;
varying float v_base;
varying vec4 v_custom;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	vec3 origin = MODEL_MATRIX[3].xyz;
	v_base = VERTEX.y - origin.y;
	VERTEX += tree_sway(VERTEX, origin, v_custom.b * 6.2831853, stiffness);
	v_wn = NORMAL;
	v_wp = VERTEX;
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 alb = texture(bark_tex, uv).rgb * mix(tint, alt_tint, clamp(v_custom.a, 0.0, 1.0));
	float n = texture(noise_tex, v_wp.xz * 0.35 + v_wp.y * 0.11).g;
	if (birch > 0.0) {
		// Chalk-white birch bark with dark horizontal lenticels and a rough,
		// darker foot.
		float lum = dot(alb, vec3(0.33));
		alb = mix(alb, vec3(0.9, 0.88, 0.83) * (0.75 + lum * 0.5), birch);
		float d = texture(noise_tex, vec2(UV.x * 0.9, v_wp.y * 2.6)).r;
		float dash = smoothstep(0.64, 0.72, d) * (0.6 + 0.4 * n);
		float base = 1.0 - smoothstep(0.2, 1.4 + n, v_base);
		alb = mix(alb, vec3(0.1, 0.09, 0.08), clamp(dash + base * 0.7, 0.0, 1.0) * birch);
	}
	float top = smoothstep(0.25, 0.85, v_wn.y + (n - 0.5) * 0.7);
	float foot = 1.0 - smoothstep(0.0, 1.1 + n, v_base);
	float moss = clamp((top * 0.9 + foot * 0.75) * moss_amount, 0.0, 1.0);
	alb = mix(alb, moss_color * (0.75 + 0.5 * n), moss);
	vec3 nmap = texture(bark_normal, uv).rgb;
	float spec = 0.2;
	if (cut_face > 0.0) {
		// Sawn heartwood: wobbly growth rings, a dark pith, radial checks,
		// weathered grey patches and a ring of bark and moss at the rim.
		vec2 c = UV - 0.5;
		float r = length(c) * 2.0;
		float w = texture(noise_tex, UV * 0.8).r;
		float ring = 0.5 + 0.5 * sin((r + (w - 0.5) * 0.12) * 46.0);
		vec3 wood = mix(vec3(0.5, 0.29, 0.1), vec3(0.34, 0.18, 0.06), ring * 0.6);
		wood = mix(vec3(0.18, 0.1, 0.05), wood, smoothstep(0.0, 0.14, r));
		float ang = atan(c.y, c.x);
		float check = texture(noise_tex, vec2(ang * 0.32, r * 0.06)).g;
		wood *= 1.0 - smoothstep(0.8, 0.9, check) * smoothstep(0.08, 0.35, r) * 0.65;
		wood = mix(wood, vec3(0.34, 0.28, 0.2) * (0.8 + 0.4 * n), smoothstep(0.5, 0.8, n) * 0.35);
		float rim = smoothstep(0.84, 0.93, r);
		vec3 cut = mix(wood, alb, rim);
		float cut_moss = smoothstep(0.6, 0.95, r + (n - 0.5) * 0.6) * moss_amount * 2.5;
		alb = mix(cut, moss_color * (0.75 + 0.5 * n), clamp(cut_moss, 0.0, 1.0) * 0.8);
		nmap = mix(vec3(0.5, 0.5, 1.0), nmap, rim);
		spec = 0.06;
	}
	float ao = mix(0.45, 1.0, COLOR.r);
	float melt = 0.0;
	if (ground_inside(v_wp.xz) > 0.5) {
		float hg = v_wp.y - ground_height_at(v_wp.xz);
		melt = 1.0 - smoothstep(0.0, 0.16, hg + (n - 0.5) * 0.14);
		if (melt > 0.001) {
			float mudm;
			float contact;
			vec4 det = texture(ground_detail, ground_detail_uv(v_wp.xz));
			vec3 g = ground_albedo(v_wp.xz, ground_mask_at(v_wp.xz), det, alb, 0.0, 0.0, mudm, contact);
			alb = mix(alb, g, melt);
			NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz, melt * 0.6));
		}
		float c = 1.0 - smoothstep(0.0, 0.55, hg);
		alb *= 1.0 - c * 0.18;
		ao *= 1.0 - c * 0.45;
	}
	ALBEDO = alb;
	NORMAL_MAP = nmap;
	NORMAL_MAP_DEPTH = normal_strength * (1.0 - moss * 0.7) * (1.0 - melt);
	ROUGHNESS = 0.92;
	SPECULAR = spec;
	AO = ao;
	AO_LIGHT_AFFECT = 0.35;
}
