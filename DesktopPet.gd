extends CharacterBody2D

@export var desktop_pet_node: Node
@export var gravity_strength := 1000.0
@export var floor_offset := 90.0
@export var rotation_speed := 0.2
@export var drag_smoothness := 15.0
@export var bounce_strength := 0.5
@export var bounce_damping := 0.8
@export var throw_multiplier := 1.0

# --- WANDER SETTINGS ---
@export var walk_speed := 150.0
@export var wander_chance := 0.005 
var wander_timer := 0.0
var is_wandering := false
var wander_direction := 1.0 

# --- STATE VARIABLES ---
var dragging := false
var drag_target := Vector2.ZERO
var offset := Vector2.ZERO
var interaction_cooldown := 0.0
const INTERACTION_COOLDOWN_TIME := 1.0
var previous_mouse_pos := Vector2.ZERO
var vertical_velocity := 0.0
var horizontal_velocity := 0.0
var drag_velocity := Vector2.ZERO 

# --- PER-INSTANCE HOVER STATE ---
var is_currently_hovered := false
var last_mouse_position := Vector2.ZERO
var hover_debounce_timer := 0.0  # NEW
const HOVER_DEBOUNCE_DELAY := 0.15  # NEW: 150ms debounce

func _ready() -> void:
	input_pickable = true
	randomize() 
	
	var window_size = DisplayServer.window_get_size()
	global_position = Vector2(window_size.x / 2.0, 50.0)
	vertical_velocity = 100.0
	
	var screen_count = desktop_pet_node.GetScreenCount()
	print("Pet initialized. Available screens: ", screen_count)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and is_mouse_over():
			dragging = true
			is_wandering = false 
			offset = global_position - event.global_position
			previous_mouse_pos = get_global_mouse_position()
			drag_velocity = Vector2.ZERO
			vertical_velocity = 0.0
			horizontal_velocity = 0.0
			interaction_cooldown = INTERACTION_COOLDOWN_TIME
		elif not event.pressed and dragging: 
			dragging = false
			horizontal_velocity = drag_velocity.x * throw_multiplier
			vertical_velocity = drag_velocity.y * throw_multiplier
			interaction_cooldown = INTERACTION_COOLDOWN_TIME

	# Screen Switching Keys
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_1: switch_to_screen(0)
		elif event.keycode == KEY_2: switch_to_screen(1)
		elif event.keycode == KEY_3: switch_to_screen(2)

func _process(delta: float) -> void:
	interaction_cooldown -= delta
	hover_debounce_timer -= delta  # NEW: Count down debounce timer

	if dragging:
		process_dragging(delta)
		return

	update_hover_status()

	# Reset rotation when not being dragged
	if abs(rotation) > 0.01:
		rotation = lerp(rotation, 0.0, 10.0 * delta)
	
	apply_physics_and_wander(delta)

func update_hover_status() -> void:
	if dragging:
		return
	
	var mouse_over = is_mouse_over()
	
	# ONLY act if the status has actually flipped
	if mouse_over != is_currently_hovered:
		# Check debounce timer
		if hover_debounce_timer <= 0:
			is_currently_hovered = mouse_over
			# TELL C# TO CHANGE STYLE
			desktop_pet_node.ReportHoverState(is_currently_hovered)
			hover_debounce_timer = HOVER_DEBOUNCE_DELAY

func process_dragging(delta: float) -> void:
	var current_mouse_pos = get_viewport().get_mouse_position()
	
	drag_target = current_mouse_pos + offset
	
	var mouse_move_vec = current_mouse_pos - previous_mouse_pos
	drag_velocity = mouse_move_vec / delta
	
	global_position = global_position.lerp(drag_target, drag_smoothness * delta)
	
	var target_rotation = clamp(mouse_move_vec.x * 0.05, -0.5, 0.5)
	rotation = lerp(rotation, target_rotation, 0.2)
	
	previous_mouse_pos = current_mouse_pos

func apply_physics_and_wander(delta: float) -> void:
	var window_pos = DisplayServer.window_get_position()
	var pet_screen_pos = Vector2(window_pos.x + global_position.x, window_pos.y + global_position.y)
	var floor_y = calculate_floor_y(pet_screen_pos, window_pos)
	var grounded = global_position.y >= floor_y - 1.0

	# --- HORIZONTAL MOVEMENT ---
	if grounded:
		if not is_wandering and randf() < wander_chance and interaction_cooldown <= 0:
			start_wandering()
		
		if is_wandering:
			wander_timer -= delta
			horizontal_velocity = wander_direction * walk_speed
			if wander_timer <= 0:
				is_wandering = false
				horizontal_velocity = 0
		else:
			horizontal_velocity = move_toward(horizontal_velocity, 0, 500 * delta)
	else:
		is_wandering = false
		horizontal_velocity *= 0.98

	global_position.x += horizontal_velocity * delta
	handle_side_bounces()

	# --- VERTICAL MOVEMENT ---
	vertical_velocity += gravity_strength * delta
	global_position.y += vertical_velocity * delta

	# Ceiling Collision
	if global_position.y <= 0:
		global_position.y = 0
		vertical_velocity = abs(vertical_velocity) * bounce_strength

	# Floor Collision
	if global_position.y >= floor_y:
		if abs(vertical_velocity) > 50:
			vertical_velocity = -abs(vertical_velocity) * bounce_strength
		else:
			vertical_velocity = 0
			global_position.y = floor_y
		vertical_velocity *= bounce_damping

func start_wandering() -> void:
	is_wandering = true
	wander_timer = randf_range(1.5, 4.0)
	wander_direction = 1.0 if randf() > 0.5 else -1.0
	if has_node("Sprite2D"):
		get_node("Sprite2D").flip_h = (wander_direction < 0)

func calculate_floor_y(pet_pos: Vector2, win_pos: Vector2i) -> float:
	for i in range(DisplayServer.get_screen_count()):
		var s_pos = DisplayServer.screen_get_position(i)
		var s_size = DisplayServer.screen_get_size(i)
		if Rect2(s_pos, s_size).has_point(pet_pos):
			var taskbar = desktop_pet_node.GetTaskbarHeight() if desktop_pet_node.IsTaskbarOnScreen(i) else 0
			return (s_pos.y + s_size.y) - win_pos.y - taskbar - floor_offset
	return DisplayServer.window_get_size().y - 48 - floor_offset

func handle_side_bounces() -> void:
	var win_size = DisplayServer.window_get_size()
	if global_position.x <= 0:
		global_position.x = 0
		horizontal_velocity = abs(horizontal_velocity) * bounce_strength
		is_wandering = false
	elif global_position.x >= win_size.x:
		global_position.x = win_size.x
		horizontal_velocity = -abs(horizontal_velocity) * bounce_strength
		is_wandering = false

func is_mouse_over() -> bool:
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = get_global_mouse_position()
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var result = space_state.intersect_point(query, 32)
	
	# Check if THIS specific pet is under the mouse
	for collision in result:
		if collision.collider == self or (collision.collider.get_parent() == self):
			return true
	return false
	
	

func switch_to_screen(screen_index: int) -> void:
	var screen_count = desktop_pet_node.GetScreenCount()
	if screen_index >= screen_count: return
	
	desktop_pet_node.MoveToScreen(screen_index)
	await get_tree().process_frame
	
	var screen_size = DisplayServer.screen_get_size(screen_index)
	var screen_pos = DisplayServer.screen_get_position(screen_index)
	var window_size = DisplayServer.window_get_size()
	
	var window_target_pos = Vector2i(
		screen_pos.x + (screen_size.x - window_size.x) / 2,
		screen_pos.y + (screen_size.y - window_size.y) / 2
	)
	
	DisplayServer.window_set_position(window_target_pos)
	global_position = Vector2(window_size.x / 2.0, window_size.y / 2.0)
	vertical_velocity = 0.0
	horizontal_velocity = 0.0
