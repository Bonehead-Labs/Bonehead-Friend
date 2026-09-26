extends RefCounted

## The monitor's freeze (Blue Screen): he has crashed. For two frames a blue-screen panel flickers
## straight over his face — the moment the picture of him stops — and then it jumps out beside his
## head as an error window, title bar, frown and all, glitching sideways now and then while he stands
## there frozen; it goes the way a CRT does, squeezed to a line.
##
## The one payoff allowed over his face, and only for those two frames. The panel is drawn, not
## plotted, at the art's two-pixel grain, in the monitor's own blue.

const BLUE := Color("1f56d8")
const INK := Color("f4f1e6")
const BAR := Color("0f2a6b")

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var drawing := PayoffSketch.take(afx, "Bsod", Drawing, 1) as Drawing
	drawing.setup(at, size, colour, ability)

class Drawing extends PayoffSketch:
	const FLICKER := 0.05
	var _face := Vector2.ZERO
	var _beside := Vector2.ZERO

	func setup(at: Vector2, s: float, tint: Color, ability: WeaponAbility) -> void:
		size = s
		colour = tint
		fire(at, 1.15)
		var him := ability.buddy() if ability else null
		var monitor := ability.body.global_position if ability and ability.body else at - Vector2(100, 0)
		if him:
			var rect := him.get_interaction_rect()
			var away := 1.0 if rect.get_center().x >= monitor.x else -1.0
			_face = Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.3) - global_position
			_beside = Vector2(rect.get_center().x + away * (rect.size.x * 0.5 + 64.0), rect.position.y + 18.0) \
				- global_position
		else:
			_face = Vector2.ZERO
			_beside = Vector2(70.0, -30.0)

	func _paint(_k: float) -> void:
		if age < FLICKER:
			# Over his face, on, off, on: the frame freezing.
			if int(age * 60.0) % 2 == 0:
				_panel(_face, 1.0, 0.0)
			return
		var squeeze := span(1.0, 1.15)
		var glitch := 3.0 if int(age * 30.0) % 7 == 0 else 0.0
		var pop := overshoot(span(FLICKER, FLICKER + 0.08))
		_panel(_beside + Vector2(glitch, 0.0), pop * (1.3 + 0.3 * size), squeeze)

	## The error window at `at`: `scale` of its size, `squeeze` 0..1 of the way to a line.
	func _panel(at: Vector2, scale: float, squeeze: float) -> void:
		# Screen pixels to one of its art pixels: a whole number, so it grows and shrinks in steps.
		var u := roundf(ART * scale)
		if u < 1.0:
			return
		var w := 34.0 * u
		var h := roundf(24.0 * u * (1.0 - squeeze))
		if h < 4.0:
			box(Rect2(at - Vector2(w * 0.5, 1.0), Vector2(w, 2.0)), INK)
			return
		var r := Rect2((at - Vector2(w, h) * 0.5).round(), Vector2(w, h))
		box(r, BLUE)
		if squeeze > 0.0 or u < 2.0:
			return
		var o := r.position
		# Title bar and its three dots.
		draw_rect(Rect2(o, Vector2(r.size.x, 3.0 * u)), BAR)
		for i in 3:
			draw_rect(Rect2(o + Vector2(r.size.x - (4.0 + 3.0 * float(i)) * u, u), Vector2(u, u)), INK)
		# ":(" — two dots and a bracket, big.
		var f := o + Vector2(3.0 * u, 6.0 * u)
		draw_rect(Rect2(f, Vector2(2.0, 2.0) * u), INK)
		draw_rect(Rect2(f + Vector2(0.0, 5.0 * u), Vector2(2.0, 2.0) * u), INK)
		draw_rect(Rect2(f + Vector2(5.0 * u, 0.0), Vector2(2.0, 2.0) * u), INK)
		draw_rect(Rect2(f + Vector2(4.0 * u, 2.0 * u), Vector2(2.0, 3.0) * u), INK)
		draw_rect(Rect2(f + Vector2(5.0 * u, 5.0 * u), Vector2(2.0, 2.0) * u), INK)
		# Three lines of text and a percentage.
		var lines := [14.0, 10.0, 12.0]
		for i in lines.size():
			draw_rect(Rect2(o + Vector2(11.0 * u, (6.0 + 2.0 * float(i)) * u), Vector2(float(lines[i]) * u, u)), INK)
		draw_rect(Rect2(o + Vector2(3.0 * u, 20.0 * u), Vector2(8.0 * u, u)), INK)
