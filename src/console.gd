@abstract
class_name Console
extends Object

const KEY_TEXT = ConsolePanel.KEY_TEXT
const KEY_TYPE = ConsolePanel.KEY_TYPE
const OutputType = ConsolePanel.OutputType

## 全局日志入口（静态转发到当前实例）
static var _instance: ConsolePanel
## 实例未就绪时的待回放日志缓冲（防止丢失）
static var _pending_messages: Array[Dictionary] = []

static func initialize(instance: ConsolePanel) -> void:
	_instance = instance
	for message: Dictionary in _pending_messages:
		_push_message(message)
	_pending_messages.clear()

static func log_info(message: String) -> void:
	_push_message({ KEY_TEXT: message, KEY_TYPE: OutputType.INFO })

static func log_error(message: String) -> void:
	_push_message({ KEY_TEXT: message, KEY_TYPE: OutputType.ERROR })

static func log_warning(message: String) -> void:
	_push_message({ KEY_TEXT: message, KEY_TYPE: OutputType.WARNING })

static func _push_message(message: Dictionary) -> void:
	if _instance:
		_instance.append_message(message.get(KEY_TEXT), message.get(KEY_TYPE))
	else:
		_pending_messages.append(message)
