extends RefCounted

## The monitor's REBOOT! (Blue Screen's dump): he comes back on like an old screen. A bright line cuts
## across him, opens top and bottom into a blue frame round him, a boot bar under his feet fills in
## blocks, and a power symbol pops up beside his head. Then the frame's corners fly off.
##
## A line across him and a frame round him, never a fill over him: the dump is the moment every
## stored hit lands, and the player has to see him take it.

const LIGHT := Color("cfe9ff")
const INK := Color("f4f1e6")

const POWER := [
	"....x....",
	"..x.x.x..",
	".x..x..x.",
	"x...x...x",
	"x...x...x",
	"x.......x",
	"x.......x",
	".x.....x.",
	"..xxxxx..",
]

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var drawing := PayoffSketch.take(afx, "Reboot", Drawing, 1) as Drawing
	drawing.setup(at, size, colour, ability)

class Drawing extends PayoffSketch:
	var _half := Vector2(40, 56)
	var _side := 1.0
	var _floor := 0.0
	var _power: Texture2D

	func setup(at: Vector2, s: float, tint: Color, ability: WeaponAbility) -> void:
		size = s
		colour = tint
		_power = plot("power", POWER, LIGHT)
		var him := ability.buddy() if ability else null
		var rect := him.get_interaction_rect() if him else Rect2(at - Vector2(24, 44), Vector2(48, 88))
		var monitor := ability.body.global_position if ability and ability.body else at - Vector2(100, 0)
		_side = 1.0 if rect.get_center().x >= monitor.x else -1.0
		fire(rect.get_center(), 0.75)
		_half = rect.size * 0.5 + Vector2(16.0, 12.0) * (0.8 + 0.4 * s)
		_floor = rect.end.y - global_position.y

	func _paint(_k: float) -> void:
		_scan()
		_bar()
		_symbol()

	## The line, then the frame opening out of it, then its corners flying off.
	func _scan() -> void:
		var line_in := ease_out(span(0.0, 0.06))
		if age < 0.07:
			var w := _half.x * 1.5 * line_in
			line(Vector2(-w, 0.0), Vector2(w, 0.0), LIGHT, 3.0)
			return
		var open := ease_out(span(0.07, 0.17))
		var fly := span(0.4, 0.6)
		if fly >= 1.0:
			return
		var h := _half.y * open
		var w := _half.x
		if fly <= 0.0:
			strokes(PackedVector2Array([Vector2(-w, -h), Vector2(w, -h), Vector2(w, h), Vector2(-w, h),
				Vector2(-w, -h)]), colour, 3.0)
			if open < 1.0:
				line(Vector2(-w, 0.0), Vector2(w, 0.0), LIGHT, 3.0)
			return
		# The corners, flying out and shrinking.
		var out := 1.0 + fly * 0.6
		var arm := 14.0 * (1.0 - fly)
		if arm < 3.0:
			return
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var c := Vector2(sx * w, sy * h) * out
				strokes(PackedVector2Array([c - Vector2(sx * arm, 0.0), c, c - Vector2(0.0, sy * arm)]), colour, 3.0)

	## The boot bar under his feet, filling a block at a time.
	func _bar() -> void:
		var fill := span(0.1, 0.34)
		var gone := span(0.55, 0.7)
		if fill <= 0.0 or gone >= 1.0:
			return
		var w := 64.0 * (1.0 - gone)
		if w < 8.0:
			return
		var r := Rect2(Vector2(-w * 0.5, _floor + 10.0), Vector2(w, 10.0))
		box(r, Color("0f2a6b"))
		var blocks := int(fill * 8.0)
		var step := (w - 4.0) / 8.0
		for i in blocks:
			draw_rect(Rect2(r.position + Vector2(2.0 + step * float(i), 2.0), Vector2(step - 2.0, 6.0)).abs(), colour.lightened(0.25))

	## The power symbol beside his head: popped in, and gone by scale.
	func _symbol() -> void:
		var k := span(0.12, 0.2)
		if k <= 0.0:
			return
		var scale := overshoot(k) * (1.0 - span(0.58, 0.75)) * (2.0 + 0.4 * size)
		picture(_power, Vector2(_side * (_half.x + 30.0), -_half.y + 20.0), scale)
