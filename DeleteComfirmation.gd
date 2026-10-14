extends Control

@export var fade_out_duration := 0.25

@onready var prompt_label: Label = $Name
@onready var delete_button: Button = $DeleteFrame/Delete
@onready var cancel_button: Button = $CancelFrame/Cancel

var current_target_node: Node = null

func _ready() -> void:
	visible = false
	
	if delete_button:
		delete_button.pressed.connect(_on_delete_pressed)
	if cancel_button:
		cancel_button.pressed.connect(_on_cancel_pressed)

	EventBus.delete_confirmation_requested.connect(_on_confirmation_requested)

func _on_confirmation_requested(target_node: Node, pet_name: String) -> void:
	current_target_node = target_node
	
	if prompt_label:
		prompt_label.text = "Are you sure you want to delete " + pet_name + "?"
		
	visible = true

func _on_delete_pressed() -> void:
	if is_instance_valid(current_target_node):
		EventBus.delete_confirmed.emit(current_target_node)
		
		# Reference target node for tweening
		var target = current_target_node
		
		# Create tween directly on the target slot node
		var tween = target.create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_OUT)
		
		# Fade out modulate alpha to 0
		tween.tween_property(target, "modulate:a", 0.0, fade_out_duration)
		
		# Queue free right after the tween completes
		tween.tween_callback(target.queue_free)
		
	current_target_node = null
	visible = false

func _on_cancel_pressed() -> void:
	current_target_node = null
	visible = false
