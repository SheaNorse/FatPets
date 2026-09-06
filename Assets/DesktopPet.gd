class_name Pet
extends CharacterBody2D

@export var gravity_strength := 1000.0
@export var floor_offset := 90.0
@export var rotation_speed := 0.01
@export var smoothed_rotation := 0.0 
@export var drag_smoothness := 25.0 # Adjusted for frame-independent decay rate
@export var bounce_strength := 0.5
@export var bounce_damping := 0.8
@export var throw_multiplier := 1.0

# --- EDIBLE PET SETTING ---
@export var is_edible := false

# --- PER-PET FLIP OFFSETS ---
@export var eyes_offset_x_override := -1.0
@export var mouth_offset_x_override := -1.0
@export var petting_area_offset_x_override := -1.0

# Some pet sprites were drawn facing the opposite default direction.
@export var invert_facing_direction := false

# --- WANDER & FRICTION SETTINGS ---
@export var walk_speed := 150.0
@export var walk_acceleration := 600.0 # How quickly the pet speeds up to walk_speed
@export var walk_friction := 800.0     # How quickly the pet slows down to a stop
@export var wander_chance := 0.0025
var wander_timer := 0.0
var is_wandering := false
var wander_direction := 1.0 

# --- STATE TRACKING ---
enum State { NORMAL, RELAXED, SITTING, SLEEPING }
var current_state: State = State.NORMAL

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

# --- CACHED FLIP OFFSETS ---
var eyes_base_x := 0.0
var mouth_base_x := 0.0
var petting_area_base_x := 0.0
var sleeping_particles_base_x := 0.0
var eyes_default_position := Vector2.ZERO

# --- MENU VARIABLES ---
@onready var body_area = $Area2D
@onready var petting_hitbox = $Petting 
@onready var context_menu = $ContextMenu
@onready var state_menu = $ContextMenu/StateMenu
@onready var body = $Body
@onready var eyes = $Body/Eyes
@onready var mouth = $Body/Eyes/Mouth
@onready var particles = $Petting/PettingHitbox/GPUParticles2D
@onready var petting_area = $Petting/PettingHitbox

@onready var sleeping_particles = $Sleeping
@onready var sitting_anchor = $EyeAnchors/Sitting

var is_menu_open := false
var state_enabled := false

func _ready() -> void:
	input_pickable = true
	randomize() 
	
	if eyes:
		eyes_default_position = eyes.position
		
	if sleeping_particles:
		sleeping_particles_base_x = sleeping_particles.position.x
		sleeping_particles.emitting = false
	
	var window_size = DisplayServer.window_get_size()
	global_position = Vector2(window_size.x / 2.0, 50.0)
	vertical_velocity = 100.0
	
	if context_menu:
		context_menu.visible = false
	if state_menu:
		state_menu.visible = false
	
	_resolve_flip_offsets()
	connect_menu_buttons()
	_setup_edible_status()
	
	if is_instance_valid(DesktopPet):
		var screen_count = DesktopPet.GetScreenCount()
		print("Pet initialized. Available screens: ", screen_count)

func _setup_edible_status() -> void:
	if is_edible and body_area:
		if not body_area is FoodArea and not body_area.has_node("FoodAreaMarker"):
			var food_marker = FoodArea.new()
			food_marker.name = "FoodAreaMarker"
			body_area.add_child(food_marker)

func _resolve_flip_offsets() -> void:
	var override_sign := 1.0 if invert_facing_direction else -1.0

	if eyes_offset_x_override >= 0.0:
		eyes_base_x = eyes_offset_x_override * override_sign
	elif eyes:
		eyes_base_x = eyes.position.x

	if mouth_offset_x_override >= 0.0:
		mouth_base_x = mouth_offset_x_override * override_sign
	elif mouth:
		mouth_base_x = mouth.position.x

	if petting_area_offset_x_override >= 0.0:
		petting_area_base_x = petting_area_offset_x_override * override_sign
	elif petting_area:
		petting_area_base_x = petting_area.position.x

func _enter_tree() -> void:
	if is_instance_valid(DesktopPet):
		DesktopPet.RegisterPet()

func _exit_tree() -> void:
	if dragging_instance == get_instance_id():
		dragging_instance = -1
		
	if is_instance_valid(DesktopPet):
		DesktopPet.ReportHoverState(false, get_unique_id())
		DesktopPet.ReportHoverState(false, get_menu_id())
		DesktopPet.UnregisterPet(get_tree())

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
		if is_instance_valid(DesktopPet):
			DesktopPet.ReportHoverState(false, get_unique_id())
			DesktopPet.ReportHoverState(false, get_menu_id())

func bring_to_front() -> void:
	var parent = get_parent()
	if parent:
		parent.move_child(self, -1)

func _unhandled_input(event: InputEvent) -> void:
	if is_menu_open and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			if not is_mouse_over_menu() and not is_mouse_over(1):
				toggle_menu(false)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed and is_mouse_over(1):
			bring_to_front()
			toggle_menu(!is_menu_open)
			get_viewport().set_input_as_handled()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if is_mouse_over(1) and dragging_instance == -1:
				dragging_instance = get_instance_id()
				dragging = true
				bring_to_front()
				set_state(State.NORMAL) # Reset action state when grabbed
				is_wandering = false
				toggle_menu(false)
				offset = global_position - event.global_position
				previous_mouse_pos = get_global_mouse_position()
				drag_velocity = Vector2.ZERO
				vertical_velocity = 0.0
				horizontal_velocity = 0.0
				interaction_cooldown = INTERACTION_COOLDOWN_TIME
				if is_instance_valid(DesktopPet):
					DesktopPet.ReportHoverState(true, get_unique_id())
				is_currently_hovered = true

		elif not event.pressed and dragging:
			if dragging_instance == get_instance_id():
				dragging_instance = -1
			dragging = false
			
			_check_eat_on_release()

			horizontal_velocity = drag_velocity.x * throw_multiplier
			vertical_velocity = drag_velocity.y * throw_multiplier
			interaction_cooldown = INTERACTION_COOLDOWN_TIME
			is_currently_hovered = false
			if is_instance_valid(DesktopPet):
				DesktopPet.ReportHoverState(false, get_unique_id())

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
		if not (area.get_parent() is CharacterBody2D):
			_check_and_eat_area(area)

func set_state(new_state: State) -> void:
	current_state = new_state
	
	if current_state != State.NORMAL:
		is_wandering = false
		horizontal_velocity = 0.0

	# Handle Sleeping Particle Emission
	if sleeping_particles:
		sleeping_particles.emitting = (current_state == State.SLEEPING)

	# Align eyes with sitting anchor or revert to default position
	if eyes:
		if current_state == State.SITTING and sitting_anchor:
			var target_x = sitting_anchor.position.x
			if body.flip_h:
				target_x = -target_x
			eyes.position = Vector2(target_x, sitting_anchor.position.y)
		else:
			var target_x = eyes_base_x
			if body.flip_h:
				target_x = -eyes_base_x
			eyes.position = Vector2(target_x, eyes_default_position.y)

func _check_eat_on_release() -> void:
	var overlapping = body_area.get_overlapping_areas()
	for area in overlapping:
		if area == body_area or area.get_parent() == self:
			continue
			
		if area is FoodArea or area.has_node("FoodAreaMarker"):
			var target_node = area.get_parent()
			
			if target_node is CharacterBody2D:
				if target_node.get("is_menu_open") == true:
					continue

				var target_is_dragged = target_node.get("dragging") == true
				
				if not target_is_dragged:
					if target_node.has_method("play_sfx"):
						target_node.play_sfx()
					elif target_node.get("SFX"):
						target_node.SFX.play()
					else:
						SFX.play()
					
					queue_free()
					return

func _check_and_eat_area(area: Area2D) -> void:
	if area == body_area or area.get_parent() == self:
		return
		
	if area is FoodArea or area.has_node("FoodAreaMarker"):
		var is_selected = area.get("selected")
		if is_selected == true:
			return

		var target_node = area.get_parent()
		
		if not (target_node is CharacterBody2D):
			SFX.play()
			area.queue_free()

func play_sfx() -> void:
	if SFX:
		SFX.play()

func toggle_menu(open: bool) -> void:
	if not context_menu: return
	is_menu_open = open
	context_menu.visible = open
	
	if open:
		bring_to_front()
	else:
		state_enabled = false
		if state_menu:
			state_menu.visible = false

	if is_instance_valid(DesktopPet):
		if is_menu_open:
			DesktopPet.ReportHoverState(true, get_menu_id())
		else:
			DesktopPet.ReportHoverState(false, get_menu_id())
			is_currently_hovered = is_mouse_over(1)
			DesktopPet.ReportHoverState(is_currently_hovered, get_unique_id())

func update_hover_status() -> void:
	if dragging or is_menu_open:
		return
	
	var mouse_over_pet = is_mouse_over(1) or is_mouse_over(2)
	var mouse_over_menu = is_mouse_over_menu()
	var should_be_solid = mouse_over_pet or mouse_over_menu
	
	if should_be_solid != is_currently_hovered:
		if hover_debounce_timer <= 0:
			is_currently_hovered = should_be_solid
			if is_instance_valid(DesktopPet):
				DesktopPet.ReportHoverState(is_currently_hovered, get_unique_id())
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
		
	var safe_delta = min(delta, 0.033)
	var current_mouse_pos = get_viewport().get_mouse_position()
	drag_target = current_mouse_pos + offset
	
	var raw_velocity = (current_mouse_pos - previous_mouse_pos) / safe_delta
	drag_velocity = drag_velocity.lerp(raw_velocity, 1.0 - exp(-15.0 * safe_delta))
	
	var lerp_factor = 1.0 - exp(-drag_smoothness * safe_delta)
	global_position = global_position.lerp(drag_target, lerp_factor)
	
	var mouse_move_x = current_mouse_pos.x - previous_mouse_pos.x
	var target_rotation = clamp(mouse_move_x * 0.03, -0.5, 0.5)
	rotation = lerp(rotation, target_rotation, 1.0 - exp(-10.0 * safe_delta))
	
	previous_mouse_pos = current_mouse_pos

func apply_physics_and_wander(delta: float) -> void:
	var window_pos = DisplayServer.window_get_position()
	var pet_screen_pos = Vector2(window_pos.x + global_position.x, window_pos.y + global_position.y)
	var floor_y = calculate_floor_y(pet_screen_pos, window_pos)
	var grounded = global_position.y >= floor_y - 1.0

	if grounded:
		if current_state == State.SLEEPING:
			body.play("Sleeping")
			eyes.visible = false
			mouth.visible = false
		elif current_state == State.SITTING:
			body.play("Sitting")
			eyes.visible = true
			mouth.visible = true
			eyes.play("Blinking")
		else:
			if current_state != State.RELAXED and not is_wandering and randf() < wander_chance and interaction_cooldown <= 0:
				start_wandering()
			
			if is_wandering:
				body.play("Walking")
				eyes.visible = false
				mouth.visible = false
				wander_timer -= delta
				
				var target_speed = wander_direction * walk_speed
				horizontal_velocity = move_toward(horizontal_velocity, target_speed, walk_acceleration * delta)
				
				if wander_timer <= 0:
					is_wandering = false
			else:
				horizontal_velocity = move_toward(horizontal_velocity, 0.0, walk_friction * delta)
				
				if abs(horizontal_velocity) < 10.0:
					body.play("Breathing")
					eyes.visible = true
					mouth.visible = true
					eyes.play("Blinking")
				else:
					body.play("Walking")
					eyes.visible = false
					mouth.visible = false
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
	
	var is_flipped = (wander_direction > 0)
	if invert_facing_direction:
		is_flipped = !is_flipped
		
	_apply_facing_flip(is_flipped)

func _apply_facing_flip(is_flipped: bool) -> void:
	if body:
		body.flip_h = is_flipped
	if eyes:
		eyes.flip_h = is_flipped
		if current_state == State.SITTING and sitting_anchor:
			eyes.position.x = -sitting_anchor.position.x if is_flipped else sitting_anchor.position.x
		else:
			eyes.position.x = -eyes_base_x if is_flipped else eyes_base_x
	if mouth:
		mouth.flip_h = is_flipped
		mouth.position.x = -mouth_base_x if is_flipped else mouth_base_x
	if petting_area:
		petting_area.position.x = -petting_area_base_x if is_flipped else petting_area_base_x
		
	# Flip particle position and direction safely for CPUParticles2D
	if sleeping_particles:
		sleeping_particles.position.x = -sleeping_particles_base_x if is_flipped else sleeping_particles_base_x
		
		# Invert the horizontal direction directly on CPUParticles2D
		var base_dir = abs(sleeping_particles.direction.x) if sleeping_particles.direction.x != 0 else 1.0
		sleeping_particles.direction.x = -base_dir if is_flipped else base_dir

func calculate_floor_y(pet_pos: Vector2, win_pos: Vector2i) -> float:
	if is_instance_valid(DesktopPet):
		for i in range(DisplayServer.get_screen_count()):
			var s_pos = DisplayServer.screen_get_position(i)
			var s_size = DisplayServer.screen_get_size(i)
			if Rect2(s_pos, s_size).has_point(pet_pos):
				var global_floor_y = DesktopPet.GetFloorPositionForScreen(i)
				return global_floor_y - win_pos.y - floor_offset
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
	query.collide_with_areas = true
	query.collide_with_bodies = true
	
	var result = space_state.intersect_point(query, 32)
	for collision in result:
		if collision.collider == body_area or collision.collider == petting_hitbox:
			return true
	return false

func switch_to_screen(screen_index: int) -> void:
	if is_instance_valid(DesktopPet):
		DesktopPet.SwitchToScreen(screen_index, self)

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
	set_state(State.SLEEPING)

func _on_sit_pressed() -> void:
	toggle_menu(false)
	set_state(State.SITTING)

func _on_relax_pressed() -> void:
	toggle_menu(false)
	set_state(State.RELAXED)

func _on_reset_pressed() -> void:
	toggle_menu(false)
	is_wandering = false
	interaction_cooldown = 0.0 # Reset cooldown so wander can start right away
	set_state(State.NORMAL)
	start_wandering()

func _on_area_2d_area_entered(area):
	if (area is FoodArea or area.has_node("FoodAreaMarker")) and area != body_area and area.get_parent() != self:
		var target_node = area.get_parent()
		if target_node is CharacterBody2D and (target_node.get("dragging") == true or target_node.get("is_menu_open") == true):
			return
		mouth.play("default")

func _on_area_2d_area_exited(area):
	if (area is FoodArea or area.has_node("FoodAreaMarker")) and area != body_area and area.get_parent() != self:
		mouth.play("default", -1, true)
