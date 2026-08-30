class_name DeviceLayer
extends Node2D

## The automation you have bought, standing on the desk doing it.
##
## Before this, a capstone was a number in a panel and nothing on screen: the player bought
## a Bat Sentry and the desk looked exactly as it had a moment earlier. "An idle desktop
## still looks alive" is one of the game's three pillars, and it was the one thing the
## whole automation system did not deliver.
##
## **Devices are decoration and nothing else.** They earn nothing, collide with nothing and
## are saved nowhere. `Economy` already pays automation from
## `Progression.automation_rate_per_second`, so a device that also emitted damage would pay
## twice for the same purchase; and a device that *was* the income would put the game's
## earnings behind a physics simulation that only runs while the window is visible. What
## is on screen is a picture of the rate, and the rate is the truth.
##
## **They are composited, not authored.** One mount sprite plus the item's own sprite, per
## `AugmentNode.device_mount` — three pictures for twenty-eight devices. Twenty-eight
## bespoke devices is most of an art budget, and they would all be the same idea drawn
## again.

const MOUNTS_DIR := "res://Assets/sprites/devices"

## Sideways nudge per mount, in art pixels. Only the claw arm needs one: it reaches out to
## the right, so what it is holding is not over its own base.
const MOUNT_NUDGE := {
	&"tripod": Vector2(0, 0),
	&"pedestal": Vector2(0, 0),
	&"arm": Vector2(7, 0),
}

## How far the held item sinks into the mount's head, in art pixels. Without it the two
## pictures touch at exactly one row and the item reads as hovering.
const MOUNT_OVERLAP := 5.0

## Devices stand in rows along the floor, from the left. Spacing is generous enough that a
## 128-cell prop does not overlap its neighbour, and the row wraps upward rather than
## marching off the side of a 480px play area — twenty-eight devices is 2,100px of desk.
const SPACING := Vector2(76.0, 92.0)
const MARGIN := Vector2(56.0, 70.0)
const ART_SCALE := 2.0

## How far a device travels on its idle cycle, and how long the cycle takes. Small and slow
## on purpose: this is peripheral vision furniture for an eight-hour session, not an
## animation anyone is meant to watch (D6).
const BOB := 5.0
const SWING_DEGREES := 9.0
const CYCLE := 1.6

var _devices: Dictionary = {}   ## augment id -> Node2D

func _ready() -> void:
	EventBus.augment_purchased.connect(_on_augment_purchased)
	EventBus.automation_toggled.connect(func(_id: StringName, _on: bool) -> void: _rebuild())
	EventBus.prestige_performed.connect(func(_gained: int) -> void: _rebuild())
	# The row is laid out against the window, which moves and resizes under the player.
	# `size_changed` on the viewport is not enough: the resize has not landed when a window
	# mode is applied, so a layout done then is against the previous window.
	OverlayManager.window_rect_changed.connect(func(_rect: Rect2i) -> void: _relayout())
	EventBus.focus_mode_changed.connect(func(_intensity: int) -> void: _rebuild())
	_rebuild()

func _on_augment_purchased(node_id: StringName, _level: int) -> void:
	var node := ItemDB.get_augment(node_id)
	if node and node.is_automation:
		_rebuild()

## One device per owned, switched-on capstone. Rebuilt wholesale rather than diffed: this
## runs on a purchase, a toggle and a reincarnation, none of which happen sixty times a
## second, and a diff that gets it wrong leaves a ghost device on the desk forever.
func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_devices.clear()

	for node in Progression.automation_nodes():
		if not Progression.is_automation_enabled(node.id):
			continue
		var device := _build(node)
		if device == null:
			continue
		add_child(device)
		_devices[node.id] = device
	_relayout()

func _build(node: AugmentNode) -> Node2D:
	var mount_texture := _mount_for(node)
	var item_texture := _item_art(node.item_id)
	if mount_texture == null and item_texture == null:
		return null

	var device := Node2D.new()
	# Named after the augment, so the remote scene tree and any test can find it. A device
	# called @Node2D@41 is invisible to both.
	device.name = "Device_%s" % node.id

	if mount_texture:
		var mount := Sprite2D.new()
		mount.name = "Mount"
		mount.texture = mount_texture
		mount.scale = Vector2(ART_SCALE, ART_SCALE)
		device.add_child(mount)

	if item_texture:
		var held := Sprite2D.new()
		held.name = "Held"
		held.texture = item_texture
		held.scale = Vector2(ART_SCALE, ART_SCALE)
		held.position = _stack_offset(mount_texture, item_texture, node.device_mount)
		device.add_child(held)
		_animate(held, node.device_mount)

	return device

## The idle cycle. Off entirely when Focus Mode is Off — that setting is the promise that a
## player in a meeting can stop the desktop moving *without giving up the income* (D21), and
## a device that keeps swinging through it breaks exactly that promise. The income is
## untouched either way, because the income was never here.
func _animate(held: Sprite2D, mount: StringName) -> void:
	if Settings.focus_intensity == Settings.Intensity.OFF:
		return
	var tween := held.create_tween().set_loops()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if mount == &"pedestal":
		var rest := held.position
		tween.tween_property(held, "position", rest + Vector2(0, -BOB), CYCLE * 0.5)
		tween.tween_property(held, "position", rest, CYCLE * 0.5)
	else:
		tween.tween_property(held, "rotation_degrees", SWING_DEGREES, CYCLE * 0.5)
		tween.tween_property(held, "rotation_degrees", -SWING_DEGREES, CYCLE * 0.5)

## Where the held item sits so that it stands *on* the mount rather than beside or above it.
##
## Measured from the two pictures' own opaque bounds rather than authored per item: the
## roster is twenty-eight items whose art ranges from a 10px baseball to a 76px massage
## chair, and a table of hand-tuned offsets would be twenty-eight numbers to maintain and
## get wrong. Both sprites are centred in their cells by `item_postprocess.py`, so centre
## to centre is (half the mount) + (half the item) - the overlap.
func _stack_offset(mount: Texture2D, held: Texture2D, mount_id: StringName) -> Vector2:
	var nudge: Vector2 = MOUNT_NUDGE.get(mount_id, Vector2.ZERO)
	var lift := (_content_height(mount) + _content_height(held)) * 0.5 - MOUNT_OVERLAP
	return (nudge + Vector2(0, -lift)) * ART_SCALE

func _content_height(texture: Texture2D) -> float:
	if texture == null:
		return 0.0
	var image := texture.get_image()
	if image == null:
		return float(texture.get_height())
	var used := image.get_used_rect()
	return float(used.size.y if used.size.y > 0 else image.get_height())

## Rows along the bottom of the play area. Read from the viewport rather than from
## `Settings.play_area_size`: in overlay mode the window is the whole screen and the two
## disagree.
func _relayout() -> void:
	var rect := get_viewport_rect()
	var per_row := maxi(1, int((rect.size.x - MARGIN.x * 2.0) / SPACING.x))
	var index := 0
	for id in _devices:
		var device := _devices[id] as Node2D
		if device == null:
			continue
		var column := index % per_row
		var row := index / per_row
		device.position = Vector2(
			MARGIN.x + float(column) * SPACING.x,
			rect.size.y - MARGIN.y - float(row) * SPACING.y)
		index += 1

func _mount_for(node: AugmentNode) -> Texture2D:
	if node.device_mount == &"":
		return null
	var path := "%s/mount_%s.png" % [MOUNTS_DIR, node.device_mount]
	return ResourceLoader.load(path) as Texture2D if ResourceLoader.exists(path) else null

## The item's world sprite, which is what the device is holding. Cursor powers have no world
## sprite by design (docs/art-direction.md), so those devices hold their icon instead —
## which is the same picture at half the size, and reads correctly on a claw arm.
func _item_art(item_id: StringName) -> Texture2D:
	for path in ["res://Assets/sprites/items/%s.png" % item_id,
			"res://Assets/sprites/icons/%s.png" % item_id]:
		if ResourceLoader.exists(path):
			return ResourceLoader.load(path) as Texture2D
	return null

## How many devices are standing on the desk. Read by `loop_check`.
func device_count() -> int:
	return _devices.size()
