class_name HUD
extends CanvasLayer

## One box in the corner: what you have, how close he is to collapsing, and what mood he
## is in. Nothing else is permanent.
##
## It was three separate things — a row of currency chips, a meter card, and a five-button
## dock — spread across two corners of somebody's desktop. That is a lot of chrome to leave
## on screen all day for a game whose whole promise is that it sits quietly while you work.
## The dock is gone (the panel owns its own tab strip now, `PanelLayer`), and the rest is
## one block.
##
## Two readouts earn their place by *not* being permanent: the item count and the grime
## warning only appear when they are true of something.

## Inset from the window edge, in UI pixels. Small: the overlay sits on someone's desktop
## and the HUD should read as part of the game, not as a border around their screen.
const MARGIN := 12.0
## Wide enough for two meters with their captions beside them, narrow enough not to be a
## sidebar. At 2x this is 480 real pixels.
const WIDTH := 268.0

var _root: Control
var _purse: PurseStrip
var _box: PanelContainer
var _meter: ProgressBar
var _mood_meter: ProgressBar
var _mood_label: Label
var _mood_fill: StyleBoxFlat
var _mood_label_colour := Color.TRANSPARENT
var _footer: HBoxContainer
## The equipped cursor power, and the button that puts it away (D47).
var _armed_button: Button
var _item_count: Label
var _clear_button: Button

## Key for the one-off tip that teaches both removal gestures. Lives in `Settings`, so it is
## remembered per machine and survives the Reincarnation that wipes the save.
const HINT_REMOVAL := &"removal_gestures"

## Key for the one-off tip that teaches what being armed does and does not cost (D47).
##
## The rules are good and none of them is *visible*: nothing on screen says that your toys
## still pick up normally, or that Shift gets you your plain hands back. A control scheme
## that has to be discovered by experiment is a control scheme most players will conclude is
## broken — they will try to drag him, shoot him instead, and stop equipping powers.
const HINT_CURSOR_POWER := &"cursor_power_gestures"
var _grime_label: Label
var _toast: PanelContainer
var _toast_label: Label
var _toast_tween: Tween

## Optional auto-hide (Settings > Shell). The column parks against the left edge — the edge
## it is anchored to — and an arrow pointing right marks the way back.
var _drawer: HoverDrawer
var _column: VBoxContainer

## Income, as a rolling average: the number an idle player checks on every glance and the
## one that makes an upgrade feel like it did something. Nothing else in the game showed a
## rate outside one line in the tree (assessment-2026-09).
const RATE_WINDOW := 10.0
var _rate_row: HBoxContainer
var _rate_labels := {}          ## currency -> Label
var _income := {}               ## currency -> Array of [seconds, amount]
var _rate_timer: Timer

## The next thing to buy, always on screen. The genre's single biggest hook and the shell
## had it only inside an open shop page, behind a drawer that hides by default.
const NEXT_SETTLE := 0.4
var _next_row: HBoxContainer
var _next_face: TextureRect
var _next_name: Label
var _next_price: Label
var _next_bar: ProgressBar
var _next_fill: StyleBoxFlat
var _next_item: StringName = &""
var _next_affordable := false
var _next_timer: Timer

var _health: HealthComponent
var _spawner: ItemSpawner
## The knockout meter only reacts when it jumps, not when it creeps — a bar that punches
## on every physics frame is a flicker.
var _meter_shown := 0.0
## The meter glows once it is nearly full. Anticipation is the genre's cheapest reward: a
## bar at 90% is a promise, and a promise that pulses gets kept. One looping tween, only while
## in the zone, and never at Focus Off.
const METER_HOT_FROM := 0.85
var _meter_hot := false
var _hot_tween: Tween

## Found by group, never by path (docs/decisions.md D9). `FXLayer` needs this one to keep the
## big payout numbers off the corner the HUD occupies (D48).
const GROUP_HUD := &"hud"

func _ready() -> void:
	layer = 10
	add_to_group(GROUP_HUD)
	_build()
	_install_drawer()
	EventBus.buddy_state_changed.connect(_on_buddy_state_changed)
	EventBus.mood_changed.connect(_on_mood_changed)
	EventBus.grime_changed.connect(_on_grime_changed)
	EventBus.cursor_power_changed.connect(_on_cursor_power_changed)
	EventBus.payout.connect(_on_payout)
	EventBus.payout.connect(_on_streak_payout)
	EventBus.currency_changed.connect(func(_c: StringName, _b: float) -> void: _mark_next_dirty())
	EventBus.item_purchased.connect(func(_id: StringName) -> void: _mark_next_dirty())
	EventBus.prestige_performed.connect(func(_m: float) -> void:
		_mark_next_dirty()
		# A new life is a new personality, and the mood row names him.
		_on_mood_changed(Economy.mood))
	EventBus.ui_scale_changed.connect(func(_f: int) -> void: _fit())
	get_viewport().size_changed.connect(_fit)
	# `size_changed` is not enough on its own. Changing the play area resizes the OS window,
	# and the viewport has not caught up at the moment the setting is applied — so the shell
	# was laid out against the *previous* window and stayed that way, which put a 697px-wide
	# strip inside a 480px window. `window_rect_changed` fires once the window has actually
	# settled, which is the moment the layout is answerable.
	OverlayManager.window_rect_changed.connect(func(_r: Rect2i) -> void: _fit())
	_fit()
	# Signals only fire on change, so a fresh boot would leave both readouts showing their
	# placeholder text until something happened to him.
	_on_mood_changed(Economy.mood)
	_on_grime_changed(Economy.grime)
	_mark_next_dirty()

## Driven by the meter's own signals, not polled: a HUD reading `fill_fraction()` every
## rendered frame for eight hours was the one per-frame cost left in the shell.
func _on_health_changed() -> void:
	if _health == null or _meter == null:
		return
	var fill := _health.fill_fraction()
	_meter.value = fill
	# A tenth of the bar in one step is a real hit, not decay.
	if fill - _meter_shown > 0.1:
		UIMotion.punch(_box, 1.04)
	_meter_shown = fill
	_set_meter_hot(fill >= METER_HOT_FROM and not _health.down)

## The meter belongs to the buddy, so main.gd hands it over rather than the HUD hunting
## for a node path across scenes (docs/decisions.md D9).
func bind_health(health: HealthComponent) -> void:
	if _health and _health.meter_reset.is_connected(_on_health_changed):
		_health.damaged.disconnect(_on_health_damaged)
		_health.meter_reset.disconnect(_on_health_changed)
	_health = health
	if _health:
		_health.damaged.connect(_on_health_damaged)
		_health.meter_reset.connect(_on_health_changed)
	_on_health_changed()

func _on_health_damaged(_amount: float, _total: float) -> void:
	_on_health_changed()

func bind_spawner(spawner: ItemSpawner) -> void:
	_spawner = spawner
	spawner.item_count_changed.connect(_set_item_count)
	# The signal only fires on a change, so the readout would sit at its placeholder until
	# the player spawned something — showing a limit of zero on a fresh boot.
	_set_item_count(spawner.item_count(), spawner.item_limit())

## Built last: the drawer hangs its mark off `_box`, which does not exist until the card
## above has been assembled.
func _install_drawer() -> void:
	_drawer = HoverDrawer.new()
	_drawer.name = "HudDrawer"
	add_child(_drawer)
	# The mark rides the status card itself, not the column — the column also carries the
	# toast, whose height comes and goes.
	_drawer.setup(_column, _root, HoverDrawer.Edge.LEFT, _box)
	_drawer.pinned = Settings.hud_pinned
	_drawer.pin_toggled.connect(func(value: bool) -> void: Settings.set_hud_pinned(value))
	_drawer.set_home(Vector2(MARGIN, MARGIN))

func _fit() -> void:
	if _root:
		UIScale.apply(self, _root)
	if _drawer:
		_drawer.set_home(Vector2(MARGIN, MARGIN))

## Onboarding pins the card open so a first-time player can see there is a game here. Goes
## through the drawer's own setter, so it is remembered exactly as a click on the pin is.
func pin_drawer(value: bool) -> void:
	if _drawer:
		_drawer.pinned = value


func _build() -> void:
	# A plain Control, not a MarginContainer: a container lays every child out in the same
	# rect and ignores its anchors. Sized explicitly by UIScale rather than anchored,
	# because a top-level Control knows nothing about the scale on the layer above it.
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.get_theme()
	add_child(_root)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE)
	column.position = Vector2(MARGIN, MARGIN)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	_root.add_child(column)
	_column = column

	_box = PanelContainer.new()
	_box.custom_minimum_size = Vector2(WIDTH, 0)
	_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_box.theme_type_variation = &"Card"
	column.add_child(_box)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	_box.add_child(stack)

	# --- what you have ---
	_purse = PurseStrip.new()
	_purse.value_size = UIStyle.TITLE
	# 2x the glyph canvas, so the bone and the heart carry their share of a TITLE-sized
	# figure instead of sitting beside it as specks.
	_purse.glyph_size = UIStyle.GLYPH * 2
	_purse.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_child(_purse)

	# --- how fast it is coming in ---
	stack.add_child(_build_rate_row())
	# --- the rhythm, while it lasts ---
	stack.add_child(_build_streak_row())

	# --- how he is doing ---
	stack.add_child(_meter_row(&"knockout"))
	stack.add_child(_meter_row(&"mood"))

	# --- what to want next ---
	stack.add_child(_build_next_row())
	stack.add_child(_build_rebirth_row())

	# What is in your hand, and the way to put it down (D47). Only on screen while something
	# is equipped, so it costs a permanently-installed player nothing.
	#
	# This row exists because equipping a cursor power was a trip into the panel and so was
	# unequipping it, and nothing on screen said you were still holding one. Being armed
	# changes what a left click does, which makes it the one piece of hidden state in the
	# game that the player can act on by accident.
	_armed_button = UIStyle.button("", UIStyle.MICRO)
	_armed_button.name = "ArmedChip"
	_armed_button.theme_type_variation = &"GhostButton"
	# Tall enough for a shop icon at its own size. The art size contract (D27) forbids
	# stepping a 32px icon down into the 22px row the other footer buttons use, and the row
	# is only on screen while something is equipped, so the height costs nothing at rest.
	_armed_button.custom_minimum_size = Vector2(0, UIStyle.ICON_CANVAS)
	_armed_button.tooltip_text = "Put it away (Esc). Hold Shift to use your hands without unequipping."
	_armed_button.visible = false
	_armed_button.pressed.connect(_on_armed_pressed)
	stack.add_child(_armed_button)

	# --- only when true of something ---
	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation", 6)
	_footer.visible = false
	stack.add_child(_footer)

	_item_count = UIStyle.label("", UIStyle.MICRO, UIStyle.TEXT_DIM)
	_item_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_footer.add_child(_item_count)

	# Clearing the desk used to be a trash bin you dragged things into. It was a 36x45
	# catch area under a 64px sprite, sitting above where dropped items come to rest, so
	# in practice nothing ever landed in it. A button that says what it does is honest.
	#
	# It then spent a milestone *not* saying what it does: a 26x22 ghost carrying a bare
	# cross, sat beside a "3 / 12 items" readout. The first player to want the desk cleared
	# reported that the game had no way to do it — while looking at the button for it. A
	# cross is a close box everywhere else in this shell, which is the wrong promise.
	_clear_button = UIStyle.button("Clear desk", UIStyle.MICRO)
	_clear_button.theme_type_variation = &"GhostButton"
	_clear_button.tooltip_text = "Remove everything you have spawned"
	_clear_button.custom_minimum_size = Vector2(0, 22)
	_clear_button.pressed.connect(_on_clear_pressed)
	_footer.add_child(_clear_button)

	_grime_label = UIStyle.label("", UIStyle.MICRO, UIStyle.LOCKED)
	_grime_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_grime_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_footer.add_child(_grime_label)

	# --- toast ---
	var toast_row := HBoxContainer.new()
	toast_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(toast_row)
	_toast = PanelContainer.new()
	# Named, so a suite can find it. An unnamed `PanelContainer.new()` comes out as
	# `@PanelContainer@31`, which no test can look up and nobody can read in a remote tree.
	_toast.name = "Toast"
	_toast.theme_type_variation = &"Card"
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_row.add_child(_toast)
	# Silkscreen: a toast is nearly always carrying a figure — what you earned while you
	# were away, which rank you just hit — and those are the numbers a player is most
	# likely to read once and never again.
	_toast_label = UIStyle.label("", UIStyle.MICRO, UIStyle.TEXT)
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.custom_minimum_size = Vector2(WIDTH - 24, 0)
	_toast.add_child(_toast_label)

## A bar with its caption on the same line, because two stacked bars each with a heading
## above them is four rows of chrome for two numbers.
func _meter_row(which: StringName) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.step = 0.001
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)

	if which == &"knockout":
		bar.add_theme_stylebox_override("fill", UIStyle.meter_fill(UIStyle.BONES))
		_meter = bar
		var caption := UIStyle.eyebrow("Knockout")
		caption.custom_minimum_size = Vector2(76, 0)
		row.add_child(caption)
	else:
		# Mapped to 0..1 with neutral at the centre, so the bar reads as a seesaw rather
		# than as a fill: half full is the trough, and both ends are worth 2x. The
		# multiplier is printed beside it rather than left to be inferred — mood pays on a
		# U-curve, and a player who reads it as a happiness bar will conclude the middle is
		# fine and quietly earn 0.6x all session (docs/economy.md).
		bar.value = 0.5
		# Held and recoloured in place rather than replaced. Mood changes several times a
		# second during play, and a fresh StyleBoxFlat per change is a steady drip of
		# garbage in a game designed to be left running all day.
		_mood_fill = UIStyle.meter_fill(UIStyle.TEXT_DIM)
		bar.add_theme_stylebox_override("fill", _mood_fill)
		_mood_meter = bar
		_mood_label = UIStyle.label("neutral", UIStyle.MICRO, UIStyle.TEXT_DIM)
		_mood_label.custom_minimum_size = Vector2(76, 0)
		_mood_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(_mood_label)
	return row

# --- income ----------------------------------------------------------------

## One line, two figures, only while something is coming in. Bones and Hearts each get a
## glyph and a "/s"; Dollars are deliberately absent — they are never multiplied and arrive
## on a schedule of attention, so a rate for them is a number nobody can act on.
func _build_rate_row() -> Control:
	_rate_row = HBoxContainer.new()
	_rate_row.add_theme_constant_override("separation", 10)
	_rate_row.visible = false
	for currency in [Economy.BONES, Economy.HEARTS]:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
		cell.add_child(UIStyle.icon(_glyph_id(currency), UIStyle.GLYPH,
			UIStyle.currency_colour(currency)))
		var value := UIStyle.label("", UIStyle.MICRO, UIStyle.currency_colour(currency))
		cell.add_child(value)
		_rate_labels[currency] = value
		_income[currency] = []
		_rate_row.add_child(cell)
	_rate_timer = Timer.new()
	_rate_timer.name = "RateTimer"
	_rate_timer.wait_time = 1.0
	_rate_timer.timeout.connect(_refresh_rate)
	add_child(_rate_timer)
	return _rate_row

func _glyph_id(currency: StringName) -> StringName:
	return &"bone" if currency == Economy.BONES else &"heart"

func _on_payout(currency: StringName, amount: float, _world_pos: Vector2, _source_id: StringName) -> void:
	if not _income.has(currency) or amount <= 0.0:
		return
	(_income[currency] as Array).append([Time.get_ticks_msec() / 1000.0, amount])
	if _rate_timer and _rate_timer.is_stopped():
		_rate_timer.start()
		_refresh_rate()

## Runs once a second while there is income in the window and stops itself when the window
## has drained — a HUD that ticks every second all night is a HUD that costs something.
func _refresh_rate() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var any := false
	for currency in _income:
		var samples: Array = _income[currency]
		while not samples.is_empty() and now - float(samples[0][0]) > RATE_WINDOW:
			samples.pop_front()
		var total := 0.0
		for sample in samples:
			total += float(sample[1])
		var rate := total / RATE_WINDOW
		var label := _rate_labels[currency] as Label
		label.text = "%s/s" % UIStyle.format_amount(rate) if rate > 0.0 else ""
		(label.get_parent() as Control).visible = rate > 0.0
		any = any or rate > 0.0
	_rate_row.visible = any
	if not any and _rate_timer:
		_rate_timer.stop()

# --- next up ---------------------------------------------------------------

## The cheapest thing the player can reach for, with how close they are. It is a link: a
## click opens Toys on that item. It never buys — a purchase is a decision made on a page
## that shows what the thing is, not a reflex on the HUD.
func _build_next_row() -> Control:
	_next_row = HBoxContainer.new()
	_next_row.name = "NextUp"
	_next_row.add_theme_constant_override("separation", 6)
	_next_row.mouse_filter = Control.MOUSE_FILTER_STOP
	_next_row.tooltip_text = "Open in Toys"
	_next_row.visible = false
	_next_row.gui_input.connect(_on_next_input)
	_next_row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	_next_face = UIStyle.sprite(null, UIStyle.ICON_CANVAS)
	_next_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_next_row.add_child(_next_face)

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_next_row.add_child(text)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(line)
	var eyebrow := UIStyle.eyebrow("Next")
	eyebrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(eyebrow)
	_next_name = UIStyle.label("", UIStyle.MICRO, UIStyle.TEXT)
	_next_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_next_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(_next_name)
	_next_price = UIStyle.label("", UIStyle.MICRO, UIStyle.TEXT_DIM)
	_next_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_next_price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(_next_price)

	_next_bar = ProgressBar.new()
	_next_bar.max_value = 1.0
	_next_bar.step = 0.001
	_next_bar.show_percentage = false
	_next_bar.custom_minimum_size = Vector2(0, 6)
	_next_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_next_fill = UIStyle.meter_fill(UIStyle.TEXT_DIM)
	_next_bar.add_theme_stylebox_override("fill", _next_fill)
	text.add_child(_next_bar)

	_next_timer = Timer.new()
	_next_timer.name = "NextTimer"
	_next_timer.one_shot = true
	_next_timer.wait_time = NEXT_SETTLE
	_next_timer.timeout.connect(_refresh_next)
	add_child(_next_timer)
	return _next_row

## Coalesced: `currency_changed` fires on every hit and every pet, and walking the roster
## fourteen times a second to answer a question whose answer changes once a minute is the
## kind of cost that adds up over a working day.
func _mark_next_dirty() -> void:
	if _next_timer and _next_timer.is_stopped():
		_next_timer.start()

## Affordable and cheapest first; otherwise whatever the purse is closest to. Items only —
## an augment level is always for sale, so "next" would never point anywhere else.
func _pick_next() -> ItemData:
	var best: ItemData = null
	var best_score := -1.0
	for item in ItemDB.all_items():
		if item.cost <= 0 or not Progression.can_purchase(item.id):
			continue
		var cost := float(item.cost)
		var ratio := Economy.balance_of(item.currency_id()) / cost
		# Affordable items score above every unaffordable one, and among the affordable
		# the cheapest wins — that is the thing a player reaches for next, not the biggest.
		var score := (2.0 + 1.0 / cost) if ratio >= 1.0 else minf(ratio, 0.999)
		if score > best_score:
			best_score = score
			best = item
	return best

func _refresh_next() -> void:
	_refresh_rebirth()
	var item := _pick_next()
	if item == null:
		_next_row.visible = false
		_next_item = &""
		return
	var cost := float(item.cost)
	var have := Economy.balance_of(item.currency_id())
	var affordable := have >= cost
	var colour := UIStyle.currency_colour(item.currency_id())
	if item.id != _next_item:
		_next_item = item.id
		_next_affordable = false
		UIStyle.set_sprite(_next_face, UIStyle.item_face(item, UIStyle.ICON_CANVAS))
		_next_name.text = item.display_name
		_next_price.text = UIStyle.format_amount(cost)
		_next_price.add_theme_color_override("font_color", colour)
		_next_fill.bg_color = colour
	_next_bar.value = clampf(have / cost, 0.0, 1.0)
	_next_row.visible = true
	if affordable and not _next_affordable:
		# The flip is the moment. Once, when it becomes true, never on every tick after.
		UIMotion.punch(_next_row, 1.08)
		UIMotion.flash(_box, Color(1.15, 1.25, 1.1), 0.4)
		UIMotion.sparkle(_next_row, UIStyle.AFFORDABLE, 12, 150.0)
		_next_price.add_theme_color_override("font_color", UIStyle.AFFORDABLE)
		_next_fill.bg_color = UIStyle.AFFORDABLE
	elif not affordable and _next_affordable:
		_next_price.add_theme_color_override("font_color", colour)
		_next_fill.bg_color = colour
	_next_affordable = affordable

func _on_next_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT and _next_item != &"":
		_next_row.accept_event()
		EventBus.ui_show_item.emit(_next_item)

# --- the long game ---------------------------------------------------------

## "Reincarnate for +N." Prestige is the biggest decision in the game and it lived at the
## bottom of the Arcade tab, where a player who never opens the Arcade never learns the game
## has one (assessment-2026-09 §4). Once a run is worth a whole Marrow the HUD says so, and
## the row is a link to the page that spells out the trade — it never resets anything itself.
const REBIRTH_SHOW_FROM := 1.0
var _rebirth_row: HBoxContainer
var _rebirth_label: Label
var _rebirth_shown := 0.0

func _build_rebirth_row() -> Control:
	_rebirth_row = HBoxContainer.new()
	_rebirth_row.name = "RebirthCall"
	_rebirth_row.add_theme_constant_override("separation", 6)
	_rebirth_row.mouse_filter = Control.MOUSE_FILTER_STOP
	_rebirth_row.tooltip_text = "Open Reincarnation"
	_rebirth_row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_rebirth_row.visible = false
	_rebirth_row.gui_input.connect(_on_rebirth_input)
	var glyph := UIStyle.icon(&"star", UIStyle.GLYPH, UIStyle.DOLLARS)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rebirth_row.add_child(glyph)
	_rebirth_label = UIStyle.label("", UIStyle.MICRO, UIStyle.DOLLARS)
	_rebirth_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rebirth_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rebirth_row.add_child(_rebirth_label)
	return _rebirth_row

## Rides the same coalesced timer as the next-up row: `pending_marrow` moves with every payout
## and changes meaningfully once a minute.
func _refresh_rebirth() -> void:
	if _rebirth_row == null:
		return
	var pending := Economy.pending_marrow()
	if pending < REBIRTH_SHOW_FROM:
		_rebirth_row.visible = false
		_rebirth_shown = 0.0
		return
	_rebirth_label.text = "Reincarnate for +%s Marrow" % ("%.1f" % pending if pending < 100.0
		else UIStyle.format_amount(pending))
	var first_time := not _rebirth_row.visible
	_rebirth_row.visible = true
	# One punch when it first becomes worth it, and again at each whole Marrow after: the
	# moments the number means something, never every tick.
	if first_time or floorf(pending) > floorf(_rebirth_shown):
		UIMotion.punch(_rebirth_row, 1.06)
	if first_time:
		UIMotion.sparkle(_rebirth_row, UIStyle.HEARTS, 12, 150.0)
	_rebirth_shown = pending

func _on_rebirth_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		_rebirth_row.accept_event()
		EventBus.ui_show_panel.emit(&"prestige")

# --- the desk --------------------------------------------------------------

func _set_item_count(count: int, limit: int) -> void:
	_item_count.text = "%d / %d items" % [count, limit]
	if count > 0:
		_offer_the_removal_hint()
	_footer.visible = count > 0 or _grime_label.text != ""
	_clear_button.visible = count > 0
	_item_count.visible = count > 0

## Said once, the first time anything is on the desk, and never again.
##
## Both removal gestures existed for a whole milestone and neither was findable: right-click
## is not written anywhere in the game, and the button that does the rest was a bare cross.
## A tip fired at the moment the player first has something to remove is the cheapest fix
## that does not put permanent chrome on somebody's desktop — which is the whole argument for
## this HUD being as small as it is.
func _offer_the_removal_hint() -> void:
	if Settings.hint_seen(HINT_REMOVAL):
		return
	Settings.mark_hint_seen(HINT_REMOVAL)
	show_toast("Right-click an item to bin it — hold Shift for anything with a fuse. "
		+ "Clear desk removes the lot.", 10.0)

func _on_clear_pressed() -> void:
	if _spawner == null or _spawner.item_count() <= 0:
		UIMotion.buzz(_box)
		return
	_spawner.clear_desk()
	UIMotion.flash(_box, Color(1.3, 1.3, 1.5), 0.35)

# --- toast -----------------------------------------------------------------

## A single line under the HUD for the things that happen *to* the player rather than
## because of them: offline earnings, a rank up, a contract finishing. Deliberately not a
## modal — this game runs while someone is working, and a dialog box over their editor is
## the fastest way to get uninstalled.
## A toast with chips: for the one toast in a session that is a score rather than a notice.
func celebrate_toast(text: String, colour: Color, seconds: float = 7.0) -> void:
	show_toast(text, seconds)
	if _toast and _toast.visible:
		UIMotion.sparkle(_toast, colour, 24, 220.0)

func show_toast(text: String, seconds: float = 6.0) -> void:
	if _toast == null:
		return
	# Kill the previous one first. Both tweens write the same shared card, so an older
	# tween's hide callback would fire partway through the newer message — two rank-ups a
	# second apart is common in the first minutes, where rank 1 costs 100 XP.
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_label.text = text
	_toast.scale = Vector2.ONE
	_toast.visible = true
	UIMotion.rise(_toast)
	# Leaves by rolling up, never by fading: the window is transparent behind the card, and
	# a half-faded toast is grey ink over the desktop (CLAUDE.md: never fade a card).
	UIMotion.pivot(_toast, UIMotion.Pivot.TOP)
	_toast_tween = create_tween()
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(_toast, "scale", Vector2(1.0, 0.04), 0.15) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_toast_tween.tween_callback(func() -> void:
		_toast.visible = false
		_toast.scale = Vector2.ONE)

func _on_buddy_state_changed(state: StringName) -> void:
	if state == &"knockout" and _meter:
		_meter.value = 1.0
		_meter_shown = 1.0
		_set_meter_hot(false)
		UIMotion.punch(_box, 1.1)
		UIMotion.flash(_box, Color(1.6, 1.4, 1.0), 0.6)

## Mood words, not numbers. "-64" means nothing to a player; "miserable" plus the
## multiplier it is worth is the whole mechanic in five characters.
const MOOD_WORDS: Array[String] = ["despairing", "miserable", "glum", "neutral", "cheerful", "delighted", "blissful"]

func _on_mood_changed(value: float) -> void:
	if _mood_meter == null:
		return
	var normalised := clampf((value + 100.0) / 200.0, 0.0, 1.0)
	var colour := UIStyle.mood_colour(value)
	_mood_meter.value = normalised
	if _mood_fill:
		_mood_fill.bg_color = colour
	var word: String = MOOD_WORDS[clampi(int(round(normalised * (MOOD_WORDS.size() - 1))), 0, MOOD_WORDS.size() - 1)]
	# The multiplier comes from the active personality's curve, not the balance default —
	# a Diva and a Masochist read the same mood completely differently — so the personality
	# is named on the same line. It used to be visible only on the Reincarnate page, while
	# the design sells it as half the reason to Reincarnate (assessment-2026-09 §4).
	var who := ItemDB.get_personality(StringName(Economy.personality))
	var name_part := "%s · " % who.display_name if who else ""
	_mood_label.text = "%s%s x%.2f" % [name_part, word, Economy.mood_multiplier()]
	# Re-theming a Control is not free, and this runs on every hit, every pet and roughly
	# four times a second while mood decays back to neutral. The colour only actually moves
	# a handful of times across that whole slide.
	if not colour.is_equal_approx(_mood_label_colour):
		_mood_label_colour = colour
		_mood_label.add_theme_color_override("font_color", colour)

## Below this the penalty rounds to x1.00 on screen. Warning the player about a cost they
## cannot see turns the line into permanent nagging, and a readout that says "x1.00" in a
## warning colour teaches them to ignore it for the times it matters.
const GRIME_VISIBLE_AT := 0.06

func _on_grime_changed(value: float) -> void:
	if _grime_label == null:
		return
	_grime_label.text = "" if value < GRIME_VISIBLE_AT \
		else "grimy: bones x%.2f" % Economy.grime_multiplier()
	_footer.visible = _grime_label.text != "" or _clear_button.visible

## See PanelLayer.shell_rect — screen pixels, not canvas pixels.
func shell_rect() -> Rect2:
	return UIScale.screen_rect(_box) if _box else Rect2()

# --- the armed chip (D47) --------------------------------------------------

func _on_cursor_power_changed(item_id: StringName) -> void:
	if _armed_button == null:
		return
	var item := ItemDB.get_item(item_id) if item_id != &"" else null
	_armed_button.visible = item != null
	if item == null:
		return
	# The exit is written on the chip, not left in the tooltip. A tooltip has to be found by
	# hovering something the player does not yet know is interactive, which is the wrong
	# place for the one instruction they need in order to stop.
	_armed_button.text = "Holding: %s  ·  Esc" % item.display_name
	UIStyle.set_icon(_armed_button, UIStyle.item_face(item, UIStyle.ICON_CANVAS),
		UIStyle.ICON_CANVAS)
	_offer_the_power_hint(item)

## Said once, the first time the player equips anything, and never again.
##
## Same argument as the removal hint above: the alternative to teaching this once is either
## permanent chrome on somebody's desktop or a player who never finds it. Shift is the line
## that earns the toast — the other two rules are guessable, because clicking a toy to pick
## it up is what clicking a toy already did, but nothing suggests that holding a key gives
## you your hands back.
func _offer_the_power_hint(item: ItemData) -> void:
	if Settings.hint_seen(HINT_CURSOR_POWER):
		return
	Settings.mark_hint_seen(HINT_CURSOR_POWER)
	show_toast("You're holding the %s. Click him to use it — your toys still pick up "
		% item.display_name
		+ "as normal. Hold Shift to grab him instead. Esc puts it away.", 12.0)

func _on_armed_pressed() -> void:
	var spawner := get_tree().get_first_node_in_group(&"item_spawner")
	if spawner and spawner.has_method("holster_power"):
		spawner.call("holster_power")

## The knockout meter, nearly there. A slow warm pulse on the bar while it is within reach,
## and a punch on the card the moment it gets there — so the player who has been tapping
## away finishes him rather than wandering off at 87%.
func _set_meter_hot(hot: bool) -> void:
	if hot == _meter_hot or _meter == null:
		return
	_meter_hot = hot
	if _hot_tween and _hot_tween.is_valid():
		_hot_tween.kill()
	_hot_tween = null
	if not hot or not UIMotion.enabled():
		_meter.modulate = Color.WHITE
		return
	UIMotion.punch(_box, 1.06)
	_hot_tween = _meter.create_tween().set_loops()
	_hot_tween.tween_property(_meter, "modulate", Color(1.45, 1.25, 0.85), 0.42) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_hot_tween.tween_property(_meter, "modulate", Color.WHITE, 0.42) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# --- the streak and the combo ------------------------------------------------
#
# The damage streak and the kindness combo were a tag beside a payout number: visible for a
# second, in the world, wherever the last hit happened. This is the same fact on the card,
# with the one thing a tag cannot carry — a bar draining toward the moment the streak
# lapses. "Keep it going" is the genre's cheapest hook, and it needs a clock the player can
# see. The row ticks twenty times a second only while a streak or a combo is alive, and
# stops itself the moment neither is; it costs nothing while he sits there.

## The tag's own thresholds: a streak is worth calling one from the third hit.
const STREAK_FROM := 3
const COMBO_FROM := 1
## Bone-brown at a tap, orange by this many hits in a row — the same ramp the hit chips run.
const STREAK_HOT_AT := 20.0
const STREAK_HEAT := Color("ff8c1a")

var _streak_row: HBoxContainer
var _streak_cells: Dictionary = {}     ## currency -> {"cell", "value", "bar", "fill"}
var _streak_timer: Timer
var _streak_shown := 0
var _combo_shown := 0

func _build_streak_row() -> Control:
	_streak_row = HBoxContainer.new()
	_streak_row.name = "StreakRow"
	_streak_row.add_theme_constant_override("separation", 10)
	_streak_row.visible = false
	for currency in [Economy.BONES, Economy.HEARTS]:
		var colour := UIStyle.currency_colour(currency)
		var cell := HBoxContainer.new()
		cell.name = "StreakCell_%s" % currency
		cell.add_theme_constant_override("separation", 5)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.visible = false
		var value := UIStyle.label("x3", UIStyle.TITLE, colour)
		value.theme_type_variation = &"Numeral"
		value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_child(value)
		var side := VBoxContainer.new()
		side.add_theme_constant_override("separation", 2)
		side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_child(side)
		side.add_child(UIStyle.eyebrow("Streak" if currency == Economy.BONES else "Combo"))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.custom_minimum_size = Vector2(0, 6)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var fill := UIStyle.meter_fill(colour)
		bar.add_theme_stylebox_override("fill", fill)
		side.add_child(bar)
		_streak_row.add_child(cell)
		_streak_cells[currency] = {"cell": cell, "value": value, "bar": bar, "fill": fill}
	_streak_timer = Timer.new()
	_streak_timer.name = "StreakTimer"
	_streak_timer.wait_time = 0.05
	_streak_timer.timeout.connect(_tick_streak)
	add_child(_streak_timer)
	return _streak_row

## A payout that came from the player's own hands — automation is not a rhythm.
func _on_streak_payout(currency: StringName, _amount: float, _world_pos: Vector2, source_id: StringName) -> void:
	if source_id == &"automation" or source_id == &"" or _streak_timer == null:
		return
	if currency == Economy.BONES:
		var streak := Economy.damage_streak()
		if streak >= STREAK_FROM and streak != _streak_shown:
			var controls: Dictionary = _streak_cells[Economy.BONES]
			var record := streak >= 6 and streak >= int(Economy.stats.get("best_streak", 0))
			(controls["value"] as Label).text = "x%d" % streak
			var heat := clampf(float(streak) / STREAK_HOT_AT, 0.0, 1.0)
			var colour := UIStyle.BONES.lerp(STREAK_HEAT, heat)
			(controls["value"] as Label).add_theme_color_override("font_color", colour)
			(controls["fill"] as StyleBoxFlat).bg_color = colour
			(controls["cell"] as Control).visible = true
			UIMotion.punch(controls["value"], 1.2 + 0.2 * heat)
			if record:
				UIMotion.flash(controls["cell"], Color(1.6, 1.4, 0.9), 0.4)
			_streak_shown = streak
	elif currency == Economy.HEARTS and Economy.paying_kind_act:
		var combo := Economy.kindness_combo()
		if combo >= COMBO_FROM and combo != _combo_shown:
			var controls: Dictionary = _streak_cells[Economy.HEARTS]
			var b := ItemDB.balance
			var mult := EconomyMath.kindness_combo(combo, b.kindness_combo_step, b.kindness_combo_max)
			(controls["value"] as Label).text = "x%.1f" % mult
			(controls["cell"] as Control).visible = true
			UIMotion.punch(controls["value"], 1.15)
			_combo_shown = combo
	else:
		return
	if _streak_timer.is_stopped():
		_streak_timer.start()
	_tick_streak()

## Drains the bars, and puts the row away when both have run out.
func _tick_streak() -> void:
	var any := false
	var streak_left := Economy.streak_seconds_left()
	var bones: Dictionary = _streak_cells[Economy.BONES]
	if _streak_shown >= STREAK_FROM and streak_left > 0.0:
		(bones["bar"] as ProgressBar).value = clampf(streak_left / Economy.STREAK_WINDOW, 0.0, 1.0)
		any = true
	else:
		(bones["cell"] as Control).visible = false
		_streak_shown = 0
	var combo_left := Economy.combo_seconds_left()
	var hearts: Dictionary = _streak_cells[Economy.HEARTS]
	if _combo_shown >= COMBO_FROM and combo_left > 0.0:
		(hearts["bar"] as ProgressBar).value = clampf(combo_left / ItemDB.balance.kindness_combo_window, 0.0, 1.0)
		any = true
	else:
		(hearts["cell"] as Control).visible = false
		_combo_shown = 0
	_streak_row.visible = any
	if not any and _streak_timer:
		_streak_timer.stop()
