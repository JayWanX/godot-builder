class_name ConsolePanel
extends PanelContainer

enum PopupMenuAction {
	COPY,
	SELECT_ALL
}

const ICON_COPY = preload("uid://131l73n2invm")
const ICON_SELECT_ALL = preload("uid://bw7wt8c6b8c3r")

const KEY_TEXT: StringName = &"text"
const KEY_TYPE: StringName = &"type"

enum OutputType { INFO, ERROR, WARNING }

## 历史行数上限。超过后丢弃最旧的行，避免内存与重绘开销无限增长。
const MAX_LINES: int = 5000

@export var info_message_color: Color = Color(0.878, 0.878, 0.878, 1.0)
@export var error_message_color: Color = Color(0.898, 0.282, 0.302, 1.0)
@export var warning_message_color: Color = Color(1.0, 0.851, 0.396, 1.0)

@export var output_text_label: RichTextLabel
@export var console_popup_menu: PopupMenu
@export var clear_button: Button
@export var filter_line_edit: LineEdit
@export var info_button: Button
@export var error_button: Button
@export var warning_button: Button

## 元素为 { "text": String, "type": OutputType }
var _messages: Array[Dictionary] = []

## 已渲染到 RichTextLabel 的消息数量（用于增量追加，避免每帧全量重绘）
var _rendered_count: int = 0
## 当前各类型「可见」消息数量，增量维护，避免每次重算
var _visible_counts: Dictionary[OutputType, int] = { OutputType.INFO: 0, OutputType.ERROR: 0, OutputType.WARNING: 0 }

var _update_pending: bool = false
var _full_rebuild_needed: bool = false

func _ready() -> void:
	Console.initialize(self)
	console_popup_menu.add_icon_item(ICON_COPY, "复制    ", PopupMenuAction.COPY)
	console_popup_menu.add_icon_item(ICON_SELECT_ALL, "全选    ", PopupMenuAction.SELECT_ALL)

func append_info(message: String) -> void:
	append_message(message, OutputType.INFO)

func append_error(message: String) -> void:
	append_message(message, OutputType.ERROR)

func append_warning(message: String) -> void:
	append_message(message, OutputType.WARNING)

func append_message(message: String, output_type: OutputType) -> void:
	_messages.append({ KEY_TEXT: message, KEY_TYPE: output_type })
	# 超过上限时丢弃最旧行，并标记需要整屏重绘（已渲染内容需同步裁剪）
	if _messages.size() > MAX_LINES:
		var overflow := _messages.size() - MAX_LINES
		_messages = _messages.slice(overflow)
		_full_rebuild_needed = true
	_request_update()

## 合并同一帧/同一 idle 内的多次更新：只排一次延迟刷新，避免突发输出时反复全量重绘
func _request_update() -> void:
	if _update_pending:
		return
	_update_pending = true
	_flush_update.call_deferred()

func _flush_update() -> void:
	_update_pending = false
	if _full_rebuild_needed:
		_full_render()
		_full_rebuild_needed = false
	else:
		_append_new_lines()

## 整屏重建：仅在筛选/清空/超限时触发
func _full_render() -> void:
	output_text_label.clear()
	_rendered_count = 0
	_visible_counts = { OutputType.INFO: 0, OutputType.ERROR: 0, OutputType.WARNING: 0 }
	_append_new_lines()

## 仅把尚未渲染的消息增量追加到 RichTextLabel（O(增量行数) 而非 O(全部)）
func _append_new_lines() -> void:
	var filter_text: String = filter_line_edit.text
	var show_info: bool = info_button.button_pressed
	var show_error: bool = error_button.button_pressed
	var show_warning: bool = warning_button.button_pressed

	for i in range(_rendered_count, _messages.size()):
		var message: Dictionary = _messages[i]
		if not _is_visible(message, show_info, show_error, show_warning, filter_text):
			continue
		_append_line(message)
		var type: OutputType = message.get(KEY_TYPE)
		_visible_counts[type] += 1
	_rendered_count = _messages.size()
	_update_counts()

func _append_line(message: Dictionary) -> void:
	var type: OutputType = message.get(KEY_TYPE)
	match type:
		OutputType.ERROR:
			output_text_label.push_color(error_message_color)
		OutputType.WARNING:
			output_text_label.push_color(warning_message_color)
		_:
			output_text_label.push_color(info_message_color)
	output_text_label.append_text(message.get(KEY_TEXT))
	output_text_label.pop()
	output_text_label.newline()

func _is_visible(message: Dictionary, show_info: bool, show_error: bool, show_warning: bool, filter_text: String) -> bool:
	var type: OutputType = message.get(KEY_TYPE)
	var message_visible: bool
	match type:
		OutputType.INFO: message_visible = show_info
		OutputType.ERROR: message_visible = show_error
		OutputType.WARNING: message_visible = show_warning
	if not message_visible:
		return false
	if not filter_text.is_empty() and not message.get(KEY_TEXT).contains(filter_text):
		return false
	return true

func _update_counts() -> void:
	info_button.text = str(_visible_counts.get(OutputType.INFO, 0))
	error_button.text = str(_visible_counts.get(OutputType.ERROR, 0))
	warning_button.text = str(_visible_counts.get(OutputType.WARNING, 0))

func _on_clear_button_pressed() -> void:
	_messages.clear()
	_full_rebuild_needed = true
	_request_update()

func _on_filter_line_edit_text_changed(_new_text: String) -> void:
	_full_rebuild_needed = true
	_request_update()

## 类型筛选按钮切换：需整屏重建以隐藏/恢复对应行
func _on_filter_button_pressed() -> void:
	_full_rebuild_needed = true
	_request_update()

func _on_output_text_label_meta_clicked(meta: Variant) -> void:
	OS.shell_show_in_file_manager(str(meta))

func _on_output_text_label_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		event = event as InputEventMouseButton
		if event.button_index == MOUSE_BUTTON_RIGHT:
			console_popup_menu.popup(
				Rect2i(get_viewport().get_mouse_position(), Vector2i.ZERO)
			)

func _on_console_popup_menu_id_pressed(id: int) -> void:
	match id:
		PopupMenuAction.COPY:
			DisplayServer.clipboard_set(output_text_label.get_selected_text())
		PopupMenuAction.SELECT_ALL:
			output_text_label.select_all()
