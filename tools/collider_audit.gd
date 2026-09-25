class_name ColliderAudit
extends RefCounted

## Measures an item body's collision shapes against its own picture (docs/decisions.md D61).
##
## D55 made every single-collider body derive its box from the sprite's opaque pixels, and
## asserted it. The authored bodies — a bat is a capsule for the barrel and a rect for the grip,
## not a box around both (D25) — could not be checked that way, so nothing checked them, and the
## audit that finally did found a nunchaku whose shapes covered 2% of its art and a monitor that
## overhung its picture by 20 px. This is the measurement, shared by `tools/collider_report.tscn`
## (the table, and the overlays that shapes are authored against) and `loop_check` (the guard).
##
## Everything is rasterised on a one-world-pixel grid in **body-local world pixels**, from the
## nodes the game actually runs: every `Sprite2D` child is the picture (a split turret is a base
## and a barrel), every `CollisionShape2D` child is the collider, each through its own transform.
## Nothing here reads a seed table, so it measures the scene that ships, not the one intended.
##
## The numbers it returns:
##
##   coverage      share of the picture's opaque pixels inside some shape. Low means you can
##                 push another body through art you can see.
##   excess        share of the shapes' area that is not over the picture. High means it hits
##                 things it visibly did not touch.
##   overhang      furthest any shape pixel sits from the nearest opaque pixel, world px. The
##                 worst single place the collider claims space the art does not.
##   sides         the same per side, as the shapes' bounding box beyond the art's.
##   art_axis / shape_axis   principal axis of each, degrees in [0, 180), and how elongated
##                 each is. Only meaningful when both are long — a mug has no axis.
##   grip_off / com_off      distance from the drag pin / centre of mass to the nearest opaque
##                 pixel. A grip in mid-air is a weapon held by nothing.
##   grip_t / com_t          where they fall along the art's own long axis, 0 at the grip's end
##                 and 1 at the far end. A bat's grip is near 0 and its weight past 0.5.

## An art pixel counts as the picture at half opacity or more. The item sprites are keyed and
## palette-snapped, so in practice alpha is 0 or 1 and the floor only decides anti-aliased rims.
const ALPHA_FLOOR := 0.5
## Distances in the overlay grid are sampled at pixel centres, so a shape edge flush with the art
## still reads 1 px out. Anything this close is a rounding of the edge, not an overhang.
const EDGE_SLACK := 1.0

## Every collision shape directly under the body — the ones the physics server sees. The grab
## region lives under `DraggableArea` and the blast under `ExplosionArea`, and neither is solid.
static func pieces_of(body: Node) -> Array[CollisionShape2D]:
	var out: Array[CollisionShape2D] = []
	for child in body.get_children():
		if child is CollisionShape2D and (child as CollisionShape2D).shape != null:
			out.append(child)
	return out

## Whether a person authored this body's collider rather than a seed tool deriving it.
##
## Exactly the complement of what D55's guard checks: a derived collider is one rectangle, on
## the origin, unturned — the box `ItemBodyBuilder` fits around the sprite's opaque pixels.
## Anything else was typed into a table: several shapes, an offset one, a turned one, a circle.
## Between D55's assertion and D61's, every item body is covered by one or the other.
static func is_authored(body: Node) -> bool:
	var pieces := pieces_of(body)
	if pieces.size() != 1:
		return pieces.size() > 1
	var only := pieces[0]
	return not (only.shape is RectangleShape2D) or not only.position.is_zero_approx() \
		or not is_zero_approx(only.rotation)

static func sprites_of(body: Node) -> Array[Sprite2D]:
	var out: Array[Sprite2D] = []
	for child in body.get_children():
		if child is Sprite2D and (child as Sprite2D).texture != null:
			out.append(child)
	return out

## The measurement. Returns an empty dictionary for a body with no picture or no collider.
static func measure(body: Node) -> Dictionary:
	var grid := rasterise(body)
	if grid.is_empty():
		return {}
	var w: int = grid["w"]
	var h: int = grid["h"]
	var origin: Vector2 = grid["origin"]
	var art: PackedByteArray = grid["art"]
	var solid: PackedByteArray = grid["solid"]

	var art_n := 0
	var solid_n := 0
	var both_n := 0
	var art_box := Rect2i()
	var solid_box := Rect2i()
	var art_pts := PackedVector2Array()
	var solid_pts := PackedVector2Array()
	for y in h:
		for x in w:
			var i := y * w + x
			var a := art[i] != 0
			var s := solid[i] != 0
			if a:
				art_n += 1
				art_box = _grow(art_box, art_n == 1, x, y)
				art_pts.append(Vector2(x, y))
			if s:
				solid_n += 1
				solid_box = _grow(solid_box, solid_n == 1, x, y)
				solid_pts.append(Vector2(x, y))
			if a and s:
				both_n += 1
	if art_n == 0 or solid_n == 0:
		return {}

	# Distance from every cell to the nearest opaque art cell, squared, exact.
	var dist := _edt(art, w, h)
	var worst := 0.0
	for i in w * h:
		if solid[i] != 0 and dist[i] > worst:
			worst = dist[i]

	var art_axis := _principal(art_pts)
	var shape_axis := _principal(solid_pts)
	var grip: Vector2 = body.get(&"grip_offset") if &"grip_offset" in body else Vector2.ZERO
	var com: Vector2 = (body as RigidBody2D).center_of_mass \
		if body is RigidBody2D and (body as RigidBody2D).center_of_mass_mode \
			== RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM else Vector2.ZERO

	# Along the art's long axis, oriented so the grip's end is 0.
	var centre: Vector2 = art_axis["centroid"] + origin + Vector2(0.5, 0.5)
	var dir := Vector2.from_angle(deg_to_rad(float(art_axis["angle"])))
	var lo := INF
	var hi := -INF
	for p in art_pts:
		var along := (p + origin + Vector2(0.5, 0.5) - centre).dot(dir)
		lo = minf(lo, along)
		hi = maxf(hi, along)
	var span := maxf(hi - lo, 1.0)
	var grip_t := ((grip - centre).dot(dir) - lo) / span
	var com_t := ((com - centre).dot(dir) - lo) / span
	if grip_t > 0.5:
		grip_t = 1.0 - grip_t
		com_t = 1.0 - com_t

	var axis_gap := absf(float(art_axis["angle"]) - float(shape_axis["angle"]))
	axis_gap = minf(axis_gap, 180.0 - axis_gap)
	return {
		"shapes": pieces_of(body).size(),
		"coverage": float(both_n) / float(art_n),
		"excess": float(solid_n - both_n) / float(solid_n),
		"overhang": maxf(sqrt(worst) - EDGE_SLACK, 0.0),
		"sides": {
			"left": maxf(art_box.position.x - solid_box.position.x, 0),
			"right": maxf(solid_box.end.x - art_box.end.x, 0),
			"top": maxf(art_box.position.y - solid_box.position.y, 0),
			"bottom": maxf(solid_box.end.y - art_box.end.y, 0),
		},
		"art_axis": art_axis["angle"],
		"art_long": art_axis["elongation"],
		"shape_axis": shape_axis["angle"],
		"shape_long": shape_axis["elongation"],
		"axis_gap": axis_gap,
		"grip": grip,
		"com": com,
		"grip_off": maxf(sqrt(_sample(dist, w, h, grip - origin)) - EDGE_SLACK, 0.0),
		"com_off": maxf(sqrt(_sample(dist, w, h, com - origin)) - EDGE_SLACK, 0.0),
		"grip_t": grip_t,
		"com_t": com_t,
		"art_rect": Rect2(Vector2(art_box.position) + origin, Vector2(art_box.size)),
		"solid_rect": Rect2(Vector2(solid_box.position) + origin, Vector2(solid_box.size)),
	}

## The two masks on one grid: `art` where some sprite is opaque, `solid` where some shape is.
## Cell (x, y) is the world pixel whose centre is origin + (x + 0.5, y + 0.5).
static func rasterise(body: Node) -> Dictionary:
	var sprites := sprites_of(body)
	var pieces := pieces_of(body)
	if sprites.is_empty() or pieces.is_empty():
		return {}

	var bounds := Rect2()
	var first := true
	var pictures: Array = []
	for sprite in sprites:
		var image := sprite.texture.get_image()
		if image == null:
			continue
		if image.is_compressed():
			image.decompress()
		var local := sprite.get_rect()
		var box := sprite.transform * local
		bounds = box if first else bounds.merge(box)
		first = false
		pictures.append({"image": image, "inverse": sprite.transform.affine_inverse(),
			"rect": local, "flip_h": sprite.flip_h, "flip_v": sprite.flip_v})
	if pictures.is_empty():
		return {}
	var tests: Array = []
	for piece in pieces:
		bounds = bounds.merge(piece.transform * piece.shape.get_rect())
		tests.append({"shape": piece.shape, "inverse": piece.transform.affine_inverse()})
	bounds = bounds.grow(4.0)
	var mirrored := flips(body)
	if mirrored:
		# Symmetric about x = 0, so a cell and its mirror image are both on the grid.
		var reach := ceilf(maxf(absf(bounds.position.x), absf(bounds.end.x)))
		bounds = Rect2(-reach, bounds.position.y, reach * 2.0, bounds.size.y)

	var origin := Vector2(floorf(bounds.position.x), floorf(bounds.position.y))
	var w := int(ceilf(bounds.end.x) - origin.x)
	var h := int(ceilf(bounds.end.y) - origin.y)
	var art := PackedByteArray()
	art.resize(w * h)
	var solid := PackedByteArray()
	solid.resize(w * h)
	for y in h:
		for x in w:
			var p := origin + Vector2(x + 0.5, y + 0.5)
			var i := y * w + x
			for picture in pictures:
				if _opaque(picture, p):
					art[i] = 1
					break
			for test in tests:
				if _inside(test["shape"], (test["inverse"] as Transform2D) * p):
					solid[i] = 1
					break
	if mirrored:
		# The collider never mirrors, so the only picture it can match in both facings is the
		# part that is there in both.
		var both := PackedByteArray()
		both.resize(w * h)
		for y in h:
			for x in w:
				both[y * w + x] = 1 if art[y * w + x] != 0 and art[y * w + (w - 1 - x)] != 0 else 0
		art = both
	return {"w": w, "h": h, "origin": origin, "art": art, "solid": solid}

## A turret that turns its sprite round to face him (`TurretBase.flips`). Its collision shapes
## stay where they are, so it is measured against the picture *and* its mirror image.
static func flips(body: Node) -> bool:
	return body is TurretBase and bool(body.get(&"flips"))

static func _opaque(picture: Dictionary, p: Vector2) -> bool:
	var q: Vector2 = (picture["inverse"] as Transform2D) * p
	var rect: Rect2 = picture["rect"]
	var image: Image = picture["image"]
	var px := int(floorf(q.x - rect.position.x))
	var py := int(floorf(q.y - rect.position.y))
	if px < 0 or py < 0 or px >= image.get_width() or py >= image.get_height():
		return false
	if picture["flip_h"]:
		px = image.get_width() - 1 - px
	if picture["flip_v"]:
		py = image.get_height() - 1 - py
	return image.get_pixel(px, py).a >= ALPHA_FLOOR

## Point-in-shape for the three shapes the seed tables use, in the shape's own frame. Godot 4's
## capsule is vertical and `height` is end to end, caps included.
static func _inside(shape: Shape2D, q: Vector2) -> bool:
	if shape is RectangleShape2D:
		var half := (shape as RectangleShape2D).size * 0.5
		return absf(q.x) <= half.x and absf(q.y) <= half.y
	if shape is CircleShape2D:
		return q.length() <= (shape as CircleShape2D).radius
	if shape is CapsuleShape2D:
		var capsule := shape as CapsuleShape2D
		var reach := maxf(capsule.height * 0.5 - capsule.radius, 0.0)
		return Vector2(0.0, clampf(q.y, -reach, reach)).distance_to(q) <= capsule.radius
	return shape.get_rect().has_point(q)

static func _grow(box: Rect2i, first: bool, x: int, y: int) -> Rect2i:
	if first:
		return Rect2i(x, y, 1, 1)
	return box.expand(Vector2i(x, y)).expand(Vector2i(x + 1, y + 1))

## Principal axis of a point cloud: angle in degrees on [0, 180) with +x = 0 and +y (down) = 90,
## and the ratio of the long spread to the short one.
static func _principal(points: PackedVector2Array) -> Dictionary:
	var mean := Vector2.ZERO
	for p in points:
		mean += p
	mean /= float(points.size())
	var xx := 0.0
	var yy := 0.0
	var xy := 0.0
	for p in points:
		var d := p - mean
		xx += d.x * d.x
		yy += d.y * d.y
		xy += d.x * d.y
	var angle := 0.5 * atan2(2.0 * xy, xx - yy)
	var mid := (xx + yy) * 0.5
	var spread := sqrt(maxf(mid * mid - (xx * yy - xy * xy), 0.0))
	var major := mid + spread
	var minor := maxf(mid - spread, 1e-6)
	return {
		"centroid": mean,
		"angle": fposmod(rad_to_deg(angle), 180.0),
		"elongation": sqrt(major / minor),
	}

static func _sample(dist: PackedFloat64Array, w: int, h: int, at: Vector2) -> float:
	var x := clampi(int(floorf(at.x)), 0, w - 1)
	var y := clampi(int(floorf(at.y)), 0, h - 1)
	return dist[y * w + x]

## Exact squared Euclidean distance transform (Felzenszwalb & Huttenlocher), one pass down the
## columns and one along the rows. 0 on an art cell.
static func _edt(mask: PackedByteArray, w: int, h: int) -> PackedFloat64Array:
	const FAR := 1e9
	var f := PackedFloat64Array()
	f.resize(w * h)
	for i in w * h:
		f[i] = 0.0 if mask[i] != 0 else FAR
	var line := PackedFloat64Array()
	line.resize(h)
	for x in w:
		for y in h:
			line[y] = f[y * w + x]
		var d := _edt_1d(line, h)
		for y in h:
			f[y * w + x] = d[y]
	line.resize(w)
	for y in h:
		for x in w:
			line[x] = f[y * w + x]
		var d := _edt_1d(line, w)
		for x in w:
			f[y * w + x] = d[x]
	return f

static func _edt_1d(f: PackedFloat64Array, n: int) -> PackedFloat64Array:
	var d := PackedFloat64Array()
	d.resize(n)
	var v := PackedInt32Array()
	v.resize(n)
	var z := PackedFloat64Array()
	z.resize(n + 1)
	var k := 0
	v[0] = 0
	z[0] = -INF
	z[1] = INF
	for q in range(1, n):
		var s := ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2.0 * q - 2.0 * v[k])
		while s <= z[k]:
			k -= 1
			s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2.0 * q - 2.0 * v[k])
		k += 1
		v[k] = q
		z[k] = s
		z[k + 1] = INF
	k = 0
	for q in n:
		while z[k + 1] < q:
			k += 1
		d[q] = (q - v[k]) * (q - v[k]) + f[v[k]]
	return d

## A picture to author against: the sprite at `zoom` screen pixels per world pixel in its own
## colours, the shapes' outline over it in magenta, any shape area off the picture filled pink,
## a grid every 4 art pixels with the origin lines black, the grip in blue and the centre of
## mass in yellow. Coordinates read off it are art pixels from the sprite's centre — the seed
## tables' space.
static func overlay(body: Node, zoom: int = 4) -> Image:
	var grid := rasterise(body)
	if grid.is_empty():
		return null
	var w: int = grid["w"]
	var h: int = grid["h"]
	var origin: Vector2 = grid["origin"]
	var art: PackedByteArray = grid["art"]
	var solid: PackedByteArray = grid["solid"]
	var colours := _colours(body, grid)
	var image := Image.create_empty(w * zoom, h * zoom, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.93, 0.93, 0.9))
	for y in h:
		for x in w:
			var i := y * w + x
			var c: Color = colours[i]
			if solid[i] != 0 and art[i] == 0:
				c = Color(1.0, 0.6, 0.6)
			image.fill_rect(Rect2i(x * zoom, y * zoom, zoom, zoom), c)
	for y in h:
		for x in w:
			var i := y * w + x
			if solid[i] == 0:
				continue
			var edge := x == 0 or y == 0 or x == w - 1 or y == h - 1 \
				or solid[i - 1] == 0 or solid[i + 1] == 0 or solid[i - w] == 0 or solid[i + w] == 0
			if edge:
				image.fill_rect(Rect2i(x * zoom, y * zoom, zoom, zoom), Color(0.9, 0.0, 0.9))
	# Grid lines every 4 art pixels (8 world), origin darker.
	for x in w:
		var wx := int(origin.x) + x
		if posmod(wx, 8) == 0:
			var shade := Color(0, 0, 0, 1) if wx == 0 else Color(0.6, 0.6, 0.65)
			image.fill_rect(Rect2i(x * zoom, 0, 1, h * zoom), shade)
	for y in h:
		var wy := int(origin.y) + y
		if posmod(wy, 8) == 0:
			var shade := Color(0, 0, 0, 1) if wy == 0 else Color(0.6, 0.6, 0.65)
			image.fill_rect(Rect2i(0, y * zoom, w * zoom, 1), shade)
	var grip: Vector2 = body.get(&"grip_offset") if &"grip_offset" in body else Vector2.ZERO
	var com: Vector2 = (body as RigidBody2D).center_of_mass if body is RigidBody2D else Vector2.ZERO
	_mark(image, (grip - origin) * zoom, Color(0.1, 0.3, 1.0), zoom)
	_mark(image, (com - origin) * zoom, Color(1.0, 0.85, 0.0), zoom)
	return image

## The picture as opaque runs per art-pixel row, in art pixels from the body's origin — the
## numbers a seed table is written in. `y=-22: -13..-8 7..12` means art pixels -13 to -8 and 7
## to 12 are opaque on that row, inclusive. Read off the same mask `measure` uses, so for a
## turret that mirrors it is the part of the picture that is there in both facings.
static func runs(body: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var grid := rasterise(body)
	if grid.is_empty():
		return out
	var w: int = grid["w"]
	var h: int = grid["h"]
	var origin: Vector2 = grid["origin"]
	var art: PackedByteArray = grid["art"]
	var scale := 2
	for ay in range(int(floorf(origin.y / scale)), int(ceilf((origin.y + h) / scale))):
		var cy := ay * scale - int(origin.y)
		if cy < 0 or cy >= h:
			continue
		var line := ""
		var start := 0
		var inside := false
		for ax in range(int(floorf(origin.x / scale)), int(ceilf((origin.x + w) / scale)) + 1):
			var cx := ax * scale - int(origin.x)
			var on := cx >= 0 and cx < w and art[cy * w + cx] != 0
			if on and not inside:
				start = ax
				inside = true
			elif not on and inside:
				line += " %d..%d" % [start, ax - 1]
				inside = false
		if line != "":
			out.append("y=%d:%s" % [ay, line])
	return out

static func _colours(body: Node, grid: Dictionary) -> Array:
	var w: int = grid["w"]
	var h: int = grid["h"]
	var origin: Vector2 = grid["origin"]
	var out := []
	out.resize(w * h)
	var pictures: Array = []
	for sprite in sprites_of(body):
		var image := sprite.texture.get_image()
		if image.is_compressed():
			image.decompress()
		pictures.append({"image": image, "inverse": sprite.transform.affine_inverse(),
			"rect": sprite.get_rect()})
	for y in h:
		for x in w:
			var c := Color(0.93, 0.93, 0.9)
			var p := origin + Vector2(x + 0.5, y + 0.5)
			for picture in pictures:
				var q: Vector2 = (picture["inverse"] as Transform2D) * p
				var rect: Rect2 = picture["rect"]
				var image: Image = picture["image"]
				var px := int(floorf(q.x - rect.position.x))
				var py := int(floorf(q.y - rect.position.y))
				if px >= 0 and py >= 0 and px < image.get_width() and py < image.get_height():
					var texel := image.get_pixel(px, py)
					if texel.a >= ALPHA_FLOOR:
						c = Color(texel.r, texel.g, texel.b, 1.0)
						break
			out[y * w + x] = c
	return out

static func _mark(image: Image, at: Vector2, colour: Color, zoom: int) -> void:
	var r := zoom * 3
	var cx := int(at.x)
	var cy := int(at.y)
	image.fill_rect(Rect2i(cx - r, cy - 1, r * 2 + 1, 3).intersection(
		Rect2i(Vector2i.ZERO, image.get_size())), colour)
	image.fill_rect(Rect2i(cx - 1, cy - r, 3, r * 2 + 1).intersection(
		Rect2i(Vector2i.ZERO, image.get_size())), colour)
