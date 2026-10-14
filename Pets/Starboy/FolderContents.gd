extends Control

@export var fade_duration : float = 0.1
var tween : Tween

func _ready():
	# Initialize hidden and fully transparent
	modulate.a = 0.0
	visible = false

func open_menu():
	visible = true
	
	# Kill previous tween if the button is spammed
	if tween and tween.is_running():
		tween.kill()
		
	tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, fade_duration)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_OUT)

func close_menu():
	if tween and tween.is_running():
		tween.kill()
		
	tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, fade_duration)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_IN)
	
	# Hide the node AFTER the fade-out completes so it stops receiving input
	tween.tween_callback(func(): visible = false)
