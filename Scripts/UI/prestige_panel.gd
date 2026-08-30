class_name PrestigePanel
extends PanelPage

## Reincarnation: hand the run back, keep the Ectoplasm, get a new Bonehead.
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

func _build_page() -> void:
	add_theme_constant_override("separation", 10)
	add_child(UIStyle.eyebrow("Reincarnation"))

	# The gain, as big as it deserves and with the ghost beside it. Ectoplasm is the only
	# number in the game that survives the reset, so it is the only number that gets the
	# hero size.
	var gain := HBoxContainer.new()
	gain.add_theme_constant_override("separation", 8)
	add_child(gain)
	_gain_row = gain
	_ghost = UIStyle.icon(&"ecto", 16, UIStyle.ECTOPLASM)
	gain.add_child(_ghost)
	_headline = UIStyle.label("", UIStyle.HERO, UIStyle.ECTOPLASM)
	_headline.theme_type_variation = &"Numeral"
	gain.add_child(_headline)

	# The figures and the prose are separated on purpose, and not only for the layout: the
	# body face draws 5 as a rounded form that reads as an 8, so no number in the game is
	# ever set in it. Here that split does double duty — the trade is easier to weigh when
	# what you keep and what you lose is a sentence, and what it is worth is a figure.
	_figures = HBoxContainer.new()
	_figures.add_theme_constant_override("separation", 8)
	add_child(_figures)

	_detail = UIStyle.body("")
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(320, 0)
	add_child(_detail)

	_button = UIStyle.button("", UIStyle.LABEL)
	_button.custom_minimum_size = Vector2(220, 40)
	_button.pressed.connect(_on_pressed)
	add_child(_button)
	UIMotion.hook(_button)

	add_child(UIStyle.eyebrow("This life"))
	var who := PanelContainer.new()
	who.theme_type_variation = &"Tile"
	add_child(who)
	_personality_label = UIStyle.body("", UIStyle.BODY, UIStyle.TEXT)
	_personality_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_personality_label.custom_minimum_size = Vector2(300, 0)
	who.add_child(_personality_label)

## Closing the card is a decision not to reincarnate. The confirm does not survive it.
func _on_page_hidden() -> void:
	_disarm()

func _on_pressed() -> void:
	if Economy.pending_ectoplasm() <= 0:
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
	var pending := Economy.pending_ectoplasm()
	var held := Economy.ectoplasm

	# Hidden rather than showing a lone zero: "+3 ectoplasm" is a promise and "0" is a
	# non-statement, and the EVER EARNED figure below already says why the number is zero.
	_gain_row.visible = pending > 0
	_headline.text = "+%d" % pending
	_detail.text = _explain(pending, held)
	_write_figures(pending, held)

	_ghost.modulate = UIStyle.ECTOPLASM if pending > 0 else UIStyle.TEXT_DIM
	if pending <= 0:
		_button.text = "Not yet"
		_button.icon = UIStyle.glyph(&"lock")
		_button.disabled = true
		_button.theme_type_variation = &"Button"
		UIStyle.tint_button(_button, UIStyle.TEXT_DIM)
	elif _armed:
		# The armed state says what will happen, not "are you sure" — the player already
		# knows they are sure, what they need is the consequence spelled out. It is also
		# the only red button in the game, and it only turns red at this point.
		_button.text = "Press again to reset"
		_button.icon = UIStyle.glyph(&"cross")
		_button.disabled = false
		_button.theme_type_variation = &"DangerButton"
		UIStyle.tint_button(_button, UIStyle.PANEL)
	else:
		_button.text = "Reincarnate"
		_button.icon = UIStyle.glyph(&"ecto")
		_button.disabled = false
		_button.theme_type_variation = &"Button"
		UIStyle.tint_button(_button, UIStyle.ECTOPLASM)

	var personality := ItemDB.get_personality(StringName(Economy.personality))
	if personality:
		_personality_label.text = "%s — %s" % [personality.display_name, personality.description]
	else:
		_personality_label.text = Economy.personality

## The figures, in the face whose digits can be trusted. Rebuilt rather than refreshed
## because the row is two chips before a reincarnation is available and three after.
func _write_figures(pending: int, held: int) -> void:
	for child in _figures.get_children():
		child.queue_free()
	if pending <= 0:
		# Lifetime, not current balance, is what the cube root is taken of — so lifetime is
		# the number to show someone asking why the button is dark.
		var lifetime := Economy.lifetime_of(Economy.BONES) + Economy.lifetime_of(Economy.HEARTS)
		_figures.add_child(_figure(&"bone", "EVER EARNED", UIStyle.format_amount(lifetime),
			UIStyle.BONES))
		return
	_figures.add_child(_figure(&"ecto", "ECTOPLASM", "%d \u2192 %d" % [held, held + pending],
		UIStyle.ECTOPLASM))
	_figures.add_child(_figure(&"star", "ALL INCOME", "+%d%%" % (held + pending), UIStyle.BONES))

func _figure(mark: StringName, caption: String, value: String, colour: Color) -> Control:
	var chip := PanelContainer.new()
	chip.theme_type_variation = &"Sunk"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	chip.add_child(row)
	row.add_child(UIStyle.icon(mark, 16, colour))
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	text.add_child(UIStyle.eyebrow(caption))
	var value_label := UIStyle.label(value, UIStyle.LABEL, colour)
	value_label.theme_type_variation = &"Numeral"
	text.add_child(value_label)
	return chip

## Deliberately free of digits: every figure in this screen lives in `_write_figures`,
## where it is set in Silkscreen. What is left here is the part that is genuinely prose —
## the trade, in words.
func _explain(pending: int, _held: int) -> String:
	if pending <= 0:
		return ("Ectoplasm comes from everything you have ever earned, across every life. "
			+ "Keep going; each point is worth roughly eight times the last.")
	return ("You keep your ectoplasm and everything you have ever earned.\n"
		+ "You lose every Bone, every Heart, every toy, every upgrade and all mastery.\n"
		+ "He comes back with a new personality, which changes what his moods are worth — "
		+ "so the next life asks you to play differently, not just faster.")
