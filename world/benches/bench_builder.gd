class_name BenchBuilder
extends RefCounted
## Builds the five hand-made benches out of swept profiles and tubes, sized for
## Kelings (the seat is knee-high to a Keling, so their little feet dangle).
##
## Bench space: +X runs along the bench, +Z is the way a seated Keling faces,
## Y is up from the ground at the bench centre. Each style returns a Node3D with
## one MeshInstance3D per material, plus collision boxes in `colliders`.

const SH_WOOD := preload("res://world/benches/shaders/bench_wood.gdshader")
const SH_GLYPH := preload("res://world/benches/shaders/bench_glyph.gdshader")

const SEAT_H := 0.25            ## top of the seat
const SEAT_FRONT := 0.2
const SEAT_BACK := -0.24
const HIP_ABOVE_SEAT := 0.06    ## hip joint above the seat surface
const HIP_Z := 0.03             ## hip joint along the seat depth

## Glow colour of each element's emblem.
const ELEMENT_GLOW := {
	&"water": Color(0.3, 0.75, 1.0), &"spirit": Color(1.0, 0.5, 0.85), &"air": Color(0.65, 0.95, 1.0),
	&"earth": Color(1.0, 0.62, 0.25), &"life": Color(0.55, 1.0, 0.4),
}

var kit: NatureKit
var rng := RandomNumberGenerator.new()
## {shape: Shape3D, xform: Transform3D} in bench space.
var colliders: Array[Dictionary] = []
var glyph_material: ShaderMaterial
## Where the emblem sits (bench space), for the sparkles.
var glyph_point := Vector3.ZERO

var _tools := {}
var _materials := {}


func _init(p_kit: NatureKit) -> void:
	kit = p_kit


func build(site: Dictionary) -> Node3D:
	rng.seed = hash(site.id)
	colliders.clear()
	_tools.clear()
	glyph_material = ShaderMaterial.new()
	glyph_material.shader = SH_GLYPH
	glyph_material.set_shader_parameter("glow_color", ELEMENT_GLOW.get(site.element, Color.WHITE))
	var length: float = site.length
	match site.style:
		&"driftwood":
			_driftwood(length, site.element)
		&"lotus":
			_painted(length, site.element, Color(0.9, 0.84, 0.72), Color(0.27, 0.52, 0.52), false)
		&"sunset":
			_painted(length, site.element, Color(0.62, 0.34, 0.2), Color(0.42, 0.22, 0.13), true)
		&"stone":
			_stone(length, site.element)
		&"living":
			_living(length, site.element)
	var root := Node3D.new()
	root.name = "Model"
	for key in _tools:
		var st: SurfaceTool = _tools[key]
		var mi := MeshInstance3D.new()
		mi.name = String(key).capitalize()
		var mesh := st.commit()
		mesh.surface_set_material(0, _material(key))
		mi.mesh = mesh
		if key == &"glyph":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


## Seat spots along a bench of `seats`, as hip-joint positions in bench space.
static func seat_points(seats: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in seats:
		var x := (i - (seats - 1) * 0.5) * BenchSites.SEAT_SPACING
		out.append(Vector3(x, SEAT_H + HIP_ABOVE_SEAT, HIP_Z))
	return out


# ----------------------------------------------------------------------------
# Styles

## Lotus Pond (cream boards, teal frame) and Sunset Ridge (warm red timber,
## armrests, a lantern): a carved garden bench with an arched back.
func _painted(length: float, element: StringName, board: Color, frame: Color, grand: bool) -> void:
	var half := length * 0.5
	# Seat boards with a little hand-made irregularity.
	var boards := 3
	var gap := 0.018
	var w := (SEAT_FRONT - SEAT_BACK - gap * (boards - 1)) / boards
	for i in boards:
		var z := SEAT_FRONT - w * 0.5 - i * (w + gap)
		var col := _vary(board, 0.05)
		var y := SEAT_H - 0.017 + rng.randf_range(-0.003, 0.003)
		_sweep(&"wood", _line(Vector3(-half, y, z), Vector3(half, y, z)), _rounded_rect(w, 0.034, 0.008), col)
	# Frames: front leg, back leg rising into the backrest post, seat rail.
	var posts := [-half + 0.1, half - 0.1]
	if length > 2.4:
		posts.append(0.0)
	var back_top := 0.78 if grand else 0.68
	for x: float in posts:
		var fc := _vary(frame, 0.03)
		_sweep(&"wood", _line(Vector3(x, 0.0, SEAT_FRONT - 0.04), Vector3(x, SEAT_H - 0.034, SEAT_FRONT - 0.04)), _rounded_rect(0.05, 0.05, 0.01), fc)
		_sweep(&"wood", _bezier(Vector3(x, 0.0, SEAT_BACK + 0.03), Vector3(x, SEAT_H, SEAT_BACK + 0.0), Vector3(x, back_top, SEAT_BACK - 0.07), 6), _rounded_rect(0.05, 0.05, 0.01), fc)
		_sweep(&"wood", _line(Vector3(x, SEAT_H - 0.06, SEAT_BACK), Vector3(x, SEAT_H - 0.06, SEAT_FRONT)), _rounded_rect(0.045, 0.05, 0.008), fc * Color(0.92, 0.92, 0.92))
		# A stretcher low between the legs.
		_sweep(&"wood", _line(Vector3(x, 0.07, SEAT_BACK + 0.04), Vector3(x, 0.07, SEAT_FRONT - 0.05)), _rounded_rect(0.03, 0.03, 0.006), fc)
	# Backrest slats follow the reclined posts.
	var slat_ys := [0.42, 0.53, 0.64] if grand else [0.42, 0.53]
	for y in slat_ys:
		var z := _back_z(y, back_top)
		_sweep(&"wood", _line(Vector3(-half + 0.08, y, z + 0.03), Vector3(half - 0.08, y, z + 0.03)), _rounded_rect(0.024, 0.07, 0.008), _vary(board, 0.04))
	# The arched top rail.
	var rail := PackedVector3Array()
	var lift := 0.09 if grand else 0.06
	for i in 13:
		var t := float(i) / 12.0
		var x := lerpf(-half + 0.04, half - 0.04, t)
		var y := back_top + lift * sin(t * PI) - 0.01
		rail.append(Vector3(x, y, _back_z(y, back_top) + 0.02))
	_sweep(&"wood", rail, _rounded_rect(0.04, 0.065, 0.015), frame)
	# Carved medallion with the view emblem.
	var my := back_top + lift - 0.02 if grand else 0.475
	var mz := _back_z(my, back_top) + 0.055
	if grand:
		# A plaque crowning the rail.
		_plate(&"wood", _rounded_poly(0.36, 0.17, 0.05), Transform3D(Basis(), Vector3(0.0, my, mz - 0.01)), 0.035, frame * Color(0.8, 0.8, 0.8))
	else:
		_plate(&"wood", _circle(0.085, 18), Transform3D(Basis(), Vector3(0.0, my, mz - 0.01)), 0.03, board * Color(0.95, 0.95, 0.95))
	_glyph(element, Transform3D(Basis().scaled(Vector3.ONE * (1.25 if grand else 0.9)), Vector3(0.0, my, mz + 0.012)))
	if grand:
		# Armrests with curled fronts on the end frames.
		for x: float in [-half + 0.1, half - 0.1]:
			_sweep(&"wood", _line(Vector3(x, SEAT_H, SEAT_FRONT - 0.04), Vector3(x, 0.43, SEAT_FRONT - 0.04)), _rounded_rect(0.045, 0.045, 0.01), frame)
			var arm := PackedVector3Array()
			for i in 9:
				var t := float(i) / 8.0
				var z := lerpf(_back_z(0.45, back_top), SEAT_FRONT + 0.04, t)
				arm.append(Vector3(x, 0.45 + 0.025 * sin(t * PI * 0.9), z))
			_sweep(&"wood", arm, _rounded_rect(0.07, 0.035, 0.012), board * Color(0.9, 0.9, 0.9))
		_lantern(Vector3(half + 0.32, 0.0, -0.05))
	colliders.append(_box_collider(Vector3(0.0, SEAT_H * 0.5, (SEAT_FRONT + SEAT_BACK) * 0.5), Vector3(length, SEAT_H, SEAT_FRONT - SEAT_BACK)))
	colliders.append(_box_collider(Vector3(0.0, (SEAT_H + back_top) * 0.5, SEAT_BACK - 0.04), Vector3(length, back_top - SEAT_H, 0.08)))


static func _back_z(y: float, top: float) -> float:
	var t := clampf((y - SEAT_H) / (top - SEAT_H), 0.0, 1.0)
	return SEAT_BACK + 0.0 - 0.07 * t * t


## Brookside: a silvered split log worn smooth by the stream, propped on two
## river stones, with a crooked driftwood post carrying the wave emblem.
func _driftwood(length: float, element: StringName) -> void:
	var half := length * 0.5
	var r := 0.19
	var cy := SEAT_H - 0.06
	var cz := -0.02
	# Split-log profile: a trunk with its top sawn flat, the chord `top` above
	# the heart, lumpy with old knots.
	var prof := PackedVector2Array()
	var top := 0.06
	var a0 := asin(top / r)
	for i in 19:
		var a := lerpf(a0, -PI - a0, float(i) / 18.0)
		var rr := r * (1.0 + 0.035 * sin(a * 5.0 + 1.0))
		prof.append(Vector2(cos(a) * rr, sin(a) * rr - top))
	# Gently bowed along its length so it reads as a real trunk.
	var path := PackedVector3Array()
	for i in 9:
		var t := float(i) / 8.0
		path.append(Vector3(lerpf(-half, half, t), SEAT_H, cz + 0.015 * sin(t * PI)))
	_sweep(&"wood", path, prof, Color(0.78, 0.76, 0.71))
	# River stones it rests on.
	for x: float in [-half + 0.32, half - 0.32]:
		_extra.append({"mesh": kit.mesh("Pebble_Round_" + str(1 + rng.randi() % 5)), "size": Vector3(0.36, 0.14, 0.34), "xform": Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(x, -0.03, cz))})
	# The crooked post with its emblem disc.
	var px := half + 0.18
	var post := PackedVector3Array([Vector3(px, -0.05, -0.05), Vector3(px + 0.03, 0.25, -0.07), Vector3(px - 0.01, 0.5, -0.04), Vector3(px + 0.02, 0.68, -0.06)])
	_tube(&"wood", post, [0.045, 0.04, 0.034, 0.028], 7, Color(0.74, 0.72, 0.68))
	_tube(&"wood", PackedVector3Array([Vector3(px + 0.0, 0.5, -0.04), Vector3(px + 0.12, 0.6, -0.05), Vector3(px + 0.17, 0.66, -0.03)]), [0.02, 0.015, 0.01], 5, Color(0.74, 0.72, 0.68))
	_plate(&"wood", _circle(0.085, 16), Transform3D(Basis(), Vector3(px, 0.54, -0.0)), 0.025, Color(0.82, 0.8, 0.75))
	_glyph(element, Transform3D(Basis().scaled(Vector3.ONE * 0.85), Vector3(px, 0.54, 0.0 + 0.016)))
	glyph_point = Vector3(px, 0.54, 0.03)
	colliders.append(_box_collider(Vector3(0.0, SEAT_H * 0.5, cz), Vector3(length, SEAT_H, 0.38)))


## Misty Falls: a mossy stone slab on two blocks with a standing back stone,
## the spiral of the wind carved into it.
func _stone(length: float, element: StringName) -> void:
	var half := length * 0.5
	var stone := Color(0.85, 0.85, 0.82)
	# Seat slab with a hewn, slightly uneven edge.
	var prof := PackedVector2Array()
	var d := SEAT_FRONT - SEAT_BACK + 0.04
	var th := 0.085
	for p in [Vector2(-d * 0.5, -th * 0.5), Vector2(d * 0.5, -th * 0.5), Vector2(d * 0.5 + 0.01, th * 0.2), Vector2(d * 0.5 - 0.015, th * 0.5),
			Vector2(-d * 0.5 + 0.02, th * 0.5), Vector2(-d * 0.5 - 0.01, th * 0.1)]:
		prof.append(p)
	var path := PackedVector3Array()
	for i in 6:
		var t := float(i) / 5.0
		path.append(Vector3(lerpf(-half, half, t), SEAT_H - th * 0.5 + rng.randf_range(-0.004, 0.004), (SEAT_FRONT + SEAT_BACK) * 0.5 + rng.randf_range(-0.008, 0.008)))
	_sweep(&"stone", path, prof, stone)
	# Two support blocks.
	for x: float in [-half + 0.3, half - 0.3]:
		_sweep(&"stone", _line(Vector3(x - 0.13, (SEAT_H - th) * 0.5, -0.02), Vector3(x + 0.13, (SEAT_H - th) * 0.5, -0.02)), _rounded_rect(0.34, SEAT_H - th + 0.02, 0.03), stone * Color(0.9, 0.9, 0.9))
	# Standing back stone, leaning back a touch, its crown rough.
	var back := PackedVector2Array()
	var bw := length * 0.92
	var bh := 0.66
	back.append(Vector2(-bw * 0.5, 0.0))
	back.append(Vector2(bw * 0.5, 0.0))
	for i in 9:
		var t := float(i) / 8.0
		var x := lerpf(bw * 0.5, -bw * 0.5, t)
		var y := bh - 0.08 * pow(absf(t * 2.0 - 1.0), 2.0) + rng.randf_range(-0.02, 0.02)
		back.append(Vector2(x, y))
	var lean := Basis(Vector3.RIGHT, -0.12)
	var pivot := Vector3(0.0, -0.05, SEAT_BACK - 0.05)
	_plate(&"stone", back, Transform3D(lean, pivot), 0.09, stone)
	_glyph(element, Transform3D(lean.scaled(Vector3.ONE * 1.1), pivot + lean * Vector3(0.0, 0.5, 0.05)))
	colliders.append(_box_collider(Vector3(0.0, SEAT_H * 0.5, (SEAT_FRONT + SEAT_BACK) * 0.5), Vector3(length, SEAT_H, SEAT_FRONT - SEAT_BACK + 0.04)))
	colliders.append(_box_collider(Vector3(0.0, 0.3, SEAT_BACK - 0.08), Vector3(bw, 0.66, 0.12)))


## Elder's Meadow: a bench the forest grew by itself: a raft of branches on
## curling roots, an arch of boughs for a back, in leaf and in flower.
func _living(length: float, element: StringName) -> void:
	var half := length * 0.5
	var bark := Color(0.95, 0.9, 0.85)
	# Seat of four bowed branches.
	var zs := [SEAT_FRONT - 0.045, 0.06, -0.08, SEAT_BACK + 0.045]
	for z: float in zs:
		var path := PackedVector3Array()
		var phase := rng.randf() * TAU
		for i in 9:
			var t := float(i) / 8.0
			path.append(Vector3(lerpf(-half - 0.04, half + 0.04, t), SEAT_H - 0.045 + 0.008 * sin(t * 9.0 + phase), z + 0.01 * sin(t * 5.0 + phase)))
		_tube(&"bark", path, [0.04, 0.047, 0.05, 0.047, 0.042], 8, _vary(bark, 0.05))
	# Root legs curling out into the ground.
	for sx: float in [-1.0, 1.0]:
		for z: float in [SEAT_FRONT - 0.06, SEAT_BACK + 0.06]:
			var x := sx * (half - 0.14)
			var out := Vector3(sx * 0.12, 0.0, signf(z) * 0.08)
			var leg := _bezier(Vector3(x, SEAT_H - 0.06, z), Vector3(x, 0.08, z), Vector3(x, -0.04, z) + out, 6)
			_tube(&"bark", leg, [0.05, 0.048, 0.045, 0.04, 0.035, 0.03], 7, bark * Color(0.9, 0.88, 0.86))
	# Two boughs arch up from the ends to meet over the middle.
	var top := 0.8
	var crest := Vector3(0.0, top, SEAT_BACK - 0.08)
	for sx: float in [-1.0, 1.0]:
		var a := Vector3(sx * (half - 0.08), SEAT_H - 0.04, SEAT_BACK + 0.03)
		var c := Vector3(sx * half * 0.75, top + 0.02, SEAT_BACK - 0.06)
		var bough := _bezier(a, c, crest + Vector3(-sx * 0.06, 0.02, 0.0), 10)
		_tube(&"bark", bough, [0.045, 0.04, 0.035, 0.03, 0.026, 0.022], 7, bark)
		# Leaves sprout along the bough.
		for k in range(2, bough.size() - 1):
			for j in 2:
				var p := bough[k] + Vector3(rng.randf_range(-0.03, 0.03), 0.02, rng.randf_range(-0.03, 0.03))
				var yaw := rng.randf() * TAU
				var tilt := rng.randf_range(0.4, 1.1)
				_leaf(p, Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -tilt), rng.randf_range(0.055, 0.085))
	# Thin uprights woven between seat and arch.
	for i in 5:
		var x := lerpf(-half * 0.6, half * 0.6, float(i) / 4.0)
		var t := absf(x) / half
		var y_top := top - 0.26 * t * t - 0.04
		_tube(&"bark", PackedVector3Array([Vector3(x, SEAT_H, SEAT_BACK + 0.04), Vector3(x + 0.015, (SEAT_H + y_top) * 0.5, SEAT_BACK - 0.02), Vector3(x, y_top, SEAT_BACK - 0.06)]), [0.018, 0.016, 0.013], 5, bark * Color(0.92, 0.92, 0.9))
	_glyph(element, Transform3D(Basis().scaled(Vector3.ONE * 1.1), crest + Vector3(0.0, 0.06, 0.03)))
	glyph_point = crest + Vector3(0.0, 0.06, 0.05)
	colliders.append(_box_collider(Vector3(0.0, SEAT_H * 0.5, (SEAT_FRONT + SEAT_BACK) * 0.5), Vector3(length, SEAT_H, SEAT_FRONT - SEAT_BACK)))
	colliders.append(_box_collider(Vector3(0.0, 0.5, SEAT_BACK - 0.04), Vector3(length, 0.5, 0.08)))


func _lantern(base: Vector3) -> void:
	var dark := Color(0.2, 0.17, 0.15)
	_tube(&"wood", PackedVector3Array([base, base + Vector3(0, 0.5, 0), base + Vector3(0, 0.95, 0)]), [0.025, 0.022, 0.02], 6, dark)
	var hook := PackedVector3Array()
	for i in 7:
		var a := float(i) / 6.0 * PI
		hook.append(base + Vector3(-0.09 + 0.09 * cos(a), 0.95 + 0.09 * sin(a), 0.0))
	_tube(&"wood", hook, [0.018, 0.017, 0.016, 0.015, 0.014, 0.013, 0.012], 5, dark)
	var lp := base + Vector3(-0.18, 0.78, 0.0)
	_tube(&"wood", PackedVector3Array([lp + Vector3(0, 0.17, 0), lp + Vector3(0, 0.12, 0)]), [0.004, 0.004], 4, dark)
	_sweep(&"wood", _line(lp + Vector3(-0.05, 0.11, 0), lp + Vector3(0.05, 0.11, 0)), _rounded_rect(0.1, 0.02, 0.004), dark)
	_sweep(&"wood", _line(lp + Vector3(-0.045, -0.01, 0), lp + Vector3(0.045, -0.01, 0)), _rounded_rect(0.09, 0.02, 0.004), dark)
	_sweep(&"glyph", _line(lp + Vector3(-0.035, 0.05, 0), lp + Vector3(0.035, 0.05, 0)), _rounded_rect(0.07, 0.1, 0.01), Color.WHITE)
	lantern_point = lp + Vector3(0, 0.05, 0)


var lantern_point := Vector3.INF
var _extra: Array[Dictionary] = []

## Kit meshes (rocks) that belong to the model, placed in bench space.
func take_extras() -> Array[Dictionary]:
	var out := _extra.duplicate()
	_extra.clear()
	return out


# ----------------------------------------------------------------------------
# Emblems: one glyph per element, a flat inlay a few millimetres proud.

func _glyph(element: StringName, xf: Transform3D) -> void:
	glyph_point = xf.origin + xf.basis.z.normalized() * 0.02
	var s := 0.065
	match element:
		&"water":
			# Two rolling waves.
			for row in 2:
				var poly := PackedVector2Array()
				var y0 := (0.4 - row * 0.8) * s
				for i in 13:
					var t := float(i) / 12.0
					poly.append(Vector2((t * 2.0 - 1.0) * s * 1.1, y0 + sin(t * TAU * 1.25) * s * 0.28))
				for i in 13:
					var t := 1.0 - float(i) / 12.0
					poly.append(Vector2((t * 2.0 - 1.0) * s * 1.1, y0 - s * 0.24 + sin(t * TAU * 1.25) * s * 0.28))
				_plate(&"glyph", poly, xf, 0.006, Color.WHITE)
		&"earth":
			# Twin peaks, the taller one snow-capped, over a ridge line.
			_plate(&"glyph", Transform2D().scaled(Vector2(s, s)) * PackedVector2Array([Vector2(-1.2, -0.7), Vector2(-0.35, 0.75), Vector2(0.1, 0.05), Vector2(0.45, 0.45), Vector2(1.2, -0.7)]), xf, 0.006, Color.WHITE)
			_plate(&"glyph", Transform2D().scaled(Vector2(s, s)) * PackedVector2Array([Vector2(-1.3, -0.95), Vector2(1.3, -0.95), Vector2(1.3, -0.82), Vector2(-1.3, -0.82)]), xf, 0.006, Color.WHITE)
			# A sun setting behind them.
			_plate(&"glyph", _circle(s * 0.28, 12), xf * Transform3D(Basis(), Vector3(s * 0.75, s * 0.75, -0.002)), 0.006, Color.WHITE)
		&"air":
			# A spiral gust.
			var outer := PackedVector2Array()
			var inner := PackedVector2Array()
			for i in 30:
				var t := float(i) / 29.0
				var a := t * TAU * 1.6
				var r := s * (0.15 + 0.85 * t)
				var w := s * (0.06 + 0.12 * t)
				outer.append(Vector2(cos(a), sin(a)) * (r + w))
				inner.append(Vector2(cos(a), sin(a)) * maxf(r - w, 0.0))
			inner.reverse()
			_plate(&"glyph", outer + inner, xf, 0.006, Color.WHITE)
			_plate(&"glyph", Transform2D().scaled(Vector2(s, s)) * PackedVector2Array([Vector2(-1.3, -1.05), Vector2(0.4, -1.05), Vector2(0.4, -0.92), Vector2(-1.3, -0.92)]), xf, 0.006, Color.WHITE)
		&"life":
			# A leaf with its midrib cut out.
			var leaf := PackedVector2Array()
			for i in 17:
				var t := float(i) / 16.0
				leaf.append(Vector2(sin(t * PI) * 0.55, t * 2.0 - 1.0) * s)
			for i in range(15, 0, -1):
				var t := float(i) / 16.0
				leaf.append(Vector2(sin(t * PI) * 0.12, t * 2.0 - 1.0) * s)
			_plate(&"glyph", leaf, xf * Transform3D(Basis(Vector3.BACK, -0.35), Vector3.ZERO), 0.006, Color.WHITE)
			var other := PackedVector2Array()
			for p in leaf:
				other.append(Vector2(-p.x, p.y))
			other.reverse()
			_plate(&"glyph", other, xf * Transform3D(Basis(Vector3.BACK, -0.35), Vector3.ZERO), 0.006, Color.WHITE)
		&"spirit":
			# A lotus: five petals fanning up from the water line.
			for k in 5:
				var a := lerpf(-1.05, 1.05, float(k) / 4.0)
				var petal := PackedVector2Array()
				for i in 13:
					var t := float(i) / 12.0 * TAU
					petal.append(Vector2(sin(t) * 0.24, 0.5 - 0.5 * cos(t)) * s * 1.5)
				var plen := 1.0 - absf(a) * 0.25
				_plate(&"glyph", Transform2D().scaled(Vector2(1.0, plen)) * petal, xf * Transform3D(Basis(Vector3.BACK, -a), Vector3(0, -s * 0.7, 0.001 * k)), 0.006, Color.WHITE)
			_plate(&"glyph", Transform2D().scaled(Vector2(s, s)) * PackedVector2Array([Vector2(-1.1, -0.82), Vector2(1.1, -0.82), Vector2(1.1, -0.7), Vector2(-1.1, -0.7)]), xf, 0.006, Color.WHITE)


# ----------------------------------------------------------------------------
# Geometry

func _tool(key: StringName) -> SurfaceTool:
	if not _tools.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[key] = st
	return _tools[key]


func _material(key: StringName) -> Material:
	if key == &"glyph":
		return glyph_material
	if _materials.has(key):
		return _materials[key]
	var mat: Material
	match key:
		&"stone":
			var m := (kit.rock_material("Rocks_Diffuse", 0.6) as ShaderMaterial).duplicate() as ShaderMaterial
			m.set_shader_parameter("sink_height", 0.06)
			m.set_shader_parameter("moss_amount", 0.75)
			mat = m
		&"bark":
			var m := ShaderMaterial.new()
			m.shader = SH_WOOD
			m.set_shader_parameter("noise_tex", NatureKit.NOISE)
			m.set_shader_parameter("bark", 1.0)
			m.set_shader_parameter("bark_tex", kit.texture("Bark_NormalTree"))
			m.set_shader_parameter("bark_normal", kit.texture("Bark_NormalTree_Normal"))
			m.set_shader_parameter("moss_amount", 0.5)
			mat = m
		&"leaf":
			var m := ShaderMaterial.new()
			m.shader = SH_WOOD
			m.set_shader_parameter("noise_tex", NatureKit.NOISE)
			m.set_shader_parameter("grain", 0.0)
			m.set_shader_parameter("moss_amount", 0.0)
			m.set_shader_parameter("roughness", 0.6)
			mat = m
		_:
			var m := ShaderMaterial.new()
			m.shader = SH_WOOD
			m.set_shader_parameter("noise_tex", NatureKit.NOISE)
			m.set_shader_parameter("moss_amount", 0.22)
			mat = m
	_materials[key] = mat
	return mat


func _vary(c: Color, amount: float) -> Color:
	var k := 1.0 + rng.randf_range(-amount, amount)
	return Color(c.r * k, c.g * k * (1.0 + rng.randf_range(-0.02, 0.02)), c.b * k, 1.0)


func _vertex(st: SurfaceTool, p: Vector3, n: Vector3, uv: Vector2, col: Color, ao: float) -> void:
	st.set_normal(n)
	st.set_uv(uv)
	st.set_color(Color(col.r, col.g, col.b, ao))
	st.add_vertex(p)


## Sweeps a closed 2D profile (x across, y up, counter-clockwise) along a path,
## capping both ends. Normals are smooth across shallow corners.
func _sweep(key: StringName, path: PackedVector3Array, profile: PackedVector2Array, col: Color) -> void:
	if Geometry2D.is_polygon_clockwise(profile):
		profile = profile.duplicate()
		profile.reverse()
	var st := _tool(key)
	var frames := _frames(path)
	var m := profile.size()
	# Per-corner normals in profile space (split at sharp corners).
	var edge_n := PackedVector2Array()
	for i in m:
		var e := profile[(i + 1) % m] - profile[i]
		edge_n.append(Vector2(e.y, -e.x).normalized())
	var dist := 0.0
	var perim := PackedFloat32Array([0.0])
	for i in m:
		perim.append(perim[i] + profile[i].distance_to(profile[(i + 1) % m]))
	for k in path.size() - 1:
		var f0: Basis = frames[k]
		var f1: Basis = frames[k + 1]
		var seg := path[k].distance_to(path[k + 1])
		for i in m:
			var j := (i + 1) % m
			var n_e := edge_n[i]
			var n_i := _smooth(n_e, edge_n[(i - 1 + m) % m])
			var n_j := _smooth(n_e, edge_n[j])
			var a0 := path[k] + f0 * Vector3(profile[i].x, profile[i].y, 0.0)
			var b0 := path[k] + f0 * Vector3(profile[j].x, profile[j].y, 0.0)
			var a1 := path[k + 1] + f1 * Vector3(profile[i].x, profile[i].y, 0.0)
			var b1 := path[k + 1] + f1 * Vector3(profile[j].x, profile[j].y, 0.0)
			var na0 := (f0 * Vector3(n_i.x, n_i.y, 0.0)).normalized()
			var nb0 := (f0 * Vector3(n_j.x, n_j.y, 0.0)).normalized()
			var na1 := (f1 * Vector3(n_i.x, n_i.y, 0.0)).normalized()
			var nb1 := (f1 * Vector3(n_j.x, n_j.y, 0.0)).normalized()
			var u0 := dist * 2.0
			var u1 := (dist + seg) * 2.0
			var va := perim[i] * 2.0
			var vb := perim[i + 1] * 2.0
			var ao_a := _ao(na0)
			var ao_b := _ao(nb0)
			_vertex(st, a0, na0, Vector2(u0, va), col, ao_a)
			_vertex(st, b0, nb0, Vector2(u0, vb), col, ao_b)
			_vertex(st, b1, nb1, Vector2(u1, vb), col, ao_b)
			_vertex(st, a0, na0, Vector2(u0, va), col, ao_a)
			_vertex(st, b1, nb1, Vector2(u1, vb), col, ao_b)
			_vertex(st, a1, na1, Vector2(u1, va), col, ao_a)
		dist += seg
	# End caps show the end grain, a shade lighter.
	var tri := Geometry2D.triangulate_polygon(profile)
	for end in [0, path.size() - 1]:
		var f: Basis = frames[end]
		var n := -f.z if end == 0 else f.z
		var cap_col := col.lightened(0.12)
		for t in tri.size():
			var p := profile[tri[t]]
			_vertex(st, path[end] + f * Vector3(p.x, p.y, 0.0), n.normalized(), p * 4.0, cap_col, 0.9)


## Shares a corner's normal with the neighbouring edge unless the corner is sharp.
static func _smooth(own: Vector2, other: Vector2) -> Vector2:
	if own.dot(other) > 0.75:
		return (own + other).normalized()
	return own


## Baked occlusion: undersides darker, tops full.
static func _ao(n: Vector3) -> float:
	return clampf(0.72 + 0.28 * n.y, 0.45, 1.0)


## Rotation-minimising frames along a path; z is the tangent, y stays as close
## to world up as it can.
func _frames(path: PackedVector3Array) -> Array[Basis]:
	var out: Array[Basis] = []
	var n := path.size()
	var up := Vector3.UP
	for k in n:
		var t := (path[mini(k + 1, n - 1)] - path[maxi(k - 1, 0)]).normalized()
		if k == 0:
			if absf(t.dot(up)) > 0.95:
				up = Vector3.BACK
			up = (up - t * up.dot(t)).normalized()
		else:
			up = (up - t * up.dot(t))
			if up.length_squared() < 1e-6:
				up = t.cross(Vector3.RIGHT)
			up = up.normalized()
		var x := up.cross(t).normalized()
		out.append(Basis(x, up, t))
	return out


## A tube along a path with radii sampled along it.
func _tube(key: StringName, path: PackedVector3Array, radii: Array, sides: int, col: Color) -> void:
	var dense := path
	var st := _tool(key)
	var frames := _frames(dense)
	var n := dense.size()
	var dist := 0.0
	for k in n - 1:
		var r0 := _radius_at(radii, float(k) / maxf(n - 1, 1))
		var r1 := _radius_at(radii, float(k + 1) / maxf(n - 1, 1))
		var seg := dense[k].distance_to(dense[k + 1])
		for s in sides:
			var a0 := TAU * s / sides
			var a1 := TAU * (s + 1) / sides
			var d0 := Vector3(cos(a0), sin(a0), 0.0)
			var d1 := Vector3(cos(a1), sin(a1), 0.0)
			var p00 := dense[k] + frames[k] * (d0 * r0)
			var p01 := dense[k] + frames[k] * (d1 * r0)
			var p10 := dense[k + 1] + frames[k + 1] * (d0 * r1)
			var p11 := dense[k + 1] + frames[k + 1] * (d1 * r1)
			var n00 := (frames[k] * d0).normalized()
			var n01 := (frames[k] * d1).normalized()
			var n10 := (frames[k + 1] * d0).normalized()
			var n11 := (frames[k + 1] * d1).normalized()
			var u0 := float(s) / sides
			var u1 := float(s + 1) / sides
			var v0 := dist * 3.0
			var v1 := (dist + seg) * 3.0
			_vertex(st, p00, n00, Vector2(u0, v0), col, _ao(n00))
			_vertex(st, p01, n01, Vector2(u1, v0), col, _ao(n01))
			_vertex(st, p11, n11, Vector2(u1, v1), col, _ao(n11))
			_vertex(st, p00, n00, Vector2(u0, v0), col, _ao(n00))
			_vertex(st, p11, n11, Vector2(u1, v1), col, _ao(n11))
			_vertex(st, p10, n10, Vector2(u0, v1), col, _ao(n10))
		dist += seg
	# Cap the far end (the near end usually meets something).
	var rl := _radius_at(radii, 1.0)
	var c := dense[n - 1]
	var fz := frames[n - 1].z
	for s in sides:
		var a0 := TAU * s / sides
		var a1 := TAU * (s + 1) / sides
		_vertex(st, c, fz, Vector2(0.5, 0.5), col.lightened(0.1), 0.9)
		_vertex(st, c + frames[n - 1] * Vector3(cos(a0), sin(a0), 0.0) * rl, fz, Vector2(0.5 + cos(a0) * 0.5, 0.5 + sin(a0) * 0.5), col.lightened(0.1), 0.9)
		_vertex(st, c + frames[n - 1] * Vector3(cos(a1), sin(a1), 0.0) * rl, fz, Vector2(0.5 + cos(a1) * 0.5, 0.5 + sin(a1) * 0.5), col.lightened(0.1), 0.9)


static func _radius_at(radii: Array, t: float) -> float:
	if radii.size() == 1:
		return radii[0]
	var f := t * (radii.size() - 1)
	var i := mini(int(f), radii.size() - 2)
	return lerpf(radii[i], radii[i + 1], f - i)


## A flat plate from a 2D outline (x right, y up) with some thickness,
## its face towards +Z of `xf`.
func _plate(key: StringName, poly: PackedVector2Array, xf: Transform3D, depth: float, col: Color) -> void:
	if Geometry2D.is_polygon_clockwise(poly):
		poly = poly.duplicate()
		poly.reverse()
	var st := _tool(key)
	var tri := Geometry2D.triangulate_polygon(poly)
	if tri.is_empty():
		return
	var nz := (xf.basis * Vector3.BACK).normalized()
	var front := Vector3(0, 0, depth * 0.5)
	for side in [1.0, -1.0]:
		for t in tri.size():
			var p := poly[tri[t]]
			_vertex(st, xf * (Vector3(p.x, p.y, 0.0) + front * side), nz * side, p * 3.0, col, 1.0 if side > 0.0 else 0.7)
	var m := poly.size()
	for i in m:
		var a := poly[i]
		var b := poly[(i + 1) % m]
		var e := (b - a).normalized()
		var n := (xf.basis * Vector3(e.y, -e.x, 0.0)).normalized()
		var a0 := xf * (Vector3(a.x, a.y, 0.0) + front)
		var b0 := xf * (Vector3(b.x, b.y, 0.0) + front)
		var a1 := xf * (Vector3(a.x, a.y, 0.0) - front)
		var b1 := xf * (Vector3(b.x, b.y, 0.0) - front)
		var shade := col * Color(0.85, 0.85, 0.85)
		_vertex(st, a0, n, a * 3.0, shade, 0.85)
		_vertex(st, b0, n, b * 3.0, shade, 0.85)
		_vertex(st, b1, n, b * 3.0 + Vector2(0, 0.1), shade, 0.85)
		_vertex(st, a0, n, a * 3.0, shade, 0.85)
		_vertex(st, b1, n, b * 3.0 + Vector2(0, 0.1), shade, 0.85)
		_vertex(st, a1, n, a * 3.0 + Vector2(0, 0.1), shade, 0.85)


## A small leaf: a pointed oval card lying in its XZ plane.
func _leaf(p: Vector3, basis: Basis, size: float) -> void:
	var poly := PackedVector2Array()
	for i in 10:
		var t := float(i) / 9.0 * TAU
		poly.append(Vector2(sin(t) * 0.38, 0.5 - 0.5 * cos(t)) * size)
	var col := Color(0.42, 0.66, 0.2).lerp(Color(0.62, 0.78, 0.25), rng.randf())
	_plate(&"leaf", poly, Transform3D(basis * Basis(Vector3.RIGHT, -PI * 0.5), p), 0.002, col)


static func _line(a: Vector3, b: Vector3) -> PackedVector3Array:
	return PackedVector3Array([a, b])


static func _bezier(a: Vector3, c: Vector3, b: Vector3, steps: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in steps + 1:
		var t := float(i) / steps
		out.append(a.lerp(c, t).lerp(c.lerp(b, t), t))
	return out


static func _rounded_rect(w: float, h: float, r: float) -> PackedVector2Array:
	return _rounded_poly(w, h, r)


static func _rounded_poly(w: float, h: float, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var corners := [Vector2(w * 0.5 - r, -h * 0.5 + r), Vector2(w * 0.5 - r, h * 0.5 - r), Vector2(-w * 0.5 + r, h * 0.5 - r), Vector2(-w * 0.5 + r, -h * 0.5 + r)]
	for c in 4:
		for s in 3:
			var a := -PI * 0.5 + (c + s / 2.0) * PI * 0.5
			out.append(corners[c] + Vector2(cos(a), sin(a)) * r)
	return out


static func _circle(r: float, sides: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in sides:
		var a := TAU * i / sides
		out.append(Vector2(cos(a), sin(a)) * r)
	return out


static func _box_collider(center: Vector3, size: Vector3) -> Dictionary:
	var shape := BoxShape3D.new()
	shape.size = size
	return {"shape": shape, "xform": Transform3D(Basis(), center)}
