class_name ForestGround
extends RefCounted
## Where the forest touches the floor. Bakes three textures that every ground
## shader reads through global uniforms, so trunks, boulders, logs, grass and
## the terrain all agree about the same patch of soil:
##
##   ground_height  241² half-float terrain height, so a rock or a trunk knows
##                  exactly where it meets the ground and fades into it.
##   ground_mask    241² RGBA8 copy of the terrain masks (worn path, bare rock,
##                  wet bank, canopy shade): props blend into the right colour.
##   ground_detail  1024² RGBA8 at ~12 cm a texel, painted with soft stamps:
##                  R bare soil, G moss, B footpath edge distance, A contact
##                  shade under whatever stands there.
##
## The CPU keeps the detail image so the scatter can grow grass up to the
## exact noisy edge the shader draws and wrap collars round trunks and stones.

const RES := 1024
const EXTENT := ForestTerrain.EXTENT
const TEXEL := 2.0 * EXTENT / RES
## Path edge distance is stored as 0.5 - d / (2 * PATH_RANGE): 1 deep inside
## the path, 0.5 on its edge, 0 at PATH_RANGE metres out into the verge.
const PATH_RANGE := 1.6
const BRUSH := 96

enum Foot { TREE, ROCK, LOG, STONE }

var terrain: ForestTerrain
var detail: Image
var feet: Array[Dictionary] = []   # {pos: Vector2, radius: float, kind: Foot}
var _brushes := {}
var _base := {}
var _edge := FastNoiseLite.new()
var _grain := FastNoiseLite.new()
var _width := FastNoiseLite.new()
var _textures: Array[Texture2D] = []


func _init(p_terrain: ForestTerrain) -> void:
	terrain = p_terrain
	detail = Image.create(RES, RES, false, Image.FORMAT_RGBA8)
	_edge.seed = ForestLayout.SEED + 401
	_edge.frequency = 0.55
	_edge.fractal_octaves = 2
	_grain.seed = ForestLayout.SEED + 402
	_grain.frequency = 2.6
	_grain.fractal_octaves = 1
	_width.seed = ForestLayout.SEED + 403
	_width.frequency = 0.08
	_width.fractal_octaves = 1


# ----------------------------------------------------------------------------
# Stamps

## Paints the footprint of something standing on the floor. `radius` is how far
## its base reaches (trunk radius, boulder half-width); the stamp spreads well
## past it so soil and moss feather out into the grass.
func stamp(kind: Foot, pos: Vector2, radius: float) -> void:
	if maxf(absf(pos.x), absf(pos.y)) > EXTENT + 8.0:
		return
	var reach: float
	match kind:
		Foot.TREE:
			reach = radius * 3.6 + 0.55
		Foot.ROCK:
			reach = radius * 1.45 + 0.3
		Foot.LOG:
			reach = radius * 2.2 + 0.25
		_:
			reach = radius * 1.6 + 0.08
	var size := clampi(int(round(reach / TEXEL)) * 2, 4, 160)
	var variant := (absi(int(pos.x * 7.3)) + absi(int(pos.y * 3.1))) % 3
	var brush := _brush(kind, variant, size)
	var c := _to_texel(pos)
	detail.blend_rect(brush, Rect2i(0, 0, size, size), Vector2i(int(round(c.x - size * 0.5)), int(round(c.y - size * 0.5))))
	feet.append({"pos": pos, "radius": radius, "kind": kind})


## A line of stamps along a fallen log.
func stamp_line(a: Vector2, b: Vector2, radius: float) -> void:
	var n := maxi(2, int(a.distance_to(b) / maxf(radius * 1.2, 0.3)) + 1)
	for k in n:
		stamp(Foot.LOG, a.lerp(b, float(k) / (n - 1)), radius)


func _brush(kind: Foot, variant: int, size: int) -> Image:
	var key := "%d/%d/%d" % [kind, variant, size]
	if _brushes.has(key):
		return _brushes[key]
	var img: Image = _base_brush(kind, variant).duplicate()
	img.resize(size, size, Image.INTERPOLATE_BILINEAR)
	_brushes[key] = img
	return img


## The full-resolution brush: a lumpy disc whose alpha falls off from the
## centre (the shader reads contact shade from high alpha, soil and moss from
## the softer rim), with moss leaning to the shady north side.
func _base_brush(kind: Foot, variant: int) -> Image:
	var key := "%d/%d" % [kind, variant]
	if _base.has(key):
		return _base[key]
	var n := FastNoiseLite.new()
	n.seed = ForestLayout.SEED + 900 + kind * 10 + variant
	n.frequency = 0.06
	n.fractal_octaves = 3
	var img := Image.create(BRUSH, BRUSH, false, Image.FORMAT_RGBA8)
	var half := BRUSH * 0.5
	for y in BRUSH:
		for x in BRUSH:
			var u := (x + 0.5 - half) / half
			var v := (y + 0.5 - half) / half
			var r := sqrt(u * u + v * v)
			var a := atan2(v, u)
			# Lumpy outline: the rim wanders in and out.
			var lump := n.get_noise_2d(cos(a) * 9.0, sin(a) * 9.0)
			var rr := r * (1.0 + lump * 0.28)
			if rr >= 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var fine := n.get_noise_2d(x * 2.0, y * 2.0) * 0.5 + 0.5
			var alpha: float
			var soil: float
			var moss: float
			match kind:
				Foot.TREE:
					# A broad bare plateau (roots, soil, no grass) then a soft rim.
					alpha = pow(1.0 - smoothstep(0.3, 1.0, rr), 1.5)
					soil = 0.55 + 0.45 * fine
					# Moss on the north (-Z) side and in random cushions.
					moss = clampf(0.25 + (-v) * 0.45 + (fine - 0.5) * 0.9, 0.0, 1.0)
				Foot.ROCK:
					alpha = 1.0 - smoothstep(0.42, 1.0, rr)
					alpha *= alpha
					soil = 0.35 + 0.4 * fine
					moss = clampf(0.3 + (-v) * 0.35 + (fine - 0.5) * 1.1, 0.0, 1.0)
				Foot.LOG:
					alpha = pow(1.0 - rr, 1.1)
					soil = 0.7 + 0.3 * fine
					moss = clampf(0.45 + (fine - 0.5) * 1.0, 0.0, 1.0)
				_:
					alpha = pow(1.0 - rr, 1.5) * 0.85
					soil = 0.15
					moss = 0.0
			img.set_pixel(x, y, Color(soil, moss, 0.0, clampf(alpha, 0.0, 1.0)))
	_base[key] = img
	return img


# ----------------------------------------------------------------------------
# Footpaths

## Signed distance (metres) from the visible edge of the nearest footpath:
## negative on the path. The edge wanders with noise and the path breathes
## wider and narrower along its length.
func path_edge(x: float, z: float) -> float:
	var d := terrain.path_distance(x, z)
	if d > 4.0:
		return d
	var w := 0.98 + 0.22 * _width.get_noise_2d(x, z)
	return d - w + 0.2 * _edge.get_noise_2d(x, z) + 0.06 * _grain.get_noise_2d(x, z)


## Rasterises the path edge distance into the detail blue channel. Only the
## grid cells near a path are visited, so this costs a fraction of a full pass.
func bake_paths() -> void:
	var N := ForestTerrain.N
	var step := ForestTerrain.STEP
	for gz in N:
		var z0 := -EXTENT + gz * step - step * 0.5
		var ty0 := clampi(ceili((z0 + EXTENT) / TEXEL - 0.5), 0, RES)
		var ty1 := clampi(ceili((z0 + step + EXTENT) / TEXEL - 0.5), 0, RES)
		for gx in N:
			if terrain.path_dist[gz * N + gx] > 3.4:
				continue
			var x0 := -EXTENT + gx * step - step * 0.5
			var tx0 := clampi(ceili((x0 + EXTENT) / TEXEL - 0.5), 0, RES)
			var tx1 := clampi(ceili((x0 + step + EXTENT) / TEXEL - 0.5), 0, RES)
			for ty in range(ty0, ty1):
				var z := -EXTENT + (ty + 0.5) * TEXEL
				for tx in range(tx0, tx1):
					var x := -EXTENT + (tx + 0.5) * TEXEL
					var e := path_edge(x, z)
					var c := detail.get_pixel(tx, ty)
					c.b = clampf(0.5 - e / (2.0 * PATH_RANGE), 0.0, 1.0)
					detail.set_pixel(tx, ty, c)


# ----------------------------------------------------------------------------
# Queries (nearest texel; cheap enough for the grass pass)

func sample(x: float, z: float) -> Color:
	var t := _to_texel(Vector2(x, z))
	var tx := int(t.x)
	var ty := int(t.y)
	if tx < 0 or ty < 0 or tx >= RES or ty >= RES:
		return Color(0, 0, 0, 0)
	return detail.get_pixel(tx, ty)


## Path edge distance read back from the baked channel (PATH_RANGE when far).
static func edge_of(c: Color) -> float:
	return (0.5 - c.b) * 2.0 * PATH_RANGE


func _to_texel(p: Vector2) -> Vector2:
	return (p + Vector2(EXTENT, EXTENT)) / TEXEL


# ----------------------------------------------------------------------------
# Textures

## Uploads everything as global shader uniforms. Call once the scatter has
## finished stamping.
func publish() -> void:
	var N := ForestTerrain.N
	var h := Image.create_from_data(N, N, false, Image.FORMAT_RF, terrain.heights.to_byte_array())
	h.convert(Image.FORMAT_RH)
	var masks := PackedByteArray()
	masks.resize(N * N * 4)
	for i in N * N:
		var c := terrain.mask_color(i)
		masks[i * 4] = int(c.r * 255.0)
		masks[i * 4 + 1] = int(c.g * 255.0)
		masks[i * 4 + 2] = int(c.b * 255.0)
		masks[i * 4 + 3] = int(c.a * 255.0)
	var m := Image.create_from_data(N, N, false, Image.FORMAT_RGBA8, masks)
	var d := detail.duplicate() as Image
	d.generate_mipmaps()
	_textures = [ImageTexture.create_from_image(h), ImageTexture.create_from_image(m), ImageTexture.create_from_image(d)]
	RenderingServer.global_shader_parameter_set("ground_height", _textures[0])
	RenderingServer.global_shader_parameter_set("ground_mask", _textures[1])
	RenderingServer.global_shader_parameter_set("ground_detail", _textures[2])
	RenderingServer.global_shader_parameter_set("ground_grid", Vector4(-EXTENT, -EXTENT, ForestTerrain.STEP, N))
	RenderingServer.global_shader_parameter_set("ground_blend", 1.0)


## Turns the blending off again and lets go of the textures (the forest is
## being freed, or another level without this ground loads).
static func withdraw() -> void:
	RenderingServer.global_shader_parameter_set("ground_blend", 0.0)
	for k in ["ground_height", "ground_mask", "ground_detail"]:
		RenderingServer.global_shader_parameter_set(k, null)
