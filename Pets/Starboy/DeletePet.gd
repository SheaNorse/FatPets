extends Button

# Export an explicit node path if assigned in Inspector,
# otherwise defaults to targeting the container (e.g. TrashButton -> DeleteFrame -> Kink)
@export var target_to_delete: Node

func _ready() -> void:
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)

func _on_pressed() -> void:
	var node_to_free = target_to_delete
	
	# Fallback: target grandparent container (e.g., DeleteButton -> DeleteFrame -> Kink)
	if not node_to_free:
		node_to_free = get_parent().get_parent()

	if node_to_free:
		# Ask EventBus to pop up the confirmation modal for this node
		EventBus.delete_confirmation_requested.emit(node_to_free, node_to_free.name)
