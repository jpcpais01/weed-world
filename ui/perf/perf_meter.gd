class_name PerfMeter
## Main-thread time per game system, for the frame-time readout under the FPS
## counter (see PerfReadout). A system wraps its per-frame work:
##   var t0 := Time.get_ticks_usec()
##   ...
##   PerfMeter.add(&"weed", Time.get_ticks_usec() - t0)
## Main thread only: worker threads hand their timings to the main thread.

static var _usec := {}
static var _peak := {}        # each system's slowest frame since the last take()
static var _frame := {}       # this frame's time per system so far
static var _frame_id := -1


static func add(system: StringName, usec: int) -> void:
	var f := Engine.get_process_frames()
	if f != _frame_id:
		_fold()
		_frame_id = f
	_usec[system] = _usec.get(system, 0) + usec
	_frame[system] = _frame.get(system, 0) + usec


## Everything added since the last call, in microseconds, and starts afresh:
## {"total": {system: usec}, "peak": {system: usec in its slowest frame}}.
static func take() -> Dictionary:
	_fold()
	var out := {"total": _usec, "peak": _peak}
	_usec = {}
	_peak = {}
	return out


static func _fold() -> void:
	for k in _frame:
		_peak[k] = maxi(_peak.get(k, 0), _frame[k])
	_frame = {}
