extends Node

func _ready():
    var current_screen := DisplayServer.window_get_current_screen()
    var screen_size := DisplayServer.screen_get_size(current_screen)
    var screen_position := DisplayServer.screen_get_position(current_screen)

    # Keep the window border
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
    
    # Set size and position to match screen
    DisplayServer.window_set_size(screen_size)
    DisplayServer.window_set_position(screen_position)

    print("Current screen:", current_screen)
    print("Screen size:", screen_size)
    print("Screen position:", screen_position)
