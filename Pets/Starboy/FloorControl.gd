extends HScrollBar

@export var base_pet_floor_offset: float = 20.0

func _ready() -> void:
	step = 1.0
	update_scroll_bounds()
	
	get_viewport().size_changed.connect(update_scroll_bounds)

	if is_instance_valid(FloorManager):
		value = FloorManager.extra_floor_offset

	value_changed.connect(_on_value_changed)

func update_scroll_bounds() -> void:
	var current_screen = DisplayServer.window_get_current_screen()
	
	var screen_pos = DisplayServer.screen_get_position(current_screen)
	var screen_size = DisplayServer.screen_get_size(current_screen)
	var usable_rect = DisplayServer.screen_get_usable_rect(current_screen)
	
	var win_height = float(screen_size.y)
	
	# Compute taskbar height strictly from display usable rect
	var taskbar_height = max(float((screen_pos.y + screen_size.y) - (usable_rect.position.y + usable_rect.size.y)), 0.0)
	
	# Minimum value (0) strictly forces floor to rest on top of taskbar
	min_value = 0.0
	
	# Maximum value lifts floor all the way up to top of screen (Y = 0)
	max_value = win_height - taskbar_height - base_pet_floor_offset
	
	if is_instance_valid(FloorManager):
		value = clamp(FloorManager.extra_floor_offset, min_value, max_value)

func _on_value_changed(new_value: float) -> void:
	if is_instance_valid(FloorManager):
		FloorManager.set_extra_offset(new_value)
