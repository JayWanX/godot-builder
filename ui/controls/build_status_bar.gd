class_name BuildStatusBar
extends HBoxContainer

const ICON_CIRCLE_GREEN = preload("uid://dwvj656dyc3br")
const ICON_CIRCLE_RED = preload("uid://c1aa2k65ktkh1")
const ICON_CIRCLE_YELLOW = preload("uid://gxarl4r1l17b")
const ICON_PROGRESS = preload("uid://bltps1hnwta4x")

const KEY_STATUS: StringName = &"status"
const KEY_TEXT: StringName = &"text"
const KEY_TOOLTIP: StringName = &"tooltip"
const ROTATE_DURATION: int = 1

enum Status {
	PROGRESS,
	ERROR,
	WARNING,
	OK,
}

@export var texture_rect: TextureRect
@export var label: Label

var _rotate_tween: Tween = null
var _current_status: Dictionary = {}
var _staged_status: Dictionary = {}

func _ready() -> void:
	_update_pivot_offset()

func _make_custom_tooltip(for_text: String) -> Control:
	var rich_text_label: RichTextLabel = RichTextLabel.new()
	rich_text_label.bbcode_enabled = true
	rich_text_label.fit_content = true
	rich_text_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	rich_text_label.scroll_active = false
	rich_text_label.parse_bbcode(for_text)
	return rich_text_label

func get_current_status() -> Status:
	return _current_status.get(KEY_STATUS, Status.OK)

func get_current_status_text() -> String:
	return _current_status.get(KEY_TEXT, "")

func get_current_status_tooltip() -> String:
	return _current_status.get(KEY_TOOLTIP, "")

func set_status(status: Status, text: String) -> void:
	label.text = text
	_current_status.set(KEY_TEXT, text)
	match status:
		Status.PROGRESS:
			texture_rect.texture = ICON_PROGRESS
			_start_rotation()
		Status.ERROR:
			texture_rect.texture = ICON_CIRCLE_RED
			_stop_rotation()
		Status.WARNING:
			texture_rect.texture = ICON_CIRCLE_YELLOW
			_stop_rotation()
		Status.OK:
			texture_rect.texture = ICON_CIRCLE_GREEN
			_stop_rotation()
	_current_status.set(KEY_STATUS, status)

func set_tooltip(tooltip: String) -> void:
	tooltip_text = tooltip
	_current_status.set(KEY_TOOLTIP, tooltip)

func append_tooltip(tooltip: String) -> void:
	set_tooltip(tooltip_text + tooltip)

func staging_status() -> void:
	_staged_status = _current_status.duplicate()

func restore_status() -> void:
	if _staged_status.is_empty():
		return
	set_status(_staged_status.get(
		KEY_STATUS, Status.OK), _staged_status.get(KEY_TEXT, "")
	)
	set_tooltip(_staged_status.get(KEY_TOOLTIP, ""))
	_staged_status.clear()

## 启动无限旋转动画（360° 线性循环，每轮相对当前值累加一圈）。
func _start_rotation() -> void:
	_stop_rotation()
	_update_pivot_offset()
	_rotate_tween = create_tween().set_loops()
	_rotate_tween.tween_property(texture_rect, "rotation", TAU, ROTATE_DURATION) \
		.as_relative().set_trans(Tween.TRANS_LINEAR)

## 停止旋转动画并复位角度。
func _stop_rotation() -> void:
	if _rotate_tween:
		_rotate_tween.kill()
		_rotate_tween = null
	if texture_rect:
		texture_rect.rotation = 0.0

## 让图标以自身中心为轴旋转（布局完成后尺寸才有意义）。
func _update_pivot_offset() -> void:
	texture_rect.pivot_offset = texture_rect.size * 0.5
