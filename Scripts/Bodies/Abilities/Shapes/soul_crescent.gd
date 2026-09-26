extends RefCounted

## The scythe's WOOOO! (Soul Reap): the ghost of the blade goes through him as a pale crescent moon,
## wisps streaming off its back, and a little ghost — his soul, O-mouthed — floats up out of his head
## and away on the side the blade went, wobbling as it goes.
##
## The katana's cut is a line and the greatsword's echoes are the sword; this is the only payoff that
## is a moon, and the only one with a face.

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var drawing := PayoffSketch.take(afx, "SoulCrescent", Drawing, 2) as Drawing
	drawing.setup(at, size, colour, ability)

const GHOST := [
	"...xxxxx...",
	"..xCCCCCx..",
	".xCCCCCCCx.",
	".xCKKCKKCx.",
	".xCKKCKKCx.",
	".xCCCCCCCx.",
	".xCCKKKCCx.",
	".xCCKdKCCx.",
	".xCCKKKCCx.",
	".xCCCCCCCx.",
	".xCCxCxCCx.",
	"..x.x.x.x..",
]

class Drawing extends PayoffSketch:
	var _heading := Vector2.RIGHT
	var _head := Vector2.ZERO
	var _ghost: Texture2D

	func setup(at: Vector2, s: float, tint: Color, ability: WeaponAbility) -> void:
		size = s
		colour = tint
		var soul := ability as SoulReapAbility
		_heading = soul.last_heading if soul and soul.last_heading.length_squared() > 0.5 else Vector2.RIGHT
		_ghost = plot("ghost", GHOST, tint)
		fire(at, 0.95)
		var him := ability.buddy() if ability else null
		if him:
			var rect := him.get_interaction_rect()
			_head = Vector2(rect.get_center().x, rect.position.y + 14.0) - global_position
		else:
			_head = Vector2(0.0, -40.0)

	func _paint(_k: float) -> void:
		_moon()
		_soul()

	## The ghost blade: a crescent, convex side first, passing through him along the reap.
	func _moon() -> void:
		var k := span(0.0, 0.3)
		if k >= 1.0:
			return
		var along := _heading
		var across := along.orthogonal()
		var centre := along * lerpf(-70.0, 130.0 + 40.0 * size, ease_out(k))
		var r := (44.0 + 20.0 * size) * (1.0 - 0.5 * k * k)
		var thick := 16.0 * (1.0 - 0.4 * k)
		var points := PackedVector2Array()
		var n := 14
		for i in n + 1:
			var a := lerpf(-1.25, 1.25, float(i) / float(n))
			points.append(centre + (along * cos(a) + across * sin(a)) * r)
		for i in range(n - 1, 0, -1):
			var t := float(i) / float(n)
			var a := lerpf(-1.25, 1.25, t)
			var inner := r - thick * sin(PI * t)
			points.append(centre - along * thick * 0.5 * sin(PI * t) + (along * cos(a) + across * sin(a)) * inner)
		# Its tail, first, behind it: a ghost's wavering trail off the back of the moon, narrowing.
		var tail := PackedVector2Array()
		var n_tail := 7
		var reach := 60.0 + 30.0 * size
		for side in [1.0, -1.0]:
			for m in n_tail:
				var f := float(m) / float(n_tail - 1) if side > 0.0 else 1.0 - float(m) / float(n_tail - 1)
				var sway := sin(age * 28.0 + f * 5.0) * 7.0 * f
				var half := r * 0.4 * (1.0 - f) + 1.5
				tail.append(centre - along * (thick * 0.5 + f * reach) + across * (sway + side * half))
		shape(tail, colour)
		shape(points, colour.lightened(0.55))
		# Its edge, lit.
		var edge := PackedVector2Array()
		for i in range(2, n - 1):
			var a := lerpf(-1.25, 1.25, float(i) / float(n))
			edge.append(centre + (along * cos(a) + across * sin(a)) * (r - 3.0))
		draw_polyline(edge, Color.WHITE, 2.0)

	## His soul: up out of his skull on the side the blade went, wobbling, and gone by scale.
	func _soul() -> void:
		var k := span(0.1, 0.95)
		if k <= 0.0 or k >= 1.0:
			return
		# Out to the side the blade went and up, clear of the badge and the words over his skull.
		var side := 1.0 if _heading.x >= 0.0 else -1.0
		var drift := Vector2(side * (34.0 + 70.0 * ease_out(k)), -10.0 - 60.0 * ease_out(k))
		var wobble := Vector2(sin(age * 16.0) * 5.0, 0.0)
		var grow := overshoot(span(0.1, 0.22))
		var shrink := 1.0 - span(0.8, 0.95)
		var scale := 2.0 * grow * shrink
		picture(_ghost, _head + drift + wobble, scale, 0.0, _heading.x < 0.0)
