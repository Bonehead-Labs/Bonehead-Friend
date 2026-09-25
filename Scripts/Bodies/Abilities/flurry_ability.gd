class_name FlurryAbility
extends SustainAbility

## The katar's Flurry (D74, the blades): hold right and the hand jabs, `jab_rate` times a second,
## for `fuel_seconds` — and the player steers the jabs by where they hold it.
##
## **The hand jabs, not the blade.** Each jab carries the handle out `jab_px` and back
## (`BaseDraggable.hand_offset`, the katana's mechanism at a jab's length): drawn back a third of that
## in the first `jab_draw` of the beat, out fast in the next `jab_out`, and back in the rest, with a
## snap of `kick` along it to start it clean. The draw is what makes a jab from a fist already
## resting on him a blow rather than a push. The
## drag joint does the carrying, so a punch-dagger held at its grip goes where the fist goes.
## **Every jab is a real contact**, billed by his ledger like any swing (D7, D64): the per-source
## cooldown (0.15 s) is what lets six a second land and no more, and the katar's own multiplier is
## all they carry. Nothing is handed to him here.
##
## Each jab goes at him if he is within `reach` of the hand, and along the blade if he is not — so
## the player aims it by moving the hand, the way a boxer's hands follow the head they are hitting.
## The point leads: the blade is laid along each jab (`BladeAim`, D56's aim, `aim_frequency`,
## `aim_accel`), so a punch-dagger that hung any way from the fist goes in point first.
##
## Row: `fuel_seconds`, `jab_rate`, `jab_px`, `jab_draw`, `jab_out`, `kick`, `reach`,
## `aim_frequency`, `aim_accel`.

var _gravity_ := 980.0
var _beat := 0.0
var _dir := Vector2.RIGHT
var _offset := Vector2.ZERO
var _landed := 0

## For the suites: jabs thrown this use and jabs that landed.
var jabs := 0
var jabs_landed := 0

func _ready() -> void:
	super._ready()
	_gravity_ = float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))

func pip_fill() -> float:
	if not _active:
		return -1.0
	return clampf(1.0 - _t / maxf(num("fuel_seconds", 2.0), 0.01), 0.0, 1.0)

func _on_press() -> void:
	_t = 0.0
	_beat = 1.0
	var him := him_world()
	_dir = (him - hand_world()).normalized() if him != Vector2.INF else Vector2.RIGHT
	_landed = 0
	jabs = 0
	jabs_landed = 0
	grinds = 0
	run(true)
	threaten(true)
	_update_pip()

func _on_release(_seconds: float) -> void:
	finish()

func _on_tick(delta: float) -> void:
	_t += delta
	var period := 1.0 / maxf(num("jab_rate", 6.0), 0.5)
	_beat += delta / period
	if _beat >= 1.0:
		_beat = fmod(_beat, 1.0)
		_jab()
	# Each beat: a short draw back, the jab out, and back to the hand. The draw is what makes a jab
	# from a fist already resting against him a blow and not a push.
	var draw := clampf(num("jab_draw", 0.2), 0.0, 0.5)
	var out := clampf(num("jab_out", 0.35), 0.1, 0.9)
	var reach := num("jab_px", 50.0)
	var k := 0.0
	if _beat < draw:
		k = -0.3 * sin(_beat / maxf(draw, 0.001) * PI * 0.5)
	elif _beat < draw + out:
		var e := (_beat - draw) / out
		k = lerpf(-0.3, 1.0, 1.0 - (1.0 - e) * (1.0 - e))
	else:
		var e := (_beat - draw - out) / maxf(1.0 - draw - out, 0.01)
		k = 1.0 - e * e * (3.0 - 2.0 * e)
	_set_offset(_dir * reach * k)
	# The point leads every jab: the blade is laid along the jab and held there (`BladeAim`).
	BladeAim.hold(self, _dir, num("aim_frequency", 16.0), 0.8, num("aim_accel", 320.0), _gravity_)
	if _landed > 0:
		var fx := fx()
		var tip := tip_world()
		for i in _landed:
			jabs_landed += 1
			payoffs += 1
			if jabs_landed == 1:
				paid_off.emit(&"flurry")
			if fx:
				fx.chips(tip, WorldFX.SPARK, 3, 220.0)
				fx.ring(tip, 18.0 + 2.0 * float(mini(jabs_landed, 8)), Color.WHITE, 0.1, 2.0)
		_landed = 0
	if _t >= num("fuel_seconds", 2.0):
		finish()

## One jab: at him if he is in reach, along the blade if he is not.
func _jab() -> void:
	jabs += 1
	var hand := hand_world() - _offset
	var him := buddy()
	_dir = (tip_world() - grip_world()).normalized()
	if him:
		var rect := him.get_interaction_rect()
		var aim := Vector2(clampf(hand.x, rect.position.x, rect.end.x), clampf(hand.y, rect.position.y, rect.end.y))
		if aim.distance_to(hand) < 1.0:
			aim = rect.get_center()
		if hand.distance_to(aim) <= num("reach", 150.0):
			_dir = (aim - hand).normalized() if aim.distance_squared_to(hand) > 1.0 else _dir
	if _dir.length_squared() < 0.5:
		_dir = Vector2.RIGHT
	body.apply_central_impulse(_dir * body.mass * num("kick", 300.0))
	sound(&"whoosh", -16.0, 2.0 + randf_range(-0.15, 0.15), 0.0)
	var fx := fx()
	if fx:
		var tip := tip_world()
		fx.tracer(tip - _dir * 18.0, tip + _dir * 22.0, Color.WHITE, 0.07, 2.0)

func _on_hit() -> void:
	_landed += 1

func _set_offset(offset: Vector2) -> void:
	# The chase already ran this frame with the old offset: move the handle by the difference too,
	# so the fist is where the jab says now and not a frame late (DashAbility's reason).
	var delta := offset - _offset
	_offset = offset
	body.hand_offset = offset
	if body.dragging and body.handle:
		body.handle.global_position += delta

func _on_dropped() -> void:
	finish()

func _on_stop() -> void:
	super._on_stop()
	_offset = Vector2.ZERO
	if body:
		body.hand_offset = Vector2.ZERO
