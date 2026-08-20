class_name PathField
extends FieldControl

@export var line_edit: LineEdit
@export var file_dialog: FileDialog
@export var browse_button: Button

func _set_control(value: Variant) -> void:
	line_edit.text = str(value)

func _on_line_edit_text_changed(new_text: String) -> void:
	_set_value(new_text)

func _on_browse_path_button_pressed() -> void:
	if line_edit.text.is_absolute_path():
		file_dialog.current_path = line_edit.text
	file_dialog.popup_file_dialog()

func _on_file_dialog_dir_selected(dir: String) -> void:
	_set_value(dir)
	_set_control(dir)

func _on_file_dialog_file_selected(path: String) -> void:
	_set_value(path)
	_set_control(path)
