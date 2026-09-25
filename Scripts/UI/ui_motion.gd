class_name UIMotion
extends RefCounted

## Everything in the menus that moves.
##
## The shell was correct and inert: buttons changed colour and panels appeared. This is
## what makes it feel like something — keys that depress under the cursor, cards that deal
## out, a coin that leaves the tile you bought from and lands in the purse.
##
## Three rules the whole file obeys, each of them a bug already paid for:
##
## 1. **Never animate `position` or `size` on a control inside a Container.** The container
##    owns both and rewrites them on the next layout pass, so the tween either fights it or
##    is silently discarded. `scale`, `rotation`, `pivot_offset` and `modulate` are ours;
##    everything else belongs to the layout. The one exception is `fly()`, which parents
##    its sprite to a bare full-rect Control precisely so it can use `position`.
## 2. **Never fade a panel's card.** The window is per-pixel transparent, so alpha below 1
##    shows the player's desktop through the UI (docs/decisions.md D6). Cards scale; only
##    the controls *on* a card may fade, because they fade against opaque cream.
## 3. **Motion is off when Focus Mode is off, and in headless.** Focus Mode off means the
##    game stops shouting, and that has to include the menus. Headless is the test runner:
##    a control mid-tween is at the wrong scale, and every hit test against it is a
##    coin flip.

# --- feel ------------------------------------------------------------------
#
# Timings are short and fixed; only the *amounts* scale with Focus Mode. A gentler setting
# should not mean a slower UI — sluggish is not calm, it is broken.
const HOVER_LIFT := 1.035
const PRESS_SQUASH := 0.955
const HOVER_TIME := 0.09
const PRESS_TIME := 0.05
const RELEASE_TIME := 0.30
const CARD_TIME := 0.22
const ROW_STEP := 0.022
## Past this many rows the cascade stops feeling like dealing cards and starts feeling
## like waiting for a list to load.
const ROW_CAP := 14

## Motion in a headless run, for the length of one check. A suite that has to see a real
## entrance — whether a card ever goes transparent on its way in — has no other way to, since
## headless is exactly where motion is off. Never set by the game; always put back.
static var run_in_headless := false

static func enabled() -> bool:
	if DisplayServer.get_name() == "headless" and not run_in_headless:
		return false
	return Settings.focus_intensity != Settings.Intensity.OFF

## How far things move, not how fast. Chaos is barely louder than Normal here on purpose:
## a menu that overshoots twice as far is not more fun, it is harder to click.
static func strength() -> float:
	match Settings.focus_intensity:
		Settings.Intensity.OFF: return 0.0
		Settings.Intensity.SUBTLE: return 0.65
		Settings.Intensity.CHAOS: return 1.15
		_: return 1.0

## Scale amounts move toward 1.0 as Focus Mode quietens, so every caller can write the
## amount it wants at full strength and forget the setting exists.
static func _amount(value: float) -> float:
	return lerpf(1.0, value, strength())

# --- pivots ----------------------------------------------------------------

enum Pivot { CENTRE, TOP, BOTTOM, BOTTOM_RIGHT }

## Scale needs a pivot, and a control's size is not known until it has been laid out — so
## this re-derives on every resize rather than sampling once and being wrong for the life
## of the panel.
static func pivot(control: Control, mode: int = Pivot.CENTRE) -> void:
	_apply_pivot(control, mode)
	var already := control.has_meta(&"_pivot_mode")
	control.set_meta(&"_pivot_mode", mode)
	if already:
		return
	control.resized.connect(func() -> void:
		_apply_pivot(control, int(control.get_meta(&"_pivot_mode"))))

static func _apply_pivot(control: Control, mode: int) -> void:
	var size := control.size
	match mode:
		Pivot.TOP: control.pivot_offset = Vector2(size.x * 0.5, 0.0)
		Pivot.BOTTOM: control.pivot_offset = Vector2(size.x * 0.5, size.y)
		Pivot.BOTTOM_RIGHT: control.pivot_offset = size
		_: control.pivot_offset = size * 0.5

# --- tween bookkeeping -----------------------------------------------------

## One named tween slot per control per kind of motion. Without this a fast cursor leaves
## two scale tweens racing on the same button and it settles wherever the loser stops.
static func _tween(control: Control, slot: StringName) -> Tween:
	# `has_meta` first: a null default does not suppress get_meta's error, because a null
	# default is indistinguishable from no default given.
	if control.has_meta(slot):
		var previous := control.get_meta(slot) as Tween
		if previous and previous.is_valid():
			previous.kill()
	var tween := control.create_tween()
	control.set_meta(slot, tween)
	return tween

static func _live(control: Control) -> bool:
	return enabled() and is_instance_valid(control) and control.is_inside_tree()

static func _sfx(id: StringName, volume_db: float = 0.0, spread: float = 0.05) -> void:
	if not enabled():
		return
	AudioManager.play(id, spread, volume_db)

# --- buttons ---------------------------------------------------------------

## Make a button feel like a key.
##
## `tile` and `sprite` are the row the button belongs to and the item picture in it. Both
## are optional and both are the reason a shop tile reads as one object: hovering the
## price lifts the whole row and nudges the toy inside it, so the thing you are buying
## reacts rather than the widget you are pointing at.
static func hook(button: Button, tile: Control = null, sprite: Control = null) -> void:
	# The tile and the sprite are stored on the button, not captured in the lambdas, so a
	# later, richer hook can upgrade an earlier one. `UIStyle.button()` hooks everything it
	# builds with no tile and no sprite — that is what gives a plain button its press feel —
	# and every call site that then hooked the same button *with* a tile was silently
	# discarded by a guard that only asked whether the button had been hooked at all. The
	# whole card-lifts-with-the-press effect existed and reached nothing.
	if tile != null:
		button.set_meta(&"_tile", tile)
	if sprite != null:
		button.set_meta(&"_sprite", sprite)
	if button.has_meta(&"_hooked"):
		return
	button.set_meta(&"_hooked", true)
	var tile_of := func() -> Control:
		return button.get_meta(&"_tile") as Control if button.has_meta(&"_tile") else null
	var sprite_of := func() -> Control:
		return button.get_meta(&"_sprite") as Control if button.has_meta(&"_sprite") else null
	button.mouse_entered.connect(func() -> void: _hover(button, tile_of.call(), sprite_of.call(), true))
	button.mouse_exited.connect(func() -> void: _hover(button, tile_of.call(), sprite_of.call(), false))
	button.button_down.connect(func() -> void: _down(button, tile_of.call()))
	button.button_up.connect(func() -> void: _up(button, tile_of.call()))

static func _hover(button: Button, tile: Control, sprite: Control, inside: bool) -> void:
	if not _live(button) or button.disabled:
		return
	_scale(button, HOVER_LIFT if inside else 1.0, HOVER_TIME, Tween.TRANS_QUAD)
	if tile:
		_scale(tile, 1.012 if inside else 1.0, HOVER_TIME, Tween.TRANS_QUAD)
	if sprite:
		if inside:
			_bob(sprite)
		else:
			_settle(sprite)
	if inside:
		_sfx(&"ui_hover", -26.0, 0.10)

static func _down(button: Button, tile: Control) -> void:
	if not _live(button) or button.disabled:
		return
	_scale(button, PRESS_SQUASH, PRESS_TIME, Tween.TRANS_QUAD)
	if tile:
		_scale(tile, 0.99, PRESS_TIME, Tween.TRANS_QUAD)

static func _up(button: Button, tile: Control) -> void:
	if not _live(button) or button.disabled:
		return
	# BACK on the way out is the whole feel: the key does not return to rest, it
	# overshoots slightly and settles, which is what a real key does.
	_scale(button, HOVER_LIFT, RELEASE_TIME, Tween.TRANS_BACK)
	if tile:
		_scale(tile, 1.012, RELEASE_TIME, Tween.TRANS_BACK)
	_sfx(&"ui_click", -10.0, 0.08)

static func _scale(control: Control, target: float, time: float,
		trans: Tween.TransitionType = Tween.TRANS_BACK) -> void:
	if not _live(control):
		if is_instance_valid(control):
			control.scale = Vector2.ONE
		return
	pivot(control)
	var tween := _tween(control, &"_scale_tween")
	tween.set_trans(trans).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE * _amount(target), time)

## A held hover on an item picture. Looping, but only one tween and only while the cursor
## is on the row — a game with a 3% idle budget cannot afford ambient motion that runs
## whether or not anyone is looking at it.
static func _bob(sprite: Control) -> void:
	if not _live(sprite):
		return
	pivot(sprite)
	var tween := _tween(sprite, &"_bob_tween")
	tween.set_loops()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(sprite, "rotation", _amount(1.10) - 1.0, 0.42)
	tween.tween_property(sprite, "rotation", 1.0 - _amount(1.10), 0.42)

static func _settle(sprite: Control) -> void:
	if not is_instance_valid(sprite):
		return
	var tween := _tween(sprite, &"_bob_tween")
	if not _live(sprite):
		sprite.rotation = 0.0
		return
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "rotation", 0.0, 0.18)

# --- reactions -------------------------------------------------------------

## A burst of chips over a control — the shell's own particles, for a win, a deed done, a
## finish worn. A one-shot `GPUParticles2D` parented to the control, so it rides the control's
## canvas layer and integer scale and draws above it; it frees itself when it is spent. The
## chip is a four-pixel square, the same one the world's payout numbers throw: pixel art must
## not have the one soft round particle on screen. Off at Focus Off and in headless like every
## other motion here, so no test ever meets one.
##
## `behind` puts the burst under the control's own face and over everything before it, for a
## control that *is* words: a toast's chips burst out of its edges instead of across the line
## it has just printed (D75). Every mastery rank used to arrive as "Baseball Bat rea[chips]
## mastery 1".
const CHIP_LIFETIME := 0.7
static var _chip_texture: Texture2D
static var _chip_materials: Dictionary = {}   ## speed -> ParticleProcessMaterial

static func sparkle(control: Control, colour: Color, count: int = 14, speed: float = 180.0,
		behind: bool = false) -> void:
	if not enabled() or control == null or not control.is_inside_tree():
		return
	var sparks := GPUParticles2D.new()
	sparks.name = "Sparkle"
	sparks.texture = _chips()
	sparks.process_material = _chip_material(speed)
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.lifetime = CHIP_LIFETIME
	sparks.amount = maxi(1, int(round(float(count) * strength())))
	sparks.position = control.size * 0.5
	sparks.modulate = colour
	# Above its siblings in the same layer: a burst under the very row it celebrates is a
	# burst nobody sees.
	sparks.z_index = 0 if behind else 60
	sparks.show_behind_parent = behind
	sparks.emitting = true
	control.add_child(sparks)
	control.get_tree().create_timer(CHIP_LIFETIME + 0.3).timeout.connect(sparks.queue_free)

static func _chips() -> Texture2D:
	if _chip_texture == null:
		var image := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_chip_texture = ImageTexture.create_from_image(image)
	return _chip_texture

static func _chip_material(speed: float) -> ParticleProcessMaterial:
	var key := int(round(speed))
	if _chip_materials.has(key):
		return _chip_materials[key]
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = speed * 0.4
	mat.initial_velocity_max = speed
	mat.gravity = Vector3(0, 380.0, 0)
	mat.scale_min = 1.0
	mat.scale_max = 2.2
	# Shrinking to nothing rather than fading: alpha on a pixel chip reads as a smudge.
	var curve := CurveTexture.new()
	var shape := Curve.new()
	shape.add_point(Vector2(0.0, 1.0))
	shape.add_point(Vector2(0.65, 0.85))
	shape.add_point(Vector2(1.0, 0.0))
	curve.curve = shape
	mat.scale_curve = curve
	mat.damping_min = 40.0
	mat.damping_max = 120.0
	_chip_materials[key] = mat
	return mat

## A progress bar that moves to its value rather than jumping there. `value` is a property,
## not a rect, so a Container cannot fight it; with motion off it is set outright.
static func fill(bar: Range, value: float, time: float = 0.35) -> void:
	if bar == null:
		return
	if not enabled() or not bar.is_inside_tree():
		bar.value = value
		return
	var tween := _tween(bar, &"_fill_tween")
	tween.tween_property(bar, "value", value, time).set_trans(Tween.TRANS_QUAD) \
		.set_ease(Tween.EASE_OUT)

## "Yes." A quick overshoot and settle — for the thing that just changed because the
## player pressed something.
static func punch(control: Control, amount: float = 1.16) -> void:
	if not _live(control):
		return
	pivot(control)
	var tween := _tween(control, &"_scale_tween")
	tween.tween_property(control, "scale", Vector2.ONE * _amount(amount), 0.07) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE, 0.26) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## "No." Rotation rather than a positional shake, because a shake written as `position`
## is erased by the next container layout — and the layout runs on the same frame, because
## refreshing the row that refused you changes its text and therefore its minimum size.
static func buzz(control: Control) -> void:
	_sfx(&"ui_denied", -8.0, 0.04)
	if not _live(control):
		return
	pivot(control)
	var tween := _tween(control, &"_buzz_tween")
	var swing := 0.05 * strength()
	for step in [swing, -swing, swing * 0.6, -swing * 0.35, 0.0]:
		tween.tween_property(control, "rotation", step, 0.045) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	flash(control, Color(1.35, 0.72, 0.80), 0.30)

## A colour wash that decays back to nothing. `modulate` multiplies, so values above 1
## bloom — which is how the gold on a purchase reads as light rather than as paint.
static func flash(control: Control, colour: Color, time: float = 0.35) -> void:
	if not _live(control):
		return
	var tween := _tween(control, &"_flash_tween")
	control.modulate = colour.lerp(Color.WHITE, 1.0 - strength())
	tween.tween_property(control, "modulate", Color.WHITE, time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## Bought. Gold bloom, a punch, and the sound — used for the tile, so the object the
## player paid for is the thing that celebrates.
static func confirm(control: Control) -> void:
	flash(control, Color(1.55, 1.40, 0.95), 0.45)
	punch(control, 1.09)

# --- entrances -------------------------------------------------------------

## One row unfurling. Scales up from a squashed state pinned to its top edge, so a column
## of them reads as cards being dealt rather than as a list fading in.
##
## It fades as well, so it is for rows *on* a card only. A card that sits straight on the window
## unrolls instead — the HUD's toast used this and spent its first 0.18 s as smoked glass.
static func rise(control: Control, delay: float = 0.0) -> void:
	if not _live(control):
		if is_instance_valid(control):
			control.scale = Vector2.ONE
			control.modulate = Color.WHITE
		return
	pivot(control, Pivot.TOP)
	control.scale = Vector2(1.0, lerpf(1.0, 0.55, strength()))
	control.modulate = Color(1, 1, 1, 1.0 - strength())
	var tween := _tween(control, &"_rise_tween")
	tween.set_parallel(false)
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.set_parallel(true)
	tween.tween_property(control, "scale", Vector2.ONE, 0.26) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "modulate", Color.WHITE, 0.18)

## Deal a whole page. Only the direct children that are visible, capped, because a shop
## with forty tiles should not take a second to arrive.
static func stagger(host: Node, step: float = ROW_STEP) -> void:
	if not enabled():
		return
	var index := 0
	for child in host.get_children():
		var control := child as Control
		if control == null or not control.visible:
			continue
		rise(control, index * step)
		index += 1
		if index >= ROW_CAP:
			return

## The card unrolling from the strip it hangs off. It grows downward from its own top
## edge — the edge welded to the open tab — and never fades, because a fading card shows
## the player's desktop through the text printed on it.
##
## `sound` is off for a card that arrives on its own rather than because the player opened it —
## the HUD's toast, which can land several times a minute.
static func unroll(card: Control, from: int = Pivot.TOP, sound: bool = true) -> void:
	if not _live(card):
		return
	pivot(card, from)
	card.scale = Vector2(1.0, lerpf(1.0, 0.72, strength()))
	var tween := _tween(card, &"_card_tween")
	tween.tween_property(card, "scale", Vector2.ONE, CARD_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if sound:
		_sfx(&"ui_open", -12.0, 0.03)

## The card rolling back up. `done` hides it — the caller cannot hide it up front or there
## would be nothing to animate, and cannot hide it after without knowing when the tween
## ended.
static func roll_up(card: Control, done: Callable, from: int = Pivot.TOP) -> void:
	if not _live(card):
		done.call()
		return
	pivot(card, from)
	# Scale only — no alpha. The window is transparent behind the card, so a fading card
	# is grey ink over the desktop for six frames (CLAUDE.md: never fade a card).
	var tween := _tween(card, &"_card_tween")
	tween.tween_property(card, "scale", Vector2(1.0, 0.04), 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		card.scale = Vector2.ONE
		done.call())
	_sfx(&"ui_close", -14.0, 0.03)

## Switching pages inside an open panel. The card stays put; only its contents change, so
## only the contents move.
static func page_in(page: Control) -> void:
	if not _live(page):
		return
	stagger(page)
	_sfx(&"ui_tab", -14.0, 0.06)

# --- flight ----------------------------------------------------------------

## The coin that leaves the tile you bought from and lands in the purse.
##
## `host` must be a plain full-rect Control, never a Container: this is the one thing in
## the file that animates `position`, and it can only do that because nothing is going to
## lay it out from underneath.
static func fly(host: Control, texture: Texture2D, colour: Color,
		from_global: Vector2, to_global: Vector2) -> void:
	if not _live(host) or texture == null:
		return
	var coin := TextureRect.new()
	coin.texture = UIStyle.boxed(texture, 16)
	coin.custom_minimum_size = Vector2(16, 16)
	coin.size = Vector2(16, 16)
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	coin.modulate = colour
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin.pivot_offset = Vector2(8, 8)
	host.add_child(coin)

	var start := from_global - Vector2(8, 8)
	var finish := to_global - Vector2(8, 8)
	coin.global_position = start
	# Lobbed rather than dragged in a straight line: up and out first, then down into the
	# chip. Two eased legs are cheaper than a curve and read the same at this distance.
	var apex := start.lerp(finish, 0.45) + Vector2(0, -46.0 * strength())

	var tween := coin.create_tween()
	tween.tween_property(coin, "global_position", apex, 0.17) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(coin, "scale", Vector2(1.3, 1.3), 0.17)
	tween.tween_property(coin, "global_position", finish, 0.24) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(coin, "scale", Vector2(0.55, 0.55), 0.24)
	tween.tween_callback(coin.queue_free)
