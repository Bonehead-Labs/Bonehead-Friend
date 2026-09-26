class_name RemoteFuse
extends FuseAbility

## The sticky bomb's Remote (docs/decisions.md D78): lit, right again, and it goes on the clicker —
## it will not go off until you click it.
##
## The fuse archetype's hold, with the clicker as the trigger. The fuse sparks stop and a red light
## starts blinking on the casing, with a chirp. From then it is a sticky bomb that waits: thrown, it
## still sticks where it lands (on him, most of the time: that is the item), and it goes off the
## moment the player right-clicks it — in the hand, lying on the desk, or riding him round the desk
## as he tries to shake it off. The light blinks faster as `wait_seconds` runs out, and at the end
## it goes by itself.
##
## A right-click on it is taken as the trigger (`_press_again`), never the bin: the one gesture
## that bins a live charge is Shift+right, as it always was (D24). While it is stuck to him he is
## `ticking` — pawing at it, wide-eyed.
##
## Row: `wait_seconds`, `blink`.

const LED := Color("ff3b30")
const LED_DIM := Color("5a1410")

var _led: Led
var _blink_t := 0.0
var _next_tell := 0.0

## For the suites: whether it was ever stuck to him while on the clicker.
var rode_him := false

func _on_hold() -> void:
	_blink_t = 0.0
	_next_tell = 0.0
	rode_him = false
	# The fuse's sparks stop: it is not burning down any more.
	var sparks := body.get_node_or_null("Fuse") as GPUParticles2D
	if sparks:
		sparks.emitting = false
	if _led == null:
		_led = Led.new()
		_led.name = "RemoteLed"
		_led.z_index = 32
		body.add_child(_led)
	_led.position = body.grip_offset + Vector2(0, -2)
	_led.visible = true
	_led.lit = true
	_led.queue_redraw()
	sound(&"beep", -6.0, 1.0)
	sound(&"beep", -8.0, 1.5)

## A click on it, held or not: now.
func _press_again() -> bool:
	go(&"clicked")
	return true

func _on_holding(delta: float) -> void:
	# Faster as the wait runs out: once a second, then five times.
	var left := clampf(1.0 - _t / maxf(num("wait_seconds", 10.0), 0.01), 0.0, 1.0)
	var period := lerpf(num("blink", 0.2), 1.0, left)
	_blink_t += delta
	if _blink_t >= period:
		_blink_t = 0.0
		if _led:
			_led.lit = not _led.lit
			_led.queue_redraw()
			if _led.lit:
				sound(&"beep", -16.0, 1.2 + 0.6 * (1.0 - left), 0.02)
	var sticky := body as StickyBomb
	if sticky and sticky.is_stuck():
		rode_him = true
		_next_tell -= delta
		if _next_tell <= 0.0:
			_next_tell = 0.6
			var him := buddy()
			if him:
				tell(&"ticking", him.get_interaction_rect().get_center())

func _before_go() -> void:
	if _led:
		_led.visible = false
	sound(&"beep", -4.0, 2.0)
	if went == &"clicked":
		AbilityCues.payoff(self, &"remote", com_world(), "click")

## A red light on the casing: a dark bead, lit on the blink.
class Led extends Node2D:
	var lit := true

	func _draw() -> void:
		draw_circle(Vector2.ZERO, 4.0, Color("141210"))
		draw_circle(Vector2.ZERO, 3.0, RemoteFuse.LED if lit else RemoteFuse.LED_DIM)
		if lit:
			draw_rect(Rect2(-2, -2, 1, 1), Color("ffd0c8"))
