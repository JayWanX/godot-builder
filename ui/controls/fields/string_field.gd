class_name StringField
extends FieldControl

@export var line_edit: LineEdit

func _set_control(value: Variant) -> void:
	line_edit.text = str(value)

func _on_line_edit_text_changed(new_text: String) -> void:
	_set_value(new_text)
