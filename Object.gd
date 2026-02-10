extends CharacterBody2D

@export var manager: Node2D # Assign your DesktopPet node here
var dragging = false
var offset = Vector2.ZERO

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and is_mouse_over():
				start_dragging()
			else:
				stop_dragging()

func start_dragging():
	dragging = true
	# Calculate offset so the cat doesn't "snap" its center to the mouse
	offset = global_position - get_global_mouse_position()
	manager.set("IsDragging", true)

func stop_dragging():
	dragging = false
	manager.set("IsDragging", false)

var screen_size = DisplayServer.screen_get_size()

func _process(delta):
	if dragging:
		global_position = get_global_mouse_position() + offset
	else:
		# Simple gravity: fall to the bottom of the screen
		var bottom_limit = screen_size.y - 50 # Adjust '50' based on sprite size
		if global_position.y < bottom_limit:
			global_position.y += 500 * delta # Fall speed
			if global_position.y > bottom_limit:
				global_position.y = bottom_limit

# Helper function to check if mouse is over this specific pet
func is_mouse_over() -> bool:
	# This checks the "IsMouseOverUI" status we already set up
	return manager.get("IsMouseOverUI")
