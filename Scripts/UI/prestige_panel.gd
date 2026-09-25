class_name PrestigePanel
extends PanelPage

## Reincarnation: hand the run back, keep the Marrow, get a new Bonehead.
##
## The page has one job beyond the button, and it is the harder one — making the trade
## legible. A reset screen that does not say plainly what is lost gets pressed by accident
## once and then never trusted again, so this spells out both halves and requires a second
## press to confirm.

## Two-stage confirm. Not a modal dialog: this game runs over someone's work, and a modal
## that steals focus is the fastest way to get uninstalled (D6's reasoning, applied to a
## destructive action instead of to a menu).
var _armed := false

## The armed state is a mode the player can be in without knowing it, so it is not allowed
## to outlive the moment. It expires on its own, and closing the card drops it — otherwise
## arming the button and walking away leaves the run one stray click from being deleted.
const ARM_WINDOW_MS := 6000
var _armed_at := 0

var _headline: Label
var _ghost: TextureRect
var _figures: HBoxContainer
var _gain_row: HBoxContainer
var _detail: Label
var _personality_label: Label
var _button: Button
var _sleep_label: Label
var _sleep_button: Button

## The offline cap, bought here. A refusal is a reaction, not a silence (the shop's rule).
func _on_sleep_pressed() -> void:
	if not Economy.buy_offline_cap():
		UIMotion.buzz(_sleep_button)
		return
	UIMotion.confirm(_sleep_button)
	EventBus.ui_spend.emit(Economy.HEARTS, 0.0, UIScale.screen_centre(_sleep_button))
	_refresh()

func _refresh_sleep() -> void:
	if _sleep_label == null:
		return
	var b := ItemDB.balance
	var hours := b.offline_cap_seconds(Economy.offline_cap_level) / 3600.0
	var cost := Economy.offline_cap_cost()
	# The figure in the display, in the face whose digits can be trusted (D20).
	_sleep_cabinet.say("Sleeps up to %d h" % int(round(hours)), UIStyle.TEXT)
	if cost < 0.0:
		_sleep_label.text = ("He keeps earning for up to %d hours while the game is closed, at half "
			+ "rate. That is as long as he can sleep.") % int(round(hours))
		_sleep_button.text = "Sleeps %d h" % int(round(hours))
		UIStyle.set_icon(_sleep_button, UIStyle.glyph(&"check"))
		_sleep_button.disabled = true
		UIStyle.tint_button(_sleep_button, UIStyle.TEXT_DIM)
		return
	var next_hours := b.offline_cap_seconds(Economy.offline_cap_level + 1) / 3600.0
	_sleep_label.text = ("He keeps earning for up to %d hours while the game is closed, at half "
		+ "rate, then stops. Teach him to sleep %d hours.") % [int(round(hours)), int(round(next_hours))]
	_sleep_button.text = "Sleep longer  %s" % UIStyle.format_amount(cost)
	UIStyle.set_icon(_sleep_button, UIStyle.currency_glyph(Economy.HEARTS))
	_sleep_button.disabled = false
	UIStyle.tint_button(_sleep_button, UIStyle.HEARTS if Economy.balance_of(Economy.HEARTS) >= cost
		else UIStyle.TEXT_DIM)

func _ready() -> void:
	EventBus.currency_changed.connect(func(_c: StringName, _b: float) -> void: request_refresh())
	EventBus.prestige_performed.connect(func(_gained: int) -> void: _disarm())
	super()

## Clears the confirm and repaints, but only when there is something to clear — `_refresh()`
## walks the whole page and this runs on every visibility flip, including the card's own.
func _disarm() -> void:
	if not _armed:
		return
	_armed = false
	_refresh()

## The back room's cabinets (D58): Reincarnation, built like every machine in the Arcade —
## marquee, stage, paytable, deck — and a second, smaller one below it for the one thing sold
## between lives. The trade reads the way a machine does: what it pays in the display, what
## you lose on the stage, the figures in the paytable, one key on the deck.
var _cabinet: Cabinet
var _sleep_cabinet: Cabinet
var _lives: Label

## The back room's second cabinet only has a sentence to show, so its stage is short.
const SLEEP_STAGE := 44

func _build_page() -> void:
	add_theme_constant_override("separation", 10)

	_cabinet = Cabinet.new("Reincarnation", &"star", &"night")
	_cabinet.name = "RebirthCabinet"
	add_child(_cabinet)
	var stage := _cabinet.stage_body
	stage.alignment = BoxContainer.ALIGNMENT_BEGIN
	stage.add_theme_constant_override("separation", 10)

	# The gain, as big as it deserves and with its mark beside it. Marrow is the only
	# number in the game that survives the reset, so it is the only number that gets the
	# hero size.
	var gain := HBoxContainer.new()
	gain.add_theme_constant_override("separation", 8)
	stage.add_child(gain)
	_gain_row = gain
	_ghost = UIStyle.icon(&"star", Cabinet.MARK_BOX, UIStyle.DOLLARS)
	_ghost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gain.add_child(_ghost)
	_headline = UIStyle.label("", UIStyle.HERO, UIStyle.DOLLARS)
	_headline.theme_type_variation = &"Numeral"
	gain.add_child(_headline)
	var unit := UIStyle.label("Marrow", UIStyle.LABEL, UIStyle.DOLLARS)
	unit.theme_type_variation = &"Numeral"
	unit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gain.add_child(unit)

	# The figures and the prose are separated on purpose, and not only for the layout: the
	# body face draws 5 as a rounded form that reads as an 8, so no number in the game is
	# ever set in it. Here that split does double duty — the trade is easier to weigh when
	# what you keep and what you lose is a sentence, and what it is worth is a figure, which
	# is why the figures are the cabinet's paytable.
	_figures = _cabinet.odds

	_detail = UIStyle.body("")
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(320, 0)
	stage.add_child(_detail)

	# This life, under a rule: who he is now is the thing the reset changes.
	stage.add_child(UIStyle.rule(false))
	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 10)
	stage.add_child(who)
	var eyebrow := UIStyle.eyebrow("This life")
	eyebrow.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	who.add_child(eyebrow)
	_personality_label = UIStyle.body("", UIStyle.BODY, UIStyle.TEXT)
	_personality_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_personality_label.custom_minimum_size = Vector2(300, 0)
	_personality_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_child(_personality_label)

	# Where the machines keep their stake, the back room keeps count of what has been staked
	# already: every life handed back so far.
	var lives := HBoxContainer.new()
	lives.add_theme_constant_override("separation", 6)
	lives.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cabinet.deck.add_child(lives)
	var caption := UIStyle.eyebrow("Lives handed back")
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lives.add_child(caption)
	_lives = UIStyle.label("", UIStyle.LABEL, UIStyle.TEXT)
	_lives.theme_type_variation = &"Numeral"
	_lives.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lives.add_child(_lives)
	_cabinet.push_right()
	_button = Cabinet.key("", 260)
	_button.name = "Reincarnate"
	_button.pressed.connect(_on_pressed)
	_cabinet.deck.add_child(_button)
	UIMotion.hook(_button, _cabinet.stage)

	# Between lives: how long he keeps earning while the game is closed. Meta, like Marrow —
	# it survives the reset — which is why it is sold here and not in the run's upgrade tree.
	# The docs promised it (2 h, then 8, then 24, for Hearts) and nothing sold it.
	_sleep_cabinet = Cabinet.new("Between lives", &"heart", &"night", SLEEP_STAGE)
	_sleep_cabinet.name = "SleepCabinet"
	add_child(_sleep_cabinet)
	_sleep_label = UIStyle.body("", UIStyle.BODY, UIStyle.TEXT)
	_sleep_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sleep_label.custom_minimum_size = Vector2(300, 0)
	_sleep_cabinet.stage_body.add_child(_sleep_label)
	_sleep_cabinet.add_odds_prose("Kept through every reset, like Marrow. Paid in Hearts.")
	_sleep_cabinet.push_right()
	_sleep_button = Cabinet.key("", 260)
	_sleep_button.name = "SleepLonger"
	_sleep_button.pressed.connect(_on_sleep_pressed)
	_sleep_cabinet.deck.add_child(_sleep_button)
	UIMotion.hook(_sleep_button, _sleep_cabinet.stage)

## Closing the card is a decision not to reincarnate. The confirm does not survive it.
## Below this, a reset is a mistake dressed as a choice: there is no threshold in the maths
## any more (D33), so the floor is a courtesy rather than a rule, and it is stated in the
## same figure the player is reading.
const MINIMUM_WORTH_TAKING := 0.01

func _on_page_hidden() -> void:
	_disarm()

func _on_pressed() -> void:
	if Economy.pending_marrow() < MINIMUM_WORTH_TAKING:
		return
	if not _armed or Time.get_ticks_msec() - _armed_at > ARM_WINDOW_MS:
		_armed = true
		_armed_at = Time.get_ticks_msec()
		_refresh()
		# The button changing colour is not enough warning for a button that deletes the
		# run. It flinches, so the second press is a decision rather than a reflex.
		UIMotion.buzz(_button)
		return
	_armed = false
	Economy.perform_prestige()
	UIMotion.punch(_ghost, 2.2)
	UIMotion.flash(_headline, Color(1.8, 2.0, 1.6), 0.9)

func _refresh() -> void:
	var pending := Economy.pending_marrow()
	var held := Economy.marrow
	var worth_taking := pending >= MINIMUM_WORTH_TAKING

	# Hidden rather than showing a lone zero: "+1.40" is a promise and "0" is a
	# non-statement, and the EVER EARNED figure below already says why the number is zero.
	_gain_row.visible = worth_taking
	_headline.text = "+%.2f" % pending
	_lives.text = str(Economy.prestige_count)
	_detail.text = _explain(pending, held)
	_write_figures(pending, held)

	_ghost.modulate = UIStyle.DOLLARS if worth_taking else UIStyle.TEXT_DIM
	if not worth_taking:
		_button.text = "Not yet"
		UIStyle.set_icon(_button, UIStyle.glyph(&"lock"))
		_button.disabled = true
		_button.theme_type_variation = &"DeckKey"
		UIStyle.tint_button(_button, UIStyle.TEXT_DIM)
		_cabinet.say("Nothing to take yet")
	elif _armed:
		# The armed state says what will happen, not "are you sure" — the player already
		# knows they are sure, what they need is the consequence spelled out. It is also
		# the only red button in the game, and it only turns red at this point.
		_button.text = "Press again to reset"
		UIStyle.set_icon(_button, UIStyle.glyph(&"cross"))
		_button.disabled = false
		_button.theme_type_variation = &"DangerButton"
		UIStyle.tint_button(_button, UIStyle.PANEL)
		_cabinet.say("This ends the run", UIStyle.LOCKED)
	else:
		_button.text = "Reincarnate"
		UIStyle.set_icon(_button, UIStyle.glyph(&"dollar"))
		_button.disabled = false
		_button.theme_type_variation = &"DeckKey"
		UIStyle.tint_button(_button, UIStyle.DOLLARS)
		_cabinet.say("+%.2f Marrow, and a new life" % pending, UIStyle.DOLLARS)

	var personality := ItemDB.get_personality(StringName(Economy.personality))
	if personality:
		_personality_label.text = "%s — %s" % [personality.display_name, personality.description]
	else:
		_personality_label.text = Economy.personality
	_refresh_sleep()

## The figures, in the face whose digits can be trusted, as the cabinet's paytable. Rebuilt
## rather than refreshed because the strip is one cell before a reincarnation is available
## and two after.
func _write_figures(pending: float, held: float) -> void:
	_cabinet.clear_odds()
	if pending < MINIMUM_WORTH_TAKING:
		# **This run**, not lifetime: Marrow is scaled by what this life earned, so lifetime
		# is the wrong number to show someone asking why the button is dark (D33). Showing
		# lifetime here was true of the Ectoplasm curve and is a lie about this one.
		_cabinet.add_odds_figure(&"bone", "This run", UIStyle.format_amount(Economy.run_earnings),
			UIStyle.BONES)
		return
	_cabinet.add_odds_figure(&"star", "Marrow", "%.2f \u2192 %.2f" % [held, held + pending],
		UIStyle.DOLLARS)
	_cabinet.add_odds_figure(&"bone", "All income", "x%.2f" % (1.0 + held + pending),
		UIStyle.BONES)

## Deliberately free of digits: every figure in this screen lives in `_write_figures`,
## where it is set in Silkscreen. What is left here is the part that is genuinely prose —
## the trade, in words.
func _explain(pending: float, _held: float) -> String:
	if pending < MINIMUM_WORTH_TAKING:
		return ("Marrow comes from what *this* life earns, and it climbs the whole time you "
			+ "play. There is no threshold to cross — come back when the number is worth it.")
	return ("You keep your Marrow, your Dollars, your hats and everything you have ever earned.\n"
		+ "You lose every Bone, every Heart, every toy, every upgrade and all mastery.\n"
		+ "He comes back with a new personality, which changes what his moods are worth — "
		+ "so the next life asks you to play differently, not just faster.")
