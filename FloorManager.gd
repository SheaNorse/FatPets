extends Node

signal floor_offset_changed(additional_offset: float)

var extra_floor_offset: float = 0.0

func set_extra_offset(value: float) -> void:
	if not is_equal_approx(extra_floor_offset, value):
		extra_floor_offset = value
		floor_offset_changed.emit(extra_floor_offset)

func get_local_floor_y(window_height: float, base_floor_offset: float) -> float:
	var current_screen = DisplayServer.window_get_current_screen()
	var screen_pos = DisplayServer.screen_get_position(current_screen)
	var screen_size = DisplayServer.screen_get_size(current_screen)
	var usable_rect = DisplayServer.screen_get_usable_rect(current_screen)
	
	# Calculate taskbar height for current screen
	var taskbar_height = max(float((screen_pos.y + screen_size.y) - (usable_rect.position.y + usable_rect.size.y)), 0.0)
	
	# Absolute floor boundary sits strictly at taskbar top
	var baseline_floor = window_height - taskbar_height - base_floor_offset
	
	# Subtract extra_floor_offset to move floor upward towards top of screen
	var target_y = baseline_floor - extra_floor_offset
	
	# Clamp strictly between top of screen (0.0) and taskbar top (baseline_floor)
	return clamp(target_y, 0.0, max(0.0, baseline_floor))
