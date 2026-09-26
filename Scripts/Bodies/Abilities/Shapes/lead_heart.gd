extends RefCounted

## The Lead Heart's payoff, on every blow: a heartbeat. Two heart-shaped shockwaves thump out of
## him, lub and dub, behind him so they show only round his outline; and where the leaden head
## landed, the bone cracks — short dark-red fractures splitting out from the dent.

const Piece := preload("res://Scripts/Bodies/Abilities/Shapes/kit/fx_piece.gd")

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var beat := Piece.take(afx, "LeadHeartBeat", Beat) as Beat
	var dent := Piece.take(afx, "LeadHeartDent", Dent) as Dent
	var rect := Piece.him_rect(ability, at)
	var him: Buddy = ability.buddy() if ability else null
	if beat:
		beat.base = rect.size.x * 0.5
		beat.fire(rect.get_center(), Beat.LIFE, size, colour)
		if him:
			beat.follow(him)
	if dent:
		var centre := rect.get_center()
		dent.inward = (centre - at).normalized() if centre.distance_squared_to(at) > 1.0 else Vector2.RIGHT
		dent.fire(at, Dent.LIFE, size, colour)

class Beat extends Piece:
	const LIFE := 0.62
	const DUB := 0.2
	const BEAT_T := 0.4
	var base := 24.0
	var _heart := PackedVector2Array()

	func _ready() -> void:
		super._ready()
		z_index = -41
		# A heart, 32 units across, point down.
		for i in 40:
			var a := TAU * float(i) / 40.0
			var s := sin(a)
			_heart.append(Vector2(16.0 * s * s * s,
				-(13.0 * cos(a) - 5.0 * cos(2.0 * a) - 2.0 * cos(3.0 * a) - cos(4.0 * a)) + 2.0) / 16.0)

	func _draw() -> void:
		for i in 2:
			var k := k_of(DUB * float(i), DUB * float(i) + BEAT_T)
			if k <= 0.0 or k >= 1.0:
				continue
			var reach := lerpf(base + 10.0, base + lerpf(70.0, 120.0, size) * (1.0 - 0.3 * float(i)), ease_out(k))
			var w := roundf(lerpf(8.0 - 2.0 * float(i), 2.0, k))
			var points := PackedVector2Array()
			for p in _heart:
				points.append(p * reach)
			points.append(points[0])
			ink_polyline(points, colour if i == 0 else colour.lightened(0.3), w)

class Dent extends Piece:
	const LIFE := 0.4
	const DARK := Color("7a1a12")
	var inward := Vector2.RIGHT
	var _cracks: Array = []

	func fire(at: Vector2, seconds: float, amount: float, tint: Color) -> void:
		super.fire(at, seconds, amount, tint)
		_cracks.clear()
		for i in 5:
			var d := inward.rotated(rng.randf_range(-1.3, 1.3))
			var points := PackedVector2Array([Vector2.ZERO])
			var p := Vector2.ZERO
			var legs := 2 + rng.randi() % 2
			for leg in legs:
				p += d.rotated(rng.randf_range(-0.6, 0.6)) * rng.randf_range(6.0, 11.0) * lerpf(0.8, 1.2, amount)
				points.append(p)
			_cracks.append(points)

	func _draw() -> void:
		var grow := ease_out(k_of(0.0, 0.06)) * (1.0 - k_of(LIFE * 0.6, LIFE))
		if grow <= 0.05:
			return
		for points in _cracks:
			var shown := PackedVector2Array()
			for p in points:
				shown.append(p * grow)
			ink_polyline(shown, DARK, 2.0)
		ink_star(Vector2.ZERO, 6, 9.0 * grow + 2.0, 3.0, colour.lightened(0.2))
