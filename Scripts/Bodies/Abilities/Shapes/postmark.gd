extends RefCounted

## The letter opener's DELIVERED! (Special Delivery): signed for. An envelope pops out of the hit,
## addressed and stamped, flips over in the air as it rises and comes open with a love letter in it,
## and a postbox-red postmark — a ring and its wavy cancellation lines — slams down beside his head.
##
## The only payoff that is post. Red on cream with a dark rim, so it reads on bone, on the desk and on
## the chroma green.

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var drawing := PayoffSketch.take(afx, "Postmark", Drawing, 2) as Drawing
	drawing.setup(at, size, colour, ability)

const FRONT := [
	"CCCCCCCCCCCCC",
	"CCCCCCCCCxxxC",
	"CCCCCCCCCxwxC",
	"CCCCCCCCCxxxC",
	"CCCkkkkkCCCCC",
	"CCCCCCCCCCCCC",
	"CCCkkkkkkkCCC",
	"CCCCCCCCCCCCC",
	"CCCCCCCCCCCCC",
]

const OPEN := [
	"......c......",
	".....cCc.....",
	"....cCCCc....",
	"...cCCCCCc...",
	"..cCWWWWWCc..",
	".cCWxWWWxWCc.",
	"cCWxxxWxxxWCc",
	"CCWxxxxxxxWCC",
	"CccWxxxxxWccC",
	"CCCcWxxxWcCCC",
	"CCCCcWxWcCCCC",
	"CCCCCcccCCCCC",
	"CCCCCCCCCCCCC",
]

class Drawing extends PayoffSketch:
	var _back := 1.0
	var _stamp := Vector2.ZERO
	var _front: Texture2D
	var _open: Texture2D

	func setup(at: Vector2, s: float, tint: Color, ability: WeaponAbility) -> void:
		size = s
		colour = tint
		var delivery := ability as DeliveryAbility
		var heading := delivery.launch_heading if delivery else Vector2.RIGHT
		_back = -1.0 if heading.x >= 0.0 else 1.0
		_front = plot("front", FRONT, tint)
		_open = plot("open", OPEN, tint)
		fire(at, 0.95)
		var him := ability.buddy() if ability else null
		if him:
			var rect := him.get_interaction_rect()
			_stamp = Vector2(rect.get_center().x + _back * (rect.size.x * 0.5 + 30.0), rect.position.y + 30.0) \
				- global_position
		else:
			_stamp = Vector2(_back * 60.0, -30.0)

	func _paint(_k: float) -> void:
		_postmark()
		_envelope()

	## Out of the hit, up and back the way it came, flipping over to come open.
	func _envelope() -> void:
		var t := minf(age, 0.95)
		var p := Vector2(_back * 110.0 * t, -230.0 * t + 150.0 * t * t)
		var grow := overshoot(span(0.0, 0.1))
		var shrink := 1.0 - span(0.8, 0.95)
		var scale := (1.4 + 0.4 * size) * grow * shrink
		if age < 0.14:
			picture(_front, p, scale, -0.2 * _back)
		elif age < 0.2:
			# Edge on, half way through the flip.
			var w := 13.0 * ART * scale * 0.5
			box(Rect2(p - Vector2(w, 2.0), Vector2(w * 2.0, 4.0)), Color("fcfcee"))
		else:
			picture(_open, p, scale, 0.15 * _back * sin(age * 12.0))

	## The postmark: a ring with its date bar, and three wavy lines, slammed down beside his head.
	func _postmark() -> void:
		var land := span(0.08, 0.16)
		if land <= 0.0:
			return
		var gone := span(0.78, 0.95)
		if gone >= 1.0:
			return
		var slam := lerpf(1.7, 1.0, land) * (1.0 - gone) * (0.85 + 0.3 * size)
		var r := 18.0 * slam
		if r < 3.0:
			return
		var c := _stamp
		arc(c, r, 0.0, TAU, colour, 3.0)
		# The date, as two short lines of type inside the ring.
		for j in 2:
			var y := (float(j) - 0.5) * 7.0 * slam
			var w := r * (0.5 if j == 0 else 0.34)
			draw_rect(Rect2((c + Vector2(-w, y - 1.5)).round(), Vector2(w * 2.0, 3.0).round()), colour)
		for j in 3:
			var y := (float(j) - 1.0) * 8.0 * slam
			var wave := PackedVector2Array()
			for m in 7:
				var x := r + 4.0 + float(m) * 5.0 * slam
				wave.append(c + Vector2(x * _back, y + sin(float(m) * 1.6) * 3.0 * slam))
			strokes(wave, colour, 3.0)
