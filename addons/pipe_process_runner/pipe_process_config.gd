@tool
class_name PipeProcessConfig
extends Resource

## 管道读取行为枚举
enum PipeReadBehavior {
	NONE, ## 不读取
	GET_BUFFER, ## 按字节块读取，原样累积
	GET_BUFFER_AND_PARSE_LINES, ## 按字节块读取，并按换行符解析拆分为行
}

## run_command 使用的系统 shell 类型
enum RunCommandShellType {
	DEFAULT,    ## 平台默认（Windows=CMD，POSIX=SH）
	CMD,        ## Windows cmd.exe
	POWERSHELL, ## Windows PowerShell（powershell.exe）
	PWSH,       ## PowerShell 7+（pwsh.exe / pwsh，跨平台）
	SH,         ## POSIX /bin/sh
}

## 进程命令环境变量
@export var environments: Dictionary[String, String] = {}
## run_command 默认使用的系统 shell 类型，可被单次调用覆盖
@export var run_command_shell_type: RunCommandShellType = RunCommandShellType.DEFAULT
## 管道读取行为
@export var pipe_read_behavior: PipeReadBehavior = PipeReadBehavior.GET_BUFFER_AND_PARSE_LINES:
	set(value):
		if pipe_read_behavior != value:
			pipe_read_behavior = value
			notify_property_list_changed()
## 单次读取管道输出字节数
@export_range(64, 1024 * 1024, 64, "or_greater") var read_chunk_size: int = 4096
## 是否启用输出流字节缓冲上限
@export var enable_stream_buffer_limit: bool = true:
	set(value):
		if enable_stream_buffer_limit != value:
			enable_stream_buffer_limit = value
			notify_property_list_changed()
## 单个输出流（stdout/stderr）字节缓冲上限，解析模式回收已解析前缀，纯累积模式丢弃最旧字节
@export_range(1024, 1073741824, 1024, "or_greater") var max_stream_buffer_bytes: int = 64 * 1024 * 1024
## 是否启用输出行记录上限
@export var enable_output_line_limit: bool = true:
	set(value):
		if enable_output_line_limit != value:
			enable_output_line_limit = value
			notify_property_list_changed()
## 进程记录保留的最大输出行数，超出丢弃最旧行
@export_range(100, 1000000, 100, "or_greater") var max_output_lines: int = 500000
## 是否启用数据桥接
@export var enable_data_bridge: bool = true
## 是否启用进程超时
@export var enable_timeout: bool = false:
	set(value):
		if enable_timeout != value:
			enable_timeout = value
			notify_property_list_changed()
## 进程超时时间（毫秒）
@export_range(1_000, 60_000, 1, "or_greater") var timeout_duration: int = 60_000

func _validate_property(property: Dictionary) -> void:
	if property.name == &"read_chunk_size":
		if pipe_read_behavior == PipeReadBehavior.NONE:
			property.usage = property.usage & ~PROPERTY_USAGE_EDITOR
		else:
			property.usage = property.usage | PROPERTY_USAGE_EDITOR
	if property.name == &"enable_data_bridge":
		if pipe_read_behavior == PipeReadBehavior.GET_BUFFER_AND_PARSE_LINES:
			property.usage = property.usage | PROPERTY_USAGE_EDITOR
		else:
			property.usage = property.usage | PROPERTY_USAGE_READ_ONLY
			enable_data_bridge = false
	if property.name == &"timeout_duration":
		if enable_timeout:
			property.usage = property.usage | PROPERTY_USAGE_EDITOR
		else:
			property.usage = property.usage & ~PROPERTY_USAGE_EDITOR
	if property.name == &"max_stream_buffer_bytes":
		if enable_stream_buffer_limit:
			property.usage = property.usage | PROPERTY_USAGE_EDITOR
		else:
			property.usage = property.usage & ~PROPERTY_USAGE_EDITOR
	if property.name == &"max_output_lines":
		if enable_output_line_limit:
			property.usage = property.usage | PROPERTY_USAGE_EDITOR
		else:
			property.usage = property.usage & ~PROPERTY_USAGE_EDITOR
