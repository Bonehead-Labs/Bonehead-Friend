class_name ArcadeGame
extends Node

## The base every arcade machine extends: the wheel, the slot machine, the blackjack table.
##
## The contract is one sentence — **a machine describes itself and its outcome, and the page
## does the paying.** A game never touches `Economy`: it reports a `Prize` and `ArcadePanel`
## is the only thing that grants one. Three machines each minting currency would be three
## places for a bug that prints money, and a slot machine is exactly the kind of code that
## gets a table edited at midnight.
##
## A machine is a `Node`, not a `Control`. Parented to the page it has a tree, a
## `create_tween()` and a `get_tree().create_timer()` — everything a reel or a wheel needs to
## animate — while the *look* of its cabinet stays the page's business, which is what keeps
## every machine the same width, the same type and the same contrast grade as the rest of the
## shell (docs/decisions.md D20). Its visuals go onto the stage of a `Cabinet` the page builds (D58).
##
## The whole lifecycle, from the page's side:
##
##   game = SomeMachine.new()      # the page instances it and adds it as a child
##   game.build_deck(cabinet)      # once: any keys of its own, left of the page's Play key
##   game.build_odds(cabinet)      # once: its paytable, into the cabinet's strip
##   game.build_body(host)         # once, into the cabinet's stage
##   ... the player presses Play, the page takes `stake()` in Dollars ...
##   game.play()                   # never while is_busy()
##   ... the machine animates for as long as it likes ...
##   game.report(prize)            # exactly once, and the page grants it
##
## A spin that is still running when the card closes keeps running and still pays. That is
## deliberate: the player has already been charged, so a machine must never abandon a play it
## took money for.

## What one play may win. A dumb record — built by the `prize_*` helpers below, read by the
## page, and understood by nothing else.
class Prize extends RefCounted:
	## The four things a spin may pay (docs/decisions.md D32), plus a garnish and the empty
	## case. A prize that is none of these is not a prize the arcade is allowed to give.
	const NOTHING := &"nothing"
	const DOLLARS := &"dollars"
	const BOOST := &"boost"
	const GARNISH := &"garnish"
	const COSMETIC := &"cosmetic"
	const BOON := &"boon"

	var kind: StringName = NOTHING
	## One short line for the cabinet's readout. The helpers write a serviceable one; pass
	## your own when the machine has something better to say.
	var caption: String = ""
	## DOLLARS and GARNISH: how much. GARNISH names its currency as well.
	var amount: float = 0.0
	var currency: StringName = &""
	## BOOST: the shared timed slot on `Economy` — which effect, how big, how long.
	var effect_id: StringName = &""
	var multiplier: float = 1.0
	var seconds: float = 0.0
	## COSMETIC and BOON: what was won.
	var id: StringName = &""

	func is_win() -> bool:
		return kind != NOTHING

## The outcome of one `play()`, emitted exactly once. The page grants it; the machine has
## already finished with it by the time this fires.
signal finished(prize: Prize)
## "My cabinet's chrome is stale" — the cost changed, the caption changed, or the machine
## became busy or idle. The page repaints; it does not rebuild, so the machine's own visuals
## are never touched.
signal changed()
## A line for the cabinet's readout, for anything the machine wants to say between plays
## ("Hit or stand?", "Spinning..."). The page owns the label, so the type and the contrast
## stay the shell's business.
signal said(text: String)

# --- what a machine says about itself -------------------------------------
#
# Set these in `_init()` or at the top of `_build_body()`. Change one later and emit
# `changed` — the page reads them on every repaint and caches nothing.

var display_name: String = "Machine"
## One line under the name. Say what it costs you and what it can pay.
var blurb: String = ""
## The mark on the cabinet: a glyph id from `Assets/sprites/ui` (bolt, star, crate, ...).
var mark: StringName = &"dollar"
## The word on the page's Play button. "Spin", "Deal", "Hit me".
var play_caption: String = "Play"
## The colour the cabinet's marquee and its room key are lit in: a key of
## `UIStyle.MARQUEES`, which is also the whole list to choose from (D58).
var accent: StringName = &"gold"
## Dollars per play at the lowest stake — the price every table below is written against.
## The page checks `stake()` against the purse, takes it, and only then calls `play()`; a
## machine is never asked to charge for itself.
var cost: float = 10.0
## Height the page reserves for the stage, in UI pixels before `UIScale` — at least `Cabinet.STAGE`. The cabinet must
## not change height while the machine animates, or the whole page moves under the cursor,
## so this is the space the machine gets whether it is spinning or idle.
var body_height: int = 96

## The stage the page built, once `build_body()` has run. Held so a machine can rebuild its
## own contents later without the page having to hand it back.
var body: VBoxContainer = null

var _busy := false

# --- limits the page enforces, stated here so tables can be written against them ---------

## Bones and Hearts are a **garnish and nothing more** (docs/decisions.md D32). This cap is
## the whole reason an arcade is safe to build: the moment a machine can pay a real pile of
## Hearts the optimal line becomes "farm Dollars, gamble for Hearts, skip being kind" — and
## automation being Hearts-priced (D2), which is the spine of the entire design, is dead.
##
## It is anchored to *acts* rather than to a fixed figure, and run through the same payout
## pipeline the act itself would have used: three of the biggest single hit the damage cap
## allows, or three full sponge-downs. So a garnish is worth about ten seconds of play at
## every point in the game — never nothing, never a shortcut — and it inflates with the
## player instead of against them.
const GARNISH_ACTS := 3.0

## A timed multiplier is **minutes, never permanent** (D32). Fifteen minutes at x5 is worth
## a bit over an hour of ordinary income: a real prize, and still an order of magnitude short
## of an afternoon of being kind to him, which is what it must never replace.
const BOOST_MAX_SECONDS := 900.0
const BOOST_MAX_MULT := 5.0

## The stake the deck's stepper offers, as whole multiples of `cost`. **Every Dollars prize
## scales with it and nothing else does**: a table written as "12x the stake" or "10 Dollars
## on a 25 Dollar spin" keeps its odds and its return per Dollar at every rung, while a
## garnish and a boost stay exactly the size they were — both are capped by acts and by
## minutes rather than by the stake (D32), so a bigger bet can never buy a bigger one. A
## single rung hides the stepper.
const STAKES: Array[int] = [1, 2, 5, 10]

var _stake_step := 0

## The multiple of `cost` the player has chosen.
func stake_multiple() -> int:
	return STAKES[clampi(_stake_step, 0, STAKES.size() - 1)]

## Dollars this play costs, and the figure every Dollars prize is written against.
func stake() -> float:
	return cost * float(stake_multiple())

## One rung up or down. Refused while a play is running: the stake a hand was dealt at is
## the stake it is paid at, and a stepper live mid-hand would be a way to change it.
func step_stake(delta: int) -> bool:
	if _busy:
		return false
	var next := clampi(_stake_step + delta, 0, STAKES.size() - 1)
	if next == _stake_step:
		return false
	_stake_step = next
	_stake_changed()
	changed.emit()
	return true

func can_step_stake(delta: int) -> bool:
	if _busy:
		return false
	var next := _stake_step + delta
	return next >= 0 and next < STAKES.size()

## The most Bones or Hearts a single play may pay, at the player's current multipliers.
## Both the page and the machines read this, so the cap has one definition — the page still
## clamps to it, because the page is what mints.
static func garnish_cap(currency: StringName) -> float:
	var b := ItemDB.balance
	var act := b.hearts_per_grime_cleaned
	if currency != Economy.HEARTS:
		# The largest single hit `max_hit_fraction` allows, in Bones.
		act = b.knockout_damage * b.max_hit_fraction * b.bones_per_damage
	return Economy.payout_for(act * GARNISH_ACTS, &"arcade")

# --- what the page calls ---------------------------------------------------

## Build the machine's visuals into `host`, once, at page build time.
##
## `host` is a `VBoxContainer` on the cabinet's stage: add one child or ten, they are laid out.
## It is a container rather than a bare `Control` on purpose — a child of a plain `Control`
## is never laid out and keeps whatever size it was created with, which is zero.
##
## Override `_build_body()`, not this.
func build_body(host: VBoxContainer) -> void:
	body = host
	_build_body(host)

## Print how the machine pays into the cabinet's paytable strip, once. Override
## `_build_odds()`; the default prints the blurb, which is a paytable in words.
func build_odds(cabinet: Cabinet) -> void:
	_build_odds(cabinet)

## Add any keys of the machine's own to the deck, once — they land between the stake and the
## page's Play key. Most machines have none; blackjack's Hit and Stand live here, on the deck
## beside Deal, rather than on the table where they were the one control off the deck.
func build_deck(cabinet: Cabinet) -> void:
	_build_deck(cabinet)

## The width the stage will have, in UI pixels, whenever the card changes size. A machine laid
## out by its containers needs nothing; one that draws at a fixed size picks the largest that
## fits, because a fixed-width stage wider than a small card would widen the card for every
## page in the shell (D22). Called before the first paint and again on every resize.
func fit_stage(width: float) -> void:
	_fit_stage(width)

## Play one round. The page has already taken `cost` in Dollars and has already checked
## `is_busy()`; the machine only has to produce an outcome.
##
## Override `_play()`, not this — so no machine can forget to raise the busy flag, and none
## can be started twice while its reels are still moving.
func play() -> void:
	if _busy:
		push_warning("ArcadeGame: %s was played while it was still busy" % display_name)
		return
	_busy = true
	changed.emit()
	_play()

## True while an outcome is pending. The page keeps Play disabled until it clears, which is
## also how a multi-step machine (blackjack, whose Hit and Stand live in its own body) holds
## the page's button down for the length of a hand.
func is_busy() -> bool:
	return _busy

# --- what a machine overrides ----------------------------------------------

## Create the visuals. Use `UIStyle` for every one of them (see the note at the foot of this
## file); nothing here builds its own look.
func _build_body(_host: VBoxContainer) -> void:
	pass

func _build_odds(cabinet: Cabinet) -> void:
	cabinet.add_odds_prose(blurb)

func _build_deck(_cabinet: Cabinet) -> void:
	pass

func _fit_stage(_width: float) -> void:
	pass

## The stake moved. Repaint anything printed in Dollars — a paytable written in figures
## rather than multiples has to follow it.
func _stake_changed() -> void:
	pass

## Produce an outcome. Report it now, or in ten seconds when the wheel stops — but report it,
## once, on every path out of this function.
func _play() -> void:
	report(prize_nothing())

# --- what a machine calls --------------------------------------------------

## Hand the outcome back. **Exactly once per `play()`**, from wherever the machine finally
## knows what happened.
##
## A second report for one play would pay twice, so it is refused rather than trusted — the
## same reasoning that puts every grant in the page instead of in three machines.
func report(prize: Prize) -> void:
	if prize == null:
		push_error("ArcadeGame: %s reported a null prize" % display_name)
		return
	if not _busy:
		push_warning("ArcadeGame: %s reported a prize it was not playing for" % display_name)
		return
	_busy = false
	finished.emit(prize)
	changed.emit()

## Put a line in the cabinet's readout. Cleared by the page when the next play starts.
func say(text: String) -> void:
	said.emit(text)

## Tell the page its chrome is stale, after changing `cost`, `play_caption` or anything else
## the cabinet prints.
func restate() -> void:
	changed.emit()

# --- prizes ----------------------------------------------------------------
#
# Static, so a machine writes `report(prize_dollars(120.0))` and never has to know the shape
# of the record it is filling in.

static func prize_nothing(caption: String = "No luck") -> Prize:
	var prize := Prize.new()
	prize.kind = Prize.NOTHING
	prize.caption = caption
	return prize

## The main one, and the honest one: gambling your own currency (D32).
static func prize_dollars(amount: float, caption: String = "") -> Prize:
	var prize := Prize.new()
	prize.kind = Prize.DOLLARS
	prize.amount = maxf(0.0, amount)
	prize.caption = caption if caption != "" else "+%s Dollars" % UIStyle.format_amount(amount)
	return prize

## A timed multiplier on all Bones and Hearts income, through the one shared slot the Dream
## Journal and Overtime Pay use as well. `effect_id` is that slot: give each machine its own
## so a second win refreshes its own boost instead of piling up, and pick a `snake_case` id
## the way every other content id in the game is picked.
##
## Clamped to `BOOST_MAX_MULT` and `BOOST_MAX_SECONDS` by the page.
static func prize_boost(effect_id: StringName, multiplier: float, seconds: float,
		caption: String = "") -> Prize:
	var prize := Prize.new()
	prize.kind = Prize.BOOST
	prize.effect_id = effect_id
	prize.multiplier = clampf(multiplier, 1.0, BOOST_MAX_MULT)
	prize.seconds = clampf(seconds, 0.0, BOOST_MAX_SECONDS)
	prize.caption = caption if caption != "" else "x%.2f income for %d min" % [
		prize.multiplier, int(prize.seconds / 60.0)]
	return prize

## A small pile of Bones or Hearts — `Economy.BONES` or `Economy.HEARTS`. Size it against
## `garnish_cap()`; anything above that is clamped by the page and warned about, because a
## machine that pays real Hearts breaks the dual-currency bargain (D2, D32).
static func prize_garnish(currency: StringName, amount: float, caption: String = "") -> Prize:
	var prize := Prize.new()
	prize.kind = Prize.GARNISH
	prize.currency = currency
	prize.amount = maxf(0.0, amount)
	prize.caption = caption if caption != "" else "+%s" % UIStyle.format_amount(prize.amount)
	return prize

## A hat. **Not yet grantable** — the cosmetics store is M3.5-B and the save has the slot
## reserved and nothing that fills it — so the page refuses one loudly rather than paying a
## prize that vanishes. The kind exists so the tables can grow the day the store lands; keep
## it off your table until then.
static func prize_cosmetic(id: StringName, caption: String = "") -> Prize:
	var prize := Prize.new()
	prize.kind = Prize.COSMETIC
	prize.id = id
	prize.caption = caption if caption != "" else "A hat"
	return prize

## A permanent boon, the same kind the Séance sells (D32). Rare, and — like a cosmetic — not
## grantable until the store that owns them exists.
static func prize_boon(id: StringName, caption: String = "") -> Prize:
	var prize := Prize.new()
	prize.kind = Prize.BOON
	prize.id = id
	prize.caption = caption if caption != "" else "A permanent boon"
	return prize

# --- building visuals ------------------------------------------------------
#
# Everything a machine draws goes through `UIStyle`, for the same reason every other panel
# does: a control that builds its own look is a control the contrast suite cannot grade and
# the theme cannot restyle when the art pass lands.
#
#   UIStyle.label(text, UIStyle.LABEL, colour)   a figure — and set
#                                                `theme_type_variation = &"Numeral"` on it,
#                                                because the body face draws 5 as something
#                                                that reads as 8 and no number in this game
#                                                is ever set in it
#   UIStyle.body(text)                           a sentence
#   UIStyle.eyebrow(text)                        an all-caps rule-line heading
#   UIStyle.button(text, UIStyle.LABEL)          a key, already hooked to UIMotion
#   UIStyle.icon(&"bolt", UIStyle.GLYPH, colour) a glyph at exactly its box size
#   UIStyle.sprite(texture, box)                 art at exactly its box size
#
# The stage is already a section with one rule across its top: do not put a framed panel
# around the whole machine, which is the frame-inside-a-frame D58 took out. A machine's own
# glass is `theme_type_variation = &"Glass"`, divided into windows by `UIStyle.rule()`; the
# variation names live in `Scripts/UI/ui_theme.gd` and a misspelled one falls back silently
# and merely looks wrong. The paytable goes through `Cabinet.add_odds()`.
#
# Three traps this file cannot stop you walking into:
#
#   * **Never tween `position` or `size` on a Control inside a Container** — the container
#     owns both and rewrites them next layout. `scale`, `rotation`, `pivot_offset` and
#     `modulate` are yours; `UIMotion` is where the shared moves live.
#   * **Never fade anything that is the size of the card.** The window is per-pixel
#     transparent, so alpha below 1 shows the player's desktop through the UI.
#   * **A full-rect layout Control must be `MOUSE_FILTER_IGNORE`** unless it is deliberately
#     blocking input — one invisible full-window container once ate every click in the game.
