class_name StateButton
extends Button

var state_machine: PetStateMachine

## Called by Pet.gd to bind this button to the active state machine
func setup(sm: PetStateMachine) -> void:
	state_machine = sm
	
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)
		
	if state_machine and not state_machine.state_changed.is_connected(_on_state_changed):
		state_machine.state_changed.connect(_on_state_changed)
		
	# Sync visual state on startup
	_update_selected_visual(state_machine.get_current_state_name())

func _on_pressed() -> void:
	if state_machine:
		# Use button node name directly as target state key
		state_machine.change_state(name)

func _on_state_changed(_old_state: String, new_state: String) -> void:
	_update_selected_visual(new_state)

func _update_selected_visual(active_state_name: String) -> void:
	# Disable the button if its node name matches the active state
	var is_selected := (active_state_name.to_lower() == name.to_lower())
	disabled = is_selected
