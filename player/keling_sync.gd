class_name KelingSync
extends RefCounted
## Network look of a Keling. `pack()` squeezes everything another player needs
## to see into ~35 bytes (where it is, how it moves, which animation state,
## how it leans, looks and sits), sent ~15 times a second. On the receiving
## side the snapshots queue up and `sample()` plays them back a little in the
## past, so a friend's Keling glides between snapshots instead of stepping,
## and keeps coasting for a moment if the relay hiccups.

## Every animation state by index (anything else goes over as its name).
const STATES: Array[StringName] = [&"Move", &"JumpStart", &"Fall", &"Land", &"SprintStop",
	&"Turn90L", &"Turn90R", &"Turn180L", &"Turn180R", &"Dance", &"Cheer", &"SitDown",
	&"SitIdle", &"SitUp", &"Nod", &"Surprise"]

## How far behind the newest snapshot we play (ms): enough to ride out jitter.
const DELAY := 140.0
## Coast on the last velocity for at most this long (ms) when snapshots stop.
const COAST := 300.0
## Jumps bigger than this (m) between snapshots snap instead of sliding.
const TELEPORT := 4.0

var _snaps: Array[Dictionary] = []
var _offset := 0.0
var _has_offset := false
var _last_pos := Vector3.INF


static func pack(k: KelingController) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u32(Time.get_ticks_msec())
	var p := k.global_position
	b.put_float(p.x)
	b.put_float(p.y)
	b.put_float(p.z)
	b.put_half(k.velocity.x)
	b.put_half(k.velocity.y)
	b.put_half(k.velocity.z)
	b.put_half(k.facing)
	b.put_u8(k.mode)
	var state := k.animator.current_state()
	var si := STATES.find(state)
	b.put_u8(si if si >= 0 else 255)
	if si < 0:
		b.put_utf8_string(state)
	var flags := 0
	if k.is_on_floor():
		flags |= 1
	if k.wants_move():
		flags |= 2
	b.put_u8(flags)
	var proc := k.procedural
	b.put_8(clampi(roundi((proc.look_yaw if proc else 0.0) * 400.0), -127, 127))
	b.put_8(clampi(roundi((proc.look_pitch if proc else 0.0) * 400.0), -127, 127))
	var sit := k.sit
	b.put_u8(roundi(clampf(sit.amount if sit else 0.0, 0.0, 1.0) * 255.0))
	b.put_u8(roundi(clampf(sit.legs if sit else 0.0, 0.0, 1.0) * 255.0))
	b.put_8(clampi(roundi((sit.hop if sit else 0.0) * 1000.0), -127, 127))
	b.put_half(k.visual.scale.y)
	return b.data_array


## Queues a snapshot from the wire.
func push(bytes: PackedByteArray) -> void:
	var b := StreamPeerBuffer.new()
	b.data_array = bytes
	if bytes.size() < 30:
		return
	var s := {}
	s.t = float(b.get_u32())
	s.pos = Vector3(b.get_float(), b.get_float(), b.get_float())
	s.vel = Vector3(b.get_half(), b.get_half(), b.get_half())
	s.facing = b.get_half()
	s.mode = b.get_u8()
	var si := b.get_u8()
	s.state = STATES[si] if si < STATES.size() else StringName(b.get_utf8_string())
	var flags := b.get_u8()
	s.floor = flags & 1 != 0
	s.moving = flags & 2 != 0
	s.look_yaw = b.get_8() / 400.0
	s.look_pitch = b.get_8() / 400.0
	s.sit = b.get_u8() / 255.0
	s.legs = b.get_u8() / 255.0
	s.hop = b.get_8() / 1000.0
	s.scale = b.get_half()
	if not s.pos.is_finite() or not s.vel.is_finite():
		return
	# Clock offset: the smallest (arrival - sent) seen is the best guess of
	# the two clocks' difference plus the quickest trip; let it drift up
	# slowly in case the route got longer.
	var now := float(Time.get_ticks_msec())
	var o: float = now - s.t
	if not _has_offset or o < _offset:
		_offset = o
		_has_offset = true
	else:
		_offset = lerpf(_offset, o, 0.01)
	if not _snaps.is_empty() and s.t <= (_snaps[-1].t as float):
		return  # stale or the sender restarted its clock
	_snaps.append(s)
	if _snaps.size() > 32:
		_snaps.pop_front()


func has_data() -> bool:
	return not _snaps.is_empty()


## The newest snapshot as received (for "where is my friend right now").
func latest() -> Dictionary:
	return _snaps[-1] if not _snaps.is_empty() else {}


## The interpolated look for this moment. Adds "teleport": true when the
## body should snap rather than glide.
func sample() -> Dictionary:
	if _snaps.is_empty():
		return {}
	var t := float(Time.get_ticks_msec()) - _offset - DELAY
	while _snaps.size() > 2 and (_snaps[1].t as float) <= t:
		_snaps.pop_front()
	var a: Dictionary = _snaps[0]
	var last: Dictionary = _snaps[-1]
	var out: Dictionary
	if t >= (last.t as float):
		# Nothing newer yet: coast a little on the last velocity.
		out = last.duplicate()
		var ahead := minf(t - (last.t as float), COAST) / 1000.0
		var v: Vector3 = last.vel
		if last.floor:
			v.y = 0.0
		out.pos = (last.pos as Vector3) + v * ahead
	elif _snaps.size() >= 2 and t >= (a.t as float):
		var b: Dictionary = _snaps[1]
		var span := maxf((b.t as float) - (a.t as float), 1.0)
		var k := clampf((t - (a.t as float)) / span, 0.0, 1.0)
		out = (b if k > 0.5 else a).duplicate()
		if (a.pos as Vector3).distance_to(b.pos) < TELEPORT:
			out.pos = (a.pos as Vector3).lerp(b.pos, k)
		out.vel = (a.vel as Vector3).lerp(b.vel, k)
		out.facing = lerp_angle(a.facing, b.facing, k)
		for key in ["look_yaw", "look_pitch", "sit", "legs", "hop", "scale"]:
			out[key] = lerpf(a[key], b[key], k)
	else:
		out = a.duplicate()
	out.teleport = _last_pos == Vector3.INF or _last_pos.distance_to(out.pos) > TELEPORT
	_last_pos = out.pos
	return out
