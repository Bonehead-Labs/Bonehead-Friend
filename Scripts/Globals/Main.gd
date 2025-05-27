extends Node

func _ready():
	var fullscreen_mode: bool = false
	if fullscreen_mode:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		get_window().borderless = true 
	else:
		set_display_to_logical_area()

func set_display_to_logical_area():
	
	var screen_id := DisplayServer.window_get_current_screen()
	# 2) Get the screen’s size in **physical pixels**
	var phys_size: Vector2i = DisplayServer.screen_get_size(screen_id)        #  [oai_citation:3‡rokojori.com](https://rokojori.com/en/labs/godot/docs/4.3/displayserver-class?utm_source=chatgpt.com)
	# 3) Convert back to **logical points** by dividing out the DPI scale
	var dpi_scale := DisplayServer.screen_get_scale(screen_id)               #  [oai_citation:4‡rokojori.com](https://rokojori.com/en/labs/godot/docs/4.3/displayserver-class?utm_source=chatgpt.com)
	var logical_size := phys_size / dpi_scale
	print("Phys Size: ",phys_size)
	print("dpi_scale: ", dpi_scale)
	print("logical_size: ", logical_size)

	# 4) Make sure we’re windowed (so the resize actually applies)…
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	# 5) …then resize the OS window to fill the logical screen
	DisplayServer.window_set_size(phys_size)
	DisplayServer.window_set_position(Vector2.ZERO)
