extends Node

## Versioned save file at user://save/slot_1.json.
##
## Writes are atomic (tmp -> rename) with the previous file kept as .bak, because a save
## corrupted by a crash mid-write costs a player their entire progress in a game designed
## to be played for weeks. See docs/architecture.md.
##
## This is the IO shell only. The schema, its defaults and its migrations live in
## SaveSchema, which is dependency-free so the headless test runner can reach it.

const SAVE_DIR := "user://save"
const SAVE_PATH := "user://save/slot_1.json"
const BACKUP_PATH := "user://save/slot_1.bak"
const TMP_PATH := "user://save/slot_1.json.tmp"

const AUTOSAVE_DELAY := 30.0

## Objects implementing `to_save() -> Dictionary` and `from_save(root: Dictionary) -> void`.
## Each returns a partial root dictionary which is merged in; keys must not collide.
var _providers: Array = []

var _autosave_timer: Timer
var _loaded_data: Dictionary = {}

func _ready() -> void:
	_autosave_timer = Timer.new()
	_autosave_timer.one_shot = true
	_autosave_timer.wait_time = AUTOSAVE_DELAY
	_autosave_timer.timeout.connect(save_game)
	add_child(_autosave_timer)

	EventBus.save_requested.connect(save_game)
	EventBus.currency_changed.connect(_on_currency_changed)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_CRASH:
		save_game()

# --- providers -------------------------------------------------------------

func register_provider(provider: Object) -> void:
	if not provider.has_method("to_save") or not provider.has_method("from_save"):
		push_error("SaveManager: provider %s lacks to_save/from_save" % provider)
		return
	if not _providers.has(provider):
		_providers.append(provider)

func unregister_provider(provider: Object) -> void:
	_providers.erase(provider)

# --- schema ----------------------------------------------------------------

# --- save / load -----------------------------------------------------------

func collect() -> Dictionary:
	var data := _loaded_data if not _loaded_data.is_empty() else SaveSchema.new_save()
	data = data.duplicate(true)
	data["version"] = SaveSchema.SAVE_VERSION
	data["saved_at_unix"] = _now()
	data["last_played_unix"] = _now()
	for p in _providers:
		var part: Dictionary = p.to_save()
		for k in part:
			data[k] = part[k]
	return data

func save_game() -> bool:
	_autosave_timer.stop()
	var data := collect()

	if DirAccess.make_dir_recursive_absolute(SAVE_DIR) != OK and not DirAccess.dir_exists_absolute(SAVE_DIR):
		push_error("SaveManager: cannot create %s" % SAVE_DIR)
		return false

	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: cannot open %s (error %d)" % [TMP_PATH, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

	# Keep the previous good file as .bak before replacing it.
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.copy_absolute(SAVE_PATH, BACKUP_PATH)

	var err := DirAccess.rename_absolute(TMP_PATH, SAVE_PATH)
	if err != OK:
		push_error("SaveManager: failed to commit save (error %d)" % err)
		return false

	_loaded_data = data
	return true

func load_game() -> Dictionary:
	var data := _read_json(SAVE_PATH)
	if data.is_empty():
		# Primary unreadable or corrupt — fall back to the last known good file.
		data = _read_json(BACKUP_PATH)
		if not data.is_empty():
			push_warning("SaveManager: primary save unreadable; recovered from %s" % BACKUP_PATH)
	if data.is_empty():
		data = SaveSchema.new_save()
	else:
		data = SaveSchema.migrate(data)

	_loaded_data = data
	for p in _providers:
		p.from_save(data)
	return data

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(BACKUP_PATH)

# --- internals -------------------------------------------------------------

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveManager: %s is not valid save JSON" % path)
		return {}
	return parsed

func _on_currency_changed(_currency: StringName, _balance: float) -> void:
	request_autosave()

## Debounced — a busy minute of play produces one write, not hundreds.
func request_autosave() -> void:
	if _autosave_timer and _autosave_timer.is_stopped():
		_autosave_timer.start()

func _now() -> int:
	return int(Time.get_unix_time_from_system())
