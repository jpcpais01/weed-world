class_name PerfMeter
## Main-thread time per game system, for the frame-time readout under the FPS
## counter (see PerfReadout). A system wraps its per-frame work:
##   var t0 := Time.get_ticks_usec()
##   ...
##   PerfMeter.add(&"weed", Time.get_ticks_usec() - t0)
## Main thread only: worker threads hand their timings to the main thread.

static var _usec := {}


static func add(system: StringName, usec: int) -> void:
	_usec[system] = _usec.get(system, 0) + usec


## Everything added since the last call, in microseconds, and starts afresh.
static func take() -> Dictionary:
	var out := _usec
	_usec = {}
	return out
