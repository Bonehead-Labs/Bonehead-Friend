extends RefCounted

## Airburst (the cluster bomb, D78): the shell opens over him and its bomblets rain down in a ring.
##
## At the burst (`play`, the payoff) a black flak cloud blooms where the shell was, lit orange at its
## heart for an instant; the casing splits in two, the red nose one way and the tail the other,
## tumbling away; and the bomblets — little round black bombs — drop out of it, each on its own short
## arc to its place on the ring round his feet, landing exactly as its blast goes off, one after
## another. A flak burst is the one thing in the game that goes off black.

const Moment := preload("res://Scripts/Bodies/Abilities/Shapes/kit/moment.gd")
const NAME := "ShapeFlakBurst"

const NOSE := [
	"..rRRqq",
	".rRWRqq",
	"rRRRqqq",
	"rRRRqqq",
	".rRRqqq",
	"..rRqqq",
]
const TAIL := [
	"qqYqq..",
	"qqYqqcc",
	"qqYqqqc",
	"qqYqqqc",
	"qqYqqcc",
	"qqYqq..",
]
const BOMBLET := [
	"...h...",
	"..hHh..",
	".HHHHH.",
	"HhHHHHH",
	"HHHHHHH",
	".HHHHH.",
	"..HHH..",
]
## Where the cloud's puffs sit round the middle, and how big each grows: x, y, radius.
const PUFFS := [Vector3(0, 0, 20), Vector3(-17, 5, 14), Vector3(16, 6, 15), Vector3(-6, -13, 13),
	Vector3(9, -11, 12)]

static func play(afx: AbilityFX, at: Vector2, size: float, colour: Color, ability: WeaponAbility) -> void:
	(Moment.canvas(afx, NAME, Flak) as Flak).burst(at, size, colour, ability)

class Flak extends "res://Scripts/Bodies/Abilities/Shapes/kit/moment.gd":
	const CLOUD_T := 0.75
	const FLASH_T := 0.07
	const MOST := 8

	var _at := Vector2.ZERO
	var _burst_at := -10.0
	var _k := 1.0
	var _drops := PackedVector2Array()
	var _lands := PackedFloat32Array()
	var _drop_count := 0

	func _ready() -> void:
		super._ready()
		_drops.resize(MOST)
		_lands.resize(MOST)

	func burst(at: Vector2, size: float, _colour: Color, ability: WeaponAbility) -> void:
		reserve(4)
		_at = at
		_burst_at = clock
		_k = lerpf(0.7, 1.0, size)
		# Where each bomblet is going and when it gets there: the ring the hook chose, one blast every
		# `submunition_interval`, the first a physics frame after the casing's own.
		_drop_count = 0
		var gap := 0.14
		if ability and ability.body and ability.body.get("submunition_interval") != null:
			gap = float(ability.body.get("submunition_interval"))
		var points = ability.get("points") if ability else null
		if points is Array:
			for p in points:
				if _drop_count < MOST:
					_drops[_drop_count] = p
					_lands[_drop_count] = 1.0 / 60.0 + gap * float(_drop_count)
					_drop_count += 1
		# The casing splits: nose one way, tail the other.
		var nose := throw(picture("nose", NOSE), at + Vector2(-6.0, 0.0), Vector2(-230.0, -150.0) * _k, 0.8, 900.0)
		nose.spin = -9.0
		var tail := throw(picture("tail", TAIL), at + Vector2(6.0, 0.0), Vector2(230.0, -150.0) * _k, 0.8, 900.0)
		tail.spin = 9.0
		var last := _lands[_drop_count - 1] if _drop_count > 0 else 0.0
		hold(maxf(CLOUD_T, last + 0.05))

	func _draw_shape() -> void:
		var age := clock - _burst_at
		if age < 0.0:
			return
		_draw_cloud(age)
		_draw_drops(age)

	## A black cloud of five puffs, blooming, holding, and drawn back in; orange at the heart at first.
	func _draw_cloud(age: float) -> void:
		if age > CLOUD_T:
			return
		var grow := clampf(age / 0.1, 0.0, 1.0)
		var shrink := clampf((CLOUD_T - age) / 0.4, 0.0, 1.0)
		var k := (1.0 - (1.0 - grow) * (1.0 - grow)) * shrink * _k
		for puff in PUFFS:
			var p: Vector3 = puff
			var r := p.z * k
			if r >= 2.0:
				draw_circle((_at + Vector2(p.x, p.y) * _k).round(), r + 2.0, OUTLINE)
		for puff in PUFFS:
			var p: Vector3 = puff
			var r := p.z * k
			if r >= 2.0:
				draw_circle((_at + Vector2(p.x, p.y) * _k).round(), r, KEY["H"])
				draw_circle((_at + Vector2(p.x - p.z * 0.3, p.y - p.z * 0.3) * _k).round(), r * 0.45, KEY["h"])
		if age < FLASH_T:
			var f := 1.0 - age / FLASH_T
			draw_circle(_at.round(), 13.0 * f * _k + 2.0, KEY["O"])
			draw_circle(_at.round(), 8.0 * f * _k + 1.0, KEY["y"])

	## Each bomblet on its own short arc from the burst to its place on the ring, gone as it lands, with
	## a dotted line ahead of it to where it is going.
	func _draw_drops(age: float) -> void:
		var bomb := picture("bomblet", BOMBLET)
		for i in _drop_count:
			var land := _lands[i]
			if age >= land:
				continue
			var t := clampf(age / maxf(land, 0.001), 0.0, 1.0)
			var p := _path(i, t)
			var dots := int(_drops[i].distance_to(p) / 14.0)
			for d in dots:
				var u := lerpf(t, 1.0, (float(d) + 1.0) / (float(dots) + 1.0))
				dot(_path(i, u), 1.0, KEY["h"])
			stamp(bomb, p, 1.0, (_drops[i].x - _at.x) * 0.004 * t)

	## Where bomblet `i` is at `t` of its fall: falling faster as it goes, on a short hop out of the burst.
	func _path(i: int, t: float) -> Vector2:
		return _at.lerp(_drops[i], t * t) + Vector2(0.0, -26.0 * sin(t * PI))
