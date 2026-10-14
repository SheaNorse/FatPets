class_name BodySwap
extends Node

@export var body_scenes : Array[PackedScene]

func body_swap(index: int):
	if index < 0 or index >= body_scenes.size():
		return

	var old_pet: Pet = get_parent() as Pet

	# Guard: refuse to swap a pet that's already mid-swap/deleting
	if is_instance_valid(old_pet) and old_pet._is_deleting:
		return
	if is_instance_valid(old_pet):
		old_pet._is_deleting = true   # mark immediately, synchronously

	var new_body_scene: PackedScene = body_scenes[index]
	var new_body_node: Pet = new_body_scene.instantiate()
	new_body_node.total_food_points = old_pet.total_food_points

	get_tree().current_scene.add_child(new_body_node)

	if is_instance_valid(old_pet):
		new_body_node.initialize_from_swapped_pet(old_pet)
	else:
		new_body_node.global_position = get_parent().global_position

	new_body_node.play_eat_effects()
	new_body_node.play_eat_sfx()

	if is_instance_valid(old_pet):
		old_pet.queue_free()
