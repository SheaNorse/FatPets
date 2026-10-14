extends Button

@export var pet_scene: PackedScene
@export var fade_duration := 0.3 # Duration of the fade-in effect in seconds

func _ready() -> void:
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)

func _on_pressed() -> void:
	if not pet_scene:
		push_error("pet_scene is not assigned on " + name)
		return

	print("Spawning pet with fade-in tween.")
	
	var new_pet = pet_scene.instantiate() as Node2D
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
