class_name PetResetState
extends PetState

func enter() -> void:
	pet.is_wandering = false
	pet.interaction_cooldown = 0.0
	pet.horizontal_velocity = 0.0
	pet.vertical_velocity = 0.0
	
	# Re-trigger wandering
	pet.start_wandering()
	
	# Instantly hand off control back to the Normal state
	if pet.state_machine:
		pet.state_machine.change_state("normal")

func allows_petting() -> bool:
	return true
