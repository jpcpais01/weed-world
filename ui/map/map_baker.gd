class_name MapBaker
extends Node
## Paints the world map once, right after the forest has grown: the terrain
## fields go through a storybook shader, every tree crown is brushed on top in
## its own species colour, and the result is read back into a mipmapped
## texture the minimap and the world map share. Nothing is stored on disk, so
## the map always matches the forest exactly, whatever the forest threads add.

signal baked(texture: Texture2D)

const SIZE := 1536
const EXTENT := ForestTerrain.EXTENT   ## the map spans [-EXTENT, EXTENT] metres
const TERRAIN_SHADER := preload("res://ui/map/map_terrain.gdshader")

var texture: Texture2D


static func world_to_uv(p: Vector2) -> Vector2:
	return (p + Vector2(EXTENT, EXTENT)) / (EXTENT * 2.0)


func bake(forest: Forest) -> void:
	if forest == null or forest.terrain == null:
		return
	if DisplayServer.get_name() == "headless":
		return  # nothing renders without a GPU
	var t0 := Time.get_ticks_msec()
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	add_child(vp)

	var ground := ColorRect.new()
	ground.size = Vector2(SIZE, SIZE)
	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	mat.set_shader_parameter("data", _data_texture(forest.terrain))
	mat.set_shader_parameter("grid_n", float(ForestTerrain.N))
	mat.set_shader_parameter("extent", EXTENT)
	mat.set_shader_parameter("grid_step", ForestTerrain.STEP)
	mat.set_shader_parameter("play_half", ForestLayout.HALF)
	mat.set_shader_parameter("pixels", float(SIZE))
	ground.material = mat
	vp.add_child(ground)

	var painter := _Painter.new()
	painter.forest = forest
	painter.ppm = SIZE / (EXTENT * 2.0)
	vp.add_child(painter)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img and not img.is_empty():
		img.convert(Image.FORMAT_RGBA8)
		img.generate_mipmaps()
		texture = ImageTexture.create_from_image(img)
	vp.queue_free()
	if texture:
		print("World map painted in %d ms" % (Time.get_ticks_msec() - t0))
		baked.emit(texture)


## Packs the terrain fields into a small half-float texture for the shader.
func _data_texture(t: ForestTerrain) -> ImageTexture:
	var n := ForestTerrain.N
	var f := PackedFloat32Array()
	f.resize(n * n * 4)
	for i in n * n:
		f[i * 4] = t.heights[i]
		f[i * 4 + 1] = minf(t.path_dist[i], 8.0)
		f[i * 4 + 2] = clampf(t.water_level[i] - t.heights[i], -2.0, 4.0)
		f[i * 4 + 3] = t.shade[i]
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RGBAF, f.to_byte_array())
	img.convert(Image.FORMAT_RGBAH)
	return ImageTexture.create_from_image(img)


## Brushes on everything the shader can't know about: tree crowns with their
## shadows, waterfall foam and lotus blossoms.
class _Painter extends Node2D:
	const CROWN := {
		"common": Color(0.36, 0.62, 0.31), "oak": Color(0.27, 0.52, 0.27), "birch": Color(0.64, 0.79, 0.4),
		"pine": Color(0.17, 0.42, 0.36), "sentinel": Color(0.2, 0.46, 0.4), "twisted": Color(0.47, 0.6, 0.3),
		"blossom": Color(0.97, 0.67, 0.81), "willow": Color(0.62, 0.77, 0.48), "sapling": Color(0.49, 0.72, 0.35),
		"far": Color(0.3, 0.5, 0.35), "elder": Color(0.74, 0.6, 0.96), "dead": Color(0.68, 0.68, 0.7),
	}
	const AUTUMN := [Color(0.97, 0.72, 0.27), Color(0.9, 0.46, 0.22), Color(0.93, 0.6, 0.2)]

	var forest: Forest
	var ppm := 12.8

	func _px(p: Vector2) -> Vector2:
		return (p + Vector2(EXTENT, EXTENT)) * ppm

	func _draw() -> void:
		var trees: Array = forest.scatter.trees.duplicate() if forest.scatter else []
		# North first, so crowns further south overlap the ones behind them.
		trees.sort_custom(func(a, b): return a.pos.y < b.pos.y)
		var rng := RandomNumberGenerator.new()
		rng.seed = ForestLayout.SEED

		var crowns: Array[Dictionary] = []
		for t in trees:
			var p: Vector2 = t.pos
			if absf(p.x) > EXTENT + 4.0 or absf(p.y) > EXTENT + 4.0:
				continue
			var kind: String = t.get("kind", "common")
			if kind == "":
				kind = "common"
			var r: float = t.canopy * (0.62 if kind in ["pine", "sentinel"] else 0.8)
			# Keep crowns off the paths so the trails stay readable.
			var pd := forest.terrain.path_distance(p.x, p.y)
			r = clampf(r, t.canopy * 0.35, maxf(pd - 0.8, t.canopy * 0.35))
			var col: Color = CROWN.get(kind, CROWN.common)
			var autumn: float = t.get("autumn", 0.0)
			if autumn > 0.0:
				col = col.lerp(AUTUMN[rng.randi() % AUTUMN.size()], clampf(autumn, 0.0, 1.0) * 0.85)
			col = col.lightened(rng.randf_range(-0.06, 0.08))
			crowns.append({"c": _px(p), "r": r * ppm, "col": col, "kind": kind, "seed": rng.randi()})

		# Soft shadows fall south-east, away from the cartographer's sun.
		for cr in crowns:
			if cr.kind == "dead":
				continue
			draw_circle(cr.c + Vector2(0.22, 0.32) * cr.r, cr.r * 1.04, Color(0.06, 0.16, 0.08, 0.26))
		for cr in crowns:
			match cr.kind:
				"pine", "sentinel":
					_conifer(cr)
				"dead":
					_snag(cr)
				_:
					_broadleaf(cr)

		_waterfalls()
		if forest.water:
			for lp in forest.water.lotus_points:
				var c := _px(Vector2(lp.x, lp.z))
				draw_circle(c, 0.32 * ppm, Color(0.35, 0.62, 0.38))
				draw_circle(c + Vector2(-0.08, -0.1) * ppm, 0.17 * ppm, Color(1.0, 0.75, 0.86))

	func _broadleaf(cr: Dictionary) -> void:
		var c: Vector2 = cr.c
		var r: float = cr.r
		var col: Color = cr.col
		var rng := RandomNumberGenerator.new()
		rng.seed = cr.seed
		var body := col.darkened(0.16)
		# Lumpy cloud outline: a ring of lobes around the crown.
		var lobes := 6 + int(r / 10.0)
		var a0 := rng.randf() * TAU
		for k in lobes:
			var a := a0 + TAU * k / lobes
			draw_circle(c + Vector2(cos(a), sin(a)) * r * 0.62, r * rng.randf_range(0.4, 0.5), body)
		draw_circle(c, r * 0.78, body)
		draw_circle(c + Vector2(-0.16, -0.2) * r, r * 0.64, col)
		draw_circle(c + Vector2(-0.32, -0.38) * r, r * 0.28, col.lightened(0.22))
		if cr.kind == "blossom":
			for k in 5:
				var q := c + Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6)) * r
				draw_circle(q, maxf(r * 0.08, 1.2), Color(1, 0.95, 0.97, 0.9))
		elif cr.kind == "elder":
			draw_arc(c, r * 1.1, 0.0, TAU, 64, Color(0.9, 0.8, 1.0, 0.5), maxf(r * 0.05, 2.0), true)
			for k in 9:
				var q := c + Vector2(rng.randf_range(-0.7, 0.7), rng.randf_range(-0.7, 0.7)) * r
				draw_circle(q, maxf(r * 0.04, 1.5), Color(1.0, 0.95, 0.7, 0.9))
		elif cr.kind == "willow":
			for k in 7:
				var a := a0 + TAU * k / 7.0
				draw_line(c + Vector2(cos(a), sin(a)) * r * 0.3, c + Vector2(cos(a), sin(a)) * r * 0.85, col.lightened(0.15), maxf(r * 0.06, 1.0), true)

	func _conifer(cr: Dictionary) -> void:
		var c: Vector2 = cr.c
		var r: float = cr.r
		var col: Color = cr.col
		var spikes := 9
		var rng := RandomNumberGenerator.new()
		rng.seed = cr.seed
		var a0 := rng.randf() * TAU
		for layer in 2:
			var rr := r * (1.0 if layer == 0 else 0.62)
			var off := Vector2(-0.12, -0.15) * r * layer
			var pts := PackedVector2Array()
			for k in spikes * 2:
				var a := a0 + PI * k / spikes + layer * 0.3
				var d := rr if k % 2 == 0 else rr * 0.68
				pts.append(c + off + Vector2(cos(a), sin(a)) * d)
			draw_colored_polygon(pts, col.darkened(0.12) if layer == 0 else col.lightened(0.08))
		draw_circle(c + Vector2(-0.16, -0.2) * r, r * 0.16, col.lightened(0.3))

	func _snag(cr: Dictionary) -> void:
		var c: Vector2 = cr.c
		var s: float = maxf(cr.r, 10.0)
		var g: Color = cr.col
		for k in 5:
			var a := TAU * k / 5.0 + 0.4
			var tip := c + Vector2(cos(a), sin(a)) * s
			draw_line(c + Vector2(2, 3), tip + Vector2(2, 3), Color(0, 0, 0, 0.2), s * 0.16, true)
			draw_line(c, tip, g, s * 0.14, true)
			draw_line(c.lerp(tip, 0.6), c.lerp(tip, 0.6) + Vector2(cos(a + 0.8), sin(a + 0.8)) * s * 0.35, g, s * 0.08, true)
		draw_circle(c, s * 0.18, g.darkened(0.2))

	func _waterfalls() -> void:
		for f in forest.terrain.falls:
			var c := _px(Vector2(f.lip.x, f.lip.z))
			var dir: Vector2 = f.dir
			var side := Vector2(-dir.y, dir.x)
			for k in 3:
				var o := c + dir * ppm * (0.2 + k * 0.35)
				draw_line(o - side * ppm * 0.7, o + side * ppm * 0.7, Color(1, 1, 1, 0.85 - k * 0.22), maxf(ppm * 0.18, 1.5), true)
