class_name WorldFX
extends Node2D

## Bursts at the point of contact: bone chips off a hit, hearts off a kind act, a shower of
## both when he comes apart.
##
## The floating payout numbers (`FXLayer`, D30) already say *how much*. This says *where*,
## and it is the half that was missing: a hit registered as a number appearing in the top
## corner of the buddy and nothing happening at the place the bat actually landed.
##
## **Everything here is the UI glyph set at world scale.** A bone chip is `bone.png`, a
## heart is `heart.png` — the same two shapes the purse counts in, thrown off the point of
## impact. That is free, it is exactly on-brand, and it means a chip can never drift out of
## step with the currency it represents.
##
## Three things this must not do, all of them budget:
##   - it must cost nothing while idle. Particle nodes are pooled and parked, never spawned
##     per hit; a game that allocates on every contact for eight hours is a game that
##     stutters in hour three.
##   - it must be silent under Focus Mode Off, like every other moving thing (D21).
##   - it must not survive its own burst. One-shot emitters are restarted from the pool, so
##     the node count is constant for the life of the process.

## Emitters in the ring. Six is enough that a knockout's several bursts overlap without the
## oldest being cut off mid-flight, and small enough that the whole pool is built once at
## boot and never touched again.
const POOL := 6

## Chips per burst at the extremes of the damage range, and the damage that earns the top
## of it. Anchored on `balance.hit_stop_full_damage`, so the biggest shower and the longest
## hit-stop are the same hit — two channels saying one thing rather than two.
const CHIPS_MIN := 3
const CHIPS_MAX := 14

## Kind acts fire several times a second while petting, so their burst is deliberately the
## smallest thing here. The same reasoning that makes the petting *sound* quiet.
const HEART_CHIPS := 3

var _pool: Array[CPUParticles2D] = []
var _next := 0

func _ready() -> void:
	add_to_group(&"world_fx")
	for i in POOL:
		var emitter := CPUParticles2D.new()
		# Named, not left as @CPUParticles2D@31: a node with a generated name cannot be
		# found by a test and cannot be read in the remote scene tree.
		emitter.name = "Burst%d" % i
		emitter.emitting = false
		emitter.one_shot = true
		emitter.explosiveness = 1.0
		emitter.lifetime = 0.7
		emitter.direction = Vector2.UP
		emitter.spread = 180.0
		emitter.gravity = Vector2(0, 900)
		emitter.damping_min = 20.0
		emitter.damping_max = 60.0
		emitter.angular_velocity_min = -720.0
		emitter.angular_velocity_max = 720.0
		emitter.scale_amount_min = 0.7
		emitter.scale_amount_max = 1.4
		add_child(emitter)
		_pool.append(emitter)

	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.kindness_given.connect(_on_kindness_given)
	EventBus.buddy_state_changed.connect(_on_buddy_state_changed)

func _on_damage_dealt(info: HitInfo) -> void:
	var full := maxf(1.0, ItemDB.balance.hit_stop_full_damage)
	var heat := clampf(info.amount / full, 0.0, 1.0)
	burst(info.position, &"bone", UIStyle.BONES,
		int(lerpf(CHIPS_MIN, CHIPS_MAX, heat)), lerpf(110.0, 340.0, heat))

func _on_kindness_given(_source_id: StringName, _value: float, world_pos: Vector2) -> void:
	burst(world_pos, &"heart", UIStyle.HEARTS, HEART_CHIPS, 90.0)

## He comes apart, so the chips do too — a wide, slow shower rather than a spray, because
## this one is the round's full stop and wants to hang in the air for a moment.
func _on_buddy_state_changed(state: StringName) -> void:
	if state != &"knockout":
		return
	var buddy := get_tree().get_first_node_in_group(Buddy.GROUP_BUDDY) as Node2D
	if buddy == null:
		return
	burst(buddy.global_position, &"bone", UIStyle.BONES, 22, 260.0, 1.1)

## Throws `count` chips of one glyph from a point. Public because the arcade, the NPCs and
## anything else that wants a physical reaction should use this pool rather than building a
## second one.
func burst(at: Vector2, glyph: StringName, colour: Color, count: int, speed: float,
		lifetime: float = 0.7) -> void:
	if Settings.focus_intensity == Settings.Intensity.OFF:
		return
	# Subtle halves the shower rather than removing it: the setting is about how loud the
	# game is, and a hit that produces nothing at all reads as a hit that missed.
	if Settings.focus_intensity == Settings.Intensity.SUBTLE:
		count = maxi(1, count / 2)

	var emitter := _pool[_next]
	_next = (_next + 1) % _pool.size()
	emitter.restart()
	emitter.emitting = false
	emitter.global_position = at
	emitter.texture = UIStyle.glyph(glyph)
	emitter.color = colour
	emitter.amount = maxi(1, count)
	emitter.lifetime = lifetime
	emitter.initial_velocity_min = speed * 0.45
	emitter.initial_velocity_max = speed
	emitter.emitting = true
