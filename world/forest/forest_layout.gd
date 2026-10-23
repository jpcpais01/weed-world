class_name ForestLayout
extends RefCounted
## Hand-authored design of the Whispering Glade: landmarks, splines and the
## height function the terrain is sculpted from. Everything is deterministic so
## every client in a session builds the exact same forest from the same seed.
##
## Coordinates are metres on the XZ plane. -Z is north, +X is east.
## The playable square is [-50, 50] on both axes.

const HALF := 50.0
const SEED := 4207

# Landmarks
const GLADE := Vector2(-2.0, 6.0)          # sunny central meadow
const GLADE_RADIUS := 12.5
const SPAWN := Vector2(-3.0, 20.0)         # looks north over the glade to the Elder tree
const ELDER := Vector2(-15.0, -11.0)       # giant spirit tree with the fairy ring
const POND := Vector2(11.0, -18.0)
const POND_RADIUS := 6.0
const OVERLOOK := Vector2(-11.0, -37.5)    # sunset viewpoint on the ridge
const OVERLOOK_RADIUS := 5.5
const OVERLOOK_HEIGHT := 8.2
const HOLLOW := Vector2(32.0, -8.0)        # dim glowshroom hollow
const GROVE := Vector2(-28.0, 26.0)        # blossom grove
const DEAD_TREE := Vector2(-36.0, -27.0)   # silver snag on the ridge shoulder

# Water: a spring creek tumbles down the ridge into the pond, a stream leaves it
# and meanders south out of the valley.
const CREEK: Array[Vector2] = [
	Vector2(18.5, -56.0), Vector2(17.0, -46.0), Vector2(16.5, -38.0),
	Vector2(15.0, -31.0), Vector2(13.4, -25.5), Vector2(12.4, -22.0),
]
const STREAM: Array[Vector2] = [
	Vector2(14.6, -14.2), Vector2(16.6, -11.6), Vector2(19.0, -6.0), Vector2(18.0, 4.0),
	Vector2(22.0, 15.0), Vector2(29.0, 25.0), Vector2(27.0, 36.0),
	Vector2(31.0, 47.0), Vector2(33.0, 60.0),
]

# Footpaths worn into the forest floor.
const PATH_MAIN: Array[Vector2] = [
	Vector2(-16.0, 60.0), Vector2(-13.0, 45.0), Vector2(-7.5, 32.0),
	Vector2(-3.5, 20.0), Vector2(-4.0, 8.0), Vector2(-7.0, -2.0),
	Vector2(-7.5, -11.0), Vector2(-4.0, -19.0), Vector2(-2.5, -25.5),
	Vector2(-6.5, -30.0), Vector2(-11.0, -32.5), Vector2(-11.0, -36.5),
]
const PATH_POND: Array[Vector2] = [
	Vector2(-3.0, 6.0), Vector2(2.5, -1.0), Vector2(6.0, -7.0), Vector2(7.5, -11.0),
]
const PATH_HOLLOW: Array[Vector2] = [
	Vector2(-2.5, 11.0), Vector2(7.0, 10.0), Vector2(14.0, 6.0),
	Vector2(18.5, 4.5), Vector2(24.0, 1.0), Vector2(30.0, -5.0),
]
const STREAM_CROSSING := Vector2(18.3, 4.6)

var _noise_base := FastNoiseLite.new()
var _noise_detail := FastNoiseLite.new()
var _noise_crag := FastNoiseLite.new()


func _init() -> void:
	_noise_base.seed = SEED
	_noise_base.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_base.frequency = 0.022
	_noise_base.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_base.fractal_octaves = 4
	_noise_detail.seed = SEED + 1
	_noise_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_detail.frequency = 0.11
	_noise_detail.fractal_octaves = 2
	_noise_crag.seed = SEED + 2
	_noise_crag.noise_type = FastNoiseLite.TYPE_CELLULAR
	_noise_crag.frequency = 0.07
	_noise_crag.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	_noise_crag.fractal_octaves = 2


## Direction the overlook looks out over the valley towards the sunset.
static func vista_dir() -> Vector2:
	var sun := Vector2(ForestAtmosphere.SUN_TOWARDS.x, ForestAtmosphere.SUN_TOWARDS.z).normalized()
	return sun.lerp(Vector2(0.0, 1.0), 0.35).normalized()


static func sstep(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Rounded-square distance from the centre; lets the rim follow the square map.
static func square_dist(x: float, z: float) -> float:
	return pow(pow(absf(x), 4.0) + pow(absf(z), 4.0), 0.25)


## Raw landform before water and paths are carved in.
func landform(x: float, z: float) -> float:
	var h := _noise_base.get_noise_2d(x, z) * 1.7
	h += _noise_detail.get_noise_2d(x, z) * 0.18
	# The whole basin tilts gently down towards the south-east.
	h += -z * 0.03 - x * 0.008

	# Northern ridge: a broad shoulder that rises to the overlook.
	var north := sstep(-13.0, -45.0, z)
	var span := 1.0 - sstep(24.0, 44.0, absf(x + 6.0))
	var ridge := north * 9.0 * lerpf(0.5, 1.0, span)
	var crag := clampf(_noise_crag.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	ridge += north * crag * 1.6
	h += ridge

	# A soft rise behind the hollow and the grove so the valley feels cupped.
	h += _bump(x, z, Vector2(44.0, -18.0), 16.0, 3.5)
	h += _bump(x, z, Vector2(-46.0, 14.0), 15.0, 3.0)
	h += _bump(x, z, Vector2(-30.0, 44.0), 10.0, 1.6)

	# The rim: terrain climbs beyond the playable square so the valley never
	# shows an edge. Gaps let the path and stream leave to the south.
	var d := square_dist(x, z)
	var rim := sstep(40.0, 66.0, d)
	var gap := 1.0
	# Open the western rim so the overlook gazes over layered hills at sunset.
	if x < -30.0:
		gap -= 0.6 * exp(-pow((z + 6.0) / 24.0, 2.0))
	if z > 30.0:
		gap -= 0.75 * exp(-pow((x - STREAM[STREAM.size() - 1].x) / 9.0, 2.0))
		gap -= 0.6 * exp(-pow((x - PATH_MAIN[0].x) / 8.0, 2.0))
	h += rim * (10.0 + _noise_base.get_noise_2d(x * 0.6 + 300.0, z * 0.6) * 5.0) * gap
	return h


func _bump(x: float, z: float, c: Vector2, r: float, amp: float) -> float:
	var d2 := (Vector2(x, z) - c).length_squared()
	return amp * exp(-d2 / (r * r))


## Irregular pond shoreline radius for an angle.
func pond_radius(angle: float) -> float:
	return POND_RADIUS + sin(angle * 3.0 + 1.3) * 0.9 + sin(angle * 5.0 - 0.4) * 0.45


## Catmull-Rom resample of a control polyline into evenly spaced points.
static func resample(ctrl: Array[Vector2], spacing: float) -> PackedVector2Array:
	var dense := PackedVector2Array()
	var n := ctrl.size()
	for i in n - 1:
		var p0 := ctrl[maxi(i - 1, 0)]
		var p1 := ctrl[i]
		var p2 := ctrl[i + 1]
		var p3 := ctrl[mini(i + 2, n - 1)]
		var steps := 24
		for s in steps:
			var t := float(s) / steps
			dense.append(_catmull(p0, p1, p2, p3, t))
	dense.append(ctrl[n - 1])
	# Even spacing by arc length.
	var out := PackedVector2Array([dense[0]])
	var carry := 0.0
	for i in range(1, dense.size()):
		var a := dense[i - 1]
		var b := dense[i]
		var seg := a.distance_to(b)
		var pos := spacing - carry
		while pos <= seg:
			out.append(a.lerp(b, pos / seg))
			pos += spacing
		carry = seg - (pos - spacing)
	if out[out.size() - 1].distance_to(dense[dense.size() - 1]) > spacing * 0.3:
		out.append(dense[dense.size() - 1])
	return out


static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
