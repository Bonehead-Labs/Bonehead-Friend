class_name WheelGame
extends ArcadeGame

## The Wheel: a ring of wedges, a pointer, one press.
##
## The cheapest machine in the arcade to build and the fastest to read, which is why it is
## first in the room and why it is the one that has to feel best (docs/decisions.md D32).
##
## **The odds are the geometry.** A wedge's share of the ring *is* its chance, so a player
## who counts the wedges knows the wheel — there is no hidden table and no weighting that
## contradicts what they are looking at. That is also why the wheel is drawn here rather than
## assembled out of Controls: one `_draw()` owns both the picture and the probabilities, so
## they cannot drift apart.
##
## **The outcome is chosen before the wheel moves.** Animating a physical spin and reading
## off where it stopped is how a wheel lands between two wedges and has to be nudged, or
## worse, pays the wedge next door. Here `_pick()` names the winner, `_rest_angle()` says
## exactly where that wedge sits under the pointer, and the tween's final value *is* that
## angle — so the wheel can only ever stop on a wedge, and on the one that was paid.
##
## Rule zero still holds: nothing in this file touches `Economy`. It reports a `Prize` and
## `ArcadePanel` does the paying.

# --- the table -------------------------------------------------------------
#
# Anchored to `COST`, and to Dollars being earned at roughly one per damaging hit
# (`balance.dollars_per_hit`), so a spin is about twenty seconds of active play.
#
# The wheel returns **0.905 Dollars per Dollar spent** — 430 Dollars of prize spread over 19
# wedge-weights against a 25 cost — plus a boost or a garnish on one spin in ten. A house
# edge that small is deliberate: Dollars buy cosmetics and boons and nothing that earns (D31),
# so an arcade that bleeds a player dry costs them hats, and one that pays over 1.0 makes
# spinning strictly better than any other use of the currency. Near-even, with the fun on top.
#
# Every figure below is at the lowest stake. A higher stake multiplies the Dollars wedges and
# nothing else (`ArcadeGame.STAKES`), so the 0.905 holds on every rung and the boost and the
# Bones are worth relatively less the more you bet — never more.

const COST := 25.0
const SMALL := 10.0     ## 0.4x the spin, and eight of the nineteen weights.
const BIG := 50.0       ## 2x, on two wedges facing each other across the ring.
const JACKPOT := 250.0  ## 10x, on one wedge in nineteen — 5% of the ring.

## Five minutes at x2 through the one shared timed slot. Well inside `BOOST_MAX_MULT` and
## `BOOST_MAX_SECONDS`; the cap is where a boost stops being a prize and starts being income.
const BOOST_MULT := 2.0
const BOOST_SECONDS := 300.0
## This machine's own slot, so a second win refreshes the wheel's boost instead of stacking
## a second one beside it.
const BOOST_ID := &"wheel_boost"

## The garnish wedge pays **Bones**, never Hearts, and pays a little over half of what a
## single play is allowed. Hearts are the currency the whole garnish cap exists to protect —
## automation is Hearts-priced and that is the spine of the design (D2, D32) — so the wheel
## keeps away from them entirely rather than approaching the line and trusting the clamp.
const GARNISH_SHARE := 0.55

## There is no hat on this wheel. `prize_cosmetic()` exists and the page refuses it, because
## the cosmetics store is M3.5-B: a player who watches themselves win a hat and does not own
## one is worse off than a player who was never offered it. The Bones wedge holds that seat
## until the store lands.

# --- the face --------------------------------------------------------------

## UI pixels, before `UIScale`. `body_height` matches it exactly, so the cabinet is the same
## height spinning as it is idle and the page never moves under the cursor mid-spin.
const FACE := 262
## Room above the rim for the pointer.
const POINTER_REACH := 12.0
## Hub radius, and where in the band a wedge's mark sits (0 at the hub, 1 at the rim).
const HUB_FRACTION := 0.38
const GLYPH_RING := 0.62
## The marks on the ring and the hub are drawn at twice the glyph — a 16px glyph on a 262px
## wheel was a speck. Boxed by a whole number through `UIStyle.boxed()`, so still crisp (D27).
const MARK_BOX := 32
## Straight up. Screen y grows downward, so angles increase clockwise and this is -90 degrees.
const POINTER_ANGLE := -PI / 2.0

# --- the spin --------------------------------------------------------------

const TURNS := 4.0
const SPIN_TIME := 2.6
## A short pull backwards before it goes, which is what makes the release read as a release.
const WIND_UP := 0.11
const WIND_UP_TIME := 0.14
## How far off a wedge's centre the wheel is allowed to settle, as a fraction of half a span.
## The outcome is already decided, so this is pure presentation — and without it the wheel
## stops dead centre every single time, which is the tell that it was scripted.
const LAND_JITTER := 0.3
## The floor between audible ticks. Early in a spin the wheel crosses forty wedges a second;
## the ear only wants the last dozen, and the eight-voice pool cannot afford the rest.
const TICK_FLOOR_MS := 45
## The pointer's kick as a wedge goes past, and how quickly it falls back.
const FLICK_MAX := 0.30
const FLICK_DECAY := 0.07

const KIND_DOLLARS := &"dollars"
const KIND_BOOST := &"boost"
const KIND_GARNISH := &"garnish"
const KIND_NOTHING := &"nothing"

## The legend's lines. Wedges of one family share a line and add their odds together.
const FAMILY_CASH := &"cash"
const FAMILY_JACKPOT := &"jackpot"
const FAMILY_BOOST := &"boost"
const FAMILY_BONES := &"bones"
const FAMILY_NOTHING := &"nothing"

## One wedge: what it pays, how wide it is, and how it is printed. `start` and `span` are
## derived from `weight` in `_build_ring()` — the picture and the odds come off the same
## number, which is the whole reason a wheel is an honest machine.
class Wedge extends RefCounted:
	## Always written by the factory below that built it. Left empty rather than defaulted to
	## a kind, so a wedge nobody finished reports nothing rather than paying something.
	var kind: StringName = &""
	var weight := 1.0
	var fill := Color.WHITE
	var glyph: StringName = &"cross"
	## The mark's colour on the wedge itself.
	var ink := Color.BLACK
	## The legend line this wedge belongs to, and that line's colour on the sunk stage.
	## Wedges sharing a family share a row, and the row's odds are their weights added up.
	## An id rather than the printed words: the words carry Dollars, which follow the stake.
	var family: StringName = &""
	var family_ink := Color.BLACK
	## At the lowest stake. `_prize_for()` multiplies by the stake the spin was paid at.
	var dollars := 0.0
	## Played on top of the page's own reaction. Only the jackpot has one.
	var sound: StringName = &""
	var start := 0.0
	var span := 0.0

## One legend row, built from the ring rather than authored beside it, so an edit to the
## table cannot leave the printed odds lying.
class LegendRow extends RefCounted:
	var glyph: StringName = &"cross"
	var ink := Color.BLACK
	var family: StringName = &""
	var weight := 0.0
	## The printed line, rewritten when the stake moves.
	var label: Label = null

var _wedges: Array[Wedge] = []
var _legend: Array[LegendRow] = []
var _total_weight := 0.0

var _face: Control = null
## The wheel's rotation. Every wedge is drawn at `start + _angle`, and this is the only thing
## the spin animates.
var _angle := 0.0
## When the last wedge passed the pointer. Drives both the tick rate limit and the pointer's
## kick, which is why it is one figure and not two.
var _last_tick_ms := 0

func _init() -> void:
	display_name = "The Wheel"
	blurb = "One press, one wedge. The odds are the wedge widths, so you can count them."
	mark = &"star"
	accent = &"gold"
	play_caption = "Spin"
	cost = COST
	body_height = FACE
	_build_ring()

# --- the ring --------------------------------------------------------------

## The wedges in the order they physically sit, which is also the order they are drawn.
##
## Laid out rather than sorted: the three blank wedges sit roughly a third of the ring apart
## and so do the three rare ones, so no side of the wheel is dead and the pointer is never a
## long way from something worth landing on.
func _build_ring() -> void:
	_wedges.assign([
		_cash(2.0, SMALL), _nothing(2.0), _cash(1.0, BIG), _boost(1.0),
		_cash(2.0, SMALL), _nothing(2.0), _cash(2.0, SMALL), _garnish(1.0),
		_cash(1.0, BIG), _nothing(2.0), _cash(2.0, SMALL), _jackpot(1.0),
	])

	_total_weight = 0.0
	for wedge in _wedges:
		_total_weight += wedge.weight

	var cursor := 0.0
	for wedge in _wedges:
		wedge.start = cursor
		wedge.span = TAU * wedge.weight / _total_weight
		cursor += wedge.span
	# The last wedge is closed against TAU rather than against the running sum. Twelve
	# divisions leave the total a hair short, and `_under_pointer()` walks these ranges — a
	# gap at the seam is an angle that belongs to no wedge at all.
	_wedges[-1].span = TAU - _wedges[-1].start

	# Wedge zero centred on the pointer at rest, through the same maths a landing uses.
	_angle = _rest_angle(0, 0.0)

## A Dollars wedge. The fill is derived from the amount rather than authored: the wheel's
## one colour rule is that the greener the wedge the more it pays, and deriving it means a
## re-tuned amount cannot end up wearing the wrong face.
func _cash(weight: float, amount: float) -> Wedge:
	var wedge := Wedge.new()
	wedge.kind = KIND_DOLLARS
	wedge.weight = weight
	wedge.dollars = amount
	wedge.glyph = &"dollar"
	var rare := amount >= BIG
	wedge.fill = UIStyle.DOLLARS if rare else UIStyle.PANEL
	wedge.ink = UIStyle.PANEL if rare else UIStyle.DOLLARS
	wedge.family = FAMILY_CASH
	wedge.family_ink = UIStyle.DOLLARS
	return wedge

func _jackpot(weight: float) -> Wedge:
	var wedge := Wedge.new()
	wedge.kind = KIND_DOLLARS
	wedge.weight = weight
	wedge.dollars = JACKPOT
	wedge.glyph = &"star"
	wedge.fill = UIStyle.HEARTS
	wedge.ink = UIStyle.PANEL
	wedge.family = FAMILY_JACKPOT
	wedge.family_ink = UIStyle.HEARTS
	wedge.sound = &"jackpot"
	return wedge

func _boost(weight: float) -> Wedge:
	var wedge := Wedge.new()
	wedge.kind = KIND_BOOST
	wedge.weight = weight
	wedge.glyph = &"bolt"
	# Teal is the skin's only cool colour and it is spent on automation, which is what a
	# timed multiplier is a few minutes of. It is the one wedge that pays in time.
	wedge.fill = UIStyle.TEAL
	wedge.ink = UIStyle.PANEL
	wedge.family = FAMILY_BOOST
	wedge.family_ink = UIStyle.TEAL
	return wedge

func _garnish(weight: float) -> Wedge:
	var wedge := Wedge.new()
	wedge.kind = KIND_GARNISH
	wedge.weight = weight
	wedge.glyph = &"bone"
	wedge.fill = UIStyle.BONES
	wedge.ink = UIStyle.PANEL
	wedge.family = FAMILY_BONES
	wedge.family_ink = UIStyle.BONES
	return wedge

func _nothing(weight: float) -> Wedge:
	var wedge := Wedge.new()
	wedge.kind = KIND_NOTHING
	wedge.weight = weight
	wedge.glyph = &"cross"
	wedge.fill = UIStyle.SUNK
	wedge.ink = UIStyle.TEXT
	wedge.family = FAMILY_NOTHING
	wedge.family_ink = UIStyle.TEXT_DIM
	return wedge

# --- the cabinet -----------------------------------------------------------

func _build_body(host: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	# Named, like every control the shell builds in code: an unnamed one comes out as
	# `@HBoxContainer@31`, which no test can find and nobody can read in the remote tree.
	row.name = "WheelRow"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.add_child(row)

	_face = Control.new()
	_face.name = "WheelFace"
	_face.custom_minimum_size = Vector2(FACE, FACE)
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The whole picture is a function of the control's own rect, so a resize has to repaint.
	# A Control does not redraw on resize by itself.
	_face.resized.connect(_face.queue_redraw)
	_face.draw.connect(_draw_wheel)
	row.add_child(_face)

	# The wheel is 262px on a stage over 600 wide, so its legend — the wheel's own printed
	# odds, which is why it is on the stage beside it rather than down in the paytable — costs
	# nothing but horizontal space that was already spare. Every string in it is short on
	# purpose: a legend that grew past the stage would widen the card for every page.
	var legend := VBoxContainer.new()
	legend.name = "WheelLegend"
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	legend.add_theme_constant_override("separation", 6)
	legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	legend.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(legend)
	_legend = _legend_rows()
	for entry in _legend:
		legend.add_child(_build_legend_row(entry))

	# A resting line, so the display says something before the first spin — and it says the
	# one number a player wants before they hand over 25 Dollars.
	say("%d%% of the ring pays nothing." % _percent(_weight_of(KIND_NOTHING)))

## The legend, folded out of the ring itself. First-seen order, so it reads down the table.
func _legend_rows() -> Array[LegendRow]:
	var rows: Array[LegendRow] = []
	var seen: Dictionary = {}
	for wedge in _wedges:
		if seen.has(wedge.family):
			var already: LegendRow = seen[wedge.family]
			already.weight += wedge.weight
			continue
		var row := LegendRow.new()
		row.glyph = wedge.glyph
		row.ink = wedge.family_ink
		row.family = wedge.family
		row.weight = wedge.weight
		seen[wedge.family] = row
		rows.append(row)
	return rows

## A legend line's words at the current stake. The Dollars follow it; the boost and the Bones
## do not, because neither is sized by the stake (D32, `ArcadeGame.STAKES`).
func _family_text(family: StringName) -> String:
	var times := float(stake_multiple())
	match family:
		FAMILY_CASH:
			return "%s / %s" % [UIStyle.format_amount(SMALL * times),
				UIStyle.format_amount(BIG * times)]
		FAMILY_JACKPOT:
			return UIStyle.format_amount(JACKPOT * times)
		FAMILY_BOOST:
			return "x%d for %dm" % [int(BOOST_MULT), int(BOOST_SECONDS / 60.0)]
		FAMILY_BONES:
			return "Bones"
	return "Nothing"

func _stake_changed() -> void:
	for entry in _legend:
		if entry.label:
			entry.label.text = _family_text(entry.family)

func _build_legend_row(entry: LegendRow) -> Control:
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 6)
	# Through `UIStyle.icon()`, which delivers the glyph at exactly its 16px box (D27).
	# Boxed at twice the glyph: one art pixel to two screen pixels, whole-number crisp, and a
	# legend that holds its own beside a wheel this size.
	line.add_child(UIStyle.icon(entry.glyph, MARK_BOX, entry.ink))

	# Three of the five rows are figures and the odds column is figures throughout, so the
	# whole legend is set in the display face rather than mixing two faces down one column —
	# the body face draws 5 as a rounded form that reads as an 8.
	var what := UIStyle.label(_family_text(entry.family), UIStyle.LABEL, entry.ink)
	what.theme_type_variation = &"Numeral"
	what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(what)
	entry.label = what

	var odds := UIStyle.label("%d%%" % _percent(entry.weight), UIStyle.LABEL, UIStyle.TEXT_DIM)
	odds.theme_type_variation = &"Numeral"
	line.add_child(odds)
	return line

# --- playing ---------------------------------------------------------------

func _play() -> void:
	var index := _pick()
	var wedge := _wedges[index]
	var landing := _rest_angle(index, randf_range(-LAND_JITTER, LAND_JITTER))
	# Strictly ahead of where the wheel is standing, so the tween always runs forwards and
	# the four turns are four turns rather than three and a bit. Bounded at three passes
	# because `_finish()` folds `_angle` back into one revolution.
	while landing < _angle + 0.01:
		landing += TAU
	var target := landing + TAU * TURNS

	# Focus Mode Off means the menus stop moving too (D21), and headless is the test runner.
	# The wheel still lands where it was going to land; it just gets there at once.
	if not UIMotion.enabled():
		_place(target)
		_finish(wedge)
		return

	say("Spinning...")
	var tween := create_tween()
	tween.tween_method(_set_angle, _angle, _angle - WIND_UP, WIND_UP_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# QUART out is the shape of a wheel with a brake on it: most of the travel is over in the
	# first second and the last wedge or two crawl past, which is where the whole spin lives.
	tween.tween_method(_set_angle, _angle - WIND_UP, target, SPIN_TIME) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void: _finish(wedge))

## Weighted by wedge width, which is the same number the wedge is drawn at.
func _pick() -> int:
	var roll := randf() * _total_weight
	for i in _wedges.size():
		roll -= _wedges[i].weight
		if roll < 0.0:
			return i
	return _wedges.size() - 1

## Where the wheel has to stand for `index` to sit under the pointer, `offset` being a
## fraction of half a span either side of dead centre.
func _rest_angle(index: int, offset: float) -> float:
	var wedge := _wedges[index]
	return POINTER_ANGLE - (wedge.start + wedge.span * (0.5 + offset * 0.5))

func _finish(wedge: Wedge) -> void:
	# The pointer stops kicking the moment the wheel does.
	_last_tick_ms = 0
	# Folded back into a single revolution now the spin is over. Invisible — every wedge is
	# drawn modulo TAU — and it is what stops `_angle` climbing by four and a half turns per
	# spin until the landing search in `_play()` is walking hundreds of revolutions to catch
	# up with it, and until a float this large has lost the precision a wedge boundary needs.
	_place(fposmod(_angle, TAU))
	if is_instance_valid(_face):
		# `scale`, not `size`: the face is a child of a Container, which owns its rect and
		# would rewrite a tweened size on the next layout pass.
		UIMotion.punch(_face, 1.06)
	if wedge.sound != &"":
		AudioManager.play(wedge.sound, 0.0, -4.0)
	report(_prize_for(wedge))

func _prize_for(wedge: Wedge) -> ArcadeGame.Prize:
	match wedge.kind:
		KIND_DOLLARS:
			# The table is written at the lowest stake and scaled by the one this spin was paid
			# at, so the odds and the return per Dollar are the same on every rung.
			var won := wedge.dollars * float(stake_multiple())
			if wedge.family == FAMILY_JACKPOT:
				return prize_dollars(won, "Jackpot! +%s Dollars" % UIStyle.format_amount(won))
			return prize_dollars(won)
		KIND_BOOST:
			return prize_boost(BOOST_ID, BOOST_MULT, BOOST_SECONDS)
		KIND_GARNISH:
			# Read at report time, not at build time: the cap is anchored to acts at the
			# player's *current* multipliers, so a garnish is worth about ten seconds of play
			# at every point in the game rather than ten seconds of the play they had when
			# they first opened the page.
			var amount := garnish_cap(Economy.BONES) * GARNISH_SHARE
			return prize_garnish(Economy.BONES, amount,
				"+%s Bones" % UIStyle.format_amount(amount))
	return prize_nothing()

# --- rotation --------------------------------------------------------------

## Move the wheel and repaint. Nothing else writes `_angle`.
func _place(value: float) -> void:
	_angle = value
	if is_instance_valid(_face):
		_face.queue_redraw()

## The same, plus the tick a wedge makes going past the pointer — which is the sound of the
## wheel slowing down, and most of what a spin actually feels like.
func _set_angle(value: float) -> void:
	var before := _under_pointer()
	_place(value)
	if _under_pointer() != before:
		_tick()

func _tick() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_tick_ms < TICK_FLOOR_MS:
		return
	_last_tick_ms = now
	AudioManager.play(&"wheel_tick", 0.10, -18.0)

## The wedge the pointer is over right now.
func _under_pointer() -> int:
	var at := fposmod(POINTER_ANGLE - _angle, TAU)
	for i in _wedges.size():
		if at < _wedges[i].start + _wedges[i].span:
			return i
	return _wedges.size() - 1

## The pointer's kick, as a function of how long ago a wedge last went past. Decayed on
## wall-clock rather than per frame, so it looks the same under the Low Power FPS governor as
## it does at 60 — and scaled by Focus Mode, which takes it to nothing when motion is off.
func _flick() -> float:
	if _last_tick_ms <= 0:
		return 0.0
	var since := float(Time.get_ticks_msec() - _last_tick_ms) / 1000.0
	return FLICK_MAX * exp(-since / FLICK_DECAY) * UIMotion.strength()

# --- drawing ---------------------------------------------------------------

func _draw_wheel() -> void:
	var box := _face.size
	# Height is what the wheel is short of — the stage reserves `FACE` and the card is much
	# wider than that — so the pointer's headroom comes out of the vertical measurement only.
	var radius := minf(box.x * 0.5, (box.y - POINTER_REACH) * 0.5) - 1.0
	if radius < 8.0:
		return
	var centre := Vector2(box.x * 0.5, POINTER_REACH + radius)
	var hub := radius * HUB_FRACTION
	var band := radius - hub
	var mid := hub + band * 0.5
	var rule := float(UIStyle.BORDER_WIDTH)

	# A thick arc is a true annulus: a polyline's width is laid off along the normal, which
	# on a circle is radial, and its flat end caps therefore fall on the wedge boundaries.
	for wedge in _wedges:
		var from := wedge.start + _angle
		_face.draw_arc(centre, mid, from, from + wedge.span, _steps(wedge.span),
			wedge.fill, band)

	for wedge in _wedges:
		var dir := Vector2.from_angle(wedge.start + _angle)
		_face.draw_line(centre + dir * hub, centre + dir * radius, UIStyle.EDGE, rule)

	_face.draw_arc(centre, radius - rule * 0.5, 0.0, TAU, 72, UIStyle.EDGE, rule)

	# The wedge under the pointer wears a heavier rule. Weight rather than a colour wash:
	# in this skin a hard black edge is what makes something an object, so more of it is
	# what makes one the object — and it survives a player who cannot use the palette's
	# red/green distinction, which is roughly one in twelve.
	var chosen := _wedges[_under_pointer()]
	var lit := rule + 2.0
	var edge_from := chosen.start + _angle
	_face.draw_arc(centre, radius - lit * 0.5, edge_from, edge_from + chosen.span,
		_steps(chosen.span), UIStyle.EDGE, lit)
	for at in [edge_from, edge_from + chosen.span]:
		var dir := Vector2.from_angle(at)
		_face.draw_line(centre + dir * hub, centre + dir * radius, UIStyle.EDGE, lit)

	_draw_marks(centre, hub + band * GLYPH_RING)

	_face.draw_circle(centre, hub, UIStyle.PANEL)
	_face.draw_arc(centre, hub - rule * 0.5, 0.0, TAU, 40, UIStyle.EDGE, rule)
	_stamp(UIStyle.boxed(UIStyle.glyph(mark), MARK_BOX), centre, UIStyle.TEXT)

	_draw_pointer(centre, radius)

## Every wedge's mark, riding the ring but **never rotated with it**. A 16px pixel glyph
## turned through an arbitrary angle is resampled off its own grid, which is the exact
## softening the whole art pipeline exists to prevent; upright and on whole pixels it is
## drawn one screen pixel per art pixel at every moment of the spin.
func _draw_marks(centre: Vector2, ring: float) -> void:
	for wedge in _wedges:
		var texture := UIStyle.boxed(UIStyle.glyph(wedge.glyph), MARK_BOX)
		if texture == null:
			continue
		var at := centre + Vector2.from_angle(wedge.start + wedge.span * 0.5 + _angle) * ring
		_stamp(texture, at, wedge.ink)

func _stamp(texture: Texture2D, at: Vector2, colour: Color) -> void:
	if texture == null:
		return
	# Drawn at its own size, so nothing is scaled and nothing needs boxing — the size
	# contract's rule, met by never asking for a size other than the art's (D27).
	_face.draw_texture(texture, (at - texture.get_size() * 0.5).round(), colour)

## The pointer, hinged at its base so it kicks as each wedge goes past.
func _draw_pointer(centre: Vector2, radius: float) -> void:
	var hinge := Vector2(centre.x, centre.y - radius - POINTER_REACH + 2.0)
	var swing := _flick()
	var points := PackedVector2Array([
		_swung(Vector2(centre.x, centre.y - radius + 6.0), hinge, swing),
		_swung(hinge + Vector2(-11.0, 0.0), hinge, swing),
		_swung(hinge + Vector2(11.0, 0.0), hinge, swing),
	])
	_face.draw_colored_polygon(points, UIStyle.PANEL)
	_face.draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[0]]),
		UIStyle.EDGE, float(UIStyle.BORDER_WIDTH))

func _swung(point: Vector2, hinge: Vector2, angle: float) -> Vector2:
	return hinge + (point - hinge).rotated(angle)

## Enough segments that a wedge's outer edge reads as a curve and no more: this runs on every
## frame of a spin, and the ring is under 300px across.
func _steps(span: float) -> int:
	return maxi(4, int(span / 0.06))

# --- odds ------------------------------------------------------------------

func _weight_of(kind: StringName) -> float:
	var total := 0.0
	for wedge in _wedges:
		if wedge.kind == kind:
			total += wedge.weight
	return total

func _percent(weight: float) -> int:
	if _total_weight <= 0.0:
		return 0
	return roundi(100.0 * weight / _total_weight)
