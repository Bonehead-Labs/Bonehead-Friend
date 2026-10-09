extends Control
## The Bonehead Labs studio splash: the boneheadlabs.org wordmark, brought to life.
##
## Self-contained (no autoloads, no project settings, no host classes): drop the
## [code]addons/bonehead_labs_splash/[/code] folder into any Godot 4.x project. See README.md.
##
## Beat sheet (seconds; [member reduce_flashing] only lengthens the closing fade):
##   0.00  the boot frame: paper, glows, the mascot standing on its shadow (art/../boot)
##   0.22  the site's jump (0.75 s): squash, leap with the happy face, land
##   0.70  "Bone" and "head" pop out of the mascot letter by letter (spring), "k-tok" at 0.76
##   1.18  the teal "Labs" pill springs on (pop)
##   1.05+ the idle vibe sways in; blinks at 1.95 and 3.05 (double)
##   1.45  the subtitle tracks in (Spline Sans Mono)
##   1.62  music notes float off both cups (marimba), again at 2.34
##   3.55  exit: the stage lifts away, the paper closes to [member exit_color]
##   4.25  [signal finished], then the next scene (4.65 with reduce_flashing)
##
## Smooth and resolution independent: no pixel snapping, no shaders, linear filtering with
## mipmaps, fonts re-rasterised at the screen's scale. The composition is laid out on a
## 1920 x 1080 design canvas and scaled to fit any size or aspect.
##
## [method evaluate] is a pure function of time, so any instant can be posed and captured.

## Emitted once when the splash has played out (or was skipped and its exit has run), just
## before it changes to the next scene.
signal finished

const Ease := preload("src/splash_ease.gd")
const MascotScript := preload("src/mascot.gd")
const WordScript := preload("src/brand_word.gd")
const PillScript := preload("src/labs_pill.gd")
const FieldScript := preload("src/splash_field.gd")
const WORDMARK_FONT: Font = preload("fonts/fraunces_wordmark.tres")
const SUBTITLE_FONT: Font = preload("fonts/spline_sans_mono.tres")
const NOTE_TEXTURES: Array[Texture2D] = [preload("art/note_eighth.svg"), preload("art/note_beamed.svg")]
const SFX_LAND: AudioStream = preload("audio/splash_land.wav")
const SFX_POP: AudioStream = preload("audio/splash_pop.wav")
const SFX_NOTES: AudioStream = preload("audio/splash_notes.wav")

# The site's palette.
const INK := Color("#071b1e")
const INK_2 := Color("#1d3336")
const PAPER := Color("#f4ede0")
const CREAM := Color("#fffcf4")
const TEAL := Color("#11abac")
const TEAL_INK := Color("#0a6c6e")
const BRASS := Color("#f0a51c")

## The scene to open when the splash finishes (a path). [member next_scene_packed] wins if set.
## Leave both empty to handle [signal finished] yourself.
@export_file("*.tscn", "*.scn") var next_scene: String = ""
## The scene to open when the splash finishes (a PackedScene). Wins over [member next_scene].
@export var next_scene_packed: PackedScene = null
## Any key, mouse button, touch or pad button skips to the exit (a second press ends it).
@export var skippable: bool = true
## The splash never flashes. With this on, its one large brightness change (the closing fade to
## [member exit_color]) runs slower.
@export var reduce_flashing: bool = false
## The bus for the splash's three short cues. A bus missing from the project falls back to Master.
@export var audio_bus: StringName = &"Master"
## Cue level on top of the bus.
@export_range(-40.0, 6.0, 0.5) var volume_db: float = 0.0
## The small line under the wordmark. Empty hides it.
@export var subtitle_text: String = "GAME AND SOFTWARE STUDIO"
## The colour the paper closes to before the hand-off.
@export var exit_color: Color = INK
## The user argument (after "--" on the command line) that skips the splash entirely.
@export var skip_argument: String = "--skip-splash"
## Plays on its own clock from _ready. Off for tools that pose it with [method evaluate].
@export var autoplay: bool = true

# ── Beat sheet ────────────────────────────────────────────────────────────────────────
const JUMP_START: float = 0.22
const JUMP_DURATION: float = 0.75
const HAPPY_START: float = 0.26
const HAPPY_END: float = 1.22
const WORDS_IN: float = 0.70
const GLYPH_STAGGER: float = 0.045
const GLYPH_DURATION: float = 0.55
const PILL_IN: float = 1.18
const PILL_DURATION: float = 0.6
const VIBE_START: float = 1.05
const SUBTITLE_IN: float = 1.45
const SUBTITLE_STAGGER: float = 0.016
const SUBTITLE_DURATION: float = 0.32
const BLINKS: Array[float] = [1.95, 3.05, 3.27]
const BLINK_DURATION: float = 0.14
## [start, side (-1 left cup, 1 right cup), texture, drift px, rotation sign].
const NOTES: Array = [
	[1.62, -1, 0, -40.0], [1.64, 1, 1, 34.0], [2.34, -1, 1, -26.0], [2.36, 1, 0, 48.0],
]
const NOTE_LIFE: float = 1.5
## [time, stream index, pitch]: land, pop, notes, notes a fourth up.
const CUES: Array = [[0.76, 0, 1.0], [1.18, 1, 1.0], [1.62, 2, 1.0], [2.34, 2, 1.335]]
const EXIT_START: float = 3.55
const STAGE_OUT: float = 0.34
const CURTAIN_DELAY: float = 0.16
const CURTAIN_DURATION: float = 0.5
const CURTAIN_DURATION_GENTLE: float = 0.9
const EXIT_HOLD: float = 0.04
## Until then the text is drawn at rest but nearly transparent (well under one 8-bit level), so
## its glyphs are rasterised at the screen's scale before they pop, not on the beat.
const PREWARM_END: float = 0.12
const PREWARM_ALPHA: float = 0.002

# ── Composition, in design px on the 1920 x 1080 canvas (origin: baseline centre) ─────
const DESIGN_SIZE := Vector2(1920.0, 1080.0)
const WORD_FONT_SIZE: int = 270
const WORD_TRACKING_EM: float = -0.05
const WORD_OUTLINE_PX: float = 9.0
const WORD_LIFT := Vector2(9.0, 10.0)
## The mascot's figure height in design px, and its feet below the baseline.
const MASCOT_HEIGHT: float = 400.0
const FEET_DROP: float = 62.0
## Words start this far either side of the mascot's centre line.
const WORD_GAP: float = 134.0
const PILL_SIZE := Vector2(176.0, 86.0)
const PILL_FONT_SIZE: int = 58
const PILL_BORDER: float = 4.0
const PILL_LIFT := Vector2(6.0, 6.0)
const PILL_REST_DEG: float = -4.0
const SUBTITLE_FONT_SIZE: int = 26
const SUBTITLE_TRACKING_EM: float = 0.32
const SUBTITLE_BASELINE: float = 205.0
const NOTE_HEIGHT: float = 66.0
const NOTE_RISE: float = 150.0

var _field: FieldScript = null
var _stage: Control = null
var _comp: Node2D = null
var _mascot: MascotScript = null
var _bone: WordScript = null
var _head: WordScript = null
var _pill: PillScript = null
var _subtitle: WordScript = null
var _notes: Array[Sprite2D] = []
var _curtain: ColorRect = null
var _players: Array[AudioStreamPlayer] = []

var _time: float = 0.0
var _exit_start: float = EXIT_START
var _next_cue: int = 0
var _skipped: bool = false
var _finished: bool = false
var _u: float = 1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Not pixel art: smooth sampling with mipmaps for everything under this node.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_build()
	resized.connect(_layout)
	_layout()
	evaluate(0.0)
	if not skip_argument.is_empty() and OS.get_cmdline_user_args().has(skip_argument):
		_finish.call_deferred()
		return
	set_process(autoplay)


func _exit_tree() -> void:
	# Cleanup only: silence any cue still ringing.
	for player: AudioStreamPlayer in _players:
		if is_instance_valid(player):
			player.stop()


func _build() -> void:
	_field = FieldScript.new()
	_field.name = "Field"
	add_child(_field)
	_field.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_stage = Control.new()
	_stage.name = "Stage"
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_comp = Node2D.new()
	_comp.name = "Composition"
	_stage.add_child(_comp)

	_bone = _make_word("Bone")
	_head = _make_word("head")
	_mascot = MascotScript.new()
	_comp.add_child(_mascot)
	_mascot.position = Vector2(0.0, FEET_DROP)
	var k: float = MASCOT_HEIGHT / maxf(_mascot.figure_height(), 1.0)
	_mascot.scale = Vector2(k, k)

	_pill = PillScript.new()
	_pill.name = "LabsPill"
	_pill.font = WORDMARK_FONT
	_pill.font_size = PILL_FONT_SIZE
	_pill.pill_size = PILL_SIZE
	_pill.border_px = PILL_BORDER
	_pill.lift = PILL_LIFT
	_pill.teal = TEAL
	_pill.ink = INK
	_comp.add_child(_pill)

	_subtitle = WordScript.new()
	_subtitle.name = "Subtitle"
	_subtitle.font = SUBTITLE_FONT
	_subtitle.font_size = SUBTITLE_FONT_SIZE
	_subtitle.tracking_em = SUBTITLE_TRACKING_EM
	_subtitle.fill_color = INK_2
	_subtitle.text = subtitle_text
	_comp.add_child(_subtitle)

	for i in range(NOTES.size()):
		var note := Sprite2D.new()
		note.name = "Note%d" % i
		note.texture = NOTE_TEXTURES[int(NOTES[i][2]) % NOTE_TEXTURES.size()]
		note.modulate = TEAL_INK
		note.visible = false
		_comp.add_child(note)
		_notes.append(note)

	_curtain = ColorRect.new()
	_curtain.name = "Curtain"
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curtain.color = Color(exit_color, 0.0)
	add_child(_curtain)
	_curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bus: StringName = audio_bus if AudioServer.get_bus_index(audio_bus) >= 0 else &"Master"
	for stream: AudioStream in [SFX_LAND, SFX_POP, SFX_NOTES]:
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.bus = bus
		player.volume_db = volume_db
		add_child(player)
		_players.append(player)


func _make_word(word: String) -> WordScript:
	var node: WordScript = WordScript.new()
	node.name = word.capitalize()
	node.font = WORDMARK_FONT
	node.font_size = WORD_FONT_SIZE
	node.tracking_em = WORD_TRACKING_EM
	node.fill_color = CREAM
	node.ink_color = INK
	node.outline_px = WORD_OUTLINE_PX
	node.lift = WORD_LIFT
	node.text = word
	_comp.add_child(node)
	return node


## Fits the 1920 x 1080 composition to the current size (any aspect) and centres it.
func _layout() -> void:
	if not is_instance_valid(_comp):
		return
	var area: Vector2 = size
	if area.x <= 0.0 or area.y <= 0.0:
		area = DESIGN_SIZE
	_u = maxf(minf(area.x / DESIGN_SIZE.x, area.y / DESIGN_SIZE.y), 0.01)
	var top: float = FEET_DROP - MASCOT_HEIGHT
	var bottom: float = SUBTITLE_BASELINE + 8.0 if not subtitle_text.is_empty() else FEET_DROP + 20.0
	var origin := Vector2(area.x * 0.5, area.y * 0.5 - (top + bottom) * 0.5 * _u)
	_comp.position = origin
	_comp.scale = Vector2(_u, _u)
	_stage.pivot_offset = area * 0.5

	_bone.position = Vector2(-WORD_GAP - _bone.word_width(), 0.0)
	_head.position = Vector2(WORD_GAP, 0.0)
	var cap: float = WORD_FONT_SIZE * 0.72
	_pill.position = Vector2(WORD_GAP + _head.word_width() - 0.39 * cap, -0.1 * cap)
	_subtitle.position = Vector2(-_subtitle.word_width() * 0.5, SUBTITLE_BASELINE)

	_field.dot_anchor = origin
	_field.dot_spacing = 48.0 * _u
	_field.dot_radius = maxf(2.0 * _u, 0.9)
	_field.glows = [
		[origin + Vector2(0.0, -150.0) * _u, Vector2(760.0, 520.0) * _u, Color(TEAL, 0.3)],
		[origin + Vector2(-560.0, 170.0) * _u, Vector2(460.0, 320.0) * _u, Color(BRASS, 0.3)],
	]
	_field.queue_redraw()


func _process(delta: float) -> void:
	if _finished:
		return
	var before: float = _time
	_time += Ease.step(delta)
	_fire_cues(before, _time)
	evaluate(_time)
	if _time >= _exit_end():
		_finish()


func _input(event: InputEvent) -> void:
	if _finished or not skippable or not is_processing():
		return
	var pressed: bool = (
		(event is InputEventKey and event.pressed and not event.echo)
		or (event is InputEventMouseButton and event.pressed)
		or (event is InputEventJoypadButton and event.pressed)
		or (event is InputEventScreenTouch and event.pressed)
	)
	if not pressed:
		return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
	skip()


## Skips to the exit (the stage lifts away and the paper closes); during the exit, ends it.
func skip() -> void:
	if _finished:
		return
	if _time >= _exit_start:
		_finish()
		return
	_skipped = true
	_exit_start = _time
	_next_cue = CUES.size()
	evaluate(_time)


func _exit_end() -> float:
	return _exit_start + CURTAIN_DELAY + _curtain_duration() + EXIT_HOLD


func _curtain_duration() -> float:
	return CURTAIN_DURATION_GENTLE if reduce_flashing else CURTAIN_DURATION


## Total running time when nothing is skipped.
func get_duration() -> float:
	return EXIT_START + CURTAIN_DELAY + _curtain_duration() + EXIT_HOLD


func _fire_cues(before: float, now: float) -> void:
	while _next_cue < CUES.size() and float(CUES[_next_cue][0]) <= now:
		var cue: Array = CUES[_next_cue]
		_next_cue += 1
		if float(cue[0]) < before - 0.25:
			continue  # long stall: drop a stale cue rather than play it late
		var player: AudioStreamPlayer = _players[int(cue[1])] if int(cue[1]) < _players.size() else null
		if is_instance_valid(player) and player.stream != null:
			player.pitch_scale = float(cue[2])
			player.play()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	set_process(false)
	evaluate(maxf(_time, _exit_end()))
	finished.emit()
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	var error: Error = OK
	if next_scene_packed != null:
		error = tree.change_scene_to_packed(next_scene_packed)
	elif not next_scene.is_empty():
		error = tree.change_scene_to_file(next_scene)
	if error != OK:
		push_error("[BoneheadLabsSplash] could not open the next scene (%s): %s" % [next_scene, error_string(error)])


# ── The sequence ──────────────────────────────────────────────────────────────────────

## Poses every element for time [param t] (seconds). No frame-to-frame state.
func evaluate(t: float) -> void:
	if not is_instance_valid(_mascot):
		return
	var exit_start: float = _exit_start
	# Before the exit the timeline plays as authored; a skip freezes it where it was.
	var tl: float = minf(t, exit_start)

	var jump: float = Ease.seg(tl, JUMP_START, JUMP_DURATION)
	var happy: bool = tl >= HAPPY_START and tl < HAPPY_END
	var vibe_w: float = Ease.out(Ease.seg(tl, VIBE_START, 0.6))
	var blink: float = 0.0
	for b: float in BLINKS:
		var p: float = Ease.seg(tl, b, BLINK_DURATION)
		if p > 0.0 and p < 1.0:
			blink = maxf(blink, clampf(minf(p / 0.35, (1.0 - p) / 0.35), 0.0, 1.0))
	_mascot.pose(jump, maxf(tl - VIBE_START, 0.0), vibe_w, blink, happy)

	_pose_word(_bone, tl, -1)
	_pose_word(_head, tl, 1)
	_pose_pill(tl)
	_pose_subtitle(tl)
	_pose_notes(tl)
	_pose_exit(t, exit_start)


## Glyphs pop out of the mascot nearest first, sliding outward on the site's spring.
func _pose_word(word: WordScript, t: float, side: int) -> void:
	var n: int = word.glyph_count()
	for i in range(n):
		var rank: int = (n - 1 - i) if side < 0 else i
		var p: float = Ease.seg(t, WORDS_IN + rank * GLYPH_STAGGER, GLYPH_DURATION)
		var s: float = Ease.spring(p)
		var settle: float = 1.0 - Ease.out(p)
		var centre: Vector2 = word.position + word.glyph_centre(i)
		if p <= 0.0 and t < PREWARM_END:
			# Drawn at rest but invisible, so the big glyphs are rasterised now, not on the beat.
			word.glyph_scale[i] = Vector2.ONE
			word.glyph_offset[i] = Vector2.ZERO
			word.glyph_rotation[i] = 0.0
			word.glyph_alpha[i] = PREWARM_ALPHA
			continue
		word.glyph_scale[i] = Vector2(s, s)
		word.glyph_offset[i] = Vector2(-centre.x * 0.45 * settle, 60.0 * settle)
		word.glyph_rotation[i] = deg_to_rad(14.0) * float(side) * settle
		word.glyph_alpha[i] = 1.0 if p > 0.0 else 0.0
	word.queue_redraw()


func _pose_pill(t: float) -> void:
	var p: float = Ease.seg(t, PILL_IN, PILL_DURATION)
	var warm: bool = p <= 0.0 and t < PREWARM_END
	_pill.visible = p > 0.0 or warm
	_pill.modulate.a = PREWARM_ALPHA if warm else 1.0
	var s: float = 1.0 if warm else Ease.spring(p)
	_pill.scale = Vector2(s, s)
	_pill.rotation = deg_to_rad(PILL_REST_DEG - 20.0 * (1.0 - Ease.out(p)))


func _pose_subtitle(t: float) -> void:
	var n: int = _subtitle.glyph_count()
	_subtitle.visible = n > 0
	for i in range(n):
		var p: float = Ease.seg(t, SUBTITLE_IN + i * SUBTITLE_STAGGER, SUBTITLE_DURATION)
		var e: float = Ease.out(p)
		_subtitle.glyph_alpha[i] = PREWARM_ALPHA if (p <= 0.0 and t < PREWARM_END) else e
		_subtitle.glyph_offset[i] = Vector2(0.0, 10.0 * (1.0 - e))
	_subtitle.queue_redraw()


## Notes leave the cups' outer edges, rise, drift and turn (-12 to 14 deg), and fade.
func _pose_notes(t: float) -> void:
	var k: float = _mascot.scale.x
	for i in range(_notes.size()):
		var note: Sprite2D = _notes[i]
		var spec: Array = NOTES[i]
		var p: float = (t - float(spec[0])) / NOTE_LIFE
		if p <= 0.0 or p >= 1.0:
			note.visible = false
			continue
		note.visible = true
		var side: int = int(spec[1])
		var cup: Vector2 = _mascot.position + _mascot.cup_local(side) * k
		var start: Vector2 = cup + Vector2(36.0 * side, -24.0)
		var rise: float = Ease.out(p)
		note.position = start + Vector2(float(spec[3]) * rise, -NOTE_RISE * rise)
		note.rotation = deg_to_rad(lerpf(-12.0, 14.0, p))
		var tex_h: float = float(note.texture.get_height()) if note.texture != null else NOTE_HEIGHT
		var grow: float = lerpf(0.55, 1.0, Ease.out(clampf(p / 0.25, 0.0, 1.0)))
		note.scale = Vector2.ONE * (NOTE_HEIGHT / maxf(tex_h, 1.0)) * grow
		var fade_in: float = clampf(p / 0.12, 0.0, 1.0)
		var fade_out: float = 1.0 - clampf((p - 0.55) / 0.45, 0.0, 1.0)
		note.modulate = Color(TEAL_INK, minf(fade_in, fade_out))


func _pose_exit(t: float, exit_start: float) -> void:
	var lift: float = Ease.in_cubic(Ease.seg(t, exit_start, STAGE_OUT))
	_stage.modulate = Color(1.0, 1.0, 1.0, 1.0 - lift)
	_stage.scale = Vector2.ONE * (1.0 - 0.03 * lift)
	# A sine ease: the gentlest S-curve (peak slope pi/2), so the one big brightness change never
	# jumps more than about 4% of the screen's brightness in a 60 Hz frame (2.5% when gentle).
	var close: float = Ease.in_out_sine(Ease.seg(t, exit_start + CURTAIN_DELAY, _curtain_duration()))
	_curtain.color = Color(exit_color, close)


# ── Test and tool reads ───────────────────────────────────────────────────────────────

func get_state() -> Dictionary:
	var shaders: int = 0
	var viewports: int = 0
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is CanvasItem and (node as CanvasItem).material != null:
			shaders += 1
		if node is SubViewport or node is SubViewportContainer:
			viewports += 1
		stack.append_array(node.get_children())
	return {
		"time": _time,
		"skipped": _skipped,
		"finished": _finished,
		"exit_start": _exit_start,
		"duration": get_duration(),
		"stage_alpha": _stage.modulate.a,
		"curtain_alpha": _curtain.color.a,
		"layout_scale": _u,
		"texture_filter": texture_filter,
		"materials": shaders,
		"viewports": viewports,
		"mascot": _mascot.get_state(),
		"pill_scale": _pill.scale.x,
		"notes_visible": _notes.filter(func(n: Sprite2D) -> bool: return n.visible).size(),
		"audio_bus": _players[0].bus if not _players.is_empty() else &"",
		"next_cue": _next_cue,
	}


## The composition's parts in this control's local px at rest: mascot figure, the two words, the
## pill and the subtitle (for layout tests at any size).
func get_layout_rects() -> Dictionary:
	var xf: Transform2D = _comp.transform
	var cap: float = WORD_FONT_SIZE * 0.72
	var fig: Rect2 = _mascot.figure_box_local()
	var k: float = _mascot.scale.x
	var mascot_rect := Rect2(_mascot.position + fig.position * k, fig.size * k)
	var bone := Rect2(_bone.position + Vector2(0.0, -cap), Vector2(_bone.word_width(), cap))
	var head := Rect2(_head.position + Vector2(0.0, -cap), Vector2(_head.word_width(), cap))
	var pill := Rect2(_pill.position - PILL_SIZE * 0.5, PILL_SIZE)
	var sub := Rect2(_subtitle.position + Vector2(0.0, -SUBTITLE_FONT_SIZE), Vector2(_subtitle.word_width(), SUBTITLE_FONT_SIZE))
	return {
		"mascot": xf * mascot_rect,
		"bone": xf * bone,
		"head": xf * head,
		"pill": xf * pill,
		"subtitle": xf * sub,
	}
