class_name EnumField
extends FieldControl

@export var option_button: OptionButton

var _possible_values: PackedStringArray

func setup_enum(possible_values: PackedStringArray) -> void:
	_possible_values = possible_values
	for value: String in _possible_values:
		option_button.add_item(value)

func _set_control(value: Variant) -> void:
	option_button.select(_possible_values.find(str(value)))

func _on_option_button_item_selected(index: int) -> void:
	var value: String = _possible_values[index]
	_set_value(value)
