extends RefCounted

## The Drive's payoff: the shot tracer a golf broadcast draws — the ball's whole flight from the
## tee to him, laid down at once in the club's blue and wiped away from the tee end — and a little
## flag on a pin popping up out of the desk at his feet, fluttering, over the cup: a hole in one.

const Piece := preload("res://Scripts/Bodies/Abilities/Shapes/kit/fx_piece.gd")

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var tracer := Piece.take(afx, "DriveTracer", Tracer) as Tracer
	var flag := Piece.take(afx, "DriveFlag", Flag) as Flag
	var rect := Piece.him_rect(ability, at)
	var tee := at + Vector2(-240.0, 0.0)
	var speed := 1100.0
	if ability:
		var from = ability.get("_ball_at")
		if from is Vector2 and (from as Vector2).is_finite() and from != Vector2.ZERO:
			tee = from
		var last = ability.get("last_speed")
		if last is float and float(last) > 1.0:
			speed = float(last)
	var side := 1.0 if at.x >= tee.x else -1.0
	if tracer:
		tracer.path = _flight(ability, tee, at, speed)
		tracer.fire(tee, Tracer.LIFE, size, colour)
	if flag:
		flag.side = side
		var foot := Vector2(rect.get_center().x + side * (rect.size.x * 0.5 + 22.0), rect.end.y)
		flag.fire(foot, Flag.LIFE, size, colour)

## The ball's flight from the tee until it reached him, relative to the tee: the club's own launch
## arc when it can say, a straight line when it cannot.
static func _flight(ability: WeaponAbility, tee: Vector2, to: Vector2, speed: float) -> PackedVector2Array:
	var points := PackedVector2Array([Vector2.ZERO])
	var gravity := float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))
	if ability and ability.has_method("launch_velocity"):
		var v: Vector2 = ability.call("launch_velocity", tee, speed)
		var dx := to.x - tee.x
		if absf(v.x) > 1.0 and signf(v.x) == signf(dx):
			var total := absf(dx / v.x)
			var steps := clampi(int(total * 60.0), 4, 90)
			for i in range(1, steps + 1):
				var s := total * float(i) / float(steps)
				points.append(v * s + Vector2(0.0, gravity) * (0.5 * s * s))
			return points
	points.append(to - tee)
	return points

class Tracer extends Piece:
	const LIFE := 0.6
	const WIPE_FROM := 0.18
	var path := PackedVector2Array()

	func _ready() -> void:
		super._ready()
		# Behind him and the club: the flight line goes into him, not across him.
		z_index = -41

	func _draw() -> void:
		if path.size() < 2:
			return
		var from := int(float(path.size() - 1) * ease_out(k_of(WIPE_FROM, LIFE)))
		var shown := path.slice(from)
		if shown.size() >= 2:
			ink_polyline(shown, colour, 4.0)
			# The ball's head end, brighter.
			var n := shown.size()
			ink_line(shown[maxi(n - 4, 0)], shown[n - 1], colour.lightened(0.5), 4.0)

class Flag extends Piece:
	const LIFE := 1.15
	const RISE_T := 0.14
	const POLE := 72.0
	const WAVE := [
		["rrrrr.....", "rrrrrrrr..", "rrrrrrrrrr", "rrrrrrrrr.", "rrrrrr....", "rrrr......"],
		["rrrr......", "rrrrrr....", "rrrrrrrrr.", "rrrrrrrrrr", "rrrrrrr...", "rrrrr....."],
	]
	var side := 1.0
	var _flags: Array[Texture2D] = []

	func fire(at: Vector2, seconds: float, amount: float, tint: Color) -> void:
		super.fire(at, seconds, amount, tint)
		if _flags.is_empty():
			for grid in WAVE:
				_flags.append(Piece.plot(grid, {"r": Color("e8402e")}))

	func _draw() -> void:
		var up := ease_out(k_of(0.0, RISE_T)) * (1.0 - k_of(LIFE - 0.18, LIFE))
		# The cup: a dark oval in the desk the pin stands in.
		var cup := 16.0 * minf(up * 3.0, 1.0)
		if cup >= 3.0:
			var oval := PackedVector2Array()
			for i in 12:
				var a := TAU * float(i) / 12.0
				oval.append(Vector2(cos(a) * cup, sin(a) * 3.0 - 1.0))
			ink_poly(oval, Color("2a2622"))
		var height := roundf(POLE * lerpf(0.8, 1.1, size) * up)
		if height < 4.0:
			return
		ink_line(Vector2(0.0, -2.0), Vector2(0.0, -height), Color("e8e4dc"), 3.0)
		var flag := _flags[int(t * 9.0) % 2]
		var w := flag.get_size().x * ART
		var h := flag.get_size().y * ART
		# The pennant flies away from where the ball came from.
		var at := Vector2(side * (w * 0.5 - 1.0), -height + h * 0.5)
		draw_set_transform(at.round(), 0.0, Vector2(ART * side, ART))
		draw_texture(flag, -flag.get_size() * 0.5)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
