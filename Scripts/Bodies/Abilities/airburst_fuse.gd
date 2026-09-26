class_name AirburstFuse
extends FuseAbility

## The cluster bomb's Airburst (docs/decisions.md D78): lit, right again, and it is set to burst in
## the air — throw it over him and it opens overhead, its bomblets coming down in a ring round him.
##
## The fuse archetype's hold, with his position as the trigger. Set, the casing's seams glow and it
## chirps. Out of the hand, the moment it is within `window` of over him and at least `height` above
## his skull, it **bursts**: the casing's own blast goes off up there, where it is, and its
## submunitions do not scatter round the casing — they fall on a ring of `ring` px round his feet,
## evenly, each one's fall drawn from the burst to where it lands. The same submunitions, the same
## blasts, the same multiplier (`ClusterBomb`); only where they land is chosen. Thrown wide, or
## held too long, it goes after `wait_seconds` wherever it is, the ordinary way.
##
## Row: `wait_seconds`, `window`, `height`, `ring`.

const GLOW := Color("ffd166")

var _glow: GPUParticles2D

## For the suites: where it burst, relative to him, and where the bomblets were sent.
var burst_over := Vector2.INF
var points: Array[Vector2] = []

func _on_hold() -> void:
	burst_over = Vector2.INF
	points.clear()
	_glow = emitter("airburst", &"chip", GLOW, 8, Vector2.ZERO, Vector2(0, -30), 180.0, 0.5)
	emit_from(_glow, true)
	sound(&"beep", -6.0, 1.3)
	sound(&"beep", -6.0, 1.7)

func _on_holding(_delta: float) -> void:
	if body.dragging:
		return
	var him := buddy()
	if him == null:
		return
	var rect := him.get_interaction_rect()
	var com := com_world()
	if absf(com.x - rect.get_center().x) <= num("window", 90.0) \
			and com.y <= rect.position.y - num("height", 60.0):
		_burst(him)

## Opens over him: the bomblets are sent to a ring round his feet, each fall drawn.
func _burst(him: Buddy) -> void:
	var cluster := body as ClusterBomb
	var rect := him.get_interaction_rect()
	var com := com_world()
	burst_over = com - rect.get_center()
	points.clear()
	var n := cluster.submunitions if cluster else 5
	var ring := num("ring", 70.0)
	var feet := Vector2(rect.get_center().x, rect.end.y)
	for i in n:
		var k := 0.0 if n <= 1 else float(i) / float(n - 1) * 2.0 - 1.0
		points.append(feet + Vector2(k * ring, 0.0))
	if cluster:
		cluster.scatter_points = points.duplicate()
	var fx := fx()
	if fx:
		for p in points:
			fx.tracer(com, p, Color("2a2e38"), 0.3, 3.0)
		fx.ring(com, 40.0, GLOW, 0.2, 3.0)
	tell(&"airburst", rect.get_center())
	AbilityCues.payoff(self, &"airburst", com, "airburst!")
	go(&"over_him")

func _before_go() -> void:
	emit_from(_glow, false)
