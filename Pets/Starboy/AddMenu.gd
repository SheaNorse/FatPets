extends Control

@export var drag_smoothness := 25.0

# --- NODE REFERENCES ---
@onready var menu_area: Area2D = $Area2D

# --- DRAGGING & HOVER STATE ---
var dragging := false
var drag_offset := Vector2.ZERO
var drag_target := Vector2.ZERO

var is_currently_hovered := false
var hover_debounce_timer := 0.0
const HOVER_DEBOUNCE_DELAY := 0.15

# --- INITIALIZATION & LIFECYCLE ---
func _ready() -> void:
	visible = false
	modulate.a = 0.0

func _exit_tree() -> void:
	if is_instance_valid(DesktopPet):
		DesktopPet.ReportHoverState(false, get_menu_id())

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if is_instance_valid(DesktopPet):
			DesktopPet.ReportHoverState(false, get_menu_id())

# --- MAIN ENGINE PROCESS LOOP ---
func _process(delta: float) -> void:
	if not visible:
		return

	hover_debounce_timer -= delta

	if dragging:
		process_dragging(delta)
		return

	update_hover_status()

# --- INPUT & DRAGGING VIA AREA2D ---
func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventMouseButton):
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Only start dragging if over the Area2D and NOT clicking an interactive control
			if is_mouse_over_area() and not is_mouse_over_interactive_control() and not dragging:
				_start_drag(event.global_position)
				get_viewport().set_input_as_handled()
		elif dragging:
			_stop_drag()

func is_mouse_over_area() -> bool:
	if not menu_area or not visible:
		return false
		
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = get_global_mouse_position()
	query.collide_with_areas = true
	query.collide_with_bodies = false
	
	for collision in space_state.intersect_point(query, 32):
		if collision.collider == menu_area:
			return true
	return false

# Checks for interactive UI elements (Buttons, ScrollBars, Sliders) under the mouse
func is_mouse_over_interactive_control() -> bool:
	var mouse_pos = get_global_mouse_position()
	for node in find_children("*", "Control", true, false):
		var ctrl = node as Control
		if ctrl and ctrl.is_visible_in_tree():
			if ctrl is BaseButton or ctrl is ScrollBar or ctrl is Range:
				if ctrl.get_global_rect().has_point(mouse_pos):
					return true
	return false

func _start_drag(click_position: Vector2) -> void:
	dragging = true
	drag_offset = global_position - click_position
	
	if is_instance_valid(DesktopPet):
		DesktopPet.ReportHoverState(true, get_menu_id())

func _stop_drag() -> void:
	dragging = false
	update_hover_status()

func process_dragging(delta: float) -> void:
	var safe_delta = min(delta, 0.033)
	var current_mouse_pos = get_global_mouse_position()
	drag_target = current_mouse_pos + drag_offset
	
	var lerp_factor = 1.0 - exp(-drag_smoothness * safe_delta)
	global_position = global_position.lerp(drag_target, lerp_factor)

# --- HOVER & WIN32 PASSTHROUGH INTEGRATION ---
func update_hover_status() -> void:
	if not visible or dragging:
		return

	var mouse_over_menu = is_mouse_over_area() or is_mouse_over_controls()

	if mouse_over_menu != is_currently_hovered:
		if hover_debounce_timer <= 0:
			is_currently_hovered = mouse_over_menu
			if is_instance_valid(DesktopPet):
				DesktopPet.ReportHoverState(is_currently_hovered, get_menu_id())
			hover_debounce_timer = HOVER_DEBOUNCE_DELAY

func is_mouse_over_controls() -> bool:
	var mouse_pos = get_global_mouse_position()
	for node in find_children("*", "Control", true, false):
		if node.is_visible_in_tree() and node.get_global_rect().has_point(mouse_pos):
			return true
	return false

# --- MENU VISIBILITY CONTROLS ---
func open_menu(target_pos: Vector2 = Vector2.ZERO) -> void:
	visible = true
	modulate.a = 1.0
	move_to_front()
	
	if target_pos != Vector2.ZERO:
		# Center the menu on the target position
		var centered_pos = target_pos - (size / 1.0)
		
		# Clamp to monitor / window bounds
		var window_size = Vector2(DisplayServer.window_get_size())
		centered_pos.x = clamp(centered_pos.x, 0.0, max(0.0, window_size.x - size.x)) 
		centered_pos.y = clamp(centered_pos.y, 0.0, max(0.0, window_size.y - size.y)) - 400
		
		global_position = centered_pos

	is_currently_hovered = true
	if is_instance_valid(DesktopPet):
		DesktopPet.ReportHoverState(true, get_menu_id())

func close_menu() -> void:
	visible = false
	dragging = false
	if is_currently_hovered:
		is_currently_hovered = false
		if is_instance_valid(DesktopPet):
			DesktopPet.ReportHoverState(false, get_menu_id())

func toggle_menu(target_pos: Vector2 = Vector2.ZERO) -> void:
	if visible:
		close_menu()
	else:
		open_menu(target_pos)

func get_menu_id() -> String:
	return str(get_instance_id()) + "_add_menu"


func _on_cancel_pressed():
	close_menu()
