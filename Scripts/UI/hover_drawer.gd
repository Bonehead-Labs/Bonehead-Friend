class_name HoverDrawer
extends Node

## Parks one half of the shell against its own edge and leaves a small mark behind it.
##
## The overlay lives on someone's desktop for eight hours. Even a tidy HUD is chrome over
## their work the whole time, so **this is how the shell behaves by default** — it is not a
## setting to find. The panel waits off screen, a small white arrow marks where it went, and
## putting the cursor on that arrow brings it out. Take the cursor away and it leaves again.
##
## **The arrow points the way the panel will travel to reveal itself** — right at the left
## edge, down at the top. That is the whole language: no label, nothing to learn.
##
## Hovering the arrow turns it into a **pin**. Click it and the panel stays out, the pin turns
## red, and hover stops mattering. Click again and it goes back to appearing on hover. The
## pinned state is per half and is remembered between sessions, because someone who pins their
## HUD open has told you how they want to work.
##
## The mark always rides its panel's *handle* — the status card, the tab bar — and never the
## whole panel. Hung off the bottom of the menu column it would sit in the middle of the
## screen whenever a page was open, which is the one place a permanent mark must not be.
##
## Three things this must not do, each of which the shell has been bitten by:
##
## - **Never animate a control a Container owns.** The panel handed in here is a direct child
##   of a plain `Control`, which is the one place in the shell where a control may own its own
##   rect — and owning it means owning its *size* too, since nothing lays such a child out.
## - **Never test the mouse against `get_global_rect()`.** The shell is scaled by a whole
##   number per `CanvasLayer`, so a control's global rect is in canvas space and wrong by
##   exactly that factor. Everything here goes through `UIScale`.
## - **Never poll `get_mouse_position()`.** That is the OS cursor, which no synthetic event can
##   move, so a drawer built on it cannot be driven by a test or a capture tool.

enum Edge { LEFT, RIGHT, TOP }

## How far past the edge the panel parks, so its border does not peek.
const OVERSHOOT := 6.0
## The mark's box. Small enough to ignore, big enough to hit without aiming.
const MARK_BOX := Vector2(22, 22)
## Slack around the panel that still counts as "the cursor is here", so it does not snap shut
## the instant the pointer strays a pixel past a button on its edge.
const GRACE := 24.0
const SPEED := 14.0

signal pin_toggled(pinned: bool)

var pinned := false:
	set(value):
		if pinned == value:
			return
		pinned = value
		if _mark:
			_mark.queue_redraw()
		_wake()
		pin_toggled.emit(pinned)

var _panel: Control
## The part of the panel the mark rides — the status card, the tab bar. Never the whole
## column, whose bottom edge moves to the middle of the screen when a page opens.
var _handle: Control
var _mark: Control
var _edge: int = Edge.LEFT
var _home := Vector2.ZERO
var _open := false
var _over_mark := false
var _mouse := Vector2(-9999, -9999)

func setup(panel: Control, host: Control, edge: int, handle: Control = null) -> void:
	_panel = panel
	_handle = handle if handle else panel
	_edge = edge
	_mark = Control.new()
	_mark.name = "DrawerMark"
	_mark.custom_minimum_size = MARK_BOX
	_mark.size = MARK_BOX
	# STOP, not IGNORE: the mark is the pin button. It is 22px square and sits against an
	# edge, so it costs the world almost nothing.
	_mark.mouse_filter = Control.MOUSE_FILTER_STOP
	_mark.tooltip_text = "Pin open"
	_mark.draw.connect(_draw_mark)
	_mark.gui_input.connect(_on_mark_input)
	host.add_child(_mark)
	if panel.get_viewport():
		_mouse = panel.get_viewport().get_mouse_position()
	set_process(true)
	set_process_input(true)
	_snap()

func _input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion:
		_mouse = motion.position
		_wake()

func _notification(what: int) -> void:
	# The cursor left the window entirely, which sends no further motion. Without this the
	# drawer stays out for as long as the player is working in another window — which is most
	# of the time, and exactly the case it exists for.
	if what == NOTIFICATION_WM_MOUSE_EXIT:
		_mouse = Vector2(-9999, -9999)
		_wake()

## The panel's resting place, recomputed by the owner whenever the layout moves.
func set_home(home: Vector2) -> void:
	_home = home
	_snap()
	_wake()

func is_open() -> bool:
	return _open or pinned

## The drawer only has anything to do after the mouse moves, the layout moves or the pin
## flips; everything it decides is a function of those. Between events it sleeps — two
## drawers polling `screen_rect()` every frame for eight hours was the largest "runs when
## nothing is happening" cost in the shell.
func _wake() -> void:
	set_process(true)

func _process(delta: float) -> void:
	if _panel == null or not is_instance_valid(_panel):
		set_process(false)
		return
	var over_mark := UIScale.screen_rect(_mark).grow(GRACE * 0.5).has_point(_mouse)
	if over_mark != _over_mark:
		_over_mark = over_mark
		_mark.queue_redraw()

	var wanted := pinned or over_mark or (_open \
		and UIScale.screen_rect(_panel).grow(GRACE).has_point(_mouse))
	if wanted != _open:
		_open = wanted
		_mark.queue_redraw()

	# Framerate-independent ease. The overlay runs at 20-60fps depending on Low Power, and a
	# fixed per-frame lerp would be a different animation at each.
	var target := _home if is_open() else _closed_position()
	_panel.position = _panel.position.lerp(target, 1.0 - exp(-SPEED * delta))
	if _panel.position.distance_to(target) < 0.5:
		_panel.position = target
		# Settled. Nothing here can change until the next event wakes it.
		set_process(false)
	_place_mark()

func _on_mark_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.button_index == MOUSE_BUTTON_LEFT and click.pressed:
		pinned = not pinned
		_mark.tooltip_text = "Unpin" if pinned else "Pin open"
		_mark.accept_event()
		UIMotion.punch(_mark, 1.25)
		_wake()

func _closed_position() -> Vector2:
	var size := _panel.size
	match _edge:
		Edge.LEFT:
			return Vector2(-size.x - OVERSHOOT, _home.y)
		Edge.RIGHT:
			return Vector2(_host_size().x + OVERSHOOT, _home.y)
		_:
			return Vector2(_home.x, -size.y - OVERSHOOT)

func _host_size() -> Vector2:
	var parent := _panel.get_parent() as Control
	return parent.size if parent else Vector2.ZERO

## Beside the handle once the panel is out, against the edge while it is away. Parked at the
## edge in both states it would sit on top of the thing it just revealed.
func _place_mark() -> void:
	if _mark == null or _panel == null:
		return
	var host := _host_size()
	# The handle's rect in host space. `_handle` is a descendant of `_panel`, so its offset
	# inside the panel plus the panel's home is where it lands when the panel is out.
	var handle_at := _home + _handle.get_global_position() - _panel.get_global_position()
	var handle_mid := handle_at + _handle.size * 0.5 - MARK_BOX * 0.5
	match _edge:
		Edge.LEFT:
			var x := handle_at.x + _handle.size.x + 3.0 if is_open() else 2.0
			_mark.position = Vector2(x, handle_mid.y)
		Edge.RIGHT:
			var x := handle_at.x - MARK_BOX.x - 3.0 if is_open() else host.x - MARK_BOX.x - 2.0
			_mark.position = Vector2(x, handle_mid.y)
		_:
			# Level with the tab bar, just outside it — never under the card below it, which
			# is the middle of the screen the moment a page is open.
			var y := handle_mid.y if is_open() else 2.0
			_mark.position = Vector2(maxf(2.0, handle_at.x - MARK_BOX.x - 3.0), y)

func _snap() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	_panel.position = _home if is_open() else _closed_position()
	_place_mark()
	if _mark:
		_mark.queue_redraw()

# --- the mark --------------------------------------------------------------

## White with a dark halo, because it is drawn over an unknown desktop — the same reason
## `art-direction.md` requires an outline on every sprite. Red once pinned: the one state
## where the shell is deliberately staying in the player's way.
func _draw_mark() -> void:
	if pinned or _over_mark:
		_draw_pin(UIStyle.LOCKED if pinned else Color(1, 1, 1, 0.95))
	else:
		_draw_arrow()

func _draw_arrow() -> void:
	var mid := MARK_BOX * 0.5
	var pointing := _point_direction()
	var tip := mid + pointing * 6.0
	var back := pointing.orthogonal() * 6.0
	var base := mid - pointing * 2.7
	var points := PackedVector2Array([tip, base + back, base - back])
	_mark.draw_colored_polygon(_grown(points, mid, 1.6), Color(0, 0, 0, 0.55))
	_mark.draw_colored_polygon(points, Color(1, 1, 1, 0.92))

## A push-pin: round head, tapering spike. Legible at 22px, which a keyhole or a padlock is
## not — and it is the icon every window that has ever offered this uses.
func _draw_pin(ink: Color) -> void:
	var mid := MARK_BOX * 0.5
	var head := mid - Vector2(0, 3.0)
	var spike := PackedVector2Array([
		Vector2(head.x - 3.0, head.y + 3.0),
		Vector2(head.x + 3.0, head.y + 3.0),
		Vector2(head.x, head.y + 9.0),
	])
	_mark.draw_circle(head, 5.6, Color(0, 0, 0, 0.55))
	_mark.draw_colored_polygon(_grown(spike, head, 1.6), Color(0, 0, 0, 0.55))
	_mark.draw_circle(head, 4.2, ink)
	_mark.draw_colored_polygon(spike, ink)

func _grown(points: PackedVector2Array, centre: Vector2, by: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in points:
		out.append(point + (point - centre).normalized() * by)
	return out

## The direction the panel travels to reveal itself — which is where the arrow points while
## it is away, and the reverse once it is out.
func _point_direction() -> Vector2:
	var reveal := Vector2.RIGHT
	match _edge:
		Edge.RIGHT:
			reveal = Vector2.LEFT
		Edge.TOP:
			reveal = Vector2.DOWN
	return reveal if not is_open() else -reveal
