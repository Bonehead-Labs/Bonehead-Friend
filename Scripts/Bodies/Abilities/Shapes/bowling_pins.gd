extends RefCounted

## The Strike's payoff (the bowling ball, D78): he is the pin that went, and ten more go with him.
##
## Ten white pins with red necks burst out from behind his legs — the rack he was standing in front
## of — thrown high and away down the lane the ball came along, most of them the way it was rolling
## and a few kicked back, turning end over end, clattering down, bouncing once and sliding to rest on
## their sides (knocked over, never standing) before they shrink away. Under them, three lane lines
## run in along the desk behind the ball to where it met him: the one ability that arrives along the
## floor, and the only payoff drawn on it. No ring and no starburst: nothing else in the game throws
## pins.

const Moment := preload("res://Scripts/Bodies/Abilities/Shapes/kit/moment.gd")
const NAME := "ShapeBowlingPins"
const PINS := 10

## A pin, standing: a round head, a narrow neck with two red stripes, a wide belly, a flat foot.
const PIN := [
	".WWW.",
	"WWWWc",
	"WWWWc",
	".WWc.",
	".RRR.",
	".WWc.",
	".RRR.",
	"WWWWc",
	"WWWWc",
	"WWWWc",
	"WWWcc",
	".Wcc.",
]

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	var pins := Moment.canvas(afx, NAME, Pins) as Pins
	pins.strike(at, size, colour, ability)

class Pins extends "res://Scripts/Bodies/Abilities/Shapes/kit/moment.gd":
	var _lane_from := Vector2.ZERO
	var _lane_to := Vector2.ZERO
	var _lane_at := -10.0
	var _colour := Color.WHITE

	## Behind him: the pins burst out from behind his legs rather than over him, and are only
	## seen once they are clear of him — the rack he was standing in front of.
	func _ready() -> void:
		super._ready()
		z_as_relative = false
		z_index = -1

	func strike(at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
		reserve(PINS)
		_colour = colour
		# Where it happened: at his feet, on the side the ball came from, rolling on the way it went.
		var feet := at + Vector2(0.0, 40.0)
		var side := 1.0
		var him := ability.buddy() if ability else null
		if him:
			var rect := him.get_interaction_rect()
			feet = Vector2(rect.get_center().x, rect.end.y)
			if ability.body:
				var v := ability.body.linear_velocity.x
				side = signf(v) if absf(v) > 5.0 else signf(rect.get_center().x - ability.com_world().x)
				if side == 0.0:
					side = 1.0
		var pin := picture("pin", PIN)
		var n := Moment.count(PINS)
		var k := lerpf(0.7, 1.0, clampf(size, 0.0, 1.0))
		for i in n:
			# A spread of throws: mostly forward and up, the last two kicked back.
			var back := i >= n - 2
			var angle := rng.randf_range(-PI * 0.42, -PI * 0.12)
			if back:
				angle = rng.randf_range(-PI * 0.4, -PI * 0.25)
			var dir := Vector2(cos(angle) * (-side if back else side), sin(angle))
			var speed := rng.randf_range(520.0, 860.0) * k
			var from := feet + Vector2(rng.randf_range(-18.0, 18.0), rng.randf_range(-40.0, -14.0))
			var bit := throw(pin, from, dir * speed, rng.randf_range(1.3, 1.7), 1300.0)
			bit.spin = rng.randf_range(9.0, 16.0) * (1.0 if dir.x >= 0.0 else -1.0)
			bit.turn = rng.randf_range(-0.3, 0.3)
			bit.floor_y = feet.y - 6.0
			bit.bounce = 0.35
			bit.lies = true
			bit.size = k
		# The lane: in along the desk from behind the ball to his feet.
		_lane_to = feet + Vector2(-side * 10.0, -3.0)
		_lane_from = _lane_to + Vector2(-side * 170.0 * k, 0.0)
		_lane_at = clock
		hold(0.3)

	func _draw_shape() -> void:
		var age := clock - _lane_at
		if age < 0.0 or age > 0.26:
			return
		# Three lines on the desk, drawing in toward him and gone.
		var k := age / 0.26
		for i in 3:
			var lift := Vector2(0.0, -8.0 * float(i))
			var from := _lane_from.lerp(_lane_to, clampf(k * 1.4 + 0.1 * float(i), 0.0, 1.0))
			var to := _lane_to + (_lane_from - _lane_to) * 0.12 * float(i)
			if (to - from).dot(_lane_to - _lane_from) <= 0.0:
				continue
			stroke(from + lift, to + lift, _colour, 3.0 - float(i) * 0.5)
