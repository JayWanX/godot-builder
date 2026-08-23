#class_name PipeProcessStream
extends Object

#region Constants
const PipeReadBehavior = PipeProcessConfig.PipeReadBehavior
const KEY_STDIO: String = PipeProcessRunner.KEY_STDIO
const KEY_STDERR: String = PipeProcessRunner.KEY_STDERR
## ASCII 控制字符 ETX (End of Text)，对应键盘组合 Ctrl+C
const CTRL_C = ord("C") - 64
#endregion

#region Variables
## 管道进程执行记录
var _process_record: PipeProcessRecord
## 管道进程执行配置
var _config: PipeProcessConfig
## 标准输入输出文件句柄（stdin+stdout 双向管道，可读可写）
var _stdio: FileAccess
## 标准错误输出文件句柄（只读）
var _stderr: FileAccess
## 读取 stdio 输出行已解析位置（指向已被提取为完整行的末尾）
var _read_stdio_line_parse_pos: int = 0
## 读取 stderr 输出行已解析位置（指向已被提取为完整行的末尾）
var _read_stderr_line_parse_pos: int = 0
## 进程启动时间
var _start_time: int = -1
#endregion

func _init(
	process_record: PipeProcessRecord,
	stdio: FileAccess,
	stderr: FileAccess,
	config: PipeProcessConfig,
) -> void:
	_process_record = process_record
	_stdio = stdio
	_stderr = stderr
	_config = config
	_start_time = Time.get_ticks_msec()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_process_record.exited_at = Time.get_unix_time_from_system()
		_process_record.exit_code = OS.get_process_exit_code(_process_record.pid)

#region Public Methods
## 检查进程是否仍在运行
func is_running() -> bool:
	return OS.is_process_running(_process_record.pid)

## 获取进程退出码
func get_exit_code() -> int:
	return OS.get_process_exit_code(_process_record.pid)

## 获取运行时间（毫秒）
func get_runtime_ms() -> int:
	return Time.get_ticks_msec() - _start_time

## 终止进程
func terminate() -> Error:
	if is_running():
		return OS.kill(_process_record.pid)
	return Error.OK

## 读取并累积新的输出流字节（运行中轮询调用） [br]
## 返回从 stdout 和 stderr 中单次读取到的完整输出行字典
func read_stream() -> Dictionary[String, PackedStringArray]:
	if not is_running():
		return {}
	
	match _config.pipe_read_behavior:
		PipeReadBehavior.GET_BUFFER_AND_PARSE_LINES:
			var stdio_bytes: PackedByteArray = _read_stream_bytes(_stdio, _config.read_chunk_size)
			var stderr_bytes: PackedByteArray = _read_stream_bytes(_stderr, _config.read_chunk_size)
			var output_lines: Dictionary[String, PackedStringArray]
			if not stdio_bytes.is_empty():
				_process_record.stdio_buffer.append_array(stdio_bytes)
				output_lines.set(KEY_STDIO, _extract_next_output_lines(KEY_STDIO))
				_process_record.output_lines.append_array(output_lines.get(KEY_STDIO))
				_apply_output_limits(KEY_STDIO)
			if not stderr_bytes.is_empty():
				_process_record.stderr_buffer.append_array(stderr_bytes)
				output_lines.set(KEY_STDERR, _extract_next_output_lines(KEY_STDERR))
				_process_record.output_lines.append_array(output_lines.get(KEY_STDERR))
				_apply_output_limits(KEY_STDERR)
			return output_lines
		PipeReadBehavior.GET_BUFFER:
			var stdio_bytes: PackedByteArray = _read_stream_bytes(_stdio, _config.read_chunk_size)
			var stderr_bytes: PackedByteArray = _read_stream_bytes(_stderr, _config.read_chunk_size)
			if not stdio_bytes.is_empty():
				_process_record.stdio_buffer.append_array(stdio_bytes)
				_apply_output_limits(KEY_STDIO)
			if not stderr_bytes.is_empty():
				_process_record.stderr_buffer.append_array(stderr_bytes)
				_apply_output_limits(KEY_STDERR)
			return {}
		_:
			return {}

## 读取管道中剩余的字节（进程退出后使用） [br]
## 返回从 stdout 和 stderr 中读取到的剩余完整输出行字典
func read_remaining_stream() -> Dictionary[String, PackedStringArray]:
	match _config.pipe_read_behavior:
		PipeReadBehavior.GET_BUFFER_AND_PARSE_LINES:
			var remaining_stdio_bytes: PackedByteArray = _read_remaining_stream_bytes(_stdio, _config.read_chunk_size)
			var remaining_stderr_bytes: PackedByteArray = _read_remaining_stream_bytes(_stderr, _config.read_chunk_size)
			var output_lines: Dictionary[String, PackedStringArray]
			if not remaining_stdio_bytes.is_empty():
				_process_record.stdio_buffer.append_array(remaining_stdio_bytes)
				output_lines.set(KEY_STDIO, _extract_all_remaining_lines(KEY_STDIO))
				_process_record.output_lines.append_array(output_lines.get(KEY_STDIO))
				_apply_output_limits(KEY_STDIO)
			if not remaining_stderr_bytes.is_empty():
				_process_record.stderr_buffer.append_array(remaining_stderr_bytes)
				output_lines.set(KEY_STDERR, _extract_all_remaining_lines(KEY_STDERR))
				_process_record.output_lines.append_array(output_lines.get(KEY_STDERR))
				_apply_output_limits(KEY_STDERR)
			return output_lines
		PipeReadBehavior.GET_BUFFER:
			var remaining_stdio_bytes: PackedByteArray = _read_remaining_stream_bytes(_stdio, _config.read_chunk_size)
			var remaining_stderr_bytes: PackedByteArray = _read_remaining_stream_bytes(_stderr, _config.read_chunk_size)
			if not remaining_stdio_bytes.is_empty():
				_process_record.stdio_buffer.append_array(remaining_stdio_bytes)
				_apply_output_limits(KEY_STDIO)
			if not remaining_stderr_bytes.is_empty():
				_process_record.stderr_buffer.append_array(remaining_stderr_bytes)
				_apply_output_limits(KEY_STDERR)
			return {}
		_:
			return {}

## 检查进程的 stdin 是否可写入
func is_stdin_writable() -> bool:
	if not is_instance_valid(_stdio) or not _stdio.is_open() or not is_running():
		return false
	return _stdio.get_error() == Error.OK

## 向进程的 stdin 写入数据 [br]
## [param data] - 要写入的数据 [br]
## 返回写入结果
func write_to_stdin(data: PackedByteArray) -> Error:
	if not is_stdin_writable():
		return Error.ERR_UNAVAILABLE
	_stdio.store_buffer(data)
	_stdio.flush()
	return _stdio.get_error()

## 向进程的 stdin 写入一行数据（自动追加换行符） [br]
## [param line] - 要写入的行内容 [br]
## 返回写入结果
func write_line_to_stdin(line: String) -> Error:
	if not is_stdin_writable():
		return Error.ERR_UNAVAILABLE
	_stdio.store_line(line)
	_stdio.flush()
	return _stdio.get_error()

## 向子进程的标准输入写入中断信号（Ctrl+C）。[br]
## 这会触发子进程的 SIGINT 信号，允许其执行清理逻辑后优雅退出（例如 Python 中的 KeyboardInterrupt）。[br]
## 返回写入操作的结果（Error 枚举）。
func write_interrupt_to_stdin() -> Error:
	return write_to_stdin(PackedByteArray([CTRL_C]))
#endregion

#region Private Methods
## 读取单个流中的字节并存入数组
func _read_stream_bytes(stream: FileAccess, read_chunk_size: int) -> PackedByteArray:
	if stream.get_error() != Error.OK:
		return PackedByteArray()
	
	var read_length: int = mini(stream.get_length() - stream.get_position(), read_chunk_size)
	if read_length <= 0:
		return PackedByteArray()
	return stream.get_buffer(read_length)

## 读取单个流中的剩余字节并存入数组
func _read_remaining_stream_bytes(stream: FileAccess, read_chunk_size: int) -> PackedByteArray:
	var result: PackedByteArray = PackedByteArray()
	while stream.get_error() == Error.OK:
		var chunk: PackedByteArray = stream.get_buffer(read_chunk_size)
		if chunk.is_empty():
			break
		result.append_array(chunk)
	
	return result

## 从输出字节流中增量提取下一批完整行
func _extract_next_output_lines(output_type: String) -> PackedStringArray:
	const LF = ord("\n")
	const CR = ord("\r")
	var unparsed_buffer: PackedByteArray
	
	# 获取未解析的缓冲区数组
	if output_type == KEY_STDIO:
		unparsed_buffer = _process_record.stdio_buffer.slice(_read_stdio_line_parse_pos)
	else:
		unparsed_buffer = _process_record.stderr_buffer.slice(_read_stderr_line_parse_pos)
	
	# 从后往前找最后一个 \n 或 \r
	var last_lf_pos: int = unparsed_buffer.rfind(LF)
	var last_cr_pos: int = unparsed_buffer.rfind(CR)
	var last_sep_pos: int = max(last_lf_pos, last_cr_pos)
	
	# 没有分隔符，说明没有完整行
	if last_sep_pos == -1:
		return PackedStringArray()
	
	# 提取从 parse_pos 到 last_sep 的完整行块（不包含分隔符）
	var complete_block: String = unparsed_buffer.slice(0, last_sep_pos).get_string_from_utf8()
	
	# 移除 \r\n 时尾部残留的 \r
	if last_lf_pos - last_cr_pos == 1:
		complete_block = complete_block.rstrip("\r")
	
	# 归一化换行符：\r\n -> \n, \r -> \n
	complete_block = complete_block.replace("\r\n", "\n").replace("\r", "\n")
	
	# 一次性分割成多行
	var lines: PackedStringArray = complete_block.split("\n")
	
	# 更新解析位置
	if output_type == KEY_STDIO:
		_read_stdio_line_parse_pos += last_sep_pos + 1
	else:
		_read_stderr_line_parse_pos += last_sep_pos + 1
	
	return lines

## 提取缓冲区中所有剩余的字节作为行（进程退出后使用）
func _extract_all_remaining_lines(output_type: String) -> PackedStringArray:
	var output_buffer: PackedByteArray
	var parse_pos: int
	
	if output_type == KEY_STDIO:
		output_buffer = _process_record.stdio_buffer
		parse_pos = _read_stdio_line_parse_pos
	else:
		output_buffer = _process_record.stderr_buffer
		parse_pos = _read_stderr_line_parse_pos
	
	# 直接从 parse_pos 到末尾提取所有字节
	var complete_block: String = output_buffer.slice(parse_pos).get_string_from_utf8()
	
	# 归一化换行符并分割
	complete_block = complete_block.replace("\r\n", "\n").replace("\r", "\n")
	var lines: PackedStringArray = complete_block.split("\n")
	
	return lines

## 按配置上限裁剪缓冲与输出行
func _apply_output_limits(output_type: String) -> void:
	_trim_stream_buffer(output_type)
	_trim_output_lines()

## 缓冲超限时裁剪：解析模式回收已解析前缀，纯累积模式丢弃最旧字节
func _trim_stream_buffer(output_type: String) -> void:
	var max_bytes: int = _config.max_stream_buffer_bytes
	if not _config.enable_stream_buffer_limit or max_bytes <= 0:
		return
	if output_type == KEY_STDIO:
		if _process_record.stdio_buffer.size() > max_bytes:
			if _config.pipe_read_behavior == PipeReadBehavior.GET_BUFFER_AND_PARSE_LINES:
				if _read_stdio_line_parse_pos > 0:
					_process_record.stdio_buffer = _process_record.stdio_buffer.slice(_read_stdio_line_parse_pos)
					_read_stdio_line_parse_pos = 0
			else:
				_process_record.stdio_buffer = _process_record.stdio_buffer.slice(_process_record.stdio_buffer.size() - max_bytes)
	else:
		if _process_record.stderr_buffer.size() > max_bytes:
			if _config.pipe_read_behavior == PipeReadBehavior.GET_BUFFER_AND_PARSE_LINES:
				if _read_stderr_line_parse_pos > 0:
					_process_record.stderr_buffer = _process_record.stderr_buffer.slice(_read_stderr_line_parse_pos)
					_read_stderr_line_parse_pos = 0
			else:
				_process_record.stderr_buffer = _process_record.stderr_buffer.slice(_process_record.stderr_buffer.size() - max_bytes)

## 输出行超限时丢弃最旧行，仅保留最新配置行数
func _trim_output_lines() -> void:
	var max_lines: int = _config.max_output_lines
	if not _config.enable_output_line_limit or max_lines <= 0 or _process_record.output_lines.size() <= max_lines:
		return
	_process_record.output_lines = _process_record.output_lines.slice(
		_process_record.output_lines.size() - max_lines
	)
#endregion
