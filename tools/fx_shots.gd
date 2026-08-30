extends CaptureWindow

## A contact sheet of the payout numbers, at every magnitude and in both economies.
##
##   Godot --fixed-fps 60 --path <project> res://tools/fx_shots.tscn
##
## `--fixed-fps` for the same reason `ui_motion_shots` needs it: without it each frame's
## delta is however long the previous PNG took to write, and the punch-in reads as a jump.
##
## This exists because a payout number cannot be reviewed from source. Its whole job is to
## be satisfying, and the only way to know whether it is, is to look at it.

const SIZE := Vector2i(1020, 720)
const OUT := "user://fx_shots"

var _main: Node
var _frame := 0

func _ready() -> void:
	_use_capture_slot()
	DirAccess.make_dir_recursive_absolute(OUT)
	Settings.focus_intensity = Settings.Intensity.NORMAL
	Settings.hud_pinned = false
	Settings.tabs_pinned = false
	_install_backdrop()

	_main = load("res://main.tscn").instantiate()
	add_child(_main)
	await _idle(20)
	_show_window(SIZE, "fx capture")
	await _idle(20)

	var fx := _find(_main, "FXLayer")
	if fx == null:
		push_error("fx_shots: no FXLayer")
		get_tree().quit(1)
		return

	# One row per tier, Bones on the left and Hearts on the right, so the two economies can
	# be told apart at a glance — which is the whole point of the change.
	var amounts := [4.0, 42.0, 480.0, 7300.0, 1_450_000.0]
	for i in amounts.size():
		var y := 90.0 + float(i) * 118.0
		EventBus.payout.emit(&"bones", amounts[i], Vector2(300, y))
		EventBus.payout.emit(&"hearts", amounts[i], Vector2(720, y))
		await _idle(3)
	# Caught mid-flight: at rest they have already faded, and the punch is the part worth
	# looking at.
	await _idle(10)
	_grab().save_png("%s/tiers.png" % OUT)
	await _idle(24)
	_grab().save_png("%s/tiers-late.png" % OUT)

	print("fx_shots: wrote %s" % ProjectSettings.globalize_path(OUT))
	get_tree().quit()
