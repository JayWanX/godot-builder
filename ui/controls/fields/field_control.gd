@abstract
class_name FieldControl
extends HBoxContainer

const DISPLAY_NAME_LABEL_MINIMUM_WIDTH: float = 200

@warning_ignore("unused_signal")
signal value_changed(value: Variant)

## 行标签（显示名）
@export var display_name_label: Label
## 行内重置按钮
@export var reset_button: Button

var _default_value: Variant

func setup(
	option_name: String,
	current_value: Variant,
	default_value: Variant,
	tooltip: String
) -> void:
	display_name_label.custom_minimum_size.x = DISPLAY_NAME_LABEL_MINIMUM_WIDTH
	tooltip_text = tooltip
	display_name_label.text = option_name
	_default_value = default_value
	_set_control(current_value)
	_set_value(current_value)

func _set_value(value: Variant) -> void:
	value_changed.emit(value)
	if value == _default_value:
		reset_button.hide()
	else:
		reset_button.show()

func set_control(value: Variant) -> void:
	_set_control(value)
	if value == _default_value:
		reset_button.hide()
	else:
		reset_button.show()

func reset_control() -> void:
	_set_control(_default_value)
	reset_button.hide()

## 更新行默认值（如模块总开关翻转后派生默认值变化）；不改变当前控件值。
func set_default(default_value: Variant) -> void:
	_default_value = default_value

@abstract func _set_control(value: Variant) -> void
