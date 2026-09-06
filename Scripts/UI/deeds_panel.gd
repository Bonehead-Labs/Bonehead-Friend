class_name DeedsPanel
extends PanelPage

## The deeds board: everything the player has done, counted forever, with the next rung of
## each in sight.
##
## Sixty-two milestones existed and paid out with a toast, and then vanished — there was no
## page, `Milestones.earned()` was called by nobody, and `Economy.stats` was displayed nowhere
## (docs/assessment-2026-09.md §4: "meta has nowhere to go"). A milestone is a biography; a
## biography nobody can read is not a reward. This is the page a player opens to see how far
## they have come and what the next rung costs, which is the genre's oldest hook after the
## number going up.
##
## Rows are built once and refreshed by value. Progress ticks on every hit, and this page has
## sixty rows; rebuilding it on `contract_event` would be the most expensive thing in the
## game. `PanelPage` coalesces the refresh and drops it while the card is shut.

var _summary: Label
var _stats: GridContainer
var _stat_values: Dictionary = {}     ## StringName -> Label
var _list: VBoxContainer
var _rows: Dictionary = {}            ## milestone id -> Dictionary of live controls

## What the stats tile shows, in order: [key, caption]. Values come from `_stat_value`.
const STATS := [
	[&"lifetime_bones", "Bones ever"],
	[&"lifetime_hearts", "Hearts ever"],
	[&"damage_dealt", "Damage dealt"],
	[&"pets", "Kind acts"],
	[&"knockouts", "Knockouts"],
	[&"best_streak", "Best streak"],
	[&"best_round", "Best round"],
	[&"items_owned", "Toys owned"],
	[&"reincarnations", "Lives"],
	[&"marrow", "Marrow"],
]

## The receipt for today: what this sitting earned and did. Never saved — that is the point.
const SESSION := [
	[&"session_bones", "Bones"],
	[&"session_hearts", "Hearts"],
	[&"session_hits", "Hits"],
	[&"session_pets", "Kind acts"],
	[&"session_knockouts", "Knockouts"],
	[&"session_best_streak", "Best streak"],
]

func _ready() -> void:
	refresh_on_show = true
	EventBus.contract_event.connect(func(_k: StringName, _c: int) -> void: request_refresh())
	EventBus.item_purchased.connect(func(_id: StringName) -> void: request_refresh())
	EventBus.prestige_performed.connect(func(_gained: float) -> void: request_refresh())
	Milestones.milestone_claimed.connect(func(id: StringName, _r: int, _d: int) -> void:
		_celebrate(id)
		request_refresh())
	super()

func _build_page() -> void:
	add_theme_constant_override("separation", 8)
	_summary = UIStyle.body("")
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size = Vector2(300, 0)
	add_child(_summary)

	# The numbers a player quotes to a friend, in the face whose digits are unambiguous.
	add_child(UIStyle.eyebrow("The record"))
	var tile := PanelContainer.new()
	tile.theme_type_variation = &"Tile"
	add_child(tile)
	_stats = GridContainer.new()
	_stats.columns = 2
	_stats.add_theme_constant_override("h_separation", 12)
	_stats.add_theme_constant_override("v_separation", 3)
	tile.add_child(_stats)
	_fill_grid(_stats, STATS)

	add_child(UIStyle.eyebrow("This session"))
	var today := PanelContainer.new()
	today.theme_type_variation = &"Sunk"
	add_child(today)
	var session_grid := GridContainer.new()
	session_grid.columns = 2
	session_grid.add_theme_constant_override("h_separation", 12)
	session_grid.add_theme_constant_override("v_separation", 3)
	today.add_child(session_grid)
	_fill_grid(session_grid, SESSION)

	add_child(UIStyle.eyebrow("Deeds"))
	# No scroll of its own: the card's host is already a ScrollContainer.
	_list = VBoxContainer.new()
	_list.name = "DeedsList"
	_list.add_theme_constant_override("separation", 5)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_list)

func _fill_grid(grid: GridContainer, rows: Array) -> void:
	for entry in rows:
		var caption := UIStyle.label(String(entry[1]).to_upper(), UIStyle.MICRO, UIStyle.TEXT_DIM)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(caption)
		var value := UIStyle.label("", UIStyle.LABEL, UIStyle.TEXT)
		value.theme_type_variation = &"Numeral"
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value)
		_stat_values[entry[0]] = value

## Once: the board is data and does not change at runtime.
func _rebuild() -> void:
	if not _rows.is_empty():
		_refresh()
		return
	for child in _list.get_children():
		child.queue_free()
	var board := ItemDB.all_milestones().duplicate()
	board.sort_custom(func(a: MilestoneData, b: MilestoneData) -> bool:
		return a.sort_order < b.sort_order)
	for milestone in board:
		_list.add_child(_make_row(milestone))
	_refresh()

func _make_row(milestone: MilestoneData) -> Control:
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
	var title := UIStyle.label("", UIStyle.NAME)
	title.theme_type_variation = &"NameLabel"
	text.add_child(title)
	var subtitle := UIStyle.label("", UIStyle.MICRO, UIStyle.TEXT_DIM)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.custom_minimum_size = Vector2(210, 0)
	text.add_child(subtitle)

	# The rung, for ladders; the tick, for a deed done.
	var badge := UIStyle.label("", UIStyle.MICRO, UIStyle.DOLLARS)
	badge.theme_type_variation = &"Numeral"
	badge.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	header.add_child(badge)

	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.step = 0.001
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	bar.add_theme_stylebox_override("fill", UIStyle.meter_fill(UIStyle.DOLLARS))
	column.add_child(bar)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 5)
	column.add_child(footer)
	var counter := UIStyle.label("", UIStyle.MICRO, UIStyle.TEXT_DIM)
	counter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(counter)
	footer.add_child(UIStyle.icon(&"dollar", UIStyle.GLYPH, UIStyle.DOLLARS))
	var reward := UIStyle.label(str(milestone.reward_dollars), UIStyle.MICRO, UIStyle.DOLLARS)
	reward.theme_type_variation = &"Numeral"
	footer.add_child(reward)

	_rows[milestone.id] = {"row": row_panel, "title": title, "subtitle": subtitle,
		"badge": badge, "bar": bar, "counter": counter}
	return row_panel

func _refresh() -> void:
	var board := ItemDB.all_milestones()
	var earned := Milestones.earned().size()
	_summary.text = "%d of %d deeds done.  Every deed pays Dollars once and %s to all income for good — breadth is the third way to earn." % [
		earned, board.size(), "+%d%%" % int(round((Milestones.income_multiplier() - 1.0) * 100.0))]

	for entry in STATS:
		(_stat_values[entry[0]] as Label).text = _stat_value(entry[0])
	for entry in SESSION:
		(_stat_values[entry[0]] as Label).text = _stat_value(entry[0])

	for milestone in board:
		if not _rows.has(milestone.id):
			continue
		var controls: Dictionary = _rows[milestone.id]
		var status := Milestones.status(milestone)
		var claimed := int(status[0])
		var progress := float(status[1])
		var next_target := float(status[2])
		var done := claimed > 0
		var ladder := milestone.repeat_every > 0.0

		# A hidden deed is the joke, and the surprise is the reward: no name until it is done.
		var secret := milestone.hidden and not done
		(controls["title"] as Label).text = "A secret deed" if secret else milestone.display_name
		(controls["subtitle"] as Label).text = "Keep going." if secret \
			else milestone.description.to_upper()

		var badge := controls["badge"] as Label
		if ladder and done:
			badge.text = "RUNG %d" % claimed
		elif done:
			badge.text = "DONE"
		else:
			badge.text = ""

		# Toward the *next* rung: a ladder always has one, a one-shot stops at full.
		var bar := controls["bar"] as ProgressBar
		var counter := controls["counter"] as Label
		if done and not ladder:
			UIMotion.fill(bar, 1.0)
			counter.text = UIStyle.format_amount(progress)
		else:
			var floor_value := milestone.next_target(maxi(claimed - 1, 0)) if claimed > 0 else 0.0
			var span := maxf(next_target - floor_value, 0.000001)
			UIMotion.fill(bar, clampf((progress - floor_value) / span, 0.0, 1.0))
			counter.text = "%s / %s" % [UIStyle.format_amount(progress), UIStyle.format_amount(next_target)]
		(controls["row"] as PanelContainer).theme_type_variation = &"TileHot" if done else &"Tile"

## A rung claimed while the page is open: the row confirms and its reward chips off the badge.
## Deeds claim themselves (D34), so this is the only place the claim is *seen* happen.
func _celebrate(id: StringName) -> void:
	if not is_visible_in_tree() or not _rows.has(id):
		return
	var controls: Dictionary = _rows[id]
	UIMotion.confirm(controls["row"] as Control)
	UIMotion.sparkle(controls["bar"] as Control, UIStyle.DOLLARS, 16, 180.0)

func _stat_value(key: StringName) -> String:
	match key:
		&"lifetime_bones":
			return UIStyle.format_amount(Economy.lifetime_of(Economy.BONES))
		&"lifetime_hearts":
			return UIStyle.format_amount(Economy.lifetime_of(Economy.HEARTS))
		&"damage_dealt":
			return UIStyle.format_amount(float(Economy.stats.get("damage_dealt", 0.0)))
		&"pets":
			return UIStyle.format_amount(float(Economy.stats.get("pets", 0)))
		&"knockouts":
			return UIStyle.format_amount(float(Economy.stats.get("knockouts", 0)))
		&"items_owned":
			return str(Progression.owned_items().size())
		&"reincarnations":
			return str(Economy.prestige_count)
		&"marrow":
			return "%.2f" % Economy.marrow
		&"best_round":
			return UIStyle.format_amount(float(Economy.stats.get("best_round_bones", 0.0)))
		&"best_streak":
			return "x%d" % int(Economy.stats.get("best_streak", 0))
		&"session_bones":
			return UIStyle.format_amount(float(Economy.session["bones"]))
		&"session_hearts":
			return UIStyle.format_amount(float(Economy.session["hearts"]))
		&"session_hits":
			return str(int(Economy.session["hits"]))
		&"session_pets":
			return str(int(Economy.session["pets"]))
		&"session_knockouts":
			return str(int(Economy.session["knockouts"]))
		&"session_best_streak":
			return "x%d" % int(Economy.session["best_streak"])
	return ""
