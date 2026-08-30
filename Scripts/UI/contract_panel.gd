class_name ContractPanel
extends PanelPage

## The contract board: a handful of rotating objectives paying Dollars.
##
## The daily-return hook. It replaces the genre's login bonus with something that does not
## smell like free-to-play — you come back because there is a job on the board, not because
## a timer filled (docs/game-design.md).
##
## Rows are rebuilt when the board rotates and only refreshed otherwise, because progress
## ticks on every hit and rebuilding a list sixty times a second is how a HUD becomes the
## most expensive thing in a game with a 3% CPU budget.

var _list: VBoxContainer
var _summary: Label
var _rows: Dictionary = {}  ## StringName (contract id) -> Dictionary of live controls
var _board: Array[StringName] = []

func _ready() -> void:
	# `request_refresh()` rather than `_refresh()` at every one of these: contract_event
	# fires once per hit, and a repaint formats numbers and re-themes a button for every
	# row. PanelPage drops the work while the card is shut and replays it on open.
	EventBus.contract_event.connect(func(_k: StringName, _c: int) -> void: request_refresh())
	EventBus.contract_completed.connect(func(_id: StringName) -> void: request_refresh())
	EventBus.contract_claimed.connect(func(_id: StringName, _e: int) -> void: request_refresh())
	EventBus.prestige_performed.connect(func(_gained: int) -> void: request_rebuild())
	# The board can roll over — daily at midnight, weekly on Monday — while the panel is
	# closed, and `_active_contracts` is replaced wholesale when it does. Nothing else tells
	# the page its rows are keyed to contracts that no longer exist.
	EventBus.contract_board_changed.connect(func() -> void: request_rebuild())
	super()

## Claiming pays Dollars, so the row throws a coin at the purse the same way a purchase
## throws a coin — the only difference is the direction of the money.
func _claim(contract_id: StringName, row_panel: Control, claim: Control) -> void:
	if not Progression.claim_contract(contract_id):
		UIMotion.buzz(row_panel)
		return
	UIMotion.confirm(row_panel)
	# Screen space — see the note at the matching emit in augment_panel.gd.
	EventBus.ui_spend.emit(Economy.DOLLARS, 0.0, UIScale.screen_centre(claim))

func _build_page() -> void:
	add_theme_constant_override("separation", 8)
	_summary = UIStyle.body("")
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size = Vector2(300, 0)
	add_child(_summary)

	# No scroll of its own: the card's host is already a ScrollContainer, and nesting two
	# means the wheel picks one of them at random.
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 5)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_list)

## Only when the board itself changes. `_refresh()` handles everything else.
func _rebuild() -> void:
	var board: Array[StringName] = []
	for contract in Progression.active_contracts():
		board.append(contract.id)
	if board == _board and not _rows.is_empty():
		_refresh()
		return

	_board = board
	_rows.clear()
	for child in _list.get_children():
		child.queue_free()

	if board.is_empty():
		_list.add_child(UIStyle.body("The board is empty today."))
		_refresh()
		return

	for contract in Progression.active_contracts():
		_list.add_child(_make_row(contract))
	_refresh()

func _make_row(contract: ContractData) -> Control:
	var row_panel := PanelContainer.new()
	row_panel.theme_type_variation = &"Tile"

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	row_panel.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	header.add_child(text)
	var title := UIStyle.label(contract.display_name, UIStyle.NAME)
	title.theme_type_variation = &"NameLabel"
	text.add_child(title)
	# An objective is a figure — "Deal 5,000 damage" — so it is set in the face whose
	# digits are unambiguous, for the same reason the augment effects are.
	var subtitle := UIStyle.label(contract.description.to_upper(), UIStyle.MICRO, UIStyle.TEXT_DIM)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.custom_minimum_size = Vector2(210, 0)
	text.add_child(subtitle)

	var claim := UIStyle.button("", UIStyle.LABEL)
	claim.theme_type_variation = &"BuyButton"
	claim.custom_minimum_size = Vector2(104, 34)
	claim.pressed.connect(func() -> void: _claim(contract.id, row_panel, claim))
	header.add_child(claim)
	UIMotion.hook(claim, row_panel)

	var bar := ProgressBar.new()
	bar.max_value = float(contract.target)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	bar.add_theme_stylebox_override("fill", UIStyle.meter_fill(UIStyle.DOLLARS))
	column.add_child(bar)

	# Progress on the left, the prize on the right, with the ghost that pays it. The
	# reward is the reason to finish the job, so it is a picture rather than a word.
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 5)
	column.add_child(footer)
	var counter := UIStyle.label("", UIStyle.MICRO, UIStyle.TEXT_DIM)
	counter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(counter)
	footer.add_child(UIStyle.icon(&"dollar", UIStyle.GLYPH, UIStyle.DOLLARS))
	var reward := UIStyle.label(str(contract.reward_dollars), UIStyle.MICRO, UIStyle.DOLLARS)
	reward.theme_type_variation = &"Numeral"
	footer.add_child(reward)

	_rows[contract.id] = {"claim": claim, "bar": bar, "counter": counter, "row": row_panel}
	return row_panel

func _refresh() -> void:
	var period_word := "Daily contracts refresh at midnight."
	_summary.text = "%s  Rewards are Dollars — they buy how he looks, never how much he earns." % period_word

	for key in _rows:
		var contract := ItemDB.get_contract(key)
		if contract == null:
			continue
		var controls: Dictionary = _rows[key]
		var progress := Progression.contract_progress(contract.id)
		(controls["bar"] as ProgressBar).value = float(progress)
		(controls["counter"] as Label).text = "%s / %s" % [
			UIStyle.format_amount(progress), UIStyle.format_amount(contract.target)]

		var claim := controls["claim"] as Button
		var row_panel := controls["row"] as PanelContainer
		if Progression.is_contract_claimed(contract.id):
			claim.text = "Claimed"
			claim.icon = UIStyle.glyph(&"check")
			claim.disabled = true
			UIStyle.tint_button(claim, UIStyle.TEXT_DIM)
			row_panel.theme_type_variation = &"Tile"
		elif Progression.is_contract_complete(contract.id):
			claim.text = "Claim"
			claim.icon = UIStyle.glyph(&"dollar")
			claim.disabled = false
			UIStyle.tint_button(claim, UIStyle.DOLLARS)
			row_panel.theme_type_variation = &"TileHot"
		else:
			# The percentage, not the word "incomplete": the player wants to know whether it
			# is worth finishing this session.
			claim.text = "%d%%" % int(100.0 * float(progress) / float(maxi(1, contract.target)))
			claim.icon = null
			claim.disabled = true
			UIStyle.tint_button(claim, UIStyle.TEXT_DIM)
			row_panel.theme_type_variation = &"Tile"
