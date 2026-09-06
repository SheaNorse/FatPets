extends Window

var window_id: String = ""
var is_dragging: bool = false
var drag_offset: Vector2i = Vector2i.ZERO

func _ready() -> void:
	window_id = str(get_path())
	
	# Ensure the Window node accepts mouse events natively
	mouse_passthrough = false
	
	# Connect Control child hover events if you have a Control wrapper
	var control_node = get_node_or_null("Control")
	if control_node:
		control_node.mouse_entered.connect(_on_mouse_entered_ui)
		control_node.mouse_exited.connect(_on_mouse_exited_ui)
	
	# Connect buttons safely
	var food_btn = get_node_or_null("Control/VBoxContainer/Food")
	var pets_btn = get_node_or_null("Control/VBoxContainer/Pets")
	
	if food_btn:
		food_btn.pressed.connect(_on_food_pressed)
	if pets_btn:
		pets_btn.pressed.connect(_on_pets_pressed)

# Override Window's built-in GUI input handler directly
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_dragging = true
			drag_offset = Vector2i(DisplayServer.mouse_get_position()) - position
			# Force DesktopPet to stop click-through while dragging
			if is_instance_valid(DesktopPet) and DesktopPet.has_method("ReportHoverState"):
				DesktopPet.ReportHoverState(true, window_id)
		else:
			is_dragging = false

func _process(_delta: float) -> void:
	if is_dragging:
		position = Vector2i(DisplayServer.mouse_get_position()) - drag_offset

func _on_mouse_entered_ui() -> void:
	if is_instance_valid(DesktopPet) and DesktopPet.has_method("ReportHoverState"):
		DesktopPet.ReportHoverState(true, window_id)

func _on_mouse_exited_ui() -> void:
	if not is_dragging:
		if is_instance_valid(DesktopPet) and DesktopPet.has_method("ReportHoverState"):
			DesktopPet.ReportHoverState(false, window_id)

func _on_food_pressed() -> void:
	print("Sleep option selected!")

func _on_pets_pressed() -> void:
	print("Sleep2 option selected!")

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if is_instance_valid(DesktopPet) and DesktopPet.has_method("ReportHoverState"):
			DesktopPet.ReportHoverState(false, window_id)
