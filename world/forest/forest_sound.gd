class_name ForestSound
extends Node3D
## The Whispering Glade's soundscape. A wind bed that swells with the same
## gusts you see rolling through the grass, brook and waterfall voices that
## follow the nearest stretch of water, bees over the flowers, frogs at the
## pond, the campfire, and songbirds calling from the treetops around you.
##
## Only a handful of players ever run: loops are moved to the closest source
## instead of placing one per source, so it stays light on phones.

const DIR := "res://assets/audio/forest/%s.ogg"
const BIRDS := [
	"bird_warbler_0", "bird_warbler_1", "bird_warbler_2", "bird_robin_0", "bird_robin_1", "bird_robin_2",
	"bird_chickadee_0", "bird_chickadee_1", "bird_chirps_0", "bird_chirps_1",
]

var forest: Forest
var rng := RandomNumberGenerator.new()
var _bed: AudioStreamPlayer
var _crickets: AudioStreamPlayer
var _brooks: Array[AudioStreamPlayer3D] = []
var _falls: Array[AudioStreamPlayer3D] = []
var _pond: AudioStreamPlayer3D
var _bees: AudioStreamPlayer3D
var _calls: Array[AudioStreamPlayer3D] = []
var _water_pts := PackedVector3Array()
var _next_call := 2.0
var _next_frog := 6.0
var _clock := 0.0


func setup(p_forest: Forest) -> void:
	forest = p_forest
	rng.seed = ForestLayout.SEED + 999
	name = "Soundscape"
	_bed = _flat("wind_leaves", -13.0)
	_crickets = _flat("crickets", -27.0)
	# Water sits under the birds and wind, not on top of them. Paired players
	# start at different points and pitches so they never phase or repeat in step.
	for i in 2:
		_brooks.append(_spatial("brook", -13.0, 3.0, 20.0, i))
	for i in 2:
		_falls.append(_spatial("waterfall", -11.0, 3.5, 26.0, i))
	_pond = _spatial("pond", -17.0, 3.0, 16.0)
	_bees = _spatial("bees", -12.0, 1.2, 9.0)
	var fire := _spatial("campfire", -4.0, 2.0, 16.0)
	fire.position = _ground(ForestLayout.OVERLOOK + ForestLayout.vista_dir() * 0.5, 0.3)
	for i in 4:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 6.0
		p.max_distance = 60.0
		p.attenuation_filter_cutoff_hz = 6000.0
		p.attenuation_filter_db = -12.0
		add_child(p)
		_calls.append(p)
	# Sample points along every stretch of running water.
	var t := forest.terrain
	for k in range(0, t.creek_points.size(), 3):
		var q := t.creek_points[k]
		_water_pts.append(Vector3(q.x, t.creek_surface[k], q.y))
	for k in range(0, t.stream_points.size(), 3):
		var q := t.stream_points[k]
		_water_pts.append(Vector3(q.x, t.stream_surface[k], q.y))


func _ground(p: Vector2, lift := 0.0) -> Vector3:
	return Vector3(p.x, forest.terrain.height_at(p.x, p.y) + lift, p.y)


func _stream(clip: String) -> AudioStream:
	var s: AudioStream = load(DIR % clip)
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	return s


func _flat(clip: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = _stream(clip)
	p.volume_db = db
	p.autoplay = true
	add_child(p)
	return p


func _spatial(clip: String, db: float, unit: float, max_d: float, voice := 0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = _stream(clip)
	p.volume_db = db
	p.unit_size = unit
	p.max_distance = max_d
	p.pitch_scale = [1.0, 0.93, 1.06][voice % 3]
	p.attenuation_filter_cutoff_hz = 6000.0
	add_child(p)
	var from := fmod(voice * 0.37 + rng.randf() * 0.2, 1.0) * p.stream.get_length()
	# The forest may be grown off-screen first; start once the player is live.
	if p.is_inside_tree():
		p.play(from)
	else:
		p.ready.connect(p.play.bind(from), CONNECT_ONE_SHOT)
	return p


func _listener() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam else _ground(ForestLayout.SPAWN, 1.6)


## The same gust field the grass and trees sway to (wind.gdshaderinc).
func _gust(p: Vector2, t: float) -> float:
	var dir := Vector2(forest.wind_direction.x, forest.wind_direction.z).normalized()
	var along := p.dot(dir)
	var across := p.dot(Vector2(-dir.y, dir.x))
	var a := sin(along * 0.11 - t * 1.05 + sin(across * 0.07) * 1.5)
	var b := sin(along * 0.043 - t * 0.41 + 1.3)
	return clampf(0.5 + 0.35 * a + 0.3 * b, 0.0, 1.2)


func _process(delta: float) -> void:
	_clock += delta
	var ear := _listener()
	var ear2 := Vector2(ear.x, ear.z)
	var t := Time.get_ticks_msec() / 1000.0
	# Wind breathes with the visible gusts, louder up on the ridge.
	var height := clampf((ear.y - 2.0) / 10.0, 0.0, 1.0)
	var g := _gust(ear2, t) * forest.wind_strength / 0.6
	_bed.volume_db = lerpf(_bed.volume_db, -19.0 + g * 7.0 + height * 3.0, clampf(delta * 2.0, 0.0, 1.0))

	# Brook voices sit on the two nearest stretches of water.
	var near := _nearest(_water_pts, ear, 2, 5.0)
	for i in mini(_brooks.size(), near.size()):
		var b := _brooks[i]
		# Glide between nearby samples, jump when the nearest stretch changes.
		if b.global_position.distance_to(near[i]) > 8.0:
			b.global_position = near[i]
		else:
			b.global_position = b.global_position.lerp(near[i], clampf(delta * 3.0, 0.0, 1.0))
	var fall_pts := forest.water.fall_points
	var fnear := _nearest(fall_pts, ear, 2, 2.0)
	for i in _falls.size():
		if i < fnear.size():
			_falls[i].global_position = fnear[i]
	# The pond laps at the shore nearest to you.
	var c := ForestLayout.POND
	var to := ear2 - c
	var shore := c + to.normalized() * minf(to.length(), forest.layout.pond_radius(to.angle()))
	_pond.global_position = Vector3(shore.x, forest.terrain.pond_level, shore.y)
	# Bees hum around the nearest flower patch.
	var hubs := forest.life.bee_homes
	var bnear := _nearest(PackedVector3Array(hubs), ear, 1, 0.0)
	if not bnear.is_empty():
		_bees.global_position = bnear[0]

	if _clock >= _next_call:
		_next_call = _clock + rng.randf_range(1.8, 6.5)
		_bird_call(ear)
	if _clock >= _next_frog:
		_next_frog = _clock + rng.randf_range(4.0, 11.0)
		if ear2.distance_to(ForestLayout.POND) < 28.0:
			var a := rng.randf() * TAU
			var r := forest.layout.pond_radius(a) + rng.randf_range(-0.5, 0.8)
			var p := ForestLayout.POND + Vector2(cos(a), sin(a)) * r
			_one_shot("frog_%d" % rng.randi_range(0, 1), Vector3(p.x, forest.terrain.pond_level + 0.1, p.y), -10.0, rng.randf_range(0.85, 1.15))


func _bird_call(ear: Vector3) -> void:
	# Pick a tree crown somewhere around the listener and sing from it.
	var trees := forest.scatter.trees
	if trees.is_empty():
		return
	for attempt in 8:
		var t: Dictionary = trees[rng.randi() % trees.size()]
		var p: Vector2 = t.pos
		var d := p.distance_to(Vector2(ear.x, ear.z))
		if d < 8.0 or d > 45.0:
			continue
		var top := Vector3(p.x, forest.terrain.height_at(p.x, p.y) + rng.randf_range(4.0, 8.0), p.y)
		var r := rng.randf()
		var clip: String = BIRDS[rng.randi() % BIRDS.size()]
		var db := rng.randf_range(-8.0, -2.0)
		if r < 0.06:
			clip = "woodpecker_0"
			db = -9.0
		elif r < 0.13:
			clip = "bird_dove_0"
			db = -8.0
		_one_shot(clip, top, db, rng.randf_range(0.9, 1.12))
		return


func _one_shot(clip: String, pos: Vector3, db: float, pitch: float) -> void:
	for p in _calls:
		if p.playing:
			continue
		var s: AudioStream = load(DIR % clip)
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = false
		p.stream = s
		p.global_position = pos
		p.volume_db = db
		p.pitch_scale = pitch
		p.play()
		return


## The `count` points nearest to `ear`, at least `apart` metres from each other.
func _nearest(pts: PackedVector3Array, ear: Vector3, count: int, apart: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var used: Array[int] = []
	for k in count:
		var best := -1
		var bd := INF
		for i in pts.size():
			if i in used:
				continue
			var d := pts[i].distance_squared_to(ear)
			if d >= bd:
				continue
			var ok := true
			for q in out:
				if q.distance_to(pts[i]) < apart:
					ok = false
					break
			if ok:
				bd = d
				best = i
		if best < 0:
			break
		used.append(best)
		out.append(pts[best])
	return out

