extends Node

enum WindowMode {
	WINDOWED,
	MAXIMIZED,
	FULLSCREEN,
	FIT_SCREEN
}

enum ScreenType {
	REGULAR_16_9,
	ULTRAWIDE,
	MAC_RETINA,
	UNKNOWN
}

var current_os: String
var current_screen_type: ScreenType
var primary_screen_id: int

func _ready():
	detect_system_info()
	setup_transparent_window()

func detect_system_info():
	# Detect operating system
	current_os = OS.get_name()
	print("Detected OS: ", current_os)
	
	# Get primary screen
	primary_screen_id = DisplayServer.window_get_current_screen()
	
	# Detect screen type
	current_screen_type = detect_screen_type()
	print("Detected screen type: ", ScreenType.keys()[current_screen_type])

func detect_screen_type() -> ScreenType:
	var screen_size = DisplayServer.screen_get_size(primary_screen_id)
	var aspect_ratio = float(screen_size.x) / float(screen_size.y)
	var dpi_scale = DisplayServer.screen_get_scale(primary_screen_id)
	
	print("Screen size: ", screen_size)
	print("Aspect ratio: ", aspect_ratio)
	print("DPI scale: ", dpi_scale)
	
	# Check for Mac Retina (high DPI scale)
	if current_os == "macOS" and dpi_scale > 1.5:
		return ScreenType.MAC_RETINA
	
	# Check for ultrawide (aspect ratio > 2.0 or common ultrawide ratios)
	if aspect_ratio >= 2.0 or is_ultrawide_ratio(aspect_ratio):
		return ScreenType.ULTRAWIDE
	
	# Check for regular 16:9 (aspect ratio between 1.7 and 1.8)
	if aspect_ratio >= 1.7 and aspect_ratio <= 1.8:
		return ScreenType.REGULAR_16_9
	
	return ScreenType.UNKNOWN

func is_ultrawide_ratio(ratio: float) -> bool:
	# Common ultrawide ratios
	var ultrawide_ratios = [
		21.0/9.0,   # 2.33... (21:9)
		32.0/9.0,   # 3.55... (32:9)
		18.0/9.0,   # 2.0 (18:9)
		43.0/18.0   # 2.38... (43:18)
	]
	
	for ur in ultrawide_ratios:
		if abs(ratio - ur) < 0.1:  # Allow some tolerance
			return true
	
	return false

func setup_transparent_window():
	# First, ensure we're in windowed mode
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	
	# Set up transparency
	get_window().transparent = true
	get_window().borderless = false  # Keep borders for moving by default
	
	# Apply appropriate window setup based on detected system
	match current_screen_type:
		ScreenType.MAC_RETINA:
			setup_mac_retina_window()
		ScreenType.ULTRAWIDE:
			setup_ultrawide_window()
		ScreenType.REGULAR_16_9:
			setup_regular_window()
		ScreenType.UNKNOWN:
			setup_fallback_window()

func setup_mac_retina_window():
	print("Setting up Mac Retina window")
	
	var phys_size: Vector2i = DisplayServer.screen_get_size(primary_screen_id)
	var dpi_scale := DisplayServer.screen_get_scale(primary_screen_id)
	var logical_size := phys_size / dpi_scale
	
	print("Physical size: ", phys_size)
	print("DPI scale: ", dpi_scale)
	print("Logical size: ", logical_size)
	
	# Use physical size for proper scaling on Mac
	DisplayServer.window_set_size(phys_size)
	DisplayServer.window_set_position(Vector2.ZERO)

func setup_ultrawide_window():
	print("Setting up ultrawide window (centered)")
	
	var screen_size = DisplayServer.screen_get_size(primary_screen_id)
	var screen_pos = DisplayServer.screen_get_position(primary_screen_id)
	
	print("Screen size: ", screen_size)
	print("Screen position: ", screen_pos)
	
	# Create a centered window that's 80% of screen height and maintains 16:9 ratio
	var window_height = int(screen_size.y * 0.8)
	var window_width = int(window_height * 16.0 / 9.0)
	
	# Make sure window width doesn't exceed screen width
	if window_width > screen_size.x:
		window_width = int(screen_size.x * 0.9)
		window_height = int(window_width * 9.0 / 16.0)
	
	# Center the window on the screen, accounting for screen position
	var pos_x = screen_pos.x + (screen_size.x - window_width) / 2
	var pos_y = screen_pos.y + (screen_size.y - window_height) / 2
	
	# Ensure position is not negative
	pos_x = max(pos_x, screen_pos.x)
	pos_y = max(pos_y, screen_pos.y)
	
	DisplayServer.window_set_size(Vector2i(window_width, window_height))
	DisplayServer.window_set_position(Vector2i(pos_x, pos_y))
	
	
	print("Calculated window size: ", Vector2i(window_width, window_height))
	print("Calculated window position: ", Vector2i(pos_x, pos_y))

func setup_regular_window():
	print("Setting up regular 16:9 window (maximized)")
	
	# For regular screens, use maximized mode
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)

func setup_fallback_window():
	print("Setting up fallback window")
	
	var screen_size = DisplayServer.screen_get_size(primary_screen_id)
	
	# Use 90% of screen size as fallback
	var window_size = Vector2i(int(screen_size.x * 0.9), int(screen_size.y * 0.9))
	var window_pos = Vector2i(
		(screen_size.x - window_size.x) / 2,
		(screen_size.y - window_size.y) / 2
	)
	
	DisplayServer.window_set_size(window_size)
	DisplayServer.window_set_position(window_pos)

# Utility functions for manual control
func set_window_mode(mode: WindowMode):
	match mode:
		WindowMode.WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			get_window().borderless = false
		WindowMode.MAXIMIZED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
			get_window().borderless = false
		WindowMode.FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		WindowMode.FIT_SCREEN:
			setup_transparent_window()

func toggle_borderless():
	get_window().borderless = !get_window().borderless
	print("Borderless mode: ", get_window().borderless)

func reconfigure_window():
	"""Call this function to reconfigure the window if screen setup changes"""
	detect_system_info()
	setup_transparent_window()

# Debug function to print current window info
func print_window_info():
	print("--- Window Info ---")
	print("OS: ", current_os)
	print("Screen type: ", ScreenType.keys()[current_screen_type])
	print("Window size: ", DisplayServer.window_get_size())
	print("Window position: ", DisplayServer.window_get_position())
	print("Screen size: ", DisplayServer.screen_get_size(primary_screen_id))
	print("DPI scale: ", DisplayServer.screen_get_scale(primary_screen_id))
	print("Transparent: ", get_window().transparent)
	print("Borderless: ", get_window().borderless)
	print("Window mode: ", DisplayServer.window_get_mode())
	print("------------------")