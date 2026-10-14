class_name PetSittingState
extends PetState

@export var eye_offset : Node2D

func allows_wandering() -> bool:
	return false

func enter() -> void:
	pet.is_wandering = false
	pet.horizontal_velocity = 0.0
	pet.play_body_anim("Sitting")
	if pet.eyes:
		pet.eyes.visible = true
		if pet.eyes.sprite_frames and pet.eyes.sprite_frames.has_animation("Blinking"):
			pet.eyes.play("Blinking")
		update_eye_position()
	if pet.mouth: pet.mouth.visible = true

func exit() -> void:
	if pet.eyes:
		var target_x = pet.eyes_base_x
		if pet.body and pet.body.flip_h:
			target_x = -target_x
		pet.eyes.position = Vector2(target_x, pet.eyes_default_position.y)

func update_eye_position() -> void:
	if pet and pet.eyes and eye_offset:
		var target_x = eye_offset.global_position.x
		if pet.body and pet.body.flip_h:
			target_x = -target_x
		pet.eyes.position = Vector2(target_x, eye_offset.global_position.y)

func allows_petting() -> bool:
	return true
