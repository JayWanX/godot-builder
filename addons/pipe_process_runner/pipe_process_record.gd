class_name PipeProcessRecord
extends RefCounted

## 系统进程 ID
var pid: int = -1
## 进程命令执行路径
var execution_path: String = ""
## 进程命令行参数数组
var arguments: PackedStringArray = PackedStringArray()
## 进程命令环境变量
var environments: Dictionary[String, String] = {}
## 管道进程标准输入输出字节数组
var stdio_buffer: PackedByteArray = PackedByteArray()
## 管道进程标准错误输出字节数组
var stderr_buffer: PackedByteArray = PackedByteArray()
## 管道进程所有输出行
var output_lines: PackedStringArray = PackedStringArray()
## 进程开始时间
var started_at: float = -1
## 进程退出时间
var exited_at: float = -1
## 进程是否超时
var is_timed_out: bool = false
## 进程退出码
var exit_code: int = -1

func _init(
	p_pid: int,
	p_execution_path: String,
	p_arguments: PackedStringArray,
	p_environments: Dictionary[String, String],
) -> void:
	self.pid = p_pid
	self.execution_path = p_execution_path
	self.arguments = p_arguments
	self.environments = p_environments
	self.started_at = Time.get_unix_time_from_system()
