class_name SmitePower
extends SpellPower

## Smite (D72): click anywhere and a thread of light comes down that column of the desk,
## brightening for `charge_seconds`; then the pillar falls. Everything standing in the column is
## struck and driven into the floor, and the floor throws everything near its foot outward.
##
## The only power you aim by the column rather than the point, and the only one that tells him it
## is coming: the charge is a `threat_changed(&"windup")`, the tell an animal's swing gives, so he
## sees the light gather and flinches from it. The strike hands him an impulse through
## `take_impulse` (D7) and drives him down; the slam into the desk, and the landing of anything
## the quake throws him into, are claimed by the spell (`Buddy.claim_impacts`, D65).
##
## One pillar at a time. The pillar is drawn by a node the power owns, in hard-edged bands that
## narrow away rather than fade, and it processes only while charging or falling.

@export var charge_seconds: float = 0.6
## The pillar's width. A body counts as in it when any of it is.
@export var column_width: float = 72.0
@export var smite_impulse: float = 11000.0
## How hard the pillar drives a body down, as a speed: a skeleton and a pencil are driven into
## the desk alike, the way D65's pulls are accelerations.
@export var slam_speed: float = 800.0
## The quake at the foot: how far it reaches either side, and the speed it throws with.
@export var quake_radius: float = 260.0
@export var quake_speed: float = 420.0
## Seconds between strikes, before "Swifter Judgement".
@export var recharge_seconds: float = 2.6
@export var claim_seconds: float = 1.2
@export var strike_seconds: float = 0.45

const IDLE := 0
const CHARGING := 1
const STRIKING := 2

var _state := IDLE
var _column_x := 0.0
var _started_msec := 0
var _ready_msec := 0
var _mote_msec := 0
var _pillar: Pillar

func is_live() -> bool:
	return _state != IDLE

func can_fire_at(_at: Vector2) -> bool:
	return true

func fire(at: Vector2) -> void:
	var now := Time.get_ticks_msec()
	if _state != IDLE or now < _ready_msec:
		_fizzle(at, HOLY)
		return
	_build()
	_state = CHARGING
	_column_x = at.x
	_started_msec = now
	_mote_msec = 0
	_ready_msec = now + int((charge_seconds + recharge_seconds
		* Progression.get_modifier(item_id, &"cooldown_mult")) * 1000.0)
	var view := get_viewport().get_visible_rect()
	_pillar.begin(_column_x, view.position.y - 20.0, _floor_y(), column_width, _tier())
	# His tell. Placed on the column at his height, so how near he is to it is the distance the
	# brain measures.
	var buddy := _buddy()
	if buddy:
		EventBus.threat_changed.emit(&"windup", Vector2(_column_x, buddy.global_position.y), 1.0)
	AudioManager.play(&"charge", 0.0, -8.0)
	set_process(true)
	_update_input()

## When the next strike can be called, for the suite.
func ready_msec() -> int:
	return _ready_msec

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var elapsed := float(now - _started_msec) / 1000.0
	match _state:
		CHARGING:
			_pillar.charge = clampf(elapsed / charge_seconds, 0.0, 1.0)
			_pillar.queue_redraw()
			if now >= _mote_msec:
				_mote_msec = now + 90
				var fx := _fx()
				if fx:
					fx.puff(Vector2(_column_x, _floor_y()), 2, HOLY, 50.0, 0.6)
			if elapsed >= charge_seconds:
				_strike()
		STRIKING:
			var t := (elapsed - charge_seconds) / strike_seconds
			if t >= 1.0:
				_state = IDLE
				_pillar.visible = false
				set_process(false)
				_update_input()
				return
			_pillar.fall = t
			_pillar.queue_redraw()
		_:
			set_process(false)
			_update_input()

func _strike() -> void:
	_state = STRIKING
	_started_msec = Time.get_ticks_msec() - int(charge_seconds * 1000.0)
	_pillar.fall = 0.0
	_pillar.striking = true
	_pillar.queue_redraw()
	var base := Vector2(_column_x, _floor_y())
	var buddy := _buddy()
	if buddy:
		EventBus.threat_changed.emit(&"windup", Vector2(_column_x, buddy.global_position.y), 0.0)
	var mult := effective_damage_mult()
	var half := column_width * 0.5
	for node in get_tree().get_nodes_in_group(BaseDraggable.GROUP_INTERACTIVE):
		var body := node as RigidBody2D
		if body == null or body.freeze or (body is BaseDraggable and (body as BaseDraggable).dragging):
			continue
		var reach := half + _half_width(body)
		var dx := body.global_position.x - _column_x
		if absf(dx) <= reach:
			# In the column: struck, and driven down into the desk.
			body.apply_central_impulse(Vector2(0.0, slam_speed) * body.mass)
			if body is Buddy:
				var him := body as Buddy
				him.take_impulse(smite_impulse, item_id, mult,
					Vector2(_column_x, him.get_interaction_rect().position.y))
				him.claim_impacts(item_id, mult, claim_seconds)
			continue
		var gap := base.distance_to(body.global_position)
		if gap > quake_radius:
			continue
		# The quake: out from the foot and up, weaker with distance, the same for any mass.
		var falloff := 1.0 - gap / quake_radius
		var away := Vector2(signf(dx), -1.3).normalized()
		body.apply_central_impulse(away * quake_speed * falloff * body.mass)
		if body is Buddy:
			(body as Buddy).claim_impacts(item_id, mult, claim_seconds)
	var fx := _fx()
	if fx:
		var tier := _tier()
		fx.ring(base, 170.0 + 20.0 * float(tier), WorldFX.GOLD, 0.45, 4.0)
		fx.burst(base + Vector2(0, -20), &"star", WorldFX.GOLD, 14 + 4 * tier, 320.0, 0.9)
		fx.puff(base + Vector2(-50, -6), 8, WorldFX.DUST, 140.0, 0.7)
		fx.puff(base + Vector2(50, -6), 8, WorldFX.DUST, 140.0, 0.7)
		fx.shake(8.0)
	AudioManager.play(&"explode_big", 0.08, -6.0)
	AudioManager.play(&"smite", 0.0, -6.0)
	_use()

## The floor under the column: the bottom of the play area, which is where `WorldBounds` puts it.
func _floor_y() -> float:
	return get_viewport().get_visible_rect().end.y

func _half_width(body: RigidBody2D) -> float:
	if body is BaseDraggable:
		return (body as BaseDraggable).get_interaction_rect().size.x * 0.5
	return 12.0

func _build() -> void:
	if _pillar != null:
		return
	_pillar = Pillar.new()
	_pillar.name = "Pillar"
	_pillar.z_index = 38
	_pillar.visible = false
	add_child(_pillar)

## The column, drawn. Charging: a thread of light from the top of the view to the floor that
## thickens and flickers, and a mark on the floor at its foot. Falling: the pillar itself — a
## white core inside gold inside pale rays — that narrows to nothing, with a flare along the
## floor. Bands of solid colour and whole-pixel widths, never alpha.
class Pillar extends Node2D:
	var top := 0.0
	var bottom := 0.0
	var width := 72.0
	var charge := 0.0
	var fall := 0.0
	var striking := false
	var tier := 0

	func begin(x: float, from_y: float, to_y: float, column: float, juice: int) -> void:
		position = Vector2(x, 0.0)
		top = from_y
		bottom = to_y
		width = column
		charge = 0.0
		fall = 0.0
		striking = false
		tier = juice
		visible = true
		queue_redraw()

	func _draw() -> void:
		var gold := WorldFX.GOLD
		if not striking:
			var flicker := 1.0 if (Time.get_ticks_msec() / 60) % 2 == 0 else 0.0
			var w := roundf(1.0 + charge * 5.0 + flicker)
			draw_rect(Rect2(-w * 0.5, top, w, bottom - top), SpellPower.HOLY)
			# The column's edges, dashed and marching down: how wide it will be, so whether he
			# is in it can be read before it lands.
			var half := roundf(width * 0.5)
			var march := float((Time.get_ticks_msec() / 30) % 16)
			var y := top + march - 16.0
			while y < bottom:
				var from := maxf(y, top)
				var to := minf(y + 8.0, bottom)
				if to > from:
					draw_rect(Rect2(-half, from, 2.0, to - from), gold)
					draw_rect(Rect2(half - 2.0, from, 2.0, to - from), gold)
				y += 16.0
			var mark := roundf(8.0 + charge * width * 0.5)
			draw_rect(Rect2(-mark, bottom - 3.0, mark * 2.0, 3.0), gold)
			return
		var k := sqrt(clampf(1.0 - fall, 0.0, 1.0))
		var outer := roundf(width * (1.25 + 0.1 * float(tier)) * k)
		var body := roundf(width * k)
		var core := roundf(width * 0.45 * k)
		if outer >= 1.0:
			draw_rect(Rect2(-outer * 0.5, top, outer, bottom - top), SpellPower.HOLY.darkened(0.08))
		if body >= 1.0:
			draw_rect(Rect2(-body * 0.5, top, body, bottom - top), gold)
		if core >= 1.0:
			draw_rect(Rect2(-core * 0.5, top, core, bottom - top), Color.WHITE)
		# The flare where it meets the desk, wider than the pillar and gone as fast.
		var flare := roundf(width * 2.4 * k)
		if flare >= 1.0:
			draw_rect(Rect2(-flare * 0.5, bottom - 6.0, flare, 6.0), Color.WHITE)
			draw_rect(Rect2(-flare * 0.35, bottom - 10.0, flare * 0.7, 4.0), gold)
