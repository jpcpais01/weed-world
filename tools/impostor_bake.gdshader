// Bake pass for tools/bake_impostors.gd: writes the tree's own-space normal
// (octahedral, RG) and a crown mask (B) for the impostor atlas. Leaf cards
// get the same spherised normals the canopy shader lights them with.
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform bool crown = false;
uniform float alpha_cut = 0.42;
uniform vec3 canopy_center = vec3(0.0, 4.0, 0.0);
uniform float canopy_radius = 3.0;
uniform float normal_sphere = 0.8;

varying vec3 v_n;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void vertex() {
	vec3 n = NORMAL;
	if (crown) {
		vec3 rel = VERTEX - canopy_center;
		n = normalize(mix(n, normalize(rel + vec3(0.0, canopy_radius * 0.35, 0.0)), normal_sphere));
	}
	v_n = n;
}

void fragment() {
	if (crown && texture(leaf_tex, UV).a < alpha_cut) {
		discard;
	}
	vec3 n = normalize(v_n);
	if (!FRONT_FACING) {
		n = -n;
	}
	n /= abs(n.x) + abs(n.y) + abs(n.z);
	vec2 e = n.xz;
	if (n.y < 0.0) {
		e = (1.0 - abs(n.zx)) * vec2(n.x >= 0.0 ? 1.0 : -1.0, n.z >= 0.0 ? 1.0 : -1.0);
	}
	// The viewport stores sRGB, so hand it the linear value of the bytes we want.
	ALBEDO = to_linear(vec3(e * 0.5 + 0.5, crown ? 1.0 : 0.0));
}
