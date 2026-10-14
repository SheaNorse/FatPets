class_name PetStateMachine
extends Node

## Emitted whenever the active state changes
signal state_changed(old_state_name: String, new_state_name: String)

## Optional initial state. If left empty, defaults to the first child state node.
@export var initial_state_name: String = "normal"

var current_state: PetState = null
var current_state_name: String = ""

# Dictionary mapping lowercased state names to PetState nodes
# e.g., {"normal": $NormalState, "sitting": $SittingState}
var states: Dictionary = {}

## Initializes all child state nodes and sets the starting state.
func init(pet_instance: CharacterBody2D) -> void:
	states.clear()
	
	# Register all child PetState nodes dynamically
	for child in get_children():
		if child is PetState:
			var key := child.name.to_lower()
			states[key] = child
			child.pet = pet_instance
			child.state_machine = self

	if states.is_empty():
		push_error("PetStateMachine has no valid child PetState nodes!")
		return

	# Determine starting state
	var start_key := initial_state_name.to_lower()
	if not states.has(start_key):
		# Fallback to the first state found if specified initial state is missing
		start_key = states.keys()[0]

	# Set up initial state without calling exit() on null
	current_state = states[start_key]
	current_state_name = start_key
	current_state.enter()
	
	state_changed.emit("", current_state_name)

## Passes physics updates directly to the active state.
func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_update(delta)

## Passes frame updates directly to the active state.
func _process(delta: float) -> void:
	if current_state:
		current_state.update(delta)

## Transitions from the current state to a target state by name.
func change_state(target_state_name: String) -> void:
	var target_key := target_state_name.to_lower()

	if not states.has(target_key):
		push_warning("State machine does not contain state: " + target_state_name)
		return

	var new_state: PetState = states[target_key]
	
	# Prevent redundant transitions to the same state
	if current_state == new_state:
		return

	var old_state_name := current_state_name

	# Exit current state
	if current_state:
		current_state.exit()

	# Enter new state
	current_state = new_state
	current_state_name = target_key
	current_state.enter()

	# Notify listeners (like StateButton)
	state_changed.emit(old_state_name, current_state_name)

## Returns the current active state's normalized name.
func get_current_state_name() -> String:
	return current_state_name
