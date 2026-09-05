@tool
extends EditorPlugin

var export_dock

func _enter_tree():
	# Load and add the exporter UI dock into the Editor
	export_dock = preload("res://addons/pet_exporter/exporter_dock.tscn").instantiate()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, export_dock)

func _exit_tree():
	# Cleanup when plugin is disabled
	remove_control_from_docks(export_dock)
	export_dock.queue_free()
