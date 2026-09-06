class_name TuningLog
extends Node

## Writes every payout and purchase to a CSV, in debug builds only.
##
## `docs/economy.md` says to retune against real playtest data rather than intuition, and
## the M3 gate is a 30-minute session with no dead ends — a claim nobody can check from
## memory. This is the instrument that makes it checkable: open the CSV, look for the gap
## where nothing was affordable for eight minutes, and fix that tier.
##
## **Debug builds only.** A shipped game writing a row per hit to disk for eight hours is a
## performance bug and a privacy smell; `main.gd` does not create this in a release build.

const LOG_DIR := "user://logs"

## Rows are buffered and flushed on a timer. A file write per hit would be the single most
## expensive thing in a game with a 3% CPU budget, and would land in the middle of the
## physics step at that.
const FLUSH_SECONDS := 5.0
## Hard ceiling in case a flush cannot happen — a runaway buffer must not become the
## memory leak the log was supposed to help find.
const MAX_BUFFERED := 4096

var _rows: PackedStringArray = []
var _path := ""
var _since_flush := 0.0
var _started_msec := 0

func _ready() -> void:
	_started_msec = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	# Named by wall-clock start so a playtest afternoon leaves one file per session rather
	# than one file that each session overwrites.
	_path = "%s/session_%s.csv" % [LOG_DIR,
		Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")]
	_write_header()

	EventBus.payout.connect(_on_payout)
	EventBus.item_purchased.connect(_on_item_purchased)
	EventBus.augment_purchased.connect(_on_augment_purchased)
	EventBus.knockout_payout.connect(_on_knockout)
	EventBus.mastery_rank_up.connect(_on_rank_up)
	EventBus.prestige_performed.connect(_on_prestige)

func _process(delta: float) -> void:
	_since_flush += delta
	if _since_flush >= FLUSH_SECONDS:
		flush()

## Flushed on the way out too, or the last few minutes of a session — usually the
## interesting ones — are the ones that never reach disk.
func _exit_tree() -> void:
	flush()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_CRASH:
		flush()

# --- events ----------------------------------------------------------------

func _on_payout(currency: StringName, amount: float, _world_pos: Vector2, source_id: StringName) -> void:
	_row("payout", String(currency), amount, String(source_id))

func _on_item_purchased(item_id: StringName) -> void:
	var item := ItemDB.get_item(item_id)
	_row("buy_item", String(item.currency_id()) if item else "",
		float(item.cost) if item else 0.0, String(item_id))

func _on_augment_purchased(node_id: StringName, level: int) -> void:
	var node := ItemDB.get_augment(node_id)
	_row("buy_augment", String(node.currency_id()) if node else "", float(level), String(node_id))

func _on_knockout(total: float) -> void:
	_row("knockout", "bones", total, "")

func _on_rank_up(item_id: StringName, rank: int) -> void:
	_row("mastery", "", float(rank), String(item_id))

func _on_prestige(gained: float) -> void:
	_row("prestige", "marrow", gained, Economy.personality)

# --- writing ---------------------------------------------------------------

## Every row carries the full economic context, not just the amount. "He earned 4 Bones" is
## unanalysable; "he earned 4 Bones at mood -80 with 0.4 grime, 200 seconds in" is the row
## that tells you which multiplier is mistuned.
func _row(event: String, currency: String, amount: float, source: String) -> void:
	if _rows.size() >= MAX_BUFFERED:
		flush()
	_rows.append("%.2f,%s,%s,%.4f,%s,%.1f,%.3f,%.2f,%.2f,%.2f,%d" % [
		float(Time.get_ticks_msec() - _started_msec) / 1000.0,
		event, currency, amount, source,
		Economy.mood, Economy.grime,
		Economy.balance_of(Economy.BONES), Economy.balance_of(Economy.HEARTS),
		Economy.mood_multiplier(), Economy.marrow,
	])

func flush() -> void:
	_since_flush = 0.0
	if _rows.is_empty():
		return
	# Reopened per flush rather than held open, so a crash still leaves every flushed row on
	# disk — a log that only survives a clean exit is no use for diagnosing a crash.
	var file := FileAccess.open(_path, FileAccess.READ_WRITE)
	if file == null:
		push_warning("TuningLog: cannot append to %s" % _path)
		_rows.clear()
		return
	file.seek_end()
	for row in _rows:
		file.store_line(row)
	file.close()
	_rows.clear()

func _write_header() -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		push_warning("TuningLog: cannot create %s" % _path)
		return
	file.store_line("t_sec,event,currency,amount,source,mood,grime,bones,hearts,mood_mult,marrow")
	file.close()
