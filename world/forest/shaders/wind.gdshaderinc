// Shared wind field. Every swaying thing in the forest samples the same gust
// fronts, so a breeze visibly rolls across the meadow and up into the trees.
uniform vec3 wind_direction = vec3(0.86, 0.0, 0.5);
uniform float wind_strength : hint_range(0.0, 2.0) = 0.4;
uniform float wind_speed = 1.0;

float wind_gust(vec2 p, float t) {
	float along = dot(p, normalize(wind_direction.xz));
	float across = dot(p, vec2(-wind_direction.z, wind_direction.x));
	float a = sin(along * 0.11 - t * 1.05 + sin(across * 0.07) * 1.5);
	float b = sin(along * 0.043 - t * 0.41 + 1.3);
	return clamp(0.5 + 0.35 * a + 0.3 * b, 0.0, 1.2);
}

// Whole-tree sway: displacement grows with the square of height above the
// trunk base so the crown leans while the roots stay planted.
vec3 tree_sway(vec3 world_v, vec3 origin, float phase, float stiffness) {
	float t = TIME * wind_speed;
	float h = max(world_v.y - origin.y, 0.0);
	float k = h * h * 0.0035 / stiffness;
	float gust = wind_gust(origin.xz, t);
	float sway = sin(t * 0.9 + phase) * 0.35 + 0.65;
	float side = sin(t * 1.37 + phase * 1.7) * 0.25;
	vec3 dir = normalize(wind_direction);
	vec3 perp = vec3(-dir.z, 0.0, dir.x);
	return (dir * sway * gust + perp * side * gust) * k * wind_strength;
}
