class_name PanelPage
extends VBoxContainer

## The base every page of the card extends. It exists for one rule that each page was
## previously expected to remember on its own, and which every page got wrong:
##
## **A page that is not on screen does no work.**
##
## The bus is loud. `currency_changed` fires on every hit — up to ~7/s per damage source at
## `damage_cooldown = 0.15` — and again once a second per currency from automation, forever.
## `contract_event` fires per hit as well. A page that rebuilds three rows of themed buttons
## on each of those, with the card shut, is a permanent background cost in a game whose whole
## pitch is that it idles under your work at under 3% CPU.
##
## The guard cannot be `if visible:` — that was the original bug. A page's own `visible` flag
## is written only when the card switches pages, so the page the player last had open stays
## flagged visible under a closed card and the guard passes forever. `is_visible_in_tree()`
## is the question that was actually meant.
##
## Skipped work is remembered, not lost: `_dirty` is set, and the page catches up the moment
## it is shown. Pages call `request_refresh()` / `request_rebuild()` from bus handlers and
## implement `_refresh()` / `_rebuild()`.

var _dirty_refresh := false
var _dirty_rebuild := false

## For a page whose contents can change with no signal to listen for — the settings page,
## whose values the F3 developer hotkeys write directly. It re-reads on every open rather
## than trusting what it drew last.
var refresh_on_show := false

## Counters the shell suite asserts against — cheap enough to leave in, and the only way to
## state "closed pages do no work" as a test rather than as a comment.
var refresh_count := 0
var rebuild_count := 0

func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)
	_build_page()
	# A page is built hidden and catches up when it is first shown, so boot does not pay for
	# five pages the player has not asked for.
	_dirty_rebuild = true
	if is_visible_in_tree():
		_catch_up()

## Pages override these three. `_build_page` runs once and creates the controls;
## `_rebuild` re-creates the variable contents; `_refresh` only repaints them.
func _build_page() -> void:
	pass

func _rebuild() -> void:
	pass

func _refresh() -> void:
	pass

## Coalesced to one repaint a frame. `currency_changed` fires on every hit and every pet, and
## a page repainting fourteen times a second is fourteen repaints of the same numbers;
## deferring lets every request this frame land in one `_refresh()`.
var _refresh_queued := false

func request_refresh() -> void:
	if not is_visible_in_tree():
		_dirty_refresh = true
		return
	if _refresh_queued:
		return
	_refresh_queued = true
	_flush_refresh.call_deferred()

func _flush_refresh() -> void:
	_refresh_queued = false
	if not is_visible_in_tree():
		_dirty_refresh = true
		return
	refresh_count += 1
	_refresh()

func request_rebuild() -> void:
	if not is_visible_in_tree():
		_dirty_rebuild = true
		return
	rebuild_count += 1
	_rebuild()

## True when the page is carrying work it deferred. The shell suite reads it; so does
## anything that wants to know whether a closed page is up to date.
func is_dirty() -> bool:
	return _dirty_refresh or _dirty_rebuild

func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_catch_up()
	else:
		_on_page_hidden()

## A rebuild is not a substitute for a repaint. Pages that create their controls empty and
## fill them in `_refresh()` — and pages with no `_rebuild()` at all, which is most of them —
## came up **blank** when a rebuild swallowed the refresh: the Rebirth page showed two empty
## boxes and Settings showed a column of em-dashes. Coming into view always repaints.
func _catch_up() -> void:
	if refresh_on_show:
		_dirty_refresh = true
	var wanted_rebuild := _dirty_rebuild
	var wanted_refresh := _dirty_refresh or _dirty_rebuild
	_dirty_rebuild = false
	_dirty_refresh = false
	if wanted_rebuild:
		rebuild_count += 1
		_rebuild()
	if wanted_refresh:
		refresh_count += 1
		_refresh()

## Pages that hold a transient mode — an armed confirm, a pending selection — drop it here.
func _on_page_hidden() -> void:
	pass
