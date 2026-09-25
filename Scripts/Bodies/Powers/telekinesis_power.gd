class_name TelekinesisPower
extends SpellPower

## Telekinesis (D72): press anywhere and a spectral hand takes him from wherever he is, carries
## him on a soft spring to the cursor, and lets go when you do — at whatever speed you were
## moving him. Right-click while holding him crushes: a squeeze that pays.
##
## It is not the drag. A drag is a pin joint on the grab region, and it is billed to nobody —
## the landing of a throw is the world's. Telekinesis holds him from anywhere, with no joint,
## on a spring loose enough that he trails the hand and swings through a turn; and while it has
## hold of him, and for `claim_seconds` after, every impact with the desk or a wall is its
## doing and is billed to it (`Buddy.claim_impacts`, D65). Fling him into the ceiling and the
## ceiling's blow is telekinesis's, at its damage multiplier. Only who is billed changes: the
## floor he has to clear is still the world's fall floor, so pressing him against a wall earns
## nothing — the steer is bounded well under the damage floor (see `SpellPower._steer`).

## How hard the gap to the cursor pulls, per second: the speed he is asked for is the gap times
## this, so he closes most of any distance in about a sixth of a second and then drifts in.
@export var spring: float = 7.0
## His top speed in the grip, and so the fastest fling.
@export var max_speed: float = 1500.0
## The ceiling on how fast the grip changes his velocity. Soft enough to swing him, and low
## enough that holding him into a wall is `3 kg x 4,800 / 60 = 240` a step, under the 350 floor.
@export var accel: float = 4800.0
## The squeeze, as the impulse he is handed.
@export var crush_impulse: float = 3200.0
## Seconds between squeezes, before "Quicker Squeeze".
@export var crush_seconds: float = 0.6
## How long after the hand lets go an impact is still the hand's: a fling across a 3,440 px
## ultrawide takes about that long.
@export var claim_seconds: float = 2.0
## The hand closed, shown while it has him.
@export var grip_cursor_texture: Texture2D

var _gripping := false
var _crush_until_msec := 0
var _refresh_msec := 0
var _tether: Line2D
var _core: Line2D
var _glow: GPUParticles2D
var _held_buddy: Buddy

## A ghost's green over him while the hand has him, the spell's colour at a glance.
const HELD_TINT := Color(0.84, 1.0, 0.9)

func is_live() -> bool:
	return _gripping

func is_gripping() -> bool:
	return _gripping

## Anywhere, as long as he is there to be taken.
func can_fire_at(_at: Vector2) -> bool:
	return _reachable(_buddy())

func fire(at: Vector2) -> void:
	var buddy := _buddy()
	if not _reachable(buddy):
		return
	_aim = at
	_held = true
	_gripping = true
	_build()
	_notice_player()
	if grip_cursor_texture:
		Input.set_custom_mouse_cursor(grip_cursor_texture, Input.CURSOR_ARROW, cursor_hotspot)
	var fx := _fx()
	if fx:
		fx.ring(buddy.global_position, 46.0, SPECTRAL, 0.25, 2.0)
		fx.puff(buddy.global_position, 6, SPECTRAL, 70.0, 0.5)
	AudioManager.play(&"psychic", 0.06, -6.0)
	_face(&"seized")
	_refresh_msec = Time.get_ticks_msec()
	_use()
	_emitting(_glow, true)
	# Possessed: a ghost's green over him for as long as the hand has him.
	buddy.modulate = HELD_TINT
	_held_buddy = buddy
	set_physics_process(true)
	_update_input()

func _released(_at: Vector2) -> void:
	_let_go()

## A scene change mid-grip must not leave him green in the next one.
func _exit_tree() -> void:
	if is_instance_valid(_held_buddy):
		_held_buddy.modulate = Color.WHITE
	_held_buddy = null
	_gripping = false

func _spell_deactivated(_was_held: bool) -> void:
	_let_go()

func _right_pressed(_at: Vector2) -> bool:
	if not _gripping:
		return false
	var buddy := _buddy()
	var now := Time.get_ticks_msec()
	if buddy == null or now < _crush_until_msec:
		# Held, so the right-click is still the grip's: a crush on cooldown, not a trip to the bin.
		return true
	_crush_until_msec = now + int(crush_seconds * Progression.get_modifier(item_id, &"cooldown_mult") * 1000.0)
	buddy.take_impulse(crush_impulse, item_id, effective_damage_mult(), buddy.global_position)
	var fx := _fx()
	if fx:
		var tier := _tier()
		fx.ring(buddy.global_position, 58.0 + 6.0 * float(tier), SPECTRAL, 0.22, 3.0)
		fx.chips(buddy.global_position, SPECTRAL_CORE, 6 + 2 * tier, 220.0)
		fx.shake(3.0)
	AudioManager.play(&"crunch", 0.1, -4.0)
	_use()
	return true

func _let_go() -> void:
	if not _gripping:
		return
	_gripping = false
	_held = false
	if _tether:
		_tether.visible = false
		_core.visible = false
	_emitting(_glow, false)
	if is_instance_valid(_held_buddy):
		_held_buddy.modulate = Color.WHITE
	_held_buddy = null
	if active and cursor_texture:
		Input.set_custom_mouse_cursor(cursor_texture, Input.CURSOR_ARROW, cursor_hotspot)
	var buddy := _buddy()
	if buddy and buddy.linear_velocity.length() > 700.0:
		AudioManager.play(&"whoosh", 0.1, -8.0)
	set_physics_process(false)
	_update_input()

func _physics_process(delta: float) -> void:
	if not _gripping:
		set_physics_process(false)
		return
	var buddy := _buddy()
	# Picked up by hand, knocked out or frozen by something else: the grip gives way to it.
	if not _reachable(buddy) or buddy.freeze:
		_let_go()
		return
	var gap := _aim - buddy.global_position
	var want := (gap * spring).limit_length(max_speed)
	_steer(buddy, want, accel, delta)
	_upright(buddy, 3.0)
	buddy.claim_impacts(item_id, effective_damage_mult(), claim_seconds)
	_draw_tether(buddy)
	if _glow:
		_glow.global_position = buddy.global_position
	# His struggle is a hold refreshed from here; the idle brain is told the same thing, so a
	# long carry never lets a routine start under the hand.
	var now := Time.get_ticks_msec()
	if now >= _refresh_msec:
		_refresh_msec = now + 300
		_face(&"seized")
		_notice_player()

## A sagging, wavering line from the hand to him: a ghost-green body and a pale core,
## bowed by how fast he is swinging, so the spring can be seen working.
func _draw_tether(buddy: Buddy) -> void:
	if _tether == null:
		return
	var from := _aim
	var to := buddy.global_position
	var span := to - from
	var side := span.orthogonal().normalized() if span.length() > 1.0 else Vector2.RIGHT
	var t := float(Time.get_ticks_msec()) / 1000.0
	var bow := side * (sin(t * 7.0) * 6.0 + clampf(buddy.linear_velocity.dot(side) * -0.02, -24.0, 24.0))
	var mid := from.lerp(to, 0.5) + bow + Vector2(0.0, minf(span.length() * 0.08, 30.0))
	var points := PackedVector2Array()
	for i in 11:
		var u := float(i) / 10.0
		points.append(from.lerp(mid, u).lerp(mid.lerp(to, u), u).round())
	_tether.points = points
	_core.points = points
	var width := 7.0 + float(_tier())
	_tether.width = width
	_core.width = maxf(2.0, roundf(width * 0.35))
	_tether.visible = true
	_core.visible = true

func _build() -> void:
	if _tether != null:
		return
	_tether = Line2D.new()
	_tether.name = "Tether"
	_tether.default_color = SPECTRAL
	_tether.antialiased = false
	_tether.joint_mode = Line2D.LINE_JOINT_ROUND
	_tether.z_index = 34
	_tether.visible = false
	add_child(_tether)
	_core = Line2D.new()
	_core.name = "TetherCore"
	_core.default_color = SPECTRAL_CORE
	_core.antialiased = false
	_core.z_index = 35
	_core.visible = false
	add_child(_core)
	var fx := _fx()
	if fx:
		var tier := _tier()
		_glow = fx.aura(self, &"chip", SPECTRAL.lerp(SPECTRAL_CORE, 0.25 * float(tier)), 12 + 4 * tier,
			"Grip", Vector2(30, 40), 1.4)
		# Riding on him, not left behind: in world space the orbit smeared into a dotted line
		# across the desk every time he was swung.
		_glow.local_coords = true
		_glow.emitting = false
