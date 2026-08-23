class_name BoolField
extends FieldControl

@export var check_button: CheckButton

func _set_control(value: Variant) -> void:
	check_button.button_pressed = bool(value)
	check_button.text = "是" if bool(value) else "否"

func _on_check_button_toggled(toggled_on: bool) -> void:
	check_button.text = "是" if toggled_on else "否"
	_set_value(toggled_on)
