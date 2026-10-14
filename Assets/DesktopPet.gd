class_name Pet
extends CharacterBody2D

signal food_eaten(amount: int)

@export var invert_facing_direction := false
@export var enable_drag_autoflip := true # <--- TOGGLE FOR DRAG AUTO-FLIPPING
@export var enable_squish := true        # <--- TOGGLE FOR MOVEMENT/PHYSICS SQUISHES (Pickup, Landing, Flip)
@export var enable_eat_squish := true    # <--- TOGGLE FOR EATING SQUISHES
@export var floor_offset := 20.0

@export_category("Eating Settings")
@export var is_edible := false
@export var can_eat := true
@export var food_points: int = 10  # Point value if THIS pet gets eaten by another pet
@export var total_food_points: int = 0 # Track total points accumulated

@export_category("Physics & Movement")
@export var gravity_strength := 1000.0
@export var drag_smoothness := 25.0
@export var bounce_strength := 0.5
@export var bounce_damping := 0.8
@export var throw_multiplier := 1.0

@export_category("Wander Settings")
@export var allow_wandering := true
@export var walk_speed := 150.0
@export var walk_acceleration := 600.0
@export var walk_friction := 800.0
## Average wait time in seconds before the pet wanders
@export var wander_interval := 8.0

@export_category("Petting & Rubbing Settings")
@export var allow_petting := true
@export var rub_velocity_threshold := 800.0 
@export var rub_decay_time := 0.4
@export var food_over_grace_time := 0.25
@export var rub_distance_threshold := 150.0
@export var rub_intensity_decay := 500.0

var wander_timer := 0.0
var is_wandering := false
var wander_direction := 1.0 

# --- NODE REFERENCES (OPTIONAL & SAFE) ---
@onready var state_machine: PetStateMachine = $StateMachine if has_node("StateMachine") else null
@onready var SFX: AudioStreamPlayer = $AudioStreamPlayer if has_node("AudioStreamPlayer") else null
@onready var body_area: Area2D = $Area2D if has_node("Area2D") else null
@onready var main_menu: Control = $MainMenu if has_node("MainMenu") else null
@onready var state_menu: Control = $StateMenu if has_node("StateMenu") else null
@onready var body: AnimatedSprite2D = $Body if has_node("Body") else null
@onready var eyes: AnimatedSprite2D = $Body/Eyes if has_node("Body/Eyes") else null
@onready var mouth: AnimatedSprite2D = $Body/Eyes/Mouth if has_node("Body/Eyes/Mouth") else null

# --- PARTICLES NODE ---
@onready var particles_node: Node2D = $Particles if has_node("Particles") else null
@onready var heart_particles: CPUParticles2D = $Particles/Petting if has_node("Particles/Petting") else null
@onready var sleeping_particles: CPUParticles2D = $Particles/Sleeping if has_node("Particles/Sleeping") else null

# --- STATE TRACKING ---
var dragging := false
var drag_target := Vector2.ZERO
var offset := Vector2.ZERO
var interaction_cooldown := 0.0
const INTERACTION_COOLDOWN_TIME := 1.0
var previous_mouse_pos := Vector2.ZERO
var vertical_velocity := 0.0
var horizontal_velocity := 0.0
var drag_velocity := Vector2.ZERO
var rub_timer := 0.0
var rub_intensity := 0.0
var food_over_grace_timer := 0.0
static var dragging_instance: int = -1

# --- PER-INSTANCE HOVER STATE ---
var is_currently_hovered := false
var hover_debounce_timer := 0.0
const HOVER_DEBOUNCE_DELAY := 0.15

# --- CACHED OFFSETS & BASE SCALES ---
var eyes_base_x := 0.0
var mouth_base_x := 0.0
var heart_particles_base_x := 0.0
var sleeping_particles_base_x := 0.0
var eyes_default_position := Vector2.ZERO
var body_base_scale := Vector2.ONE
var is_menu_open := false
var state_enabled := false
var was_grounded := false
var _is_deleting := false

# --- MENU ANIMATION TRACKING & BASE POSITIONS ---
var main_menu_base_pos := Vector2.ZERO
var state_menu_base_pos := Vector2.ZERO
var main_menu_tween: Tween
var state_menu_tween: Tween
const MENU_ANIM_DURATION := 0.2
const MENU_SLIDE_OFFSET := 12.0

# --- EAT, DELETE, FLOOR & SQUISH TWEENS ---
var eat_tween: Tween
var delete_tween: Tween
var floor_adjust_tween: Tween
var squish_tween: Tween

# --- PERFORMANCE CACHES ---
var _window_size := Vector2.ZERO
var _last_mouse_pos := Vector2.INF
var _cached_mouse_over := false
var _current_body_anim := ""
const MOUSE_CHECK_THRESHOLD_SQ := 4.0  # 2px squared


# --- INITIALIZATION ---
func _ready() -> void:
	input_pickable = true
	randomize()
	
	_window_size = DisplayServer.window_get_size()
	
	if body:
		body_base_scale = body.scale
		
	if eyes:
		eyes_default_position = eyes.position
		
	if sleeping_particles:
		sleeping_particles_base_x = sleeping_particles.position.x
		sleeping_particles.emitting = false
		
	if heart_particles:
		heart_particles.emitting = false
	
	global_position = Vector2(_window_size.x / 2.0, 50.0)
	vertical_velocity = 100.0
	
	if main_menu:
		main_menu_base_pos = main_menu.position
		main_menu.visible = false
		main_menu.modulate.a = 0.0
	if state_menu:
		state_menu_base_pos = state_menu.position
		state_menu.visible = false
		state_menu.modulate.a = 0.0
	
	_resolve_flip_offsets()
	connect_menu_buttons()
	_setup_edible_status()
	if is_instance_valid(FloorManager):
		FloorManager.floor_offset_changed.connect(_on_floor_offset_changed)
	if state_machine:
		state_machine.init(self)
		setup_state_buttons()
		if state_machine.current_state == null:
			set_state("normal")


## Call this on the new pet instance during a body swap to transfer state,
## facing direction, and prevent the single-frame falling animation.
func initialize_from_swapped_pet(old_pet: Pet) -> void:
	if not is_instance_valid(old_pet):
		return
		
	# 1. Sync transform and movement physics directly
	global_position = old_pet.global_position
	rotation = old_pet.rotation
	horizontal_velocity = old_pet.horizontal_velocity
	vertical_velocity = 0.0  # Reset vertical momentum
	
	# 2. Sync grounding and wandering state flags BEFORE visual updates
	was_grounded = old_pet.was_grounded
	is_wandering = old_pet.is_wandering
	wander_direction = old_pet.wander_direction
	
	# 3. Transfer facing direction (flip status & offsets)
	if old_pet.body:
		var is_flipped: bool = old_pet.body.flip_h
		_apply_facing_flip(is_flipped)
		
	# 4. Transfer state & totals
	total_food_points = old_pet.total_food_points
	if old_pet.state_machine and old_pet.state_machine.current_state:
		set_state(old_pet.state_machine.get_current_state_name())
		
	# 5. Lock in correct visual frame and suppress falling state on frame 1
	if was_grounded:
		if is_wandering and body and body.sprite_frames and body.sprite_frames.has_animation("Walking"):
			play_body_anim("Walking")
			if eyes: eyes.visible = false
			if mouth: mouth.visible = false
		else:
			play_body_anim("Breathing")
			if eyes: 
				eyes.visible = true
				if eyes.sprite_frames and eyes.sprite_frames.has_animation("Blinking"):
					eyes.play("Blinking")
			if mouth: mouth.visible = true
			
	# 6. Force immediate global position & canvas update to prevent 1-frame layout sync lag
	force_update_transform()


# --- SQUISH & FLIP EFFECTS ---
func play_flip_effect() -> void:
	if not body or not enable_squish: return
	
	if squish_tween and squish_tween.is_running():
		squish_tween.kill()
		body.scale = body_base_scale
		
	var target_x = abs(body_base_scale.x)
	var target_y = abs(body_base_scale.y)
	
	squish_tween = create_tween()
	# Squash X, stretch Y during directional turn
	squish_tween.tween_property(body, "scale", Vector2(target_x * 0.8, target_y * 1.15), 0.06) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	squish_tween.tween_property(body, "scale", body_base_scale, 0.1) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func play_pickup_squish() -> void:
	if not body or not enable_squish: return
	
	if squish_tween and squish_tween.is_running():
		squish_tween.kill()
		body.scale = body_base_scale
		
	var target_x = abs(body_base_scale.x)
	var target_y = abs(body_base_scale.y)
	
	squish_tween = create_tween()
	# Stretch vertically when pulled off the floor
	squish_tween.tween_property(body, "scale", Vector2(target_x * 0.75, target_y * 1.25), 0.08) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	squish_tween.tween_property(body, "scale", body_base_scale, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func play_landing_squish(impact_velocity: float) -> void:
	if not body or not enable_squish: return
	
	if squish_tween and squish_tween.is_running():
		squish_tween.kill()
		body.scale = body_base_scale
		
	# Scale intensity dynamically based on fall speed (clamped for safety)
	var intensity = clamp(impact_velocity / 1200.0, 0.15, 0.45)
	var target_x = abs(body_base_scale.x)
	var target_y = abs(body_base_scale.y)
	
	squish_tween = create_tween()
	# Compress vertically and expand horizontally on floor impact
	squish_tween.tween_property(body, "scale", Vector2(target_x * (1.0 + intensity), target_y * (1.0 - intensity)), 0.08) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	squish_tween.tween_property(body, "scale", body_base_scale, 0.15) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func play_body_anim(anim_name: String) -> void:
	if not body or not body.sprite_frames or not body.sprite_frames.has_animation(anim_name):
		return
	if _current_body_anim == anim_name and body.is_playing():
		return
	_current_body_anim = anim_name
	body.play(anim_name)


func _on_floor_offset_changed(_new_offset: float) -> void:
	if _is_deleting or dragging:
		return
		
	var target_floor_y = calculate_floor_y()
	
	if was_grounded or abs(global_position.y - target_floor_y) < 50.0:
		if floor_adjust_tween and floor_adjust_tween.is_running():
			floor_adjust_tween.kill()
			
		floor_adjust_tween = create_tween()
		floor_adjust_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		floor_adjust_tween.tween_property(self, "global_position:y", target_floor_y, 0.2)


func calculate_floor_y() -> float:
	if is_instance_valid(FloorManager):
		return FloorManager.get_local_floor_y(_window_size.y, floor_offset)
	return _window_size.y - floor_offset


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


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if is_instance_valid(DesktopPet):
			DesktopPet.ReportHoverState(false, get_unique_id())
			DesktopPet.ReportHoverState(false, get_menu_id())
	elif what == NOTIFICATION_WM_SIZE_CHANGED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_window_size = DisplayServer.window_get_size()


func _process(delta: float) -> void:
	if _is_deleting:
		return
		
	if dragging_instance == get_instance_id() and not dragging:
		dragging_instance = -1
		
	interaction_cooldown = maxf(interaction_cooldown - delta, 0.0)
	hover_debounce_timer = maxf(hover_debounce_timer - delta, 0.0)
	
	if state_machine:
		state_machine._process(delta)
		
	if dragging:
		process_dragging(delta)
		return
		
	# Fast path for fully idle grounded pets
	var is_idle := was_grounded and not is_wandering and rub_timer <= 0.0 and not is_menu_open
	if is_idle:
		update_hover_status()          # still needed for click-through
		apply_physics_and_wander(delta)
		return
		
	update_hover_status()
	process_rubbing(delta)
	
	if absf(rotation) > 0.01:
		rotation = lerpf(rotation, 0.0, 10.0 * delta)
	
	apply_physics_and_wander(delta)


func _unhandled_input(event: InputEvent) -> void:
	if _is_deleting:
		return
	if is_menu_open and event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			if not is_mouse_over_menu() and not is_mouse_over():
				toggle_menu(false)


func _input(event: InputEvent) -> void:
	if _is_deleting or not (event is InputEventMouseButton):
		return
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and is_mouse_over():
		bring_to_front()
		toggle_menu(!is_menu_open)
		get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if is_mouse_over() and dragging_instance == -1:
				_start_drag(event.global_position)
		elif dragging:
			_stop_drag()


func _start_drag(click_position: Vector2) -> void:
	if floor_adjust_tween and floor_adjust_tween.is_running():
		floor_adjust_tween.kill()
	dragging_instance = get_instance_id()
	dragging = true
	bring_to_front()
	set_state("normal")
	is_wandering = false
	toggle_menu(false)
	offset = global_position - click_position
	previous_mouse_pos = get_global_mouse_position()
	drag_velocity = Vector2.ZERO
	vertical_velocity = 0.0
	horizontal_velocity = 0.0
	interaction_cooldown = INTERACTION_COOLDOWN_TIME
	play_pickup_squish()
	rub_timer = 0.0
	rub_intensity = 0.0
	if heart_particles:
		heart_particles.emitting = false
	if is_instance_valid(DesktopPet):
		DesktopPet.ReportHoverState(true, get_unique_id())
	is_currently_hovered = true


func _stop_drag() -> void:
	if dragging_instance == get_instance_id():
		dragging_instance = -1
	dragging = false
	call_deferred("_check_eat_on_release")
	horizontal_velocity = drag_velocity.x * throw_multiplier
	vertical_velocity = drag_velocity.y * throw_multiplier
	interaction_cooldown = INTERACTION_COOLDOWN_TIME
	is_currently_hovered = false
	if is_instance_valid(DesktopPet):
		DesktopPet.ReportHoverState(false, get_unique_id())


func apply_physics_and_wander(delta: float) -> void:
	var floor_y = calculate_floor_y()
	var grounded = global_position.y >= floor_y - 1.0
	
	if grounded and not was_grounded:
		play_landing_squish(vertical_velocity)
		if state_machine and (state_machine.current_state == null or not state_machine.current_state.has_method("allows_wandering") or not state_machine.current_state.allows_wandering()):
			set_state("normal")
	was_grounded = grounded
	
	if is_menu_open:
		is_wandering = false
		horizontal_velocity = 0.0
		vertical_velocity += gravity_strength * delta
		global_position.y += vertical_velocity * delta
		if global_position.y >= floor_y:
			vertical_velocity = 0.0
			global_position.y = floor_y
			rotation = 0.0
			_snap_position_to_pixel()
		return
		
	if rub_timer > 0:
		horizontal_velocity = 0.0
		
		vertical_velocity += gravity_strength * delta
		global_position.y += vertical_velocity * delta
		
		if global_position.y >= floor_y:
			vertical_velocity = 0.0
			global_position.y = floor_y
			rotation = 0.0
			_snap_position_to_pixel()
		return
		
	var current_state_allows_wandering = true
	if state_machine and state_machine.current_state and state_machine.current_state.has_method("allows_wandering"):
		current_state_allows_wandering = state_machine.current_state.allows_wandering()
		
	var is_in_normal_state = (state_machine and state_machine.get_current_state_name() == "normal")
	
	if grounded:
		if not allow_wandering or not current_state_allows_wandering:
			is_wandering = false
			horizontal_velocity = move_toward(horizontal_velocity, 0.0, walk_friction * delta)
		else:
			var chance_this_frame = (1.0 / max(wander_interval, 0.1)) * delta
			if not is_wandering and rub_timer <= 0 and randf() < chance_this_frame and interaction_cooldown <= 0:
				start_wandering()
			
			if is_wandering:
				wander_timer -= delta
				var target_speed = wander_direction * walk_speed
				horizontal_velocity = move_toward(horizontal_velocity, target_speed, walk_acceleration * delta)
				
				if wander_timer <= 0:
					is_wandering = false
			else:
				horizontal_velocity = move_toward(horizontal_velocity, 0.0, walk_friction * delta)
				
		if is_in_normal_state:
			var has_walking_anim = body and body.sprite_frames and body.sprite_frames.has_animation("Walking")
			
			if is_wandering and has_walking_anim:
				play_body_anim("Walking")
				if eyes: eyes.visible = false
				if mouth: mouth.visible = false
			else:
				play_body_anim("Breathing")
				if eyes:
					eyes.visible = true
					if eyes.sprite_frames and eyes.sprite_frames.has_animation("Blinking"):
						eyes.play("Blinking")
				if mouth: mouth.visible = true
	else:
		is_wandering = false
		horizontal_velocity *= 0.98
		if eyes: eyes.visible = false
		if mouth: mouth.visible = false
		play_body_anim("Falling")
		
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
			_snap_position_to_pixel()
		vertical_velocity *= bounce_damping


func process_dragging(delta: float) -> void:
	play_body_anim("Falling")
	if eyes: eyes.visible = false
	if mouth: mouth.visible = false
		
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
	
	# --- AUTO-FLIP SPRITE & PLAY TWEEN WHEN DRAGGING (IF ENABLED) ---
	if enable_drag_autoflip and abs(mouse_move_x) > 5.0:
		var should_flip: bool = (mouse_move_x > 0.0)
		if invert_facing_direction:
			should_flip = !should_flip
		
		if body and body.flip_h != should_flip:
			_apply_facing_flip(should_flip)
			play_flip_effect()
			
	previous_mouse_pos = current_mouse_pos


func start_wandering() -> void:
	is_wandering = true
	wander_timer = randf_range(1.5, 4.0)
	wander_direction = 1.0 if randf() > 0.5 else -1.0
	
	var is_flipped = (wander_direction > 0)
	if invert_facing_direction:
		is_flipped = !is_flipped
		
	_apply_facing_flip(is_flipped)


func _apply_facing_flip(is_flipped: bool) -> void:
	if body: body.flip_h = is_flipped
	if eyes:
		eyes.flip_h = is_flipped
		if state_machine and state_machine.current_state and state_machine.current_state.has_method("update_eye_position"):
			state_machine.current_state.update_eye_position()
		else:
			eyes.position.x = -eyes_base_x if is_flipped else eyes_base_x
	if mouth:
		mouth.flip_h = is_flipped
		mouth.position.x = -mouth_base_x if is_flipped else mouth_base_x
		
	if heart_particles:
		heart_particles.position.x = -heart_particles_base_x if is_flipped else heart_particles_base_x
		
	if sleeping_particles:
		sleeping_particles.position.x = -sleeping_particles_base_x if is_flipped else sleeping_particles_base_x
		var base_dir = abs(sleeping_particles.direction.x) if sleeping_particles.direction.x != 0 else 1.0
		sleeping_particles.direction.x = -base_dir if is_flipped else base_dir


func can_be_petted() -> bool:
	if not allow_petting or _is_deleting or is_menu_open or dragging or not was_grounded:
		return false
		
	if rub_timer <= 0 and abs(horizontal_velocity) > 10.0:
		return false
		
	if state_machine and state_machine.current_state:
		if state_machine.current_state.has_method("allows_petting"):
			if not state_machine.current_state.allows_petting():
				return false
				
	if _is_food_being_held_over():
		return false
		
	return true


func _is_food_being_held_over() -> bool:
	var delta := get_process_delta_time()
	var found := false
	if body_area:
		for area in body_area.get_overlapping_areas():
			if area == body_area or area.get_parent() == self:
				continue
			var target_node = area.get_parent()
			if _is_food_area(area):
				if target_node and target_node.has_method("get") and target_node.get("dragging") == true:
					found = true
					break
				elif not (target_node is CharacterBody2D):
					continue
			if target_node is CharacterBody2D:
				if target_node.get("is_edible") == true and target_node.get("dragging") == true:
					found = true
					break
	if found:
		food_over_grace_timer = food_over_grace_time
	else:
		food_over_grace_timer = max(food_over_grace_timer - delta, 0.0)
	return found or food_over_grace_timer > 0.0


func process_rubbing(delta: float) -> void:
	var current_mouse_pos := get_viewport().get_mouse_position()
	var mouse_delta := current_mouse_pos - previous_mouse_pos
	var mouse_distance := mouse_delta.length()
	previous_mouse_pos = current_mouse_pos
	
	# Only do expensive checks if the mouse is actually moving reasonably fast
	if mouse_distance > 1.0 and can_be_petted() and is_mouse_over():
		var mouse_velocity := mouse_distance / maxf(delta, 0.001)
		if mouse_velocity >= rub_velocity_threshold:
			rub_intensity += mouse_distance
			
	rub_intensity = maxf(rub_intensity - rub_intensity_decay * delta, 0.0)
	
	if rub_intensity >= rub_distance_threshold:
		rub_timer = rub_decay_time
		
	if rub_timer > 0.0:
		rub_timer -= delta
		horizontal_velocity = 0.0
		
		if heart_particles:
			heart_particles.emitting = true
			
		var is_in_normal_state := state_machine and state_machine.get_current_state_name() == "normal"
		if is_in_normal_state:
			play_body_anim("Breathing")
			
		if mouth:
			mouth.visible = true
		if eyes:
			eyes.visible = true
			if eyes.sprite_frames and eyes.sprite_frames.has_animation("Closed") and eyes.animation != "Closed":
				eyes.play("Closed")
	else:
		if heart_particles and heart_particles.emitting:
			heart_particles.emitting = false
		if eyes and eyes.animation == "Closed":
			if eyes.sprite_frames and eyes.sprite_frames.has_animation("Blinking"):
				eyes.play("Blinking")


func play_eat_effects() -> void:
	if not body: return
	if eat_tween and eat_tween.is_running():
		eat_tween.kill()
		
	var base_scale := body_base_scale
	eat_tween = create_tween().set_parallel(true)
	
	eat_tween.tween_property(body, "self_modulate", Color(1.2, 1.2, 1.2, 1.0), 0.001)
	eat_tween.tween_property(body, "self_modulate", Color(1.0, 1.0, 1.0, 1.0), 0.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).set_delay(0.03)
	
	if enable_eat_squish:
		eat_tween.tween_property(body, "scale", base_scale * Vector2(1.04, 0.97), 0.1) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		eat_tween.tween_property(body, "scale", base_scale, 0.15) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_delay(0.1)


func _check_eat_on_release() -> void:
	if not body_area or _is_deleting: return
	for area in body_area.get_overlapping_areas():
		if area == body_area or area.get_parent() == self:
			continue
			
		var target_node = area.get_parent()
		if _is_food_area(area):
			if not (target_node is CharacterBody2D):
				_consume_target(area)
				return
		if can_eat and target_node is CharacterBody2D:
			if target_node.get("is_edible") == true and target_node.get("is_menu_open") != true:
				_consume_target(target_node)
				return
		if is_edible and target_node is CharacterBody2D:
			if target_node.get("can_eat") == true and target_node.get("is_menu_open") != true:
				if target_node.has_method("_consume_target"):
					target_node._consume_target(self)
				else:
					_consume_target(self)
				return


func _is_food_area(area: Area2D) -> bool:
	if area is FoodArea or area.has_node("FoodAreaMarker") or area.name == "FoodArea":
		return true
	return area.get_parent() != null and area.get_parent().name.to_lower().contains("food")


func _get_food_points_from_target(target: Node) -> int:
	if target.has_method("get_food_points"):
		return target.get_food_points()
	elif target.get("food_points") != null:
		return int(target.get("food_points"))
	return 10


func _consume_target(node_to_destroy: Node) -> void:
	var points_gained := _get_food_points_from_target(node_to_destroy)
	total_food_points += points_gained
	food_eaten.emit(total_food_points)
	print(total_food_points)
	
	play_eat_effects()
	play_eat_sfx(node_to_destroy)
	
	if node_to_destroy.has_method("fade_and_delete"):
		node_to_destroy.fade_and_delete()
	else:
		node_to_destroy.queue_free()


func play_eat_sfx(target_node: Node = null) -> void:
	if SFX and SFX.stream:
		SFX.play()
		return
	if target_node:
		var target_sfx = target_node.get("SFX")
		if target_sfx is AudioStreamPlayer and target_sfx.stream:
			if SFX:
				SFX.stream = target_sfx.stream
				SFX.play()
			else:
				target_sfx.play()


func play_sfx() -> void:
	if SFX: SFX.play()


func set_state(new_state_name: String) -> void:
	if state_machine: state_machine.change_state(new_state_name)


func setup_state_buttons() -> void:
	if not state_menu or not state_machine: return
	for child in state_menu.find_children("*", "StateButton", true, false):
		child.setup(state_machine)
		if not child.pressed.is_connected(_close_menu_on_button):
			child.pressed.connect(_close_menu_on_button)


func _close_menu_on_button() -> void:
	toggle_menu(false)


func _setup_edible_status() -> void:
	if not body_area: return
		
	if is_edible:
		if not body_area is FoodArea and not body_area.has_node("FoodAreaMarker"):
			var food_marker = Node.new()
			food_marker.name = "FoodAreaMarker"
			body_area.add_child(food_marker)
	else:
		if body_area.has_node("FoodAreaMarker"):
			body_area.get_node("FoodAreaMarker").queue_free()


func _resolve_flip_offsets() -> void:
	if eyes: eyes_base_x = eyes.position.x
	if mouth: mouth_base_x = mouth.position.x
	if heart_particles: heart_particles_base_x = heart_particles.position.x
	if sleeping_particles: sleeping_particles_base_x = sleeping_particles.position.x


func get_unique_id() -> String: return str(get_instance_id())
func get_menu_id() -> String: return str(get_instance_id()) + "_menu"


func _snap_position_to_pixel() -> void:
	global_position = global_position.round()


func bring_to_front() -> void:
	var parent = get_parent()
	if parent: parent.move_child(self, parent.get_child_count() - 1)


func _animate_menu(menu: Control, base_pos: Vector2, open: bool, active_tween: Tween) -> Tween:
	if not menu: return active_tween
	
	if active_tween and active_tween.is_running():
		active_tween.kill()
	active_tween = create_tween().set_parallel(true)
	
	if open:
		menu.visible = true
		menu.position = base_pos + Vector2(0, MENU_SLIDE_OFFSET)
		menu.modulate.a = 0.0
		
		active_tween.tween_property(menu, "position", base_pos, MENU_ANIM_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		active_tween.tween_property(menu, "modulate:a", 1.0, MENU_ANIM_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		var target_pos = base_pos + Vector2(0, MENU_SLIDE_OFFSET)
		active_tween.tween_property(menu, "position", target_pos, MENU_ANIM_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		active_tween.tween_property(menu, "modulate:a", 0.0, MENU_ANIM_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		
		active_tween.chain().tween_callback(func(): menu.visible = false)
	return active_tween


func toggle_menu(open: bool) -> void:
	if _is_deleting: return
	is_menu_open = open
	
	if open:
		bring_to_front()
		is_wandering = false
		horizontal_velocity = 0.0
		rub_timer = 0.0
		rub_intensity = 0.0
		if heart_particles:
			heart_particles.emitting = false
		main_menu_tween = _animate_menu(main_menu, main_menu_base_pos, true, main_menu_tween)
	else:
		state_enabled = false
		main_menu_tween = _animate_menu(main_menu, main_menu_base_pos, false, main_menu_tween)
		state_menu_tween = _animate_menu(state_menu, state_menu_base_pos, false, state_menu_tween)
		
	if is_instance_valid(DesktopPet):
		if is_menu_open:
			DesktopPet.ReportHoverState(true, get_menu_id())
		else:
			DesktopPet.ReportHoverState(false, get_menu_id())
			is_currently_hovered = is_mouse_over()
			DesktopPet.ReportHoverState(is_currently_hovered, get_unique_id())


func update_hover_status() -> void:
	if dragging or is_menu_open or _is_deleting: return
	
	var mouse_over_pet = is_mouse_over()
	var mouse_over_menu = is_mouse_over_menu()
	var should_be_solid = mouse_over_pet or mouse_over_menu
	
	if should_be_solid != is_currently_hovered:
		if hover_debounce_timer <= 0:
			is_currently_hovered = should_be_solid
			if is_instance_valid(DesktopPet):
				DesktopPet.ReportHoverState(is_currently_hovered, get_unique_id())
			hover_debounce_timer = HOVER_DEBOUNCE_DELAY


func is_mouse_over_menu() -> bool:
	var active_menus = [main_menu, state_menu]
	var mouse_pos = get_global_mouse_position()
	for menu in active_menus:
		if menu and menu.visible:
			for node in menu.find_children("*", "Control", true, false):
				if node.is_visible_in_tree() and node.get_global_rect().has_point(mouse_pos):
					return true
	return false


func handle_side_bounces() -> void:
	if global_position.x <= 0.0:
		global_position.x = 0.0
		horizontal_velocity = absf(horizontal_velocity) * bounce_strength
		is_wandering = false
	elif global_position.x >= _window_size.x:
		global_position.x = _window_size.x
		horizontal_velocity = -absf(horizontal_velocity) * bounce_strength
		is_wandering = false


func is_mouse_over() -> bool:
	if _is_deleting or not body_area:
		return false
		
	var mouse_pos := get_global_mouse_position()
	if mouse_pos.distance_squared_to(_last_mouse_pos) < MOUSE_CHECK_THRESHOLD_SQ:
		return _cached_mouse_over
		
	_last_mouse_pos = mouse_pos
	
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = mouse_pos
	query.collide_with_areas = true
	query.collide_with_bodies = true
	
	_cached_mouse_over = false
	for collision in space_state.intersect_point(query, 8):
		if collision.collider == body_area:
			_cached_mouse_over = true
			break
	return _cached_mouse_over


func connect_menu_buttons() -> void:
	if not main_menu: return
	
	var state_btn = main_menu.find_child("State", true, false)
	var add_btn = main_menu.find_child("Add", true, false)
	var delete_btn = main_menu.find_child("Delete", true, false)
	
	if state_btn: state_btn.pressed.connect(_on_state_pressed)
	if add_btn: add_btn.pressed.connect(_on_add_pressed)
	if delete_btn: delete_btn.pressed.connect(_on_delete_pressed)


func _on_add_pressed() -> void:
	toggle_menu(false)
	if is_instance_valid(AddMenu):
		var add_menu_parent = AddMenu.get_parent()
		if add_menu_parent:
			add_menu_parent.move_child(AddMenu, add_menu_parent.get_child_count() - 1)
			
		AddMenu.toggle_menu(global_position)


func _on_state_pressed() -> void:
	state_enabled = !state_enabled
	state_menu_tween = _animate_menu(state_menu, state_menu_base_pos, state_enabled, state_menu_tween)


func _on_delete_pressed() -> void:
	toggle_menu(false)
	fade_and_delete()


func fade_and_delete(duration: float = 0.2) -> void:
	if _is_deleting: return
	_is_deleting = true
	
	input_pickable = false
	if body_area:
		body_area.monitoring = false
		body_area.monitorable = false
		
	if is_instance_valid(DesktopPet):
		DesktopPet.ReportHoverState(false, get_unique_id())
		DesktopPet.ReportHoverState(false, get_menu_id())
	
	if delete_tween and delete_tween.is_running():
		delete_tween.kill()
		
	delete_tween = create_tween()
	delete_tween.tween_property(self, "modulate:a", 0.0, duration) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_OUT)
	delete_tween.tween_callback(queue_free)


func _on_area_2d_area_entered(area):
	if _is_deleting: return
	if area != body_area and area.get_parent() != self:
		var target_node = area.get_parent()
		if _is_food_area(area) or (can_eat and target_node is CharacterBody2D and target_node.get("is_edible") == true):
			if mouth and mouth.sprite_frames and mouth.sprite_frames.has_animation("default"):
				mouth.play("default")


func _on_area_2d_area_exited(area):
	if _is_deleting: return
	if area != body_area and area.get_parent() != self:
		if mouth and mouth.sprite_frames and mouth.sprite_frames.has_animation("default"):
			mouth.play("default", -1, true)
