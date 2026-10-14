extends Button

@export var pet_data: PetData
@export var fade_duration := 0.3 # Duration of the fade-in effect in seconds

func _ready() -> void:
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)

func _on_pressed() -> void:
	if not pet_data:
		push_error("PetSlot button clicked, but pet_data is missing on " + name)
		return

	if not pet_data.pet_scene:
		push_error("pet_scene is not assigned inside PetData for " + pet_data.pet_name)
		return

	print("Spawning pet with fade-in tween: ", pet_data.pet_name)
	
	var new_pet = pet_data.pet_scene.instantiate() as Node2D
	if new_pet:
		var main_scene = get_tree().current_scene
		main_scene.add_child(new_pet)
		
		# Position directly below the button
		var button_rect = get_global_rect()
		var spawn_x = button_rect.position.x + (button_rect.size.x / 2.0)
		var spawn_y = button_rect.position.y + button_rect.size.y + 10.0
		new_pet.global_position = Vector2(spawn_x, spawn_y)
		
		# --- MODULATION TWEEN ---
		# Start completely transparent
		new_pet.modulate.a = 0.0
		
		# Create tween on the newly spawned pet instance
		var tween = new_pet.create_tween()
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.set_ease(Tween.EASE_OUT)
		
		# Animate alpha from 0.0 to 1.0
		tween.tween_property(new_pet, "modulate:a", 1.0, fade_duration)
