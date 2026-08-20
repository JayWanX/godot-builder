class_name PipeProcessRunner
extends RefCounted

const PipeProcessStream = preload("uid://dbmfgexmxwmbx")
const PipeReadBehavior = PipeProcessConfig.PipeReadBehavior
const ShellType = PipeProcessConfig.RunCommandShellType

#region Signals
## 当进程启动时发出 [br]
## [param pid] 系统进程 ID
signal process_started(pid: int)
## 当进程产生标准输出时发出 [br]
## [param pid] 系统进程 ID [br]
## [param output] - 输出的文本行
signal process_stdout_received(pid: int, output: String)
## 当进程产生标准错误输出时发出 [br]
## [param pid] 系统进程 ID [br]
## [param output] - 输出的文本行
signal process_stderr_received(pid: int, output: String)
## 当进程通过桥接协议请求标准输入时发出 [br]
## [param pid] 系统进程 ID [br]
## [param prompt] - 请求输入的提示文本
signal process_input_request_received(pid: int, prompt: String)
## 当进程通过桥接协议返回一个明确的返回值时发出 [br]
## [param pid] 系统进程 ID [br]
## [param return_data] - 返回的数据（通常为 Dictionary 或基本类型）
signal process_return_received(pid: int, return_data: Variant)
## 当读取到进程通过桥接协议输出的结构化数据时发出 [br]
## [param pid] 系统进程 ID [br]
## [param type] - 桥接消息类型枚举 [br]
## [param data] - 解析后的数据（Variant 类型，通常为 Dictionary 或 Array）
signal process_bridge_data_received(pid: int, type: BridgeType, data: Variant)
## 当进程退出时发出 [br]
## [param pid] 系统进程 ID [br]
## [param record] 进程运行的记录数据
signal process_exited(pid: int, record: PipeProcessRecord)
#endregion

#region Enums
## 桥接消息类型枚举
enum BridgeType {
	DATA,     ## 通用数据
	RETURN,   ## 返回值数据
	INPUT_REQUEST, ## 输入请求
	ERROR,    ## 错误数据
	PROGRESS, ## 进度数据
}
#endregion

#region Constants
const KEY_PID: String = "pid"
const KEY_STDIO: String = "stdio"
const KEY_STDERR: String = "stderr"

## shell 解析结果键名：shell 路径
const KEY_SHELL_PATH: String = "path"
## shell 解析结果键名：执行命令参数前缀列表
const KEY_SHELL_ARGS: String = "args"
## Windows 系统 shell 路径环境变量名
const WINDOWS_SHELL_ENV_VAR: String = "COMSPEC"
## Windows 系统 shell 回退路径
const WINDOWS_SHELL_FALLBACK: String = "cmd.exe"
## POSIX 系统 shell 路径
const POSIX_SHELL: String = "/bin/sh"
## Windows 系统 shell 执行命令的参数前缀
const SHELL_COMMAND_FLAG_WINDOWS: String = "/c"
## POSIX 系统 shell 执行命令的参数前缀
const SHELL_COMMAND_FLAG_POSIX: String = "-c"
## Windows PowerShell 可执行文件名
const POWERSHELL_EXE: String = "powershell.exe"
## PowerShell 7+ Windows 可执行文件名
const PWSH_EXE_WINDOWS: String = "pwsh.exe"
## PowerShell 7+ POSIX 可执行文件名
const PWSH_EXE_POSIX: String = "pwsh"
## PowerShell 命令参数前缀：跳过 profile、非交互、以 -Command 执行后续字符串
const POWERSHELL_COMMAND_ARGS: Array[String] = ["-NoProfile", "-NonInteractive", "-Command"]

## 数据桥接协议行前缀
const BRIDGE_PREFIX: String = "<<@GODOT_BRIDGE>>"

## 进程轮询间隔（秒）：降频轮询减少 CPU 空转，输出延迟约 0.1s
const POLL_INTERVAL: float = 0.1

## 桥接数据 JSON 键名
const BRIDGE_KEY_TYPE: String = "type"
const BRIDGE_KEY_DATA: String = "data"

## 桥接消息类型字符串 → 枚举映射
const BRIDGE_TYPE_MAP: Dictionary[String, BridgeType] = {
	"data": BridgeType.DATA,
	"return": BridgeType.RETURN,
	"result": BridgeType.RETURN,
	"input_request": BridgeType.INPUT_REQUEST,
	"error": BridgeType.ERROR,
	"progress": BridgeType.PROGRESS,
}
#endregion

#region Variables
## 进程运行配置
var _config: PipeProcessConfig
## 运行中的管道进程读写控制器字典 { 系统进程ID -> 管道进程读写控制器 }
var _running_piped_processes: Dictionary[int, PipeProcessStream] = {}
#endregion

#region Built-in Virtual Methods
func _init(config: PipeProcessConfig = null) -> void:
	if config == null:
		config = PipeProcessConfig.new()
	_config = config
#endregion

#region Public Process Methods
func run(
	execution_path: String,
	arguments: PackedStringArray,
	environments: Dictionary[String, String] = {}
) -> PipeProcessHandle:
	# 合并环境变量
	var final_environments: Dictionary[String, String] = _config.environments.merged(environments, true)
	return _start_process(execution_path, arguments, final_environments)

## 通过系统 shell 运行终端命令字符串。[br][br]
## [param command] 完整终端命令字符串，需与所选 shell 语法兼容。[br]
## [param environments] 进程环境变量。[br]
## [param track_in_manager] 是否纳入进程管理器跟踪。[br]
## [param shell] 系统 shell 类型，平台不支持时回退到 DEFAULT。
func run_command(
	command: String,
	environments: Dictionary[String, String] = {},
	shell: ShellType = ShellType.DEFAULT
) -> PipeProcessHandle:
	var shell_command: Dictionary = _resolve_shell_command(shell)
	var shell_args: PackedStringArray = shell_command[KEY_SHELL_ARGS]
	shell_args.append(command)
	return run(
		shell_command[KEY_SHELL_PATH],
		shell_args,
		environments
	)

## 向进程的 stdin 写入数据 [br]
## [param pid] 系统进程 ID [br]
## [param data] - 要写入的数据 [br]
## 返回写入结果
func write_to_stdin(pid: int, data: PackedByteArray) -> Error:
	if not _running_piped_processes.has(pid):
		return Error.ERR_DOES_NOT_EXIST
	var process_stream: PipeProcessStream = _running_piped_processes.get(pid)
	return process_stream.write_to_stdin(data)

## 向进程的 stdin 写入一行数据（自动追加换行符） [br]
## [param pid] 系统进程 ID [br]
## [param line] - 要写入的行内容 [br]
## 返回写入结果
func write_line_to_stdin(pid: int, line: String) -> Error:
	if not _running_piped_processes.has(pid):
		return Error.ERR_DOES_NOT_EXIST
	var process_stream: PipeProcessStream = _running_piped_processes.get(pid)
	return process_stream.write_line_to_stdin(line)

## 将进程的标准输出和标准错误打印到控制台
func enable_console_output() -> void:
	if not process_stdout_received.is_connected(_on_process_stdout_received):
		process_stdout_received.connect(_on_process_stdout_received)
	if not process_stderr_received.is_connected(_on_process_stderr_received):
		process_stderr_received.connect(_on_process_stderr_received)

## 停止将进程输出打印到控制台
func disable_console_output() -> void:
	if process_stdout_received.is_connected(_on_process_stdout_received):
		process_stdout_received.disconnect(_on_process_stdout_received)
	if process_stderr_received.is_connected(_on_process_stderr_received):
		process_stderr_received.disconnect(_on_process_stderr_received)
#endregion

#region Process management
func is_running(pid: int) -> bool:
	return OS.is_process_running(pid)

func interrupt(pid: int) -> Error:
	if not _running_piped_processes.has(pid):
		return Error.ERR_DOES_NOT_EXIST
	var process_stream: PipeProcessStream = _running_piped_processes.get(pid)
	return process_stream.write_interrupt_to_stdin()

func kill(pid: int) -> Error:
	return OS.kill(pid)
#endregion

#region Private Methods
## 解析指定系统 shell 的可执行路径与参数前缀。
func _resolve_shell_command(shell: ShellType = ShellType.DEFAULT) -> Dictionary:
	var is_windows: bool = OS.get_name() == "Windows"

	# DEFAULT 优先使用 config 中的全局默认，仍为 DEFAULT 时再解析为平台默认
	if shell == ShellType.DEFAULT and _config != null:
		shell = _config.run_command_shell_type

	# 平台不支持的 shell 类型回退到 DEFAULT
	if shell == ShellType.DEFAULT:
		shell = ShellType.CMD if is_windows else ShellType.SH
	elif is_windows and shell == ShellType.SH:
		push_error("ShellType.SH is not available on Windows, falling back to DEFAULT")
		shell = ShellType.CMD
	elif not is_windows and shell == ShellType.CMD:
		push_error("ShellType.CMD is not available on POSIX systems, falling back to DEFAULT")
		shell = ShellType.SH
	elif not is_windows and shell == ShellType.POWERSHELL:
		push_error("ShellType.POWERSHELL is not available on POSIX systems, falling back to DEFAULT")
		shell = ShellType.SH

	match shell:
		ShellType.CMD:
			var cmd_path: String = OS.get_environment(WINDOWS_SHELL_ENV_VAR)
			if cmd_path.is_empty():
				cmd_path = WINDOWS_SHELL_FALLBACK
			return {KEY_SHELL_PATH: cmd_path, KEY_SHELL_ARGS: PackedStringArray([SHELL_COMMAND_FLAG_WINDOWS])}
		ShellType.POWERSHELL:
			return {KEY_SHELL_PATH: POWERSHELL_EXE, KEY_SHELL_ARGS: PackedStringArray(POWERSHELL_COMMAND_ARGS)}
		ShellType.PWSH:
			var pwsh_path: String = PWSH_EXE_WINDOWS if is_windows else PWSH_EXE_POSIX
			return {KEY_SHELL_PATH: pwsh_path, KEY_SHELL_ARGS: PackedStringArray(POWERSHELL_COMMAND_ARGS)}
		ShellType.SH:
			return {KEY_SHELL_PATH: POSIX_SHELL, KEY_SHELL_ARGS: PackedStringArray([SHELL_COMMAND_FLAG_POSIX])}

	return {}

## 启动进程，返回进程任务ID
func _start_process(
	execution_path: String,
	arguments: PackedStringArray,
	environments: Dictionary[String, String]
) -> PipeProcessHandle:
	# 设置进程环境变量
	var original_environments: Dictionary[String, String] = {}
	if not environments.is_empty():
		for variable: String in environments.keys():
			if OS.has_environment(variable):
				original_environments.set(variable, OS.get_environment(variable))
			OS.set_environment(variable, environments.get(variable))
	
	# 以非阻塞方式运行进程
	var result: Dictionary = OS.execute_with_pipe(
		ProjectSettings.globalize_path(execution_path),
		arguments,
		false
	)
	
	# 恢复进程环境变量
	if not environments.is_empty():
		for variable: String in environments.keys():
			if original_environments.has(variable):
				OS.set_environment(variable, original_environments.get(variable))
			else:
				OS.unset_environment(variable)
	
	# 如果进程启动失败则提前返回 null
	if result.is_empty():
		return null
	var pid: int = result.get(KEY_PID)
	
	# 创建管道进程句柄
	var process_handle: PipeProcessHandle = PipeProcessHandle.new(pid)
	process_handle.started.emit()
	process_started.emit(pid)
	
	# 创建管道进程执行记录对象
	var process_record: PipeProcessRecord = PipeProcessRecord.new(
		pid, execution_path, arguments, environments
	)
	
	# 创建管道进程读写控制器
	var process_stream: PipeProcessStream = PipeProcessStream.new(
		process_record, result.get(KEY_STDIO), result.get(KEY_STDERR), _config
	)
	_running_piped_processes.set(pid, process_stream)
	
	# 监控进程的运行状态和输出
	_monitor_process(
		process_handle, process_stream, process_record
	)
	
	return process_handle

## 监控指定进程的运行状态和输出
func _monitor_process(
	process_handle: PipeProcessHandle,
	process_stream: PipeProcessStream,
	process_record: PipeProcessRecord,
) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	while process_stream.is_running():
		# 低频轮询：进程空闲时不再每帧唤醒（进程输出有约 0.1s 延迟，可接受）
		await tree.create_timer(POLL_INTERVAL).timeout
		
		# 检测进程是否超时
		if _config.enable_timeout and process_stream.get_runtime_ms() > _config.timeout_duration:
			push_warning("Process %d timed out, terminating..." % process_handle.pid)
			process_stream.terminate()
			process_record.is_timed_out = true
			break
		
		# 读取并发送进程输出
		var new_lines: Dictionary[String, PackedStringArray] = process_stream.read_stream()
		for output_type: String in new_lines.keys():
			for line: String in new_lines.get(output_type):
				_emit_process_output(process_handle, line, output_type)
	
	# 读取管道中剩余的输出（进程退出后管道中可能还有未读数据）
	var remaining_lines: Dictionary[String, PackedStringArray] = process_stream.read_remaining_stream()
	for output_type: String in remaining_lines.keys():
		for line: String in remaining_lines.get(output_type):
			_emit_process_output(process_handle, line, output_type)
	
	# 释放管道进程读写控制器
	_running_piped_processes.erase(process_handle.pid)
	process_stream.free()
	
	# 发出进程退出信号
	process_handle.exited.emit(process_record)
	process_exited.emit(process_handle.pid, process_record)

## 分发进程输出行：先尝试解析桥接协议，不匹配则作为普通输出 [br]
## [param process_handle] 管道进程句柄 [br]
## [param line] 输出行 [br]
## [param output_type] 管道输出流类型
func _emit_process_output(process_handle: PipeProcessHandle, line: String, output_type: String) -> void:
	# 仅对 stdout 尝试桥接解析（stderr 不可能包含桥接数据）
	if _config.enable_data_bridge and output_type == KEY_STDIO and _try_parse_bridge_data_line(process_handle, line):
		return
	
	if output_type == KEY_STDIO:
		process_handle.stdout_received.emit(line)
		process_stdout_received.emit(process_handle.pid, line)
	else:
		process_handle.stderr_received.emit(line)
		process_stderr_received.emit(process_handle.pid, line)

## 尝试解析桥接协议行 [br]
## [param process_handle] 管道进程句柄 [br]
## [param line] 输出行 [br]
## 返回是否已被桥接协议处理
func _try_parse_bridge_data_line(process_handle: PipeProcessHandle, line: String) -> bool:
	if not line.begins_with(BRIDGE_PREFIX):
		return false
	
	# 提取前缀之后的 JSON 载荷
	var json_str: String = line.trim_prefix(BRIDGE_PREFIX)
	var json: Variant = JSON.parse_string(json_str)
	
	if json == null or not json is Dictionary:
		#push_warning("Bridge protocol JSON parse failed, treating as plain output")
		return false
	
	var parsed_data: Dictionary = json
	
	if not parsed_data.has(BRIDGE_KEY_TYPE) or not parsed_data.has(BRIDGE_KEY_DATA):
		#push_warning("Bridge protocol missing required keys, treating as plain output")
		return false
	
	var data_type_str: String = json.get(BRIDGE_KEY_TYPE)
	# 将字符串类型转换为枚举
	if not BRIDGE_TYPE_MAP.has(data_type_str):
		#push_warning("Bridge protocol unknown type '%s', treating as plain output" % data_type_str)
		return false
	
	var data: Variant = json.get(BRIDGE_KEY_DATA)
	var data_type: BridgeType = BRIDGE_TYPE_MAP[data_type_str]
	if data_type == BridgeType.RETURN:
		process_handle.return_received.emit(data)
		process_return_received.emit(process_handle.pid, data)
	if data_type == BridgeType.INPUT_REQUEST:
		process_handle.input_request_received.emit(data)
		process_input_request_received.emit(process_handle.pid, data)
	process_handle.bridge_data_received.emit(data_type, data)
	process_bridge_data_received.emit(process_handle.pid, data_type, data)
	
	return true
#endregion

#region Signal Callback Methods
func _on_process_stdout_received(_pid: int, line: String) -> void:
	print(line)

func _on_process_stderr_received(_pid: int, line: String) -> void:
	print(line)
#endregion
