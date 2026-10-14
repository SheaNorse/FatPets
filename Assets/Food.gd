class_name FoodArea
extends Area2D

@export_category("Food & Physics Settings")
@export var drag_smoothness := 15.0
@export var gravity_strength := 800.0
@export var bounce_strength := 0.3
@export var bounce_damping := 0.7
@export var floor_offset := 90.0
@export var throw_multiplier := 1.0
@export var selected := true
@export var food_points: int = 10

# --- DRAG & PHYSICS STATE ---
var dragging := false
var offset := Vector2.ZERO
var vertical_velocity := 0.0
var horizontal_velocity := 0.0
var drag_velocity := Vector2.ZERO
var previous_mouse_pos := Vector2.ZERO

# --- HOVER & WIN32 CLICK-THROUGH TRACKING ---
var is_currently_hovered := false
var hover_debounce_timer := 0.0
const HOVER_DEBOUNCE_DELAY := 0.15

# Global static lock across all food instances
static var dragging_instance: int = -1

# Performance caching
@onready var cached_window_size: Vector2i = DisplayServer.window_get_size()
var _last_mouse_pos := Vector2.INF
var _cached_mouse_over := false
var _is_deleting := false
const MOUSE_CHECK_THRESHOLD_SQ := 4.0  # 2px squared


func _ready() -> void:
	input_pickable = true
	previous_mouse_pos = get_global_mouse_position()
	
	# Window resize handler
	get_tree().root.size_changed.connect(func():
		cached_window_size = DisplayServer.window_get_size()
	)


func _enter_tree() -> void:
	if is_instance_valid(DesktopPet) and DesktopPet.has_method("RegisterFood"):
		DesktopPet.RegisterFood()


func _exit_tree() -> void:
	if dragging_instance == get_instance_id():
		dragging_instance = -1
	
	_clear_hover_state()
	
	if is_instance_valid(DesktopPet) and DesktopPet.has_method("UnregisterFood"):
		DesktopPet.UnregisterFood(get_tree())


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if dragging_instance == get_instance_id():
			dragging_instance = -1
		_clear_hover_state()


# --- CONTINUOUS WIN32 HOVER CHECKING ---
func _process(delta: float) -> void:
	if _is_deleting:
		return

	# Safety check: clear orphan drag locks
	if dragging and dragging_instance != get_instance_id():
		dragging = false
		selected = false

	hover_debounce_timer = maxf(hover_debounce_timer - delta, 0.0)

	if dragging:
		process_dragging(delta)
	else:
		update_hover_status()
		apply_gravity(delta)


func update_hover_status() -> void:
	if dragging or _is_deleting:
		return

	var is_over := is_mouse_over_area()

	if is_over != is_currently_hovered:
		if hover_debounce_timer <= 0.0:
			is_currently_hovered = is_over
			if is_instance_valid(DesktopPet) and DesktopPet.has_method("ReportHoverState"):
				DesktopPet.ReportHoverState(is_currently_hovered, get_unique_id())
			hover_debounce_timer = HOVER_DEBOUNCE_DELAY


# --- SPACE-STATE RAYCASTING ---
func is_mouse_over_area() -> bool:
	if _is_deleting:
		return false

	var mouse_pos := get_global_mouse_position()
	if mouse_pos.distance_squared_to(_last_mouse_pos) < MOUSE_CHECK_THRESHOLD_SQ:
		return _cached_mouse_over

	_last_mouse_pos = mouse_pos

	var space_state := get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = mouse_pos
	query.collide_with_areas = true
	query.collide_with_bodies = false

	_cached_mouse_over = false
	for collision in space_state.intersect_point(query, 8):
		if collision.collider == self:
			_cached_mouse_over = true
			break
	return _cached_mouse_over


# --- RELIABLE GLOBAL INPUT INTERCEPTION ---
func _input(event: InputEvent) -> void:
	if _is_deleting or not (event is InputEventMouseButton):
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if dragging_instance == -1 and not dragging and is_mouse_over_area():
				_start_dragging(event.global_position)
				get_viewport().set_input_as_handled()
		elif dragging:
			_stop_dragging()
			get_viewport().set_input_as_handled()


func _start_dragging(event_global_pos: Vector2) -> void:
	dragging_instance = get_instance_id()
	dragging = true
	selected = true
	bring_to_front()

	offset = global_position - event_global_pos
	previous_mouse_pos = get_global_mouse_position()
	drag_velocity = Vector2.ZERO
	vertical_velocity = 0.0
	horizontal_velocity = 0.0

	_force_hover_state(true)


func _stop_dragging() -> void:
	if dragging_instance == get_instance_id():
		dragging_instance = -1
	dragging = false
	selected = false

	horizontal_velocity = drag_velocity.x * throw_multiplier
	vertical_velocity = drag_velocity.y * throw_multiplier

	_force_hover_state(false)
	call_deferred("_notify_pets_of_drop")


func process_dragging(delta: float) -> void:
	var current_mouse_pos := get_global_mouse_position()
	var safe_delta := maxf(delta, 0.001)

	drag_velocity = ((current_mouse_pos - previous_mouse_pos) / safe_delta).limit_length(2000.0)

	var lerp_weight := 1.0 - exp(-drag_smoothness * delta)
	global_position = global_position.lerp(current_mouse_pos + offset, lerp_weight)

	previous_mouse_pos = current_mouse_pos


func apply_gravity(delta: float) -> void:
	var floor_y := calculate_floor_y()

	# Horizontal movement & bounce bounds
	global_position.x += horizontal_velocity * delta
	horizontal_velocity *= 0.98

	if global_position.x <= 0.0:
		global_position.x = 0.0
		horizontal_velocity = absf(horizontal_velocity) * bounce_strength
	elif global_position.x >= cached_window_size.x:
		global_position.x = float(cached_window_size.x)
		horizontal_velocity = -absf(horizontal_velocity) * bounce_strength

	# Vertical gravity & floor bounce bounds
	if global_position.y < floor_y:
		vertical_velocity += gravity_strength * delta
		global_position.y += vertical_velocity * delta

	if global_position.y >= floor_y:
		if absf(vertical_velocity) > 50.0:
			vertical_velocity = -absf(vertical_velocity) * bounce_strength
		else:
			vertical_velocity = 0.0
		global_position.y = floor_y
		vertical_velocity *= bounce_damping
	elif global_position.y <= 0.0:
		global_position.y = 0.0
		vertical_velocity = absf(vertical_velocity) * bounce_strength


func calculate_floor_y() -> float:
	var win_height := float(cached_window_size.y)
	if is_instance_valid(FloorManager):
		return FloorManager.get_local_floor_y(win_height, floor_offset)
	return win_height - floor_offset


func _notify_pets_of_drop() -> void:
	for area in get_overlapping_areas():
		var target_node = area.get_parent()
		if target_node is CharacterBody2D and target_node.has_method("_check_eat_on_release"):
			target_node._check_eat_on_release()
			break


func _force_hover_state(state: bool) -> void:
	is_currently_hovered = state
	if is_instance_valid(DesktopPet) and DesktopPet.has_method("ReportHoverState"):
		DesktopPet.ReportHoverState(state, get_unique_id())


func _clear_hover_state() -> void:
	if is_currently_hovered:
		is_currently_hovered = false
		if is_instance_valid(DesktopPet) and DesktopPet.has_method("ReportHoverState"):
			DesktopPet.ReportHoverState(false, get_unique_id())


func bring_to_front() -> void:
	var target: Node = self
	var parent = get_parent()
	if parent and not (parent is Viewport):
		target = parent

	var grand_parent = target.get_parent()
	if grand_parent:
		grand_parent.move_child(target, -1)


func get_food_points() -> int:
	var parent = get_parent()
	if parent and "food_points" in parent and parent.food_points != null:
		return int(parent.food_points)
	return food_points


func get_unique_id() -> String:
	return str(get_instance_id())
