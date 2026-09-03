class_name FoodArea
extends Area2D

@export var desktop_pet_node: Node
@export var drag_smoothness := 15.0
@export var gravity_strength := 800.0
@export var bounce_strength := 0.3
@export var bounce_damping := 0.7
@export var floor_offset := 90.0
@export var throw_multiplier := 1.0
@export var selected = true


var dragging := false
var offset := Vector2.ZERO
var is_currently_hovered := false
var vertical_velocity := 0.0
var horizontal_velocity := 0.0
var drag_velocity := Vector2.ZERO
var previous_mouse_pos := Vector2.ZERO
var last_mouse_position := Vector2.ZERO
var hover_debounce_timer := 0.0
const HOVER_DEBOUNCE_DELAY := 0.15
static var dragging_instance: int = -1

func _ready() -> void:
	input_pickable = true
	previous_mouse_pos = get_global_mouse_position()
	
func _enter_tree() -> void:
	# Calls the static C# method to register this pet instance
	desktop_pet_node.RegisterFood()

func _exit_tree() -> void:
	# Sends the SceneTree to the C# unregister method so it can handle application exit
	desktop_pet_node.UnregisterFood(get_tree())

func get_unique_id() -> String:
	return str(get_instance_id())

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		desktop_pet_node.ReportHoverState(false, get_unique_id())

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and is_mouse_over() and dragging_instance == -1:
			dragging_instance = get_instance_id()
			dragging = true
			selected = true
			offset = global_position - event.global_position
			previous_mouse_pos = get_global_mouse_position()
			drag_velocity = Vector2.ZERO
			vertical_velocity = 0.0
			horizontal_velocity = 0.0
			desktop_pet_node.ReportHoverState(true, get_unique_id())
			is_currently_hovered = true
		elif not event.pressed and dragging:
			if dragging_instance == get_instance_id():
				dragging_instance = -1
			dragging = false
			selected = false
			horizontal_velocity = drag_velocity.x * throw_multiplier
			vertical_velocity = drag_velocity.y * throw_multiplier
			is_currently_hovered = false
			desktop_pet_node.ReportHoverState(false, get_unique_id())

func _process(delta: float) -> void:
	hover_debounce_timer -= delta
	update_hover_status()
	
	if dragging:
		process_dragging(delta)
	else:
		apply_gravity(delta)
		

func update_hover_status() -> void:
	if dragging:
		return
	
	var current_mouse_pos = get_global_mouse_position()
	if current_mouse_pos.distance_to(last_mouse_position) < 1.0:
		return
	last_mouse_position = current_mouse_pos
	
	var mouse_over = is_mouse_over()
	
	if mouse_over != is_currently_hovered and hover_debounce_timer <= 0:
		is_currently_hovered = mouse_over
		desktop_pet_node.ReportHoverState(is_currently_hovered, get_unique_id())
		hover_debounce_timer = HOVER_DEBOUNCE_DELAY

func process_dragging(delta: float) -> void:
	var current_mouse_pos = get_global_mouse_position()
	var target = current_mouse_pos + offset
	
	var mouse_move_vec = current_mouse_pos - previous_mouse_pos
	drag_velocity = mouse_move_vec / delta
	drag_velocity = drag_velocity.limit_length(2000)
	
	global_position = global_position.lerp(target, drag_smoothness * delta)
	previous_mouse_pos = current_mouse_pos

func apply_gravity(delta: float) -> void:
	var window_pos = DisplayServer.window_get_position()
	var food_screen_pos = Vector2(window_pos.x + global_position.x, window_pos.y + global_position.y)
	var floor_y = calculate_floor_y(food_screen_pos, window_pos)
	
	global_position.x += horizontal_velocity * delta
	horizontal_velocity *= 0.98
	
	var window_size = DisplayServer.window_get_size()
	if global_position.x <= 0:
		global_position.x = 0
		horizontal_velocity = abs(horizontal_velocity) * bounce_strength
	elif global_position.x >= window_size.x:
		global_position.x = window_size.x
		horizontal_velocity = -abs(horizontal_velocity) * bounce_strength
	
	if global_position.y < floor_y:
		vertical_velocity += gravity_strength * delta
		global_position.y += vertical_velocity * delta
	elif global_position.y >= floor_y:
		if abs(vertical_velocity) > 50:
			vertical_velocity = -abs(vertical_velocity) * bounce_strength
			global_position.y = floor_y
		else:
			vertical_velocity = 0
			global_position.y = floor_y
		vertical_velocity *= bounce_damping
	
	if global_position.y <= 0:
		global_position.y = 0
		vertical_velocity = abs(vertical_velocity) * bounce_strength

func calculate_floor_y(food_pos: Vector2, win_pos: Vector2i) -> float:
	for i in range(DisplayServer.get_screen_count()):
		var s_pos = DisplayServer.screen_get_position(i)
		var s_size = DisplayServer.screen_get_size(i)
		if Rect2(s_pos, s_size).has_point(food_pos):
			var taskbar = desktop_pet_node.GetTaskbarHeight() if desktop_pet_node.IsTaskbarOnScreen(i) else 0
			return (s_pos.y + s_size.y) - win_pos.y - taskbar - floor_offset
	return DisplayServer.window_get_size().y - 48 - floor_offset

func is_mouse_over() -> bool:
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = get_global_mouse_position()
	query.collide_with_areas = true
	var result = space_state.intersect_point(query, 32)
	
	for collision in result:
		if collision.collider == self:
			return true
	return false
