@warning_ignore_start("unused_signal")
class_name PipeProcessHandle
extends RefCounted

## 桥接类型
const BridgeType = PipeProcessRunner.BridgeType 

## 当进程启动时发出
signal started
## 当进程产生标准输出时发出 [br]
## [param output] 输出的文本行
signal stdout_received(output: String)
## 当进程产生标准错误输出时发出 [br]
## [param output] 输出的文本行
signal stderr_received(output: String)
## 当进程通过桥接协议请求标准输入时发出 [br]
## [param prompt] 请求输入的提示文本
signal input_request_received(prompt: String)
## 当进程通过桥接协议返回一个明确的返回值时发出 [br]
## [param return_data] 返回的数据（通常为 Dictionary 或基本类型）
signal return_received(return_data: Variant)
## 当读取到进程通过桥接协议输出的结构化数据时发出 [br]
## [param type] 桥接消息类型枚举 [br]
## [param data] 解析后的数据（Variant 类型，通常为 Dictionary 或 Array）
signal bridge_data_received(type: BridgeType, data: Variant)
## 当进程退出时发出 [br]
## [param record] 进程运行的记录数据
signal exited(record: PipeProcessRecord)

## 系统进程 ID
var pid: int

func _init(p_pid: int) -> void:
	self.pid = p_pid
