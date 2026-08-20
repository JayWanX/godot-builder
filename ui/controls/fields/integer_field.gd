class_name IntegerField
extends FieldControl

@export var spin_box: SpinBox

func _set_control(value: Variant) -> void:
	spin_box.value = int(value)

func _on_spin_box_value_changed(value: float) -> void:
	_set_value(value)
