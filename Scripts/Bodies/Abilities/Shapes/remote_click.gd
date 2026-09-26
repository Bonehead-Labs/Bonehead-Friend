extends RefCounted

## Remote (the sticky bomb, D78): a big red button, pressed.
##
## The moment it is clicked (`play`, the payoff) a detonator pops up beside the bomb — a dark box with
## a big red button and an aerial — the button goes down with the click, and three signal arcs run
## from its aerial to the bomb as it goes. The bang is the bomb's own; this is the hand that set it
## off, which is the whole of what the ability adds. It pops up on the side away from him, clear of
## his face and his badge.

const Moment := preload("res://Scripts/Bodies/Abilities/Shapes/kit/moment.gd")
const NAME := "ShapeRemoteClick"

const UP := [
	"..............y.",
	"..............h.",
	"....RRRRRR....h.",
	"...RWWRRRRR...h.",
	"..RRWRRRRRRr..h.",
	"..RRRRRRRRRr..h.",
	"..rRRRRRRRrr..h.",
	"HHHHHHHHHHHHHHHH",
	"HhhhhhhhhhhhhhhH",
	"HhYhhhhhhhhhhRhH",
	"HhhhhhhhhhhhhhhH",
	"HhhhhhhhhhhhhhhH",
	"HHHHHHHHHHHHHHHH",
]
const DOWN := [
	"..............y.",
	"..............h.",
	"..............h.",
	"..............h.",
	"....RRRRRR....h.",
	"..RRWRRRRRRr..h.",
	"..rRRRRRRRrr..h.",
	"HHHHHHHHHHHHHHHH",
	"HhhhhhhhhhhhhhhH",
	"HhYhhhhhhhhhhYhH",
	"HhhhhhhhhhhhhhhH",
	"HhhhhhhhhhhhhhhH",
	"HHHHHHHHHHHHHHHH",
]

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	(Moment.canvas(afx, NAME, Click) as Click).click(at, size, colour, ability)

class Click extends "res://Scripts/Bodies/Abilities/Shapes/kit/moment.gd":
	const PRESS_AT := 0.07
	const ARCS_T := 0.24
	const LIFE := 0.62
	const TICKS_T := 0.1

	var _bomb := Vector2.ZERO
	var _remote := Vector2.ZERO
	var _clicked_at := -10.0
	var _colour := Color("ff4d2e")

	func click(at: Vector2, _size: float, colour: Color, ability: WeaponAbility) -> void:
		_colour = colour
		_bomb = at
		var side := -1.0
		var him := ability.buddy() if ability else null
		if him:
			side = signf(at.x - him.get_interaction_rect().get_center().x)
			if side == 0.0:
				side = -1.0
		_remote = at + Vector2(side * 72.0, -64.0)
		_clicked_at = clock
		hold(LIFE)

	func _draw_shape() -> void:
		var age := clock - _clicked_at
		if age < 0.0 or age > LIFE:
			return
		var k := 1.0
		if age < 0.06:
			k = lerpf(0.5, 1.2, age / 0.06)
		elif age < 0.1:
			k = lerpf(1.2, 1.0, (age - 0.06) / 0.04)
		elif age > LIFE - 0.12:
			k = clampf((LIFE - age) / 0.12, 0.0, 1.0)
		var pressed := age >= PRESS_AT
		var tex := picture("down", DOWN) if pressed else picture("up", UP)
		stamp(tex, _remote, k)
		# The click: four ticks off the button as it goes down.
		var press_age := age - PRESS_AT
		if press_age >= 0.0 and press_age < TICKS_T:
			var button := _remote + Vector2(-2.0, -8.0) * k
			var out := lerpf(12.0, 22.0, press_age / TICKS_T)
			for a in [-2.4, -1.95, -1.2, -0.75]:
				var d := Vector2(cos(a), sin(a))
				stroke(button + d * out, button + d * (out + 6.0), KEY["W"], 2.0)
		# The aerial's tip, and three arcs running from it to the bomb.
		var tip := _remote + Vector2(12.0, -13.0) * k
		var run := age - PRESS_AT
		if run < 0.0 or run > ARCS_T:
			return
		var to := _bomb - tip
		var reach := to.length()
		var facing := to.angle()
		for i in 3:
			var t := (run - 0.04 * float(i)) / (ARCS_T - 0.08)
			if t < 0.0 or t > 1.0:
				continue
			var r := lerpf(8.0, reach, t)
			var half := lerpf(0.5, 0.3, t)
			var points := PackedVector2Array()
			for s in 7:
				var a := facing - half + 2.0 * half * float(s) / 6.0
				points.append((tip + Vector2(cos(a), sin(a)) * r).round())
			strokes(points, _colour, lerpf(3.0, 2.0, t))
