extends CharacterBody2D

@export var desktop_pet_node: Node
@export var gravity_strength := 1000.0
@export var floor_offset := 90.0
@export var rotation_speed := 0.01
@export var smoothed_rotation := 0.0 
@export var drag_smoothness := 100.0
@export var bounce_strength := 0.5
@export var bounce_damping := 0.8
@export var throw_multiplier := 1.0

# --- WANDER SETTINGS ---
@export var walk_speed := 150.0
@export var wander_chance := 0.005 
var wander_timer := 0.0
var is_wandering := false
var wander_direction := 1.0 
var is_relaxed := false  # <-- Tracks relaxed state

@onready var SFX = $AudioStreamPlayer

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
var pet_timer := 0.0          
const PET_DURATION := 0.5    
static var dragging_instance: int = -1  # stores instance ID of who owns the drag

# --- PER-INSTANCE HOVER STATE ---
var is_currently_hovered := false
var hover_debounce_timer := 0.0
const HOVER_DEBOUNCE_DELAY := 0.15

# --- MENU VARIABLES ---
@onready var body_area = $Area2D
@onready var petting_hitbox = $Petting 
@onready var context_menu = $ContextMenu
@onready var state_menu = $ContextMenu/StateMenu
@onready var body = $Body
@onready var eyes = $Body/Eyes
@onready var mouth = $Body/Mouth
@onready var particles = $Petting/PettingHitbox/GPUParticles2D
@onready var petting_area = $Petting/PettingHitbox

var is_menu_open := false
var state_enabled := false

func _ready() -> void:
	input_pickable = true
	randomize() 
	
	var window_size = DisplayServer.window_get_size()
	global_position = Vector2(window_size.x / 2.0, 50.0)
	vertical_velocity = 100.0
	
	if context_menu:
		context_menu.visible = false
	if state_menu:
		state_menu.visible = false
	
	connect_menu_buttons()
	
	var screen_count = desktop_pet_node.GetScreenCount()
	print("Pet initialized. Available screens: ", screen_count)

func _enter_tree() -> void:
	desktop_pet_node.RegisterPet()

func _exit_tree() -> void:
	desktop_pet_node.UnregisterPet(get_tree())

func get_unique_id() -> String:
	return str(get_instance_id())

func get_menu_id() -> String:
	return str(get_instance_id()) + "_menu"

func get_all_children(node: Node) -> Array:
	var children = []
	for child in node.get_children():
		children.append(child)
		children.append_array(get_all_children(child))
	return children

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		desktop_pet_node.ReportHoverState(false, get_unique_id())
		desktop_pet_node.ReportHoverState(false, get_menu_id())

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed and is_mouse_over(1):
			toggle_menu(!is_menu_open)
			get_viewport().set_input_as_handled()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if is_mouse_over(1) and dragging_instance == -1:
				dragging_instance = get_instance_id()
				dragging = true
				is_wandering = false
				toggle_menu(false)
				offset = global_position - event.global_position
				previous_mouse_pos = get_global_mouse_position()
				drag_velocity = Vector2.ZERO
				vertical_velocity = 0.0
				horizontal_velocity = 0.0
				interaction_cooldown = INTERACTION_COOLDOWN_TIME
				desktop_pet_node.ReportHoverState(true, get_unique_id())
				is_currently_hovered = true

		elif not event.pressed and dragging:
			if dragging_instance == get_instance_id():
				dragging_instance = -1
			dragging = false
			horizontal_velocity = drag_velocity.x * throw_multiplier
			vertical_velocity = drag_velocity.y * throw_multiplier
			interaction_cooldown = INTERACTION_COOLDOWN_TIME
			is_currently_hovered = false
			desktop_pet_node.ReportHoverState(false, get_unique_id())

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_1: switch_to_screen(0)
		elif event.keycode == KEY_2: switch_to_screen(1)
		elif event.keycode == KEY_3: switch_to_screen(2)

func _process(delta: float) -> void:
	if dragging_instance == get_instance_id() and not dragging:
		dragging_instance = -1
		
	interaction_cooldown -= delta
	hover_debounce_timer -= delta
	
	if dragging:
		process_dragging(delta)
		return

	update_hover_status()
	process_petting(delta)

	if not dragging and abs(rotation) > 0.01:
		rotation = lerp(rotation, 0.0, 10.0 * delta)
	
	if not dragging:
		apply_physics_and_wander(delta)
	
	var overlapping = body_area.get_overlapping_areas()
	
	for area in overlapping:
		if area is FoodArea and area.selected == false:
			SFX.play()
			area.queue_free()

func toggle_menu(open: bool) -> void:
	if not context_menu: return
	is_menu_open = open
	context_menu.visible = open
	
	# Close state submenu whenever context menu closes
	if not open:
		state_enabled = false
		if state_menu:
			state_menu.visible = false

	if is_menu_open:
		desktop_pet_node.ReportHoverState(true, get_menu_id())
	else:
		desktop_pet_node.ReportHoverState(false, get_menu_id())
		is_currently_hovered = is_mouse_over(1)
		desktop_pet_node.ReportHoverState(is_currently_hovered, get_unique_id())

func update_hover_status() -> void:
	if dragging or is_menu_open:
		return
	
	var mouse_over_pet = is_mouse_over(1) or is_mouse_over(2)
	var mouse_over_menu = is_mouse_over_menu()
	var should_be_solid = mouse_over_pet or mouse_over_menu
	
	if should_be_solid != is_currently_hovered:
		if hover_debounce_timer <= 0:
			is_currently_hovered = should_be_solid
			desktop_pet_node.ReportHoverState(is_currently_hovered, get_unique_id())
			hover_debounce_timer = HOVER_DEBOUNCE_DELAY

func is_mouse_over_menu() -> bool:
	if not context_menu or not context_menu.visible:
		return false
	
	var mouse_pos = get_global_mouse_position()
	var all_menu_nodes = get_all_children(context_menu)
	all_menu_nodes.append(context_menu)
	
	for node in all_menu_nodes:
		if node is Control and node.is_visible_in_tree():
			if node.get_global_rect().has_point(mouse_pos):
				return true
	return false

func process_dragging(delta: float) -> void:
	if body:
		body.play("Falling")
	if eyes:
		eyes.visible = false
	if mouth:
		mouth.visible = false
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

	if grounded:
		# Check 'not is_relaxed' before starting a wander
		if not is_relaxed and not is_wandering and randf() < wander_chance and interaction_cooldown <= 0:
			start_wandering()
		
		if is_wandering:
			body.play("Walking")
			eyes.visible = false
			mouth.visible = false
			wander_timer -= delta
			horizontal_velocity = wander_direction * walk_speed
			if wander_timer <= 0:
				is_wandering = false
				horizontal_velocity = 0
		else:
			body.play("Breathing")
			eyes.visible = true
			mouth.visible = true
			eyes.play("Blinking")
			horizontal_velocity = move_toward(horizontal_velocity, 0, 500 * delta)
	else:
		is_wandering = false
		horizontal_velocity *= 0.98
		eyes.visible = false
		mouth.visible = false
		body.play("Falling")

	global_position.x += horizontal_velocity * delta
	handle_side_bounces()

	vertical_velocity += gravity_strength * delta
	global_position.y += vertical_velocity * delta

	if global_position.y <= 0:
		global_position.y = 0
		vertical_velocity = abs(vertical_velocity) * bounce_strength

	if global_position.y >= floor_y:
		if abs(vertical_velocity) > 50:
			vertical_velocity = -abs(vertical_velocity) * bounce_strength
			rotation *= 0.5
		else:
			vertical_velocity = 0
			global_position.y = floor_y
			rotation = 0.0
		vertical_velocity *= bounce_damping

func start_wandering() -> void:
	is_wandering = true
	wander_timer = randf_range(1.5, 4.0)
	wander_direction = 1.0 if randf() > 0.5 else -1.0
	if body:
		var is_flipped = (wander_direction > 0)
		body.flip_h = is_flipped
		if eyes:
			eyes.flip_h = is_flipped
			eyes.position.x = 65.5 if is_flipped else -65.5
		if mouth:
			mouth.flip_h = is_flipped
			mouth.position.x = 72.5 if is_flipped else -72.5
		if petting_area:                                         
			petting_area.position.x = 126.0 if is_flipped else -126.0

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

func process_petting(delta: float) -> void:
	if dragging:
		if particles: particles.emitting = false
		return

	if pet_timer > 0:
		pet_timer -= delta
		if particles: particles.emitting = true
		return
	
	if particles: particles.emitting = false

func is_mouse_over(mask: int = 1) -> bool:
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = get_global_mouse_position()
	query.collision_mask = mask
	query.collide_with_areas = true
	query.collide_with_bodies = true
	
	var result = space_state.intersect_point(query, 32)
	for collision in result:
		if collision.collider == body_area or collision.collider == petting_hitbox:
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

## CONTEXT MENU & SUBMENU CONNECTORS

func connect_menu_buttons() -> void:
	if not context_menu: return
	
	var quit_btn = context_menu.find_child("Switch", true, false)
	var state_btn = context_menu.find_child("State", true, false)
	var delete_btn = context_menu.find_child("Delete", true, false)
	
	if quit_btn: quit_btn.pressed.connect(_on_quit_pressed)
	if state_btn: state_btn.pressed.connect(_on_state_pressed)
	if delete_btn: delete_btn.pressed.connect(_on_delete_pressed)
	
	var sleep_btn = context_menu.find_child("Sleep", true, false)
	var sit_btn = context_menu.find_child("Sit", true, false)
	var relax_btn = context_menu.find_child("Relax", true, false)
	var reset_btn = context_menu.find_child("Reset", true, false)
	
	if sleep_btn: sleep_btn.pressed.connect(_on_sleep_pressed)
	if sit_btn: sit_btn.pressed.connect(_on_sit_pressed)
	if relax_btn: relax_btn.pressed.connect(_on_relax_pressed)
	if reset_btn: reset_btn.pressed.connect(_on_reset_pressed)

func _on_quit_pressed() -> void:
	toggle_menu(false)

func _on_state_pressed() -> void:
	state_enabled = !state_enabled
	if state_menu:
		state_menu.visible = state_enabled

func _on_delete_pressed() -> void:
	toggle_menu(false)
	queue_free()

# --- STATE SUBMENU HANDLERS ---

func _on_sleep_pressed() -> void:
	toggle_menu(false)

func _on_sit_pressed() -> void:
	toggle_menu(false)

func _on_relax_pressed() -> void:
	toggle_menu(false)
	is_relaxed = !is_relaxed  # Toggle state
	
	if is_relaxed:
		is_wandering = false
		horizontal_velocity = 0.0

func _on_reset_pressed() -> void:
	toggle_menu(false)
	is_relaxed = false  # Optionally clear relax state on reset

func _on_area_2d_area_entered(area):
	if area is FoodArea:
		mouth.play("default")

func _on_area_2d_area_exited(area):
	if area is FoodArea:
		mouth.play("default", -1, true)
