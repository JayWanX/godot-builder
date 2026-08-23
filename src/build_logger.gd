class_name BuildLogger
extends RefCounted

var _file: FileAccess = null
var _path: String = ""

## 打开新日志文件（时间戳命名）；目录不存在时自动创建。
## [param log_dir] 日志目录（绝对路径）
## [return] 打开成功返回 true
func start(log_dir: String) -> bool:
	var dir_error: Error = DirAccess.make_dir_recursive_absolute(log_dir)
	if dir_error != OK:
		return false
	_path = log_dir.path_join(
		"build_%s.log" % Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	)
	_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file == null:
		_path = ""
		return false
	return true

## 追加一行到日志文件（不落盘缓冲，立即写入）。
func append(line: String) -> void:
	if _file:
		_file.store_line(line)

## 关闭日志文件并释放句柄。
func stop() -> void:
	if _file:
		_file.close()
		_file = null

## 当前日志文件路径（未成功打开时为空字符串）。
func get_path() -> String:
	return _path
