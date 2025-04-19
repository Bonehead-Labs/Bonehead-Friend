extends Node

func _ready():
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

    var current_screen := DisplayServer.window_get_current_screen()
    print("Maximized on screen:", current_screen)