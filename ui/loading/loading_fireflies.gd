class_name LoadingFireflies
extends Control
## Fireflies drifting over the loading screen key art: lazy looping paths,
## a slow blink each, a few big soft out-of-focus ones up close.

const COUNT := 46

var _flies: Array[Dictionary] = []
var _time := 0.0
var _glow: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow = VineProgress.make_glow_texture()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	var rng := RandomNumberGenerator.new()
	rng.seed = 4207
	for i in COUNT:
		var near := i < 6
		_flies.append({
			"p": Vector2(rng.randf(), rng.randf_range(0.08, 0.95)),
			"r": rng.randf_range(26.0, 48.0) if near else rng.randf_range(5.0, 13.0),
			"a": rng.randf_range(0.12, 0.22) if near else rng.randf_range(0.5, 0.95),
			"speed": rng.randf_range(0.004, 0.012) * (1.6 if near else 1.0),
			"phase": rng.randf() * TAU,
			"blink": rng.randf_range(0.5, 1.4),
			"wob": rng.randf_range(0.01, 0.03),
			"hue": rng.randf(),
		})


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var s := size
	for f in _flies:
		var ph: float = f.phase
		var drift: Vector2 = Vector2(sin(_time * f.speed * 9.0 + ph) * 0.06, -_time * f.speed)
		var wob: Vector2 = Vector2(sin(_time * 1.3 + ph * 3.0), cos(_time * 0.9 + ph * 2.0)) * f.wob
		var p: Vector2 = f.p + drift + wob
		p.y = 0.08 + fposmod(p.y - 0.08, 0.9)
		p.x = fposmod(p.x, 1.0)
		var blink: float = pow(0.5 + 0.5 * sin(_time * f.blink * 2.0 + ph), 2.0)
		var c: Color = Color(1.0, 0.92, 0.5).lerp(Color(0.75, 1.0, 0.45), f.hue)
		c.a = f.a * (0.25 + 0.75 * blink)
		var r: float = f.r
		draw_texture_rect(_glow, Rect2(p * s - Vector2.ONE * r, Vector2.ONE * r * 2.0), false, c)
		if r < 20.0:
			draw_texture_rect(_glow, Rect2(p * s - Vector2.ONE * r * 0.3, Vector2.ONE * r * 0.6), false, Color(1, 1, 0.9, c.a))
