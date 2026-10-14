extends Button

@export var contents : Control

func _on_pressed():
	if not contents:
		return
		
	# Check if it's currently opening/visible to determine toggle direction
	if contents.visible and contents.modulate.a > 0.0:
		contents.close_menu()
	else:
		contents.open_menu()
