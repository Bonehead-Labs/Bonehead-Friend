class_name ClampAbility
extends WeaponAbility

## A close-range bite (D74): the hole punch's Punch, the shears' Snip, the pipe wrench's Crank.
##
## Tap right and the jaws close `bites` times, `bite_gap` seconds apart. The jaws are at `jaw`
## (body-local world px; the far end of the weapon if the row has none), and a bite lands only if
## his body is within `reach` of them as it closes — a bite on nothing is a snap in the air, and half
## the cooldown. Each bite that lands is billed once as `bite_force`, through `Buddy.take_impulse` at
## the weapon's multiplier times `bite_mult` (D7), shoving him `shove` of it away from the jaws, from
## the tick before `StepStart` (D64). The picture snaps by `snap` (its scale, for a frame or four),
## and the row can add three things:
##
## - `confetti`: the paper a hole punch makes, and `hole_seconds` of a punched hole left in him;
## - `snip_head`: a bite in the top `head_band` of him takes his headphones off. They fall to the
##   desk as a prop of their own (`Headphones`), he is bare-headed and cross about it, and after
##   `phones_seconds` they fly back onto his head — at once, if the shears leave the desk first. The
##   prop owns the return, so binning the shears cannot strand him without them, and it gives them
##   back the moment it leaves the tree, however it leaves (D62);
## - `hold_seconds`: the first bite that lands **clamps on** for that long. He is held where he was
##   bitten, hoisted `crank_lift` px — clear of the desk, with the wrench sticking out under him —
##   and **the hand going round him cranks him round**: the angle of the hand about his middle,
##   accumulated as D57's crank gesture accumulates it, is the angle he is turned to, at no more
##   than `crank_rate` rad/s. The weapon turns with him, a wrench on a nut: its jaws on the bite and
##   its handle straight out from his middle (`BaseDraggable.hand_offset` puts the hand there;
##   impulses at its grip and its jaws keep it there). Every half turn is a crank, billed as
##   `crank_force` at `crank_mult`, up to `crank_hits` of them. It lets go when its time is up, or
##   if he is picked up, knocked out, or the weapon leaves the hand; he keeps the spin.
##
## Everything done to him is an impulse from the tick (D54, D64). While clamped he and the weapon
## do not collide, and the exception stays until they are clear (D61).
##
## Row: `jaw`, `reach`, `touch`, `bites`, `bite_gap`, `bite_force`, `bite_mult`, `shove`, `snap`,
## `bite_sound`, `confetti`, `hole_seconds`, `snip_head`, `head_band`, `head_reach`,
## `phones_seconds`, `hold_seconds`, `crank_lift`, `crank_rate`, `crank_force`, `crank_mult`,
## `crank_hits`, `tell`.

const BITING := 0
const CLAMPED := 1
const SETTLE := 2
const SNAP_SECONDS := 0.07
const CONFETTI: Array[Color] = [Color("f4f1e6"), Color("f2ead8"), Color("ff5f9e"), Color("ffc247"),
	Color("7fd8ff")]

var _phase := BITING
var _bites_left := 0
var _next_bite := 0.0
var _landed := 0
var _snap_t := 0.0
var _sprite_rest := Vector2.INF
var _held_t := 0.0
var _settle_t := 0.0
var _excepted: Buddy
var _start := Vector2.ZERO
var _clamp_local := Vector2.ZERO
var _last_angle := INF
var _turn := 0.0
var _turned := 0.0
var _offset := Vector2.ZERO
var _tell_clock := 0.0
var _gravity := 980.0

## For the suites: bites closed and landed, the last bite's impulse, whether the headphones came
## off, the turns he was cranked and the cranks billed.
var bites_closed := 0
var bites_landed := 0
var last_bite := 0.0
var snipped := false
var cranks := 0
var turns := 0.0
## Why the last clamp let go, for the suites and the capture tool's trace.
var let_go_reason := ""

func _ready() -> void:
	super._ready()
	_gravity = float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))

func _can_start() -> bool:
	return buddy() != null

func is_clamped() -> bool:
	return _active and _phase == CLAMPED

func pip_fill() -> float:
	if is_clamped():
		return clampf(1.0 - _held_t / maxf(num("hold_seconds", 2.0), 0.01), 0.0, 1.0)
	return -1.0

## Where the jaws are in the world.
func jaw_world() -> Vector2:
	if row.has("jaw"):
		return body.to_global(row["jaw"])
	return tip_world()

## Whether his body is between the jaws right now: within `reach` of them, or — for a row with
## `touch`, a hole punch or a wrench whose jaws are its whole head — touching the weapon at all.
func in_jaws() -> bool:
	if touches_him(jaw_world(), num("reach", 20.0)):
		return true
	return bool(row.get("touch", false)) and overlaps_him_near(6.0)

## Any of the weapon's shapes touching him, or within `margin` px of him: the contacts the weapon
## reports, and each of its shapes asked of the physics with that margin.
func overlaps_him_near(margin: float) -> bool:
	var him := buddy()
	if him == null or not body.is_inside_tree():
		return false
	if body.get_colliding_bodies().has(him):
		return true
	var space := body.get_world_2d().direct_space_state
	for child in body.get_children():
		var cs := child as CollisionShape2D
		if cs == null or cs.shape == null or cs.disabled:
			continue
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = cs.shape
		query.transform = cs.global_transform
		query.margin = margin
		query.collision_mask = BUDDY_LAYER
		for result in space.intersect_shape(query, 4):
			if result.get("collider") == him:
				return true
	return false

func _on_press() -> void:
	_phase = BITING
	_bites_left = int(num("bites", 1.0))
	_next_bite = 0.0
	_landed = 0
	_held_t = 0.0
	_turn = 0.0
	_turned = 0.0
	_last_angle = INF
	bites_closed = 0
	bites_landed = 0
	last_bite = 0.0
	snipped = false
	cranks = 0
	turns = 0.0
	run(true)
	threaten(true)

## A tap: nothing happens on the release — the bites are timed, and a clamp holds for its time.
func _on_release(_seconds: float) -> void:
	pass

func _on_dropped() -> void:
	match _phase:
		BITING:
			_rest_sprite()
			finish(num("cooldown", 3.0) * 0.5)
		CLAMPED:
			_let_go()

func _on_tick(delta: float) -> void:
	_animate_snap(delta)
	match _phase:
		BITING:
			_next_bite -= delta
			if _next_bite <= 0.0 and _bites_left > 0:
				_bites_left -= 1
				# No gap after the last: a single bite decides on the frame its snap is over.
				_next_bite = num("bite_gap", 0.12) if _bites_left > 0 else 0.0
				_bite()
			if _bites_left <= 0 and _next_bite <= 0.0 and _snap_t <= 0.0:
				if _landed > 0 and num("hold_seconds", 0.0) > 0.0:
					_clamp_on()
				elif _landed > 0:
					finish()
				else:
					finish(num("cooldown", 3.0) * 0.5)
		CLAMPED:
			_crank(delta)
		SETTLE:
			_settle_t += delta
			if not overlaps_him() or _settle_t >= 1.0:
				finish()

## The jaws close once.
func _bite() -> void:
	bites_closed += 1
	_snap_t = SNAP_SECONDS
	var at := jaw_world()
	sound(StringName(row.get("bite_sound", &"clack")), -4.0, 1.0 + 0.08 * float(bites_closed - 1), 0.05)
	var him := buddy()
	if him == null or not in_jaws():
		var fx := fx()
		if fx:
			fx.puff(at, 3, WorldFX.DUST, 40.0, 0.35)
		return
	_landed += 1
	bites_landed += 1
	var centre := him.get_interaction_rect().get_center()
	var into := (centre - at).normalized() if centre.distance_squared_to(at) > 1.0 else Vector2.RIGHT
	var point := at.clamp(him.get_interaction_rect().position, him.get_interaction_rect().end)
	last_bite = num("bite_force", 1800.0)
	strike(last_bite, into, point, num("bite_mult", 1.0), num("shove", 0.3))
	var fx := fx()
	if fx:
		fx.ring(point, 30.0, Color.WHITE, 0.15, 2.0)
		fx.chips(point, Color("f2ead8"), 3, 200.0)
		fx.shake(3.0)
	if bool(row.get("confetti", false)):
		_confetti(point)
	if num("hole_seconds", 0.0) > 0.0:
		_punch_hole(him, point)
	if bool(row.get("snip_head", false)) and not snipped and _at_head(him):
		snipped = Headphones.snip(him, body, num("phones_seconds", 4.0))
		if snipped:
			tell(&"snipped", point)
	var event := StringName(row.get("tell", &""))
	if event != &"":
		tell(event, point)
	paid_off.emit(ability_id())

## The blades at the top `head_band` of him, where his headphones are: the jaws or the middle of
## the weapon level with his head, and beside it or on it. In his own frame, so a skeleton lying on
## his side still has his head at his head; his headphones stick out past his skull, and the jaws
## are at the far end of a weapon pressed against him, so the band reaches `head_reach` px out
## to either side of him.
func _at_head(him: Buddy) -> bool:
	var rect := him.get_interaction_rect()
	var half := rect.size * 0.5
	var reach := num("reach", 20.0)
	var side := num("head_reach", 60.0)
	var head := Rect2(-half.x, -half.y, rect.size.x, rect.size.y * num("head_band", 0.45)) 		.grow_individual(side, reach, side, 0.0)
	var centre := him.to_local(rect.get_center())
	for point in [jaw_world(), com_world()]:
		if head.has_point(him.to_local(point) - centre):
			return true
	return false

## The paper a hole punch makes: dots of five colours, thrown up and falling.
func _confetti(at: Vector2) -> void:
	var fx := fx()
	if fx == null:
		return
	for colour in CONFETTI:
		fx.chips(at, colour, 4, 280.0)
	fx.burst(at, &"star", WorldFX.GOLD, 2, 200.0)

## A hole where it went in: a dark disc with a light rim, on him and turning with him, for
## `hole_seconds`. His own child, so it goes where he goes; freed by a timer bound to it, so it
## goes whatever happens to the punch.
func _punch_hole(him: Buddy, at: Vector2) -> void:
	var hole := Hole.new()
	hole.name = "PunchedHole"
	hole.z_index = 2
	him.add_child(hole)
	# In him, not on his outline: the bite is where the jaws met his edge, and a hole drawn there is
	# half off him and lost against the desk.
	var local := him.to_local(at)
	var inward := (him.to_local(him.get_interaction_rect().get_center()) - local)
	hole.position = (local + inward.limit_length(16.0)).round()
	hole.get_tree().create_timer(num("hole_seconds", 3.0)).timeout.connect(hole.queue_free)

## A punched hole, round in two-pixel steps: a dark rim, the dark inside, and a lit lower lip.
class Hole extends Node2D:
	func _draw() -> void:
		var rim := Color("26221d")
		for r in [Rect2(-4, -8, 8, 16), Rect2(-8, -4, 16, 8), Rect2(-6, -6, 12, 12)]:
			draw_rect(r, rim)
		for r in [Rect2(-2, -6, 4, 12), Rect2(-6, -2, 12, 4), Rect2(-4, -4, 8, 8)]:
			draw_rect(r, Color("3d3833"))
		draw_rect(Rect2(-4, 4, 8, 2), Color("8a8174"))

## The picture snaps shut: its scale pinched by `snap`, eased back over a few frames.
func _animate_snap(delta: float) -> void:
	var s := sprite()
	if s == null:
		return
	if _sprite_rest == Vector2.INF:
		_sprite_rest = s.scale
	if _snap_t <= 0.0:
		return
	_snap_t = maxf(_snap_t - delta, 0.0)
	var squeeze: Vector2 = row.get("snap", Vector2(0.8, 1.0))
	var k := _snap_t / SNAP_SECONDS
	s.scale = _sprite_rest * Vector2.ONE.lerp(squeeze, k)
	if _snap_t <= 0.0:
		s.scale = _sprite_rest

func _rest_sprite() -> void:
	var s := sprite()
	if s and _sprite_rest != Vector2.INF:
		s.scale = _sprite_rest
	_snap_t = 0.0

# --- the clamp -----------------------------------------------------------------------------

func _clamp_on() -> void:
	var him := buddy()
	if him == null:
		finish()
		return
	_phase = CLAMPED
	_held_t = 0.0
	_tell_clock = 0.0
	_start = him_world()
	_clamp_local = him.to_local(jaw_world().clamp(him.get_interaction_rect().position,
		him.get_interaction_rect().end))
	_last_angle = INF
	body.add_collision_exception_with(him)
	_excepted = him
	threaten(false)
	sound(&"clack", -2.0, 0.7)
	sound(&"creak", -10.0, 0.7)
	_update_pip()

func _crank(delta: float) -> void:
	var him := buddy()
	if him == null or him.dragging or him.freeze or (him.health and him.health.down):
		let_go_reason = "he was taken out of the jaws"
		_let_go()
		return
	if not body.dragging:
		let_go_reason = "the hand let go"
		_let_go()
		return
	_held_t += delta
	var centre := him_world()
	var cursor := _cursor()
	var angle := (cursor - centre).angle()
	if _last_angle != INF:
		_turn += wrapf(angle - _last_angle, -PI, PI)
	_last_angle = angle
	# He turns to the crank's angle, no faster than `crank_rate`: a torque impulse toward the spin
	# that closes the gap, never a write to his spin (D54).
	var inertia := _inertia_of(him)
	var rate := num("crank_rate", 14.0)
	var want := clampf((_turn - _turned) * 14.0, -rate, rate)
	him.apply_torque_impulse((want - him.angular_velocity) * inertia)
	_turned += him.angular_velocity * delta
	turns = absf(_turned) / TAU
	# Held where he was bitten, lifted clear of the desk so his corners do not dig in as he turns.
	var hold := _start + Vector2(0.0, -num("crank_lift", 26.0))
	var change := (hold - centre) * 14.0 - him.linear_velocity
	change.y -= _gravity * him.gravity_scale * delta
	him.apply_central_impulse(change.limit_length(9000.0 * delta) * him.mass)
	# The weapon goes round with him, a wrench on a nut: its jaws on the bite and its handle straight
	# out from his middle through them, so it turns as he does. Aimed at the cursor instead, the
	# handle was dragged through him whenever the hand passed the far side of him.
	var bite := him.to_global(_clamp_local)
	var lever := grip_world().distance_to(jaw_world())
	var out := bite - centre
	var handle := bite + (out.normalized() if out.length_squared() > 1.0 else Vector2.LEFT) * lever
	_set_offset(handle - cursor)
	_hold_weapon(handle, bite, him, delta)
	# A crank every half turn of his.
	var halves := int(absf(_turned) / PI)
	if halves > cranks and cranks < int(num("crank_hits", 4.0)):
		cranks += 1
		_crank_hit(him, bite)
	_tell_clock -= delta
	if _tell_clock <= 0.0:
		_tell_clock = 0.5
		tell(&"cranked", bite)
	if _held_t >= num("hold_seconds", 2.0):
		let_go_reason = "its time was up"
		_let_go()

func _crank_hit(him: Buddy, at: Vector2) -> void:
	var out := at - him_world()
	var tangent := Vector2(-out.y, out.x).normalized() * signf(_turned if _turned != 0.0 else 1.0)
	strike(num("crank_force", 1500.0), tangent, at, num("crank_mult", 1.0), 0.0)
	var fx := fx()
	if fx:
		fx.chips(at, Color("f2ead8"), 4, 220.0)
		fx.ring(at, 26.0, tier_colour(), 0.18, 2.0)
	sound(&"ratchet", -4.0, 0.8 + 0.1 * float(cranks), 0.0)
	sound(&"creak", -8.0, 1.0 + 0.1 * float(cranks), 0.05)
	paid_off.emit(&"crank")

## Clamped, the weapon and he are one thing: its grip is steered onto the hand and its jaws onto
## the bite, each by an impulse at that point — never a write to its velocity (D54). The drag joint
## alone is soft on purpose, and a 16 kg wrench on it trails a hand going round him by 100 px,
## which reads as him spinning by himself.
func _hold_weapon(handle: Vector2, bite: Vector2, him: Buddy, delta: float) -> void:
	var com := com_world()
	var grip := grip_world()
	var jaw := jaw_world()
	var bite_v := him.linear_velocity + Vector2(-(bite - him_world()).y, (bite - him_world()).x) * him.angular_velocity
	var lift := Vector2(0.0, -_gravity * body.gravity_scale * delta * 0.5)
	for pair in [[grip, handle, Vector2.ZERO], [jaw, bite, bite_v]]:
		var at: Vector2 = pair[0]
		var r := at - com
		var here := body.linear_velocity + Vector2(-r.y, r.x) * body.angular_velocity
		var want: Vector2 = (pair[1] - at) * 20.0 + pair[2]
		var change := (want - here).limit_length(20000.0 * delta) + lift
		body.apply_impulse(change * body.mass * 0.5, at - body.global_position)

func _let_go() -> void:
	_set_offset(Vector2.ZERO)
	var him := buddy()
	if him and _phase == CLAMPED:
		him.claim_impacts(body.item_id, base_mult(), 1.0)
	_phase = SETTLE
	_settle_t = 0.0
	_update_pip()

## The hand, as the cursor puts it: the handle less anything this added to it.
func _cursor() -> Vector2:
	if body.dragging and body.handle:
		return body.handle.global_position - body.hand_offset
	return hand_world()

func _set_offset(offset: Vector2) -> void:
	var delta := offset - _offset
	_offset = offset
	body.hand_offset = offset
	if body.dragging and body.handle:
		body.handle.global_position += delta

func _inertia_of(other: RigidBody2D) -> float:
	var state := PhysicsServer2D.body_get_direct_state(other.get_rid())
	if state and state.inverse_inertia > 0.0:
		return 1.0 / state.inverse_inertia
	return other.mass * 1200.0

func _on_stop() -> void:
	_rest_sprite()
	_offset = Vector2.ZERO
	if body:
		body.hand_offset = Vector2.ZERO
	if is_instance_valid(_excepted) and body:
		body.remove_collision_exception_with(_excepted)
	_excepted = null

# --- his headphones ----------------------------------------------------------------------

## His headphones, snipped off (D74, D62). While this exists his own are hidden
## (`EffectsPlayer`'s `phones_off`) and this is them: a drawn pair in his teal, dyed as he wears
## them, on the desk. After `seconds` they fly back to his head, and he wears them again — at once
## if the shears are binned first. They are given back the moment this leaves the tree however it
## leaves — a cleared desk, a knockout — so he is never left without them.
class Headphones extends RigidBody2D:
	const RIM := Color("26221d")
	const TEAL := Color("2eb8b3")
	const SHADE := Color("1f7f7c")
	const LIFE := 12.0
	var him: Buddy
	var source: StringName = &""
	var weapon: WeakRef
	var seconds := 4.0
	var tint := Color.WHITE
	var dyed := false
	var _age := 0.0
	var _home := false
	var _tell := 0.0

	## Takes his headphones off, if he is wearing them. True if it did.
	static func snip(buddy: Buddy, by: Node, off_seconds: float) -> bool:
		if buddy == null or buddy.get_node_or_null("SnippedHeadphones") != null:
			return false
		for node in buddy.get_parent().get_children():
			if node is Headphones and (node as Headphones).him == buddy:
				return false
		var phones := Headphones.new()
		phones.name = "SnippedHeadphones"
		phones.him = buddy
		phones.source = StringName(by.get(&"item_id")) if by else &""
		phones.weapon = weakref(by)
		phones.seconds = off_seconds
		buddy.get_parent().add_child(phones)
		phones.global_position = buddy.to_global(Vector2(0, -30))
		phones.global_rotation = buddy.global_rotation
		# Off his head and up, turning a little: they land on the desk the right way up often enough
		# to read as headphones, which a pair spinning end over end never does.
		phones.linear_velocity = buddy.linear_velocity + Vector2(randf_range(-160.0, 160.0), -420.0)
		phones.angular_velocity = randf_range(-2.5, 2.5)
		return true

	func _ready() -> void:
		collision_layer = 0
		collision_mask = WeaponAbility.WORLD_LAYER
		mass = 0.3
		continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
		var material := PhysicsMaterial.new()
		material.bounce = 0.35
		material.friction = 0.8
		physics_material_override = material
		var shape := CollisionShape2D.new()
		shape.name = "CollisionShape2D"
		var box := RectangleShape2D.new()
		box.size = Vector2(80, 30)
		shape.shape = box
		shape.position = Vector2(0, 14)
		add_child(shape)
		var worn := ItemDB.get_cosmetic(Economy.worn_cosmetic(CosmeticData.SLOT_PHONES))
		if worn and not worn.is_free():
			tint = worn.tint
			dyed = true
		_hide(true)

	func _physics_process(delta: float) -> void:
		_age += delta
		if not is_instance_valid(him) or _age >= LIFE:
			queue_free()
			return
		# A knockout drops the pair he was wearing onto the heap in the art (D62): these go home.
		if him.freeze or (him.health and him.health.down):
			queue_free()
			return
		# The shears gone from the desk: home now, not when the snip would have worn off.
		if not _home and (weapon == null or weapon.get_ref() == null
				or (weapon.get_ref() as Node).is_queued_for_deletion()):
			_age = maxf(_age, seconds)
		_tell -= delta
		if _tell <= 0.0 and not _home:
			_tell = 0.8
			EventBus.ability_event.emit(source, &"bareheaded", him.global_position)
		if _age < seconds:
			return
		if not _home:
			_home = true
			gravity_scale = 0.0
			AudioManager.play(&"zip", 0.05, -8.0, 0.8)
		# Home: steered back onto his head, turning to match him — an impulse toward the velocity
		# that gets there, never a write to it (D54).
		var head := him.to_global(Vector2(0, -30))
		var to := head - global_position
		if to.length() <= 14.0:
			var fx := WorldFX.of(self)
			if fx:
				fx.ring(head, 40.0, TEAL, 0.2, 2.0)
			AudioManager.play(&"clack", 0.05, -6.0, 1.3)
			EventBus.ability_event.emit(source, &"phones_back", him.global_position)
			queue_free()
			return
		var want := him.linear_velocity + to.normalized() * minf(900.0, to.length() * 8.0)
		apply_central_impulse((want - linear_velocity).limit_length(6000.0 * delta) * mass)
		var spin := wrapf(him.global_rotation - global_rotation, -PI, PI) * 10.0
		apply_torque_impulse((spin - angular_velocity) * 0.5)

	func _exit_tree() -> void:
		_hide(false)

	## His own pair, hidden or worn again.
	func _hide(off: bool) -> void:
		if not is_instance_valid(him) or him.art == null or him.art.body == null:
			return
		EffectsPlayer.material_for(him.art.body).set_shader_parameter(&"phones_off", 1.0 if off else 0.0)

	func _draw() -> void:
		var teal := tint if dyed else TEAL
		var shade := teal.darkened(0.3)
		# The band: the top half of an ellipse from cup to cup, as a rim and a teal stroke over it.
		var arch := PackedVector2Array()
		for i in 17:
			var a := PI + PI * float(i) / 16.0
			arch.append((Vector2(0, 16) + Vector2(cos(a) * 38.0, sin(a) * 30.0)).round())
		draw_polyline(arch, RIM, 10.0)
		draw_polyline(arch, teal, 5.0)
		# The cups, hanging from its ends.
		for x in [-46.0, 30.0]:
			draw_rect(Rect2(x - 2, 10, 20, 32), RIM)
			draw_rect(Rect2(x, 12, 16, 28), teal)
			draw_rect(Rect2(x + 10, 12, 6, 28), shade)
