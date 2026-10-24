extends SceneTree
## Headless check of the scenic benches: grows the forest, checks all five
## benches stand on their terraces, then walks the Keling up to one, sits it
## down, checks the hips are on the seat and stands it back up. Exits non-zero
## on failure.
##   godot --headless --path . -s res://tools/bench_check.gd

var _t := 0.0
var _keling: CharacterBody3D
var _bench: Node3D
var _ok := true
var _stage := 0
var _hip_err := INF


func _initialize() -> void:
	root.add_child(load("res://world/forest/forest_level.tscn").instantiate())


func _fail(msg: String) -> void:
	print("bench_check: FAIL ", msg)
	_ok = false


func _physics_process(delta: float) -> bool:
	_t += delta
	if _keling == null:
		_keling = root.find_child("Keling", true, false) as CharacterBody3D
		if _keling == null:
			return false
		var benches := get_nodes_in_group("bench")
		if benches.size() != 5:
			_fail("expected 5 benches, found %d" % benches.size())
		var forest = root.find_child("Forest", true, false)
		for n in benches:
			var b = n
			var p: Vector3 = b.global_position
			var seats := 0
			for i in b.seats.size():
				var sp: Vector3 = b.stand_point(i)
				var drop: float = absf(forest.ground_height(sp.x, sp.z) - p.y)
				if drop > 0.25:
					_fail("%s seat %d stand point is %.2f m off the terrace" % [b.name, i, drop])
				# Nothing solid where a Keling stands to sit down.
				var q := PhysicsShapeQueryParameters3D.new()
				var cap := CapsuleShape3D.new()
				cap.radius = 0.3
				cap.height = 1.2
				q.shape = cap
				q.transform = Transform3D(Basis(), sp + Vector3.UP * 0.7)
				for h in _keling.get_world_3d().direct_space_state.intersect_shape(q, 8):
					if h.collider.name != "TerrainBody":
						_fail("%s seat %d stand point blocked by %s at %s" % [b.name, i, h.collider.get_path(), (h.collider.get_child(h.shape) as Node3D).global_position if h.collider.get_child_count() > h.shape else Vector3.ZERO])
				seats += 1
			print("bench_check: %s at %s faces %.0f°, %d seats, view %s / %s" % [b.name, p, rad_to_deg(b.facing_yaw()), seats, b.site.view, b.site.element])
		_bench = benches[0]
		# Drop the Keling a metre in front of the first seat.
		var sp: Vector3 = _bench.stand_point(0)
		var out: Vector3 = _bench.global_transform.basis.z.normalized()
		_keling.global_position = sp + out * 0.45 + Vector3.UP * 0.1
		_keling.reset_physics_interpolation()
		for cs in _bench.body.get_children():
			print("  shape ", cs.shape, " size ", cs.shape.get("size"), " at ", cs.global_position)
		print("  teleport to ", sp + out * 0.45 + Vector3.UP * 0.1, " now ", _keling.global_position, " out ", out)
		return false
	match _stage:
		0:
			if fmod(_t, 0.25) < delta:
				print("  local=%s" % _bench.to_local(_keling.global_position))
				print("  pre t=%.2f pos=%s sp=%s mode=%d floor=%s" % [_t, _keling.global_position, _bench.stand_point(0), _keling.mode, _keling.is_on_floor()])
			if _t > 1.5:
				if _bench.find_free_seat(self, _keling.global_position).is_empty():
					_fail("no seat in reach at %s" % _keling.global_position)
				_keling.try_grab()
				_stage = 1
				_t = 0.0
		1:
			if fmod(_t, 0.5) < delta:
				var sp: Vector3 = _bench.stand_point(0)
				for c in _keling.get_slide_collision_count():
					var col = _keling.get_slide_collision(c)
					print("    hit ", col.get_collider(), " ", col.get_collider().name if col.get_collider() else "", " n=", col.get_normal())
				print("  t=%.1f phase=%d pos=%s d=%.2f vel=%s facing=%.2f" % [_t, _keling.get("_sit_phase"), _keling.global_position, Vector2(sp.x - _keling.global_position.x, sp.z - _keling.global_position.z).length(), _keling.velocity, _keling.facing])
			if _t > 4.0:
				if not _keling.is_sitting():
					_fail("not seated after 4 s (mode %d)" % _keling.mode)
				var skel: Skeleton3D = _keling.get("model").find_child("Skeleton3D", true, false)
				var hip := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("Hips")).origin
				_hip_err = hip.distance_to(_bench.hip_point(0))
				print("bench_check: seated, hips %.3f m from the seat spot, bench occupied=%s" % [_hip_err, _bench.is_occupied()])
				if _hip_err > 0.05:
					_fail("hips not on the seat")
				Input.action_press("move_forward", 1.0)
				_stage = 2
				_t = 0.0
		2:
			if _t > 0.3:
				Input.action_release("move_forward")
			if _t > 1.5:
				if _keling.is_sitting() or _bench.is_occupied():
					_fail("did not stand up")
				print("bench_check: stood up at %s on_floor=%s" % [_keling.global_position, _keling.is_on_floor()])
				print("bench_check: ", "PASS" if _ok else "FAIL")
				quit(0 if _ok else 1)
	return false
