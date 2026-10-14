extends Node

@export var body_swap : BodySwap
@export var thresholds : Array[int] = []

var next_threshold_index := 0  # tracks which milestone we're waiting for

func _ready() -> void:
	var pet_node = get_parent().get_parent()

	if pet_node and pet_node.has_signal("food_eaten"):
		if not pet_node.food_eaten.is_connected(_on_food_eaten):
			pet_node.food_eaten.connect(_on_food_eaten)

func _on_food_eaten(amount: int) -> void:
	if not body_swap:
		return

	# Only ever trigger the NEXT un-crossed threshold, and only once.
	while next_threshold_index < thresholds.size() and amount >= thresholds[next_threshold_index]:
		var index_to_swap := next_threshold_index
		next_threshold_index += 1
		body_swap.body_swap(index_to_swap)
		return  # stop after one swap — the new pet will have its own handler for the next milestone
