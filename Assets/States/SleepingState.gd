class_name PetSleepingState
extends PetState

func allows_wandering() -> bool:
	return false

func enter() -> void:
	pet.is_wandering = false
	pet.horizontal_velocity = 0.0
	if pet.body: pet.body.play("Sleeping")
	if pet.eyes: pet.eyes.visible = false
	if pet.mouth: pet.mouth.visible = false
	if pet.sleeping_particles: pet.sleeping_particles.emitting = true

func exit() -> void:
	if pet.sleeping_particles: pet.sleeping_particles.emitting = false
