class_name SlotMachine
extends ArcadeGame

## Three reels, five symbols, and one long pause.
##
## The pause is the machine. A slot machine that resolved all three reels at once would be a
## random number with a picture on it; what makes it an *object* is that the reels stop one at
## a time, left to right, and the last one takes nearly three times as long as the first. The
## second reel landing on a pair and the third still turning is the only tension the game has,
## and every number in the timing block below exists to lengthen it.
##
## **The reels are the odds.** There is no weight table: each reel is the same twelve-stop
## strip, a stop is drawn uniformly, and a symbol's odds are simply how many times it appears
## on the strip. So the symbols the player watches go past the window are the very ones that
## decided the outcome — there is no second, hidden table to drift out of step with the art,
## which is the usual way a slot machine ends up lying about itself.
##
## STRIP, per reel, out of 12 stops:
##
##   dollar x4 (1/3)   bone x3 (1/4)   heart x2 (1/6)   bat x2 (1/6)   ghost x1 (1/12)
##
## PAY TABLE and what it costs the house, per pull, as a fraction of the stake:
##
##   two alike        25/48 = 52.1%    half the stake back    0.260
##   three dollars     1/27  =  3.7%   12x                    0.444
##   three ghosts      1/1728 = 0.06%  300x — the jackpot     0.174
##                                              Dollars EV =  0.878
##
##   three bones       1/64  =  1.6%   a Bones garnish     ) paid in another currency, so
##   three hearts      1/216 =  0.5%   a Hearts garnish    ) outside the fraction above —
##   three bats        1/216 =  0.5%   x2 income, 4 min    ) see GARNISH_BONES
##
## **Expected return is about 0.88 of the stake in Dollars**, i.e. a house edge near 12%, which
## is a real edge and still inside the band real machines run at. The player takes something
## home on 7/12 of pulls — 58% — because a pair is common and pays. That combination is what
## keeps a hand on the lever: frequent small returns, an occasional good one, and a jackpot
## roughly one pull in 1,728 worth about as much as clearing the whole contract board.
##
## The half-back pair is a return smaller than the stake, which is the oldest trick in the
## genre and is not presented as a win here: the caption says "half back" in as many words.
##
## Every symbol that is not Dollars pays through a kind the page is allowed to grant (D32):
## three bones and three hearts are a *garnish* sized against `garnish_cap()`, three bats is
## the shared timed slot under this machine's own effect id. Nothing here touches `Economy`.

# --- the machine -----------------------------------------------------------

const REEL_COUNT := 3

## The reel window, in UI pixels. 32 is not a taste decision: it is the one box in which a
## 16px glyph doubles to exactly 32 and a 32px item icon is already native, so a bone and a
## baseball bat fill identical windows with no fraction anywhere (D27, `UIStyle.boxed`). At
## 44 — the shop's well — the glyph would sit at 16px inside it and the bat at 32, and three
## reels would show symbols at two different sizes.
## Three times the icon canvas: a 16px glyph steps up by a whole number to 96, so the reel is
## drawn one art pixel to six screen pixels, crisp — and a slot machine you can read from the
## other side of the room.
const REEL_BOX := 96

const SYM_DOLLAR := &"dollar"
const SYM_BONE := &"bone"
const SYM_HEART := &"heart"
const SYM_BAT := &"bat"
const SYM_ECTO := &"ecto"

## Four of the five symbols are UI glyphs; the bat is real item art, so the reel carries a
## thing the player actually owns and swings rather than a fifth abstract mark.
const BAT_ITEM := &"baseball_bat"

## The strip both the odds and the animation read from. Order matters as much as the counts:
## adjacency on this ring is what a near miss *is* (see `_evaluate`), and no symbol sits next
## to itself, so a reel rolling to a stop never shows the same picture twice running.
const STRIP: Array[StringName] = [
	SYM_DOLLAR, SYM_BONE, SYM_HEART, SYM_DOLLAR, SYM_BAT, SYM_BONE,
	SYM_DOLLAR, SYM_ECTO, SYM_HEART, SYM_BONE, SYM_DOLLAR, SYM_BAT,
]

# --- the pay table ---------------------------------------------------------

## Multiples of the stake. See the arithmetic in the file header before changing one — the
## three Dollars entries are the whole expected return, and the pair is over half of it.
const PAY_PAIR := 0.5
const PAY_DOLLARS := 12.0
const PAY_JACKPOT := 300.0

## Fractions of `garnish_cap()`, never the cap itself, for two reasons. The design one: three
## bones is a 1-in-64 result and three hearts a 1-in-216 one, so the rarer symbol pays nearer
## the ceiling. The mechanical one: the cap is computed from the player's *live* multipliers,
## mood among them, so a prize written at 1.0x the cap can be worth a hair more than the cap
## by the time the page clamps it and would trip its warning during ordinary play.
const GARNISH_BONES := 0.40
const GARNISH_HEARTS := 0.70

## Three bats is a swing, so it pays time rather than money. Its own effect id, so a second
## win refreshes this machine's boost instead of stacking a second one beside it.
const BOOST_ID := &"slots_boost"
const BOOST_MULT := 2.0
const BOOST_SECONDS := 240.0

# --- timing ----------------------------------------------------------------
#
# Fixed, and deliberately not scaled by Focus Mode. `UIMotion`'s rule is that a gentler
# setting changes how far things move and never how fast — sluggish is not calm, it is broken
# — and a slot machine whose reels take longer on Subtle would be exactly that.

## Reel n walks STEPS_FIRST + n * STEPS_EXTRA stops before it lands: 10, 15, 20. Combined with
## the deceleration below that is roughly 0.8s, 1.4s and 2.3s — the last reel turning for
## three times as long as the first, which is the whole point of the machine.
const STEPS_FIRST := 10
const STEPS_EXTRA := 5

## Seconds between symbol changes, at full speed and at the moment of landing. Each reel gets
## a slower landing than the one before it, so the machine reads as three reels losing speed
## rather than one animation played three times.
const CLICK_FAST := 0.05
const CLICK_SLOW := 0.16
const CLICK_SLOW_STEP := 0.09

## How long the last reel sits on the winning symbol before rolling one stop past it. This is
## the near miss, in one number: long enough to be read, short enough not to be a promise.
const MISS_DWELL := 0.55

## The beat between the last reel landing and the prize being reported, so the reaction on the
## reels is seen before the page repaints the readout and shakes the whole cabinet.
const SETTLE_BEAT := 0.20
const MISS_BEAT := 0.45

# --- state -----------------------------------------------------------------

var _windows: Array[PanelContainer] = []
var _faces: Array[TextureRect] = []
## Where each reel came to rest, as an index into STRIP. Decided in `_play()`, before a single
## frame of animation — the reels display the outcome, they do not determine it.
var _stops: Array[int] = [0, 0, 0]
var _match_symbol: StringName = &""
var _triple := false
var _near_miss := false

func _init() -> void:
	display_name = "Three Ghosts"
	blurb = "Two alike hands half your stake back. Three alike pays, and three ghosts pays the room."
	mark = SYM_ECTO
	play_caption = "Pull"
	# Twelve Dollars is twelve hits (D31 pays one per act), so a pull costs about as much as a
	# few seconds of hitting him — cheap enough to be pulled idly, which is what a machine
	# with a 2.5 second animation has to be.
	cost = 12.0
	# The well never changes height, spinning or idle, because nothing in it changes size:
	# 32 art + 8 + 8 tile margins + 4 separation + the top-prize line, with a little slack.
	body_height = 270

# --- the cabinet -----------------------------------------------------------

func _build_body(host: VBoxContainer) -> void:
	var glass := HBoxContainer.new()
	# Named, because a control built in code comes out as `@HBoxContainer@31` — unreadable in
	# the remote scene tree and unfindable from a test.
	glass.name = "Reels"
	glass.alignment = BoxContainer.ALIGNMENT_CENTER
	glass.add_theme_constant_override("separation", 14)
	# Nothing in this well is clickable — the Play key belongs to the page — so the body
	# claims no mouse events at all rather than swallowing one that was meant for the card.
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(glass)

	for index in REEL_COUNT:
		var window := PanelContainer.new()
		window.name = "Reel%d" % index
		# A raised face on the sunk well, so each reel reads as its own lit window. The look
		# is the theme's answer to the variation, not this file's business.
		window.theme_type_variation = &"Tile"
		window.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glass.add_child(window)

		var face := UIStyle.sprite(_texture_for(STRIP[index]), REEL_BOX)
		face.name = "Face%d" % index
		window.add_child(face)
		_windows.append(window)
		_faces.append(face)
		# At rest the reels show three different symbols. Opening on a pair would advertise a
		# result the player has not paid for.
		_show(index, STRIP[index])

	# What the chase is for, printed on the glass the way a real machine prints it: the top
	# combination and its multiplier. A multiplier rather than a figure in Dollars, so the
	# line stays true if `cost` is ever retuned — one source of truth, and it is the constant.
	var top_prize := HBoxContainer.new()
	top_prize.name = "TopPrize"
	top_prize.alignment = BoxContainer.ALIGNMENT_CENTER
	top_prize.add_theme_constant_override("separation", 8)
	top_prize.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(top_prize)
	for _reel in REEL_COUNT:
		top_prize.add_child(UIStyle.icon(SYM_ECTO, UIStyle.ICON_CANVAS, UIStyle.TEXT))
	var multiple := UIStyle.label("x%d" % int(PAY_JACKPOT), UIStyle.TITLE, UIStyle.DOLLARS)
	# Every figure in the game is set in the display face: the body face draws 5 as a rounded
	# form that reads as an 8, and x300 misread as x800 is a promise the machine cannot keep.
	multiple.theme_type_variation = &"Numeral"
	top_prize.add_child(multiple)

## The picture for a symbol, always at exactly the window's size.
##
## Through `set_sprite()`, never `face.texture`: a glyph is a 16px canvas and an item icon a
## 32px one, and only the boxing brings both to the reel's box (D27). Writing the texture
## directly is the single way back to windows of three different sizes.
func _show(index: int, symbol: StringName) -> void:
	var face := _faces[index]
	UIStyle.set_sprite(face, _texture_for(symbol))
	face.modulate = _colour_for(symbol)

func _texture_for(symbol: StringName) -> Texture2D:
	if symbol == SYM_BAT:
		# `item_face` with no box returns the art itself; `set_sprite` is what boxes it. It
		# also falls back to a category glyph when the roster has not been seeded, so a
		# missing item leaves a mark on the reel rather than a hole.
		return UIStyle.item_face(ItemDB.get_item(BAT_ITEM))
	return UIStyle.glyph(symbol)

## Symbols wear the colour of what they pay, so the reel is legible before the readout is.
## The ghost is the exception: it is the jackpot and it is printed in plain ink, which is the
## one "colour" nothing else on the reel uses.
func _colour_for(symbol: StringName) -> Color:
	if symbol == SYM_HEART:
		return UIStyle.HEARTS
	if symbol == SYM_BONE:
		return UIStyle.BONES
	if symbol == SYM_DOLLAR:
		return UIStyle.DOLLARS
	if symbol == SYM_ECTO:
		return UIStyle.TEXT
	# Item art carries its own colour and must be drawn at full white, the same rule
	# `UIStyle.art_icons()` applies to a button holding a toy.
	return Color.WHITE

# --- one pull --------------------------------------------------------------

func _play() -> void:
	for index in REEL_COUNT:
		_stops[index] = randi() % STRIP.size()
	_evaluate()

	# Focus Mode Off stops the menus moving (D21) and a headless run has no frames to move in.
	# Both answer `UIMotion.enabled()` false and both want the same thing — the result, now —
	# so the spin resolves on the spot and the reels simply show what was drawn. This is also
	# what lets a headless suite press Play and read a prize without waiting 2.5 seconds.
	# `is_inside_tree()` is checked with it because `create_tween()` needs a tree: a machine
	# that has been charged must never fail to report.
	if not UIMotion.enabled() or not is_inside_tree():
		for index in REEL_COUNT:
			_show(index, _symbol_at(_stops[index]))
		_resolve()
		return

	say("Spinning...")
	for index in REEL_COUNT:
		_spin(index)

## One reel, walking the strip to its stop and losing speed as it arrives.
func _spin(index: int) -> void:
	var steps := STEPS_FIRST + index * STEPS_EXTRA
	var stop: int = _stops[index]
	var tween := create_tween()
	for step in range(steps):
		# Counted backwards from the stop, so the reel arrives at the symbol that was drawn by
		# walking the real strip into it — the last few pictures the player sees are the
		# genuine neighbours of the result, which is what makes a near miss honest.
		var symbol := _symbol_at(stop - (steps - 1 - step))
		# Both `index` and `symbol` are captured by value here, which for once is exactly what
		# is wanted: every callback needs the values from its own turn of the loop.
		tween.tween_callback(func() -> void: _show(index, symbol))
		# No interval after the final symbol. The long click belongs *before* the reel lands,
		# so the pause is the wait for the result and the reaction is on the same frame the
		# result appears — an interval on the end would land the symbol and then punch it a
		# third of a second later, which reads as a bug rather than as a stop.
		if step < steps - 1:
			tween.tween_interval(_click(index, step, steps))
	tween.tween_callback(func() -> void: _stopped(index))

## Seconds to hold the symbol shown at `step` before advancing.
func _click(index: int, step: int, steps: int) -> float:
	# The near miss, in one line: the last reel sits on the symbol that would have won and
	# then rolls one stop past it. Without the dwell that symbol is held for the same three
	# tenths as any other landing click, and a near miss looks exactly like an ordinary stop —
	# which is the whole thing the player is supposed to feel.
	if _near_miss and index == REEL_COUNT - 1 and step == steps - 2:
		return MISS_DWELL
	var t := float(step) / float(maxi(1, steps - 1))
	# Cubed rather than linear: the reel holds its speed for most of its travel and loses all
	# of it at the end. A linear ramp reads as a reel slowing from the moment it starts, which
	# gives the eye nothing to wait for.
	return lerpf(CLICK_FAST, CLICK_SLOW + index * CLICK_SLOW_STEP, t * t * t)

func _stopped(index: int) -> void:
	# Scale and rotation only. `modulate` is spoken for — it carries the symbol's colour, and
	# a flash would tween the reel back to white and leave a heart printed in plain ink.
	UIMotion.punch(_faces[index], 1.18)
	_sound(&"reel_stop", -12.0)
	if index == 1 and _symbol_at(_stops[0]) == _symbol_at(_stops[1]):
		# The gap between the second reel landing on a pair and the third arriving is the only
		# tension the machine has. Saying so out loud is most of what makes it land.
		say("Two alike...")
	if index == REEL_COUNT - 1:
		_land()

## The last reel has stopped. React on the reels, then hand the outcome over a beat later.
func _land() -> void:
	if _triple:
		for face in _faces:
			UIMotion.punch(face, 1.28)
		if _match_symbol == SYM_ECTO:
			_sound(&"jackpot", -4.0)
	elif _near_miss:
		# The two that matched jump; the one that rolled past shakes. The shake goes on the
		# window rather than the picture inside it, because `buzz()` flashes `modulate` back
		# to white and the picture's modulate is its colour.
		UIMotion.punch(_faces[0], 1.22)
		UIMotion.punch(_faces[1], 1.22)
		UIMotion.buzz(_windows[REEL_COUNT - 1])
	elif _match_symbol == &"":
		_sound(&"lose", -14.0)

	if not is_inside_tree():
		_resolve()
		return
	var settle := create_tween()
	settle.tween_interval(MISS_BEAT if _near_miss else SETTLE_BEAT)
	settle.tween_callback(_resolve)

func _resolve() -> void:
	report(_prize())

# --- reading the reels -----------------------------------------------------

func _symbol_at(position: int) -> StringName:
	# `posmod`, not `%`: a reel counts backwards from its stop and walks off the front of the
	# strip, and `-1 % 12` is -1 in GDScript.
	return STRIP[posmod(position, STRIP.size())]

func _evaluate() -> void:
	var first := _symbol_at(_stops[0])
	var second := _symbol_at(_stops[1])
	var third := _symbol_at(_stops[2])

	_triple = first == second and second == third
	_match_symbol = &""
	if _triple or first == second or first == third:
		_match_symbol = first
	elif second == third:
		_match_symbol = second

	# A near miss is not "two matched and the third was in the area". It is the physical fact
	# that the last reel rolled *through* the winning symbol and carried on one stop — which
	# is why it is read off the strip the reel actually walks, and why only a pair on the
	# first two reels qualifies. A pair split across reels 1 and 3 was never one stop from
	# anything; the player watched the third reel land on a symbol it had already passed.
	_near_miss = not _triple and first == second and _symbol_at(_stops[2] - 1) == first

## What the pull was worth. Built here and nowhere else, and the page is what pays it.
##
## Captions are kept under about 28 characters on purpose: the page's readout is a single
## un-wrapped Label, so one long line would widen the card — for every page in the shell, not
## just this one (D22).
func _prize() -> ArcadeGame.Prize:
	if _triple:
		if _match_symbol == SYM_ECTO:
			var jackpot := cost * PAY_JACKPOT
			return prize_dollars(jackpot, "JACKPOT! +%s" % UIStyle.format_amount(jackpot))
		if _match_symbol == SYM_DOLLAR:
			var won := cost * PAY_DOLLARS
			return prize_dollars(won, "Three dollars +%s" % UIStyle.format_amount(won))
		if _match_symbol == SYM_BONE:
			var bones := garnish_cap(Economy.BONES) * GARNISH_BONES
			return prize_garnish(Economy.BONES, bones,
				"Three bones +%s" % UIStyle.format_amount(bones))
		if _match_symbol == SYM_HEART:
			var hearts := garnish_cap(Economy.HEARTS) * GARNISH_HEARTS
			return prize_garnish(Economy.HEARTS, hearts,
				"Three hearts +%s" % UIStyle.format_amount(hearts))
		if _match_symbol == SYM_BAT:
			return prize_boost(BOOST_ID, BOOST_MULT, BOOST_SECONDS,
				"Three bats: x%d for %d min" % [int(BOOST_MULT), int(BOOST_SECONDS / 60.0)])

	if _match_symbol != &"":
		# Half the stake is a return, not a win, and the caption says which. A machine that
		# printed "+6 Dollars" over a 12 Dollar pull would be telling the player they had won.
		var back := cost * PAY_PAIR
		var line := "So close. Half back +%s" if _near_miss else "Two alike. Half back +%s"
		return prize_dollars(back, line % UIStyle.format_amount(back))

	return prize_nothing()

# --- sound -----------------------------------------------------------------

## Gated exactly the way `UIMotion` gates its own: Focus Mode Off means the shell stops
## shouting, and that has to include the machine that shouts loudest. It also keeps every
## headless suite silent, where `DisplayServer` is headless and `enabled()` is false anyway.
func _sound(id: StringName, volume_db: float) -> void:
	if not UIMotion.enabled():
		return
	AudioManager.play(id, 0.06, volume_db)
