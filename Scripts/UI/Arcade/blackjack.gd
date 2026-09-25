class_name BlackjackGame
extends ArcadeGame

## Blackjack: the one machine in the arcade that is a game rather than a pull.
##
## The wheel and the reels are a button and an outcome. This has rules, and it is the only
## cabinet where the player's own decision changes what they are paid — which is the whole
## reason it earns its floor space next to two machines that are cheaper to build.
##
## The rules are the ordinary table's, and they are ordinary on purpose: six-deck shoe,
## dealer draws to 16 and stands on all 17s, aces are eleven until they would bust, a
## natural pays 3:2, a push returns the stake. No doubling, no splitting, no insurance —
## each of those is another button on a cabinet that already has two, and none of them is
## the thing that makes this fun. What makes it fun is that hitting is a choice.
##
## The house edge that comes out of that is a couple of per cent, which is exactly what the
## machine wants to be: Dollars are the honest thing to gamble (docs/decisions.md D32), and
## a near-even game is one a player can sit at. It pays **nothing but Dollars** — no boost,
## no garnish. The other two machines carry those; a card game that also handed out timed
## multipliers would be saying two things at once, and the pot is already the point.
##
## Rule zero of `ArcadeGame` holds here as everywhere: this file never touches `Economy`.
## It describes an outcome and `ArcadePanel` pays it.

# --- the shoe --------------------------------------------------------------

const DECKS := 6
const SUITS := 4
const RANKS: Array[String] = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]

## The cut card. A six-deck shoe reshuffled with about a quarter of it left is ordinary
## casino penetration, and it also guarantees the arithmetic the whole file leans on: no
## single hand can run the shoe dry part-way through a deal.
const SHUFFLE_BELOW := 78

# --- the rules -------------------------------------------------------------

const DEALER_STANDS_ON := 17
const BLACKJACK_PAYS := 1.5

# --- the table, in UI pixels before `UIScale` ------------------------------
#
# A card is drawn rather than built out of panels, and the reason is width. Every panel
# variation in the shell carries 9 to 14 pixels of content margin on each side, so a card
# with a rank and a suit in it comes out around 60px wide — and six of those in a row is
# wider than the card the whole page is printed on. A row that wide does not overflow; it
# *widens the card for every page in the shell*, which is the trap `SCROLL_MODE_SHOW_NEVER`
# exists for elsewhere. Drawing means the deck is sized by the deck.
#
# Every colour below still comes from `UIStyle`, so the contrast grid already grades them.

## Two hands of these stack to fill the stage (D58): the table used to be two rows of 60x92
## cards along the top of a well that was mostly empty felt.
const CARD_W := 80
const CARD_H := 124
const CARD_GAP := 12
## The rank is set in the hero size and the pip boxed to three times the glyph: an 80x124 card
## with a 20px rank and a 16px pip is a big card wearing a small card's face.
const RANK_SIZE := UIStyle.HERO
const PIP_BOX := 48

# --- timing ----------------------------------------------------------------
#
# The cards arrive one at a time for the same reason a slot machine's reels stop one at a
# time: the outcome is decided the instant the shoe is cut, and the only thing that makes
# it feel like it is being decided now is the gap between the cards.

const DEAL_STEP := 0.30
const DRAW_STEP := 0.34
## A beat between the last card landing and the money moving, so the player reads the table
## rather than the readout.
const SETTLE_BEAT := 0.45

## Explicit, and small. A game whose state is "whichever buttons happen to be disabled" is a
## game with a bug in it — the fast clicker who hits a hand that has already been settled is
## the bug, and it is caught here rather than by the button.
##
## BETTING covers the deal as well as the moment before it: the stake is down and there is
## nothing to decide until the fourth card lands.
enum Phase { BETTING, PLAYER, DEALER, SETTLED }

var _phase: int = Phase.BETTING
## True while a card is still on its way to the table. The buttons are off then too, but
## "the buttons are off" is not a state — this is.
var _dealing := false

var _shoe: Array[int] = []
var _player: Array[int] = []
var _dealer: Array[int] = []
## The dealer's second card is face down until the player is done, as at a real table.
var _hole := false

var _player_row: Control
var _dealer_row: Control
var _player_total: Label
var _dealer_total: Label
var _shoe_label: Label
var _hit: Button
var _stand: Button

func _init() -> void:
	display_name = "Blackjack"
	blurb = "Six decks, dealer stands on 17. A natural pays 3:2 and a push hands the stake back."
	# `scroll` is the only mark in the glyph set shaped like a rectangle of card stock.
	mark = &"scroll"
	accent = &"wine"
	play_caption = "Deal"
	cost = 20.0
	# Two hands of cards and their readings — sized for the busiest frame, because a cabinet
	# that changes height mid-hand moves the page under the cursor.
	body_height = Cabinet.STAGE

# --- the cabinet -----------------------------------------------------------

## Hit and Stand live on the deck, beside Deal. They used to sit on the table while Deal sat
## outside it on the page's footer — the one machine whose controls were in two places.
func _build_deck(cabinet: Cabinet) -> void:
	_hit = _build_key("Hit", _on_hit)
	cabinet.deck.add_child(_hit)
	_stand = _build_key("Stand", _on_stand)
	cabinet.deck.add_child(_stand)

## The rules as the paytable. What is left in the shoe is stated with them: the machine
## shuffles a real shoe rather than rolling an independent card each time, so the composition
## genuinely changes as cards come out — and a player who counts is right. Hiding the count
## would make the honesty pointless.
func _build_odds(cabinet: Cabinet) -> void:
	# An ordinary win is the one line nobody needs printed; it is also the line that would not
	# fit on the 640px play area, so it is the one that went.
	cabinet.add_odds(&"star", "Blackjack", UIStyle.DOLLARS, "3:2")
	cabinet.add_odds(&"", "Push", UIStyle.TEXT, "stake back")
	cabinet.add_odds(&"", "Dealer stands", UIStyle.TEXT, str(DEALER_STANDS_ON))
	var shoe := cabinet.add_odds(&"", "Shoe", UIStyle.TEXT, "")
	shoe.name = "Shoe"
	shoe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shoe.alignment = BoxContainer.ALIGNMENT_END
	_shoe_label = UIStyle.label("", UIStyle.LABEL, UIStyle.TEXT_DIM)
	_shoe_label.theme_type_variation = &"Numeral"
	_shoe_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	shoe.add_child(_shoe_label)

func _build_body(host: VBoxContainer) -> void:
	host.add_theme_constant_override("separation", 8)

	var dealer := _build_side(host, "Dealer", true)
	_dealer_row = dealer["row"]
	_dealer_total = dealer["total"]
	var player := _build_side(host, "Player", false)
	_player_row = player["row"]
	_player_total = player["total"]
	# Hovering Hit lifts the hand it would add a card to, the way hovering a price lifts the
	# shop tile it belongs to. `scale`, which is a Container's child's to give away.
	if _hit:
		UIMotion.hook(_hit, _player_row)

	_build_shoe()
	_set_actions(false)
	_repaint()
	# A resting line, so the display says something before the first hand.
	say("Stake down, then deal.")

## One side of the table: its name and reading in a column, its cards beside them.
##
## Both eyebrows are six letters, so the two columns come out the same width and the two
## hands line up without either being pinned to a number that would have to be re-measured
## when the type changes.
func _build_side(host: VBoxContainer, caption: String, is_dealer: bool) -> Dictionary:
	var line := HBoxContainer.new()
	line.name = caption + "Side"
	line.add_theme_constant_override("separation", 14)
	host.add_child(line)

	var column := VBoxContainer.new()
	column.name = caption + "Reading"
	column.add_theme_constant_override("separation", 0)
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(column)
	column.add_child(UIStyle.eyebrow(caption))
	var total := UIStyle.label("", UIStyle.HERO, UIStyle.TEXT)
	total.name = caption + "Total"
	total.theme_type_variation = &"Numeral"
	column.add_child(total)

	var row := Control.new()
	row.name = caption + "Hand"
	row.custom_minimum_size = Vector2(0, CARD_H)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The hand is painted from the game rather than from a Control subclass, so the whole
	# machine stays in one scope and one file. `draw` fires inside the item's own draw pass,
	# which is the only place the draw_* calls are legal.
	row.draw.connect(func() -> void: _paint(row, is_dealer))
	# A Control does not repaint itself when it is resized, and the fan-out below is
	# computed from the realised width — so the first paint, taken before layout, is wrong
	# until this fires.
	row.resized.connect(row.queue_redraw)
	line.add_child(row)

	return {"row": row, "total": total}

## Hit and Stand: deck keys, the same variation and height as Deal beside them, so the deck is
## one row of keys the same size in every state they have. They spend most of a hand disabled,
## which is why the deck's key keeps a solid rule when it is (D58).
func _build_key(caption: String, handler: Callable) -> Button:
	var key := Cabinet.key(caption, 84)
	key.name = caption
	key.pressed.connect(handler)
	return key

# --- one hand --------------------------------------------------------------

func _play() -> void:
	_reshuffle_if_thin()
	_player.clear()
	_dealer.clear()
	_hole = true
	_phase = Phase.BETTING
	_dealing = true
	_set_actions(false)
	_repaint()
	say("Dealing...")

	var deal := create_tween()
	for step in 4:
		# Player, dealer, player, dealer face down — the order a real table deals in, which
		# is also the order that puts the hole card down last where it belongs.
		var to_player := step % 2 == 0
		deal.tween_interval(DEAL_STEP)
		deal.tween_callback(func() -> void: _deal(to_player))
	deal.tween_interval(DEAL_STEP)
	deal.tween_callback(_after_deal)

func _after_deal() -> void:
	_dealing = false
	if _player.size() == 2 and _total(_player) == 21:
		# The dealer checks their hole card only when the player has a natural: a mutual
		# natural is a push and has to be found now, and there is nothing left for the
		# player to decide either way.
		_finish()
		return
	_phase = Phase.PLAYER
	_set_actions(true)
	say("Hit or stand?")

func _on_hit() -> void:
	# The phase is the gate, not the button's `disabled` flag. A press queued in the frame
	# the hand settled would otherwise land a card on a hand that has already been paid out.
	if _phase != Phase.PLAYER or _dealing:
		return
	_dealing = true
	_set_actions(false)
	var beat := create_tween()
	beat.tween_interval(DEAL_STEP)
	# Each branch clears `_dealing` itself rather than the callback clearing it up front. The
	# deferred stand below is a whole idle frame away, and a flag dropped before it would
	# leave the table briefly saying "player's turn, nothing in the air" on a hand that is
	# already on its way to the dealer.
	beat.tween_callback(func() -> void:
		_deal(true)
		var total := _total(_player)
		if total > 21:
			_finish()
		elif total == 21:
			# Nobody hits twenty-one, and offering it could only ever bust the hand the
			# player has just made. Deferred because standing builds the dealer's own tween,
			# and a callback must not start a chain from inside the chain it is running in.
			_stand_now.call_deferred()
		else:
			_dealing = false
			_phase = Phase.PLAYER
			_set_actions(true)
			say("Hit or stand?"))

func _on_stand() -> void:
	if _phase != Phase.PLAYER or _dealing:
		return
	_stand_now()

func _stand_now() -> void:
	_phase = Phase.DEALER
	_dealing = true
	_set_actions(false)
	_reveal()
	say("Dealer plays.")

	# How many cards the dealer needs, worked out against a copy of the hand and a *peek* at
	# the shoe rather than by taking from it. Asking `_total()` for the answer inside the
	# tween instead would be asking the table a question it does not have the cards for yet,
	# which is a loop that never ends; and peeking rather than popping keeps the shoe count
	# on the cabinet dropping one card at a time, as each is laid down.
	var probe: Array[int] = _dealer.duplicate()
	var needed := 0
	while _total(probe) < DEALER_STANDS_ON:
		var peek := _shoe.size() - 1 - needed
		if peek < 0:
			break
		probe.append(_shoe[peek])
		needed += 1

	var beat := create_tween()
	for _step in needed:
		beat.tween_interval(DRAW_STEP)
		beat.tween_callback(func() -> void: _deal(false))
	beat.tween_callback(_finish)

## The hand is decided; only the money is outstanding. Nothing the player does from here
## can change the outcome, which is why the phase moves before the beat rather than after.
func _finish() -> void:
	_phase = Phase.SETTLED
	_dealing = false
	_set_actions(false)
	_reveal()
	# A `SceneTreeTimer` rather than another tween: this is reached from inside a tween's
	# own callback, and building a chain there is how a machine ends up killing the tween it
	# is standing in.
	get_tree().create_timer(SETTLE_BEAT).timeout.connect(_settle)

## What the hand was worth. Exactly one `report()`, on every path out.
##
## The page has already taken the stake, so every figure here is what comes *back*: twice
## the stake for a win (the stake plus the same again), two and a half for a natural at 3:2,
## the stake itself for a push, and nothing for a loss.
func _settle() -> void:
	var player := _total(_player)
	var dealer := _total(_dealer)
	var natural := _player.size() == 2 and player == 21
	var dealer_natural := _dealer.size() == 2 and dealer == 21

	if player > 21:
		report(prize_nothing("Bust on %d" % player))
	elif natural and not dealer_natural:
		report(prize_dollars(stake() * (1.0 + BLACKJACK_PAYS), "Blackjack pays 3:2"))
	elif dealer_natural and not natural:
		# A natural beats a made twenty-one as well as everything under it.
		report(prize_nothing("Dealer's blackjack"))
	elif dealer > 21:
		report(prize_dollars(stake() * 2.0, "Dealer bust on %d" % dealer))
	elif player > dealer:
		report(prize_dollars(stake() * 2.0, "%d beats %d" % [player, dealer]))
	elif player < dealer:
		report(prize_nothing("%d loses to %d" % [player, dealer]))
	else:
		# A push is not a win, but the stake has already left the purse and the only way to
		# hand it back is to pay it back — so it is a Dollars prize of exactly the stake.
		report(prize_dollars(stake(), "Push on %d" % player))

# --- cards -----------------------------------------------------------------

func _deal(to_player: bool) -> void:
	var hand := _player if to_player else _dealer
	hand.append(_draw_card())
	_repaint()
	UIMotion.punch(_player_row if to_player else _dealer_row, 1.05)
	AudioManager.play(&"card_deal", 0.10, -10.0)

func _reveal() -> void:
	if not _hole:
		return
	_hole = false
	_repaint()
	UIMotion.punch(_dealer_row, 1.08)

func _draw_card() -> int:
	if _shoe.is_empty():
		_build_shoe()
	var card: int = _shoe.pop_back()
	return card

## A real shoe, shuffled — not an independent random card per draw. The difference is the
## whole reason the count on the cabinet means anything: with independent draws a shoe that
## has already shown four aces is as likely to show a fifth, and a player who noticed would
## be right that the game was lying to them.
##
## `Array.shuffle()` draws from the same global generator `randi()` and `randf()` do, which
## is the one the rest of the game uses.
func _build_shoe() -> void:
	_shoe.clear()
	for _deck in DECKS:
		for card in SUITS * RANKS.size():
			_shoe.append(card)
	_shoe.shuffle()

func _reshuffle_if_thin() -> void:
	if _shoe.size() >= SHUFFLE_BELOW:
		return
	_build_shoe()

## A card is `suit * 13 + rank`, so one int carries both and an `Array[int]` is the whole
## shoe. Rank 0 is the ace; ranks 9 through 12 are the ten and the three court cards, all
## worth ten.
func _card_value(card: int) -> int:
	var rank := card % RANKS.size()
	if rank == 0:
		return 11
	return mini(rank + 1, 10)

func _total(cards: Array[int]) -> int:
	var total := 0
	var aces := 0
	for card in cards:
		var value := _card_value(card)
		if value == 11:
			aces += 1
		total += value
	# An ace is eleven until it would bust the hand and then it is one, demoted one at a
	# time rather than all at once — A,A,9 is twenty-one, not twelve.
	while total > 21 and aces > 0:
		total -= 10
		aces -= 1
	return total

## True when an ace in the hand is still counted as eleven, so the next card cannot bust it.
func _is_soft(cards: Array[int]) -> bool:
	var hard := 0
	var aces := 0
	for card in cards:
		var value := _card_value(card)
		if value == 11:
			aces += 1
			value = 1
		hard += value
	return aces > 0 and hard + 10 <= 21

# --- painting --------------------------------------------------------------

func _repaint() -> void:
	_dealer_row.queue_redraw()
	_player_row.queue_redraw()
	_dealer_total.text = _dealer_reading()
	_player_total.text = _reading(_player)
	_shoe_label.text = str(_shoe.size())

## A hand's reading. A soft hand is printed as both of its values — "7/17" — because "17"
## alone hides the one fact that decides how it is played, and the two readings fit the
## column the single one already needed.
func _reading(cards: Array[int]) -> String:
	if cards.is_empty():
		# Never blank. The reading is the only thing in this column that changes, and an
		# empty Label between hands would be a hole where a number lives.
		return "--"
	var best := _total(cards)
	if _is_soft(cards):
		return "%d/%d" % [best - 10, best]
	return str(best)

## What the player can actually see of the dealer's hand. The "+" says there is more without
## pretending to know what it is; an ace showing reads as 11, which is the soft value and
## the one a player is deciding against.
func _dealer_reading() -> String:
	if _dealer.is_empty():
		return "--"
	if _hole and _dealer.size() > 1:
		return "%d+" % _card_value(_dealer[0])
	return _reading(_dealer)

func _set_actions(on: bool) -> void:
	_hit.disabled = not on
	_stand.disabled = not on

## One hand of cards, drawn into `row`. Which hand is a flag rather than the array itself:
## `==` on two Arrays compares their contents, so a dealer and a player holding the same two
## ranks would have made "is this the dealer's hand?" answer yes to both.
func _paint(row: Control, is_dealer: bool) -> void:
	var cards := _dealer if is_dealer else _player
	if cards.is_empty():
		return
	var font := UITheme.get_theme().get_font("font", "Numeral")
	if font == null:
		return
	var rule := float(UIStyle.BORDER_WIDTH)

	# The cards fan out at a fixed pitch until the hand is wider than the row it was dealt
	# into, and then they overlap — which is what a real hand does, and is the only reason a
	# freak ten-card hand cannot widen the cabinet. The rank sits in the top-left corner for
	# exactly the reason it does on a real card: it is the part still showing when they do.
	var pitch := float(CARD_W + CARD_GAP)
	if cards.size() > 1:
		pitch = minf(pitch, (row.size.x - float(CARD_W)) / float(cards.size() - 1))
	pitch = maxf(pitch, 8.0)

	for index in cards.size():
		var face := Rect2(float(index) * pitch, 0.0, float(CARD_W), float(CARD_H))
		# The hard black rule every other object in the shell has, painted as a filled box
		# with the face inset into it — an unfilled `draw_rect` straddles the boundary and
		# would put half the rule outside the card.
		row.draw_rect(face, UIStyle.EDGE, true)
		var inner := face.grow(-rule)

		if _hole and is_dealer and index == cards.size() - 1:
			# The back: a sunk field with the same rule stamped into it, so a face-down card
			# reads as a card rather than as a gap where one failed to draw.
			row.draw_rect(inner, UIStyle.SUNK, true)
			# A frame, not a slab: at 60x92 a filled box read as a black hole in the table.
			row.draw_rect(inner.grow(-8.0), UIStyle.EDGE, false, rule)
			row.draw_rect(inner.grow(-16.0), UIStyle.EDGE, false, rule)
			continue

		row.draw_rect(inner, UIStyle.PANEL, true)
		var suit := cards[index] / RANKS.size()
		var ink := _suit_ink(suit)
		row.draw_string(font,
			Vector2(face.position.x + rule + 4.0, rule + 2.0 + font.get_ascent(RANK_SIZE)),
			RANKS[cards[index] % RANKS.size()],
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, RANK_SIZE, ink)
		# Through `UIStyle.boxed()` at the glyph's own canvas size, so the picture is exactly
		# the box that holds it (docs/decisions.md D27) and nothing is ever stepped down —
		# `ui_check` asserts `UIStyle.shrunk` is empty, and asking for a 16px glyph in a
		# smaller box is how that list gets its first entry.
		var pip := UIStyle.boxed(UIStyle.glyph(_suit_glyph(suit)), PIP_BOX)
		if pip != null:
			row.draw_texture(pip, Vector2(
				face.position.x + float(CARD_W) - rule - 2.0 - float(PIP_BOX),
				float(CARD_H) - rule - 2.0 - float(PIP_BOX)), ink)

## Four suits made out of the things this game is about, because the glyph set has no spade
## and no club and a card face is the wrong place to gamble on a font shipping one. Shape
## and ink separate them both, which is the palette's rule everywhere else — and all four
## inks are already graded against every surface in the shell.
static func _suit_glyph(suit: int) -> StringName:
	match suit:
		0: return &"bone"
		1: return &"heart"
		2: return &"dollar"
		_: return &"star"

static func _suit_ink(suit: int) -> Color:
	match suit:
		0: return UIStyle.BONES
		1: return UIStyle.HEARTS
		2: return UIStyle.DOLLARS
		_: return UIStyle.TEXT
