class_name PetRelaxState
extends PetState

func allows_wandering() -> bool:
	return false

func enter() -> void:
	pet.is_wandering = false
	pet.interaction_cooldown = 0.0
	pet.horizontal_velocity = 0.0
	
	# Reset visual elements to normal idle/relaxed state
	if pet.body: 
		pet.body.play("Breathing")
	if pet.eyes: 
		pet.eyes.visible = true
		pet.eyes.play("Blinking")
		# Reset eyes to base position in case previous state was Sitting
		pet.eyes.position = Vector2(pet.eyes_base_x if not pet.body.flip_h else -pet.eyes_base_x, pet.eyes_default_position.y)
	if pet.mouth: 
		pet.mouth.visible = true

func physics_update(_delta: float) -> void:
	# Guarantee the pet cannot slide or wander while relaxing
	if pet:
		pet.horizontal_velocity = 0.0
		pet.is_wandering = false

func allows_petting() -> bool:
	return true
