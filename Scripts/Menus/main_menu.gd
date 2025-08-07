extends Control

var menu_open: bool = false

func _ready() -> void:
	visible = false
	set_process_input(true)  # Always enable input processing
	process_mode = Node.PROCESS_MODE_ALWAYS  # Keep processing even when tree is paused

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):  # Escape key
		toggle_menu()

func toggle_menu() -> void:
	if menu_open:
		resume()
	else:
		pause()

func pause() -> void:
	get_tree().paused = true
	visible = true
	menu_open = true

func resume() -> void:
	get_tree().paused = false
	visible = false
	menu_open = false

func _on_resume_pressed() -> void:
	resume()



func _on_exit_pressed() -> void:
	resume()
	get_tree().quit()	