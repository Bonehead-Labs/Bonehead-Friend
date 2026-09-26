extends RefCounted

## The Wrap's catch ("GOTCHA!"): a chain cinched round his middle. It whips round him from the side
## the flail is on, link by link, the back of the loop behind him and the front across him; it bites
## as it closes, with squeeze marks at his sides; and it is locked at that side, where the chain runs
## off to the head, with tension lines pulled out along the run. Then the links draw in to nothing and
## leave the chain the hold draws (`TetherAbility.Chain`) where they were.
##
## **Why links and a lock.** The first version was a steel ellipse wider than him, spinning as it
## closed: a hula hoop. What says "chain" at this size is the alternation — a link seen face on (a
## ring with a hole) and the next edge on (a bar) — spaced evenly along the loop, not bunched where
## it turns. What says "round him, holding him" is that the loop is fastened somewhere and pulled from
## there: a padlock hanging off it, the one clasp that reads at twelve pixels. The loop is his waist's
## width, where the hold's chain goes round him, and it turns only as he does.

const Piece := preload("res://Scripts/Bodies/Abilities/Shapes/kit/fx_piece.gd")

## Where the hold's chain goes round him, in his own frame (`TetherAbility._update_chain`): the
## catch closes onto it rather than somewhere of its own.
const WAIST := Vector2(0.0, 30.0)

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var rect := Piece.him_rect(ability, at)
	var him: Buddy = ability.buddy() if ability else null
	var head := ability.com_world() if ability and is_instance_valid(ability.body) \
		else rect.get_center() + Vector2(-120.0, -40.0)
	for front in [false, true]:
		var loop := Piece.take(afx, "WrapLoopFront" if front else "WrapLoopBack", Loop, 1) as Loop
		if loop == null:
			continue
		loop.front = front
		loop.half_width = rect.size.x * 0.5
		loop.head = head
		loop.fire(him.global_transform * WAIST if him else rect.get_center() + Vector2(0.0, 26.0),
			Loop.LIFE, size, colour)
		loop.ride(him)

class Loop extends Piece:
	const LIFE := 0.8
	## Whipping round him, link by link, from wide to tight.
	const WHIP_T := 0.13
	## The bite: it closes a few pixels past his waist and springs back.
	const BITE_T := 0.22
	## The links draw in to nothing from here, the lock last.
	const LEAVE_FROM := 0.55
	## The hold's chain: half his width and four pixels, and eight deep.
	const TIGHT := 4.0
	const DEEP := 8.0
	## From one link to the next along the loop: a ring face on, then a bar edge on.
	const PITCH := 8.0
	## Samples per half loop when walking it by length.
	const WALK := 40

	var front := true
	var half_width := 24.0
	## Where the flail's head is: the lock is on this side, and the tension runs toward it.
	var head := Vector2.ZERO
	## Him, turned with (the kit's `follow` only moves a piece, and this loop turns as he does).
	var _rider: WeakRef
	## Where along the loop the lock is, radians: 0 is his right, PI his left, PI/2 in front of him.
	var _clasp := 0.0

	func fire(at: Vector2, seconds: float, amount: float, tint: Color) -> void:
		super.fire(at, seconds, amount, tint)
		z_index = 0 if front else -41
		rotation = 0.0
		_rider = null
		_aim_clasp()

	## Rides him turned with him, as the hold's chain does, so the two are one loop as he tumbles.
	func ride(him: Node2D) -> void:
		_rider = weakref(him) if him else null
		_step(0.0)
		_aim_clasp()

	func _step(_delta: float) -> void:
		var him := _rider.get_ref() as Node2D if _rider else null
		if him == null or not is_instance_valid(him) or not him.is_inside_tree():
			return
		global_position = (him.global_transform * WAIST).round()
		rotation = him.global_rotation

	## The side of him the chain comes from, kept to the front half so the lock is seen: a head above
	## him locks it at his side, not behind his back.
	func _aim_clasp() -> void:
		var toward := (head - global_position).rotated(-rotation)
		var a := atan2(toward.y / DEEP, toward.x / maxf(half_width + TIGHT, 1.0))
		if a < 0.0:
			a = 0.0 if a > -PI * 0.5 else PI
		_clasp = clampf(a, 0.3, PI - 0.3)

	func _radii() -> Vector2:
		var tight := Vector2(half_width + TIGHT, DEEP)
		if t < WHIP_T:
			var k := ease_out(k_of(0.0, WHIP_T))
			return Vector2(lerpf(half_width * 2.0, tight.x, k), lerpf(18.0, DEEP, k))
		# The bite: in by three pixels and back, once.
		var bite := sin(PI * k_of(WHIP_T, BITE_T)) * 3.0
		return tight - Vector2(bite, bite * 0.3)

	func _point(a: float, r: Vector2) -> Vector2:
		return Vector2(cos(a) * r.x, sin(a) * r.y)

	func _along(a: float, r: Vector2) -> Vector2:
		return Vector2(-sin(a) * r.x, cos(a) * r.y).normalized()

	## The angle of every link from the lock, `way` round (+1 or -1), one `PITCH` apart along the
	## loop and no further than `reach` px: evenly spaced by length, so they do not bunch at his sides
	## where the loop turns.
	func _links(r: Vector2, way: float, reach: float) -> PackedFloat32Array:
		var out := PackedFloat32Array()
		var a := _clasp
		var p := _point(a, r)
		var run := 0.0
		var next := PITCH
		var da := way * PI / float(WALK)
		for i in WALK:
			var b := a + da
			var q := _point(b, r)
			var seg := p.distance_to(q)
			while seg > 0.0 and run + seg >= next and next <= reach:
				out.append(lerpf(a, b, (next - run) / seg))
				next += PITCH
			run += seg
			a = b
			p = q
		return out

	func _draw() -> void:
		var shrink := 1.0 - ease_out(k_of(LEAVE_FROM, LIFE))
		if shrink <= 0.05:
			return
		var r := _radii()
		# How far round him it has whipped yet, both ways at once from the lock.
		var half := PI * (3.0 * (r.x + r.y) - sqrt((3.0 * r.x + r.y) * (r.x + 3.0 * r.y))) * 0.5
		var reach := half * ease_out(k_of(0.0, WHIP_T)) - PITCH * 0.5
		var ring := colour.lightened(0.35)
		var bar := colour.darkened(0.1)
		if not front:
			ring = colour.darkened(0.2)
			bar = colour.darkened(0.45)
		for way in [-1.0, 1.0]:
			var n := 0
			for a in _links(r, way, reach):
				n += 1
				if (sin(a) >= 0.0) != front:
					continue
				_link(_point(a, r), _along(a, r), n % 2 == 0, ring, bar, shrink)
		if not front:
			return
		var at := _point(_clasp, r)
		# Tension: the chain pulled taut toward the head, and his sides squeezed as it bites.
		var pull := k_of(WHIP_T * 0.7, WHIP_T) * (1.0 - k_of(0.26, 0.45))
		if pull > 0.05:
			var run := (head - global_position).rotated(-rotation) - at
			var dir := run.normalized() if run.length() > 1.0 else Vector2(signf(at.x), 0.0)
			var across := dir.orthogonal()
			for s in [-1.0, 1.0]:
				var start := at + dir * 9.0 + across * float(s) * 7.0
				ink_line(start, start + dir * (6.0 + 12.0 * pull), colour.lightened(0.6), 2.0)
		if t > WHIP_T * 0.8 and t < BITE_T + 0.12:
			for s in [-1.0, 1.0]:
				var side := Vector2(float(s) * (r.x + 7.0), 0.0)
				for k in 3:
					var d := Vector2(float(s), (float(k) - 1.0) * 0.8).normalized()
					ink_line(side + d * 2.0, side + d * 9.0, colour.lightened(0.6), 2.0)
		# Snapped shut as the two ends meet: in a size over, then settled.
		if t >= WHIP_T * 0.85:
			_lock(at, shrink * (1.3 if t < WHIP_T + 0.05 else 1.0))

	## One link at `p` along `along`: face on, a ring with a hole; edge on, a bar. `k` draws it in.
	func _link(p: Vector2, along: Vector2, face_on: bool, ring: Color, bar: Color, k: float) -> void:
		var across := along.orthogonal()
		if face_on:
			var l := 5.0 * k
			var w := 3.5 * k
			if l < 2.0:
				return
			var points := PackedVector2Array()
			for q in [p - along * l, p - along * (l - 1.5) - across * w, p + along * (l - 1.5) - across * w,
					p + along * l, p + along * (l - 1.5) + across * w, p - along * (l - 1.5) + across * w,
					p - along * l]:
				points.append((q as Vector2).round())
			draw_polyline(points, OUTLINE, 4.0)
			draw_polyline(points, ring, 2.0)
		else:
			var l := 4.0 * k
			if l < 1.0:
				return
			ink_line(p - along * l, p + along * l, bar, 3.0)

	## A padlock hanging off the loop where its ends meet: a shackle through the chain and a body
	## under it with a keyhole, upright in his frame.
	func _lock(at: Vector2, k: float) -> void:
		if k < 0.2:
			return
		var s := k
		var shackle := at + Vector2(0.0, 1.0)
		ink_arc(shackle, 4.5 * s, PI, TAU, colour.lightened(0.55), 2.0)
		var box := Rect2(at + Vector2(-6.0, 3.0) * s, Vector2(12.0, 9.0) * s)
		box = Rect2(box.position.round(), box.size.round())
		draw_rect(box.grow(1.0), OUTLINE)
		draw_rect(box, colour.lightened(0.25))
		draw_rect(Rect2(box.position, Vector2(box.size.x, 1.0)), colour.lightened(0.7))
		if box.size.x >= 8.0:
			var hole := (box.get_center() - Vector2(1.0, 1.0)).round()
			draw_rect(Rect2(hole, Vector2(2.0, 2.0)), OUTLINE)
			draw_rect(Rect2(hole + Vector2(0.5, 2.0), Vector2(1.0, 2.0)), OUTLINE)
