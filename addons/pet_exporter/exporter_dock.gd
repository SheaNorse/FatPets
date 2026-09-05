@tool
extends Control

@onready var file_dialog: FileDialog = $FileDialog
@onready var export_button: Button = $MarginContainer/VBoxContainer/ExportButton
@onready var progress_bar: ProgressBar = $MarginContainer/VBoxContainer/ExportProgressBar
@onready var status_label: Label = $MarginContainer/VBoxContainer/StatusLabel


func _ready() -> void:
	if export_button and not export_button.pressed.is_connected(_on_export_button_pressed):
		export_button.pressed.connect(_on_export_button_pressed)

	if file_dialog and not file_dialog.file_selected.is_connected(_on_file_dialog_file_selected):
		file_dialog.file_selected.connect(_on_file_dialog_file_selected)

	if file_dialog:
		file_dialog.filters = PackedStringArray(["*.pck ; Godot Package Files"])

	_reset_progress_ui()


func _reset_progress_ui() -> void:
	if progress_bar:
		progress_bar.visible = false
		progress_bar.value = 0
		progress_bar.max_value = 100
	if status_label:
		status_label.text = ""
		status_label.modulate = Color.WHITE


func _set_status(text: String, color: Color = Color.WHITE) -> void:
	if status_label:
		status_label.text = text
		status_label.modulate = color
	print(text)


func _set_progress(percent: float) -> void:
	if progress_bar:
		progress_bar.visible = true
		progress_bar.value = percent


func _on_export_button_pressed() -> void:
	file_dialog.popup_file_dialog()


func _on_file_dialog_file_selected(output_pck_path: String) -> void:
	var current_scene_root = EditorInterface.get_edited_scene_root()

	if not current_scene_root:
		_set_status("Error: No scene is currently open in the editor!", Color.RED)
		push_error("No scene is currently open in the editor!")
		return

	var root_scene_path = current_scene_root.scene_file_path
	if root_scene_path.is_empty():
		_set_status("Error: Please save your open pet scene before exporting.", Color.RED)
		push_error("Please save your open pet scene before exporting.")
		return

	var final_pck_path = _ensure_pck_extension(output_pck_path)
	export_button.disabled = true
	await export_pck(root_scene_path, final_pck_path)
	export_button.disabled = false


func _ensure_pck_extension(path: String) -> String:
	if path.get_extension().to_lower() != "pck":
		var base_path = path.get_basename()
		return base_path + ".pck"
	return path


func get_all_dependencies(path: String) -> Array[String]:
	var collected: Array[String] = []
	_collect_dependencies(path, collected)
	return collected


func _collect_dependencies(path: String, collected: Array[String]) -> void:
	if not collected.has(path):
		collected.append(path)

	var raw_deps = ResourceLoader.get_dependencies(path)
	for dep in raw_deps:
		var resolved_path: String = dep

		if resolved_path.contains("::"):
			resolved_path = resolved_path.split("::")[0]

		if resolved_path.begins_with("uid://"):
			var uid_int = ResourceUID.text_to_id(resolved_path)
			if ResourceUID.has_id(uid_int):
				resolved_path = ResourceUID.get_id_path(uid_int)

		if resolved_path.begins_with("res://") and not collected.has(resolved_path):
			_collect_dependencies(resolved_path, collected)


func _get_import_artifacts(source_path: String) -> Array[String]:
	var artifacts: Array[String] = []
	var import_file = source_path + ".import"

	if not FileAccess.file_exists(import_file):
		return artifacts

	artifacts.append(import_file)

	var cfg = ConfigFile.new()
	if cfg.load(import_file) != OK:
		push_warning("Could not parse import file: ", import_file)
		return artifacts

	if not cfg.has_section("remap"):
		return artifacts

	for key in cfg.get_section_keys("remap"):
		if key.begins_with("path"):
			var remapped_value = cfg.get_value("remap", key)
			var remapped_paths: Array = remapped_value if remapped_value is Array else [remapped_value]
			for remapped in remapped_paths:
				var remapped_str := str(remapped)
				if FileAccess.file_exists(remapped_str) and not artifacts.has(remapped_str):
					artifacts.append(remapped_str)

	return artifacts


func export_pck(root_scene_path: String, save_pck_path: String) -> void:
	_set_status("Starting export...", Color.WHITE)
	_set_progress(0)

	var packer = PCKPacker.new()
	var start_err = packer.pck_start(save_pck_path)
	if start_err != OK:
		_set_status("Error: Failed to start PCKPacker (code %d)" % start_err, Color.RED)
		push_error("Failed to start PCKPacker: Error code ", start_err)
		return

	# --- Phase 1: collect dependencies ---
	_set_status("Scanning scene dependencies...", Color.WHITE)
	await get_tree().process_frame
	var resolved_files = get_all_dependencies(root_scene_path)

	var files_to_pack: Array[String] = []
	for file_path in resolved_files:
		if FileAccess.file_exists(file_path):
			if not files_to_pack.has(file_path):
				files_to_pack.append(file_path)
			for artifact in _get_import_artifacts(file_path):
				if not files_to_pack.has(artifact):
					files_to_pack.append(artifact)

	var total := files_to_pack.size()
	if total == 0:
		_set_status("Nothing to pack - no dependencies found.", Color.YELLOW)
		return

	# --- Phase 2: pack each file, updating progress as we go ---
	for i in range(total):
		var file_path = files_to_pack[i]
		var add_err = packer.add_file(file_path, file_path)
		if add_err != OK:
			_set_status("Error packing %s (code %d)" % [file_path.get_file(), add_err], Color.RED)
			push_error("Failed to add file to PCK: ", file_path, " (Error code ", add_err, ")")
			return

		var percent := float(i + 1) / float(total) * 100.0
		_set_progress(percent)
		_set_status("Packing (%d/%d): %s" % [i + 1, total, file_path.get_file()], Color.WHITE)

		# Yield periodically so the editor UI actually redraws instead of
		# freezing during a big synchronous loop.
		if i % 5 == 0:
			await get_tree().process_frame

	_set_status("Finalizing package...", Color.WHITE)
	await get_tree().process_frame

	var flush_err = packer.flush()
	if flush_err != OK:
		_set_status("Error: Failed to flush PCK (code %d)" % flush_err, Color.RED)
		push_error("Failed to flush PCK: Error code ", flush_err)
		return

	_set_progress(100)
	_set_status("Exported %d file(s) to %s" % [total, save_pck_path.get_file()], Color.GREEN)
