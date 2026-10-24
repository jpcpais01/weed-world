class_name KelingBody
extends RefCounted
## A playable Keling's measurements, written by tools/rig_keling.py and
## tools/rig_character.py into <id>_body.json: the trunk profile, the
## landmarks the rolling and smoking choreography is fitted to, its spring
## chains and limb lengths.
##
## The two-handed choreography (KelingWeed) and the grab were authored on the
## original Keling. fit() carries a skeleton-space point authored there over to
## this body: each landmark (mouth, work spot in front of the belly, shoulders,
## hip pouches) moves to where this character has it, and every point in
## between moves with a blend of its nearby landmarks.

## The original Keling's landmarks (skeleton space).
const KELING_LANDMARKS := {
	"mouth": Vector3(0.0, 0.835, 0.455),
	"work": Vector3(0.0, 0.725, 0.62),
	"shoulder_l": Vector3(0.289, 0.774, 0.149),
	"shoulder_r": Vector3(-0.282, 0.774, 0.149),
	"pouch_l": Vector3(0.27, 0.53, 0.34),
	"pouch_r": Vector3(-0.27, 0.53, 0.34),
}
const KELING_LEG := 0.233  ## thigh + shin of the original (metres)

var id := "keling"
var landmarks := {}
## [name, tip length, stiffness] of each spring chain on the head.
var springs: Array = []
var height := 1.7
var leg_length := KELING_LEG
var identity := true
## Trunk profile rows: [height, half width, front z, back z].
var rows: Array = []

var _anchors: Array[Vector3] = []
var _deltas: Array[Vector3] = []


static func load_id(p_id: String) -> KelingBody:
	var b := KelingBody.new()
	b.id = p_id
	var path := "res://assets/characters/%s/%s_body.json" % [p_id, p_id]
	var data = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if data is Dictionary:
		var lm: Dictionary = data.get("landmarks", {})
		for k in KELING_LANDMARKS:
			var v = lm.get(k)
			b.landmarks[k] = Vector3(v[0], v[1], v[2]) if v is Array else KELING_LANDMARKS[k]
		b.springs = data.get("springs", [])
		b.rows = data.get("rows", [])
		b.height = float(data.get("height", 1.7))
		b.leg_length = float(data.get("leg_length", KELING_LEG))
	else:
		b.landmarks = KELING_LANDMARKS.duplicate()
	for k in KELING_LANDMARKS:
		var d: Vector3 = b.landmarks[k] - KELING_LANDMARKS[k]
		b._anchors.append(KELING_LANDMARKS[k])
		b._deltas.append(d)
		if d.length() > 0.001:
			b.identity = false
	return b


## Moves a point authored on the original Keling onto this body.
func fit(p: Vector3) -> Vector3:
	if identity:
		return p
	var sum := Vector3.ZERO
	var wsum := 0.0
	for i in _anchors.size():
		var w := 1.0 / (p.distance_squared_to(_anchors[i]) + 0.0009)
		sum += _deltas[i] * w
		wsum += w
	return p + sum / wsum


## Half the trunk's width at a height (skeleton space), from the profile.
func half_width(y: float) -> float:
	if rows.is_empty():
		return 0.25
	if y <= rows[0][0]:
		return rows[0][1]
	for i in range(1, rows.size()):
		if y <= rows[i][0]:
			var a: Array = rows[i - 1]
			var b: Array = rows[i]
			return lerpf(a[1], b[1], inverse_lerp(a[0], b[0], y))
	return rows[-1][1]


func mouth() -> Vector3:
	return landmarks.get("mouth", KELING_LANDMARKS.mouth)


## Locomotion clips were retargeted to this leg length: natural gait speeds
## scale with it.
func gait_scale() -> float:
	return leg_length / KELING_LEG


## Which way a hand's palm faces, from its rest pose (skeleton space): the
## side the thumb sits on, where the fingers curl to. The original Keling's
## thumb stands well off the palm, so the thumb direction says it outright;
## the twig hands of the others hold the thumb almost level with the fingers,
## so there the palm is the hand plane's normal on the thumb's side, leaning
## only a little towards it.
static func palm_normal(thumb_tip: Vector3, knuckles: Vector3, mid_dir: Vector3, index_base: Vector3, ring_base: Vector3) -> Vector3:
	var t := thumb_tip - knuckles
	var off_plane := (t - mid_dir * t.dot(mid_dir)).normalized()
	var lateral := ring_base - index_base
	lateral = (lateral - mid_dir * lateral.dot(mid_dir)).normalized()
	var n0 := mid_dir.cross(lateral).normalized()
	if absf(t.dot(n0)) >= 0.65 * t.length():
		return off_plane
	return (n0 * t.dot(n0) + lateral * t.dot(lateral) * 0.15).normalized()
