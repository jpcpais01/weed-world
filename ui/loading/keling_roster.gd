class_name KelingRoster
extends Control
## The loading screen's progress meter: all five Kelings stand along the
## growing vine. Each one idles, dimmed and waiting, until the vine reaches its
## feet; then it hops up in a burst of its own colours, its name pops in and it
## starts to dance. Sprites come from tools/render_keling_sprites.gd, so this
## costs no 3D rendering and no shader warm-up of its own.

const SPRITES := "res://ui/loading/sprites/%s_%s.png"
const CELL := 192
const COLS := 8
const IDLE_FRAMES := 16
const DANCE_FRAMES := 24
const IDLE_FPS := 9.0
const DANCE_FPS := 15.0
const FONT := preload("res://ui/fonts/Fredoka.ttf")

## 0..1 loading progress; the vine eases towards it.
var value := 0.0:
	set(v):
		value = v
		if _vine:
			_vine.value = v

var _vine: VineProgress
var _members: Array[Dictionary] = []
var _time := 0.0
var _glow: Texture2D
var _sparks: Array[Dictionary] = []
var _font: FontVariation


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow = VineProgress.make_glow_texture()
	_font = FontVariation.new()
	_font.base_font = FONT
	_font.variation_opentype = {"wght": 600}

	_vine = VineProgress.new()
	_vine.wave = 0.1
	_vine.show_behind_parent = true
	add_child(_vine)

	var ids: Array = KelingCharacters.IDS
	for i in ids.size():
		var id: String = ids[i]
		var info := KelingCharacters.get_info(id)
		var colors: Array = info.colors
		_members.append({
			"id": id,
			"name": String(info.name),
			"idle": load(SPRITES % [id, "idle"]) as Texture2D,
			"dance": load(SPRITES % [id, "dance"]) as Texture2D,
			"main": colors[0], "accent": colors[1], "sparkle": colors[2],
			# Where along the vine it stands: spread out, clear of both ends.
			"t": lerpf(0.1, 0.9, float(i) / maxf(1.0, ids.size() - 1.0)),
			"woke": -1.0,
			# Start each loop somewhere else so they don't move in lockstep.
			"phase": float(i) * 0.37,
		})
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	# The vine runs along the Kelings' feet, in the lower part of the control.
	var vh := size.y * 0.24
	_vine.position = Vector2(0, size.y * 0.78 - vh * 0.5)
	_vine.size = Vector2(size.x, vh)


## The Kelings all wake up and dance (used when loading finishes).
func wake_all() -> void:
	value = 1.0
	for m in _members:
		if m.woke < 0.0:
			_wake(m)


func _process(delta: float) -> void:
	_time += delta
	var grown := _vine.grown()
	for m in _members:
		if m.woke < 0.0 and grown >= m.t:
			_wake(m)
	for s in _sparks:
		s.life += delta
		s.p += s.v * delta
		s.v *= 1.0 - delta * 1.6
		s.v.y += 70.0 * delta
	_sparks = _sparks.filter(func(s): return s.life < s.max)
	queue_redraw()


func _wake(m: Dictionary) -> void:
	m.woke = _time
	var feet := _feet(m)
	var h := _sprite_size()
	for k in 26:
		var a := randf() * TAU
		var speed := randf_range(60.0, 190.0) * h / 150.0
		var c: Color = [m.main, m.accent, m.sparkle][k % 3]
		_sparks.append({
			"p": feet + Vector2(randf_range(-0.2, 0.2) * h, -h * randf_range(0.2, 0.7)),
			"v": Vector2.from_angle(a) * speed + Vector2(0, -speed * 0.6),
			"life": 0.0, "max": randf_range(0.7, 1.4), "c": c, "r": randf_range(3.0, 7.0) * h / 150.0,
		})


func _sprite_size() -> float:
	# Tall enough to read on a phone, never wider than its slot.
	return minf(size.y * 0.92, size.x / maxf(1.0, _members.size()) * 1.15)


func _feet(m: Dictionary) -> Vector2:
	return _vine.position + _vine.point_at(m.t)


func _draw() -> void:
	var s := _sprite_size()
	for m in _members:
		var feet := _feet(m)
		var awake: bool = m.woke >= 0.0
		var age := _time - float(m.woke) if awake else 0.0
		# A happy hop when it wakes, then a tiny bounce while it dances.
		var hop := 0.0
		if awake and age < 0.7:
			hop = sin(age / 0.7 * PI) * s * 0.22
		var squash := 1.0
		if awake and age < 0.18:
			squash = 1.0 - 0.12 * sin(age / 0.18 * PI)

		# Soft contact shadow, smaller while airborne.
		var sh := 1.0 - hop / (s * 0.3)
		draw_set_transform(feet + Vector2(0, -s * 0.02), 0.0, Vector2(1.0, 0.28))
		draw_circle(Vector2.ZERO, s * 0.2 * sh, Color(0.02, 0.05, 0.02, 0.35 * sh))
		draw_set_transform_matrix(Transform2D.IDENTITY)

		# Halo of its own colour once awake.
		if awake:
			var ga := clampf(age / 0.4, 0.0, 1.0) * (0.35 + 0.1 * sin(_time * 3.0 + m.phase * 5.0))
			var gr := s * 0.55
			draw_texture_rect(_glow, Rect2(feet + Vector2(-gr, -s * 0.5 - gr - hop), Vector2(gr, gr) * 2.0), false, Color(m.main, ga))

		var tex: Texture2D = m.dance if awake else m.idle
		var frames := DANCE_FRAMES if awake else IDLE_FRAMES
		var fps := DANCE_FPS if awake else IDLE_FPS
		var f := int((_time + m.phase * 3.0) * fps) % frames
		var src := Rect2((f % COLS) * CELL, (f / COLS) * CELL, CELL, CELL)
		var w := s * (2.0 - squash)
		var h := s * squash
		# The sprite's feet sit ~6% above the bottom of its cell.
		var dst := Rect2(feet.x - w * 0.5, feet.y - h * 0.94 - hop, w, h)
		var tint := Color(1, 1, 1, 1) if awake else Color(0.55, 0.62, 0.58, 0.9)
		if awake and age < 0.35:
			tint = Color(1, 1, 1).lerp(Color(1.6, 1.6, 1.5), 1.0 - age / 0.35)
		draw_texture_rect_region(tex, dst, src, tint)

		# Its name pops in under its feet.
		if awake:
			var a := clampf((age - 0.15) / 0.35, 0.0, 1.0)
			var px := int(maxf(14.0, s * 0.13))
			var text: String = m.name
			var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			var pos := feet + Vector2(-tw * 0.5, s * 0.2 + (1.0 - a) * 8.0)
			draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, int(px * 0.35), Color(0.03, 0.08, 0.04, 0.8 * a))
			draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(Color(m.main).lerp(Color.WHITE, 0.55), a))

	for sp in _sparks:
		var k: float = 1.0 - sp.life / sp.max
		var r: float = sp.r * (0.5 + k)
		draw_texture_rect(_glow, Rect2(sp.p - Vector2(r, r) * 2.0, Vector2(r, r) * 4.0), false, Color(sp.c, k * 0.9))
