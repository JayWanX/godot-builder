@abstract
class_name Utils
extends Object

## 版本整数字段正则模板（%s 为字段名）
const VERSION_FIELD_PATTERN: String = r'\b%s\s*[:=]\s*(\d+)'
## 版本状态字段正则模板
const VERSION_STATUS_PATTERN: String = r'\bstatus\s*[:=]\s*"([^"]+)"'

## 版本整数字段正则缓存（按字段名懒创建）
static var _version_field_regex_cache: Dictionary[String, RegEx] = {}
## 版本状态字段正则（首次使用时懒加载）
static var _version_status_regex: RegEx = null

## 扫描目录下包含的所有 Godot 源码目录及其版本（仅一级子目录，不递归）。[br][br]
## [param dir] 父目录路径（res:// 或绝对路径）[br]
## [return] 源码目录绝对路径→版本号字典（含键：目录路径(String)、版本号(String)）；目录不存在或打开失败返回空字典
static func scan_godot_source_dir(dir: String) -> Dictionary[String, String]:
	var global_dir: String = ProjectSettings.globalize_path(dir)
	if not DirAccess.dir_exists_absolute(global_dir):
		return {}
	var dir_access: DirAccess = DirAccess.open(global_dir)
	if dir_access == null:
		return {}
	var source_dirs: Dictionary[String, String] = {}
	for subdir: String in dir_access.get_directories():
		var subdir_path: String = global_dir.path_join(subdir)
		var version: String = parse_godot_version(subdir_path)
		if not version.is_empty():
			source_dirs[subdir_path] = version
	return source_dirs

## 解析 Godot 源码目录的完整版本号。[br]
## [param source_dir] Godot 引擎源码根目录（res:// 或绝对路径）[br]
## [return] 完整版本号（如 "4.7.1-stable"）；目录无效或解析失败返回空字符串
static func parse_godot_version(source_dir: String) -> String:
	var global_source_dir: String = ProjectSettings.globalize_path(source_dir)
	if not DirAccess.dir_exists_absolute(global_source_dir):
		return ""
	if not FileAccess.file_exists(global_source_dir.path_join("SConstruct")):
		return ""
	for dir_name: String in ["core", "scene", "modules", "platform", "servers", "main", "drivers", "editor", "thirdparty"]:
		if not DirAccess.dir_exists_absolute(global_source_dir.path_join(dir_name)):
			return ""
	var version_path: String = global_source_dir.path_join("version.py")
	if not FileAccess.file_exists(version_path):
		return ""
	var content: String = FileAccess.get_file_as_string(version_path)
	var major: int = _version_field_int(content, "major")
	var minor: int = _version_field_int(content, "minor")
	var patch: int = _version_field_int(content, "patch")
	var status: String = _version_field_status(content)
	if major < 0 or minor < 0:
		return ""
	# 旧版（1.x/2.x）可能没有 patch 字段，省略该段（如 "1.0-stable"）
	var version_text: String = "%d.%d" % [major, minor]
	if patch >= 0:
		version_text += ".%d" % patch
	return "%s-%s" % [version_text, status]

## 打开系统终端并切换到指定目录。[br][br]
## [param dir] 目标目录路径（res:// 或绝对路径）；为空时使用系统默认目录[br]
## [return] 是否成功启动终端
static func open_terminal(dir: String = "") -> bool:
	var target_dir: String = ProjectSettings.globalize_path(dir) if not dir.is_empty() else ""
	match OS.get_name():
		"Windows":
			return _open_windows_terminal(target_dir)
		"macOS":
			return _open_macos_terminal(target_dir)
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			return _open_linux_terminal(target_dir)
		_:
			return false

## Windows：PowerShell -NoExit 保持窗口并 cd 到目标目录。
static func _open_windows_terminal(target_dir: String) -> bool:
	var arguments: PackedStringArray = PackedStringArray(["-NoExit"])
	if not target_dir.is_empty():
		arguments.append("-Command")
		arguments.append("cd '%s'" % target_dir.replace("'", "''"))
	return OS.create_process("powershell.exe", arguments, true) != 0

## macOS：open -a Terminal 打开终端并进入目标目录。
static func _open_macos_terminal(target_dir: String) -> bool:
	var arguments: PackedStringArray = PackedStringArray(["-a", "Terminal"])
	if not target_dir.is_empty():
		arguments.append(target_dir)
	return OS.create_process("open", arguments) != 0

## Linux：按顺序尝试常见终端模拟器，首个启动成功即返回。
static func _open_linux_terminal(target_dir: String) -> bool:
	if target_dir.is_empty():
		target_dir = OS.get_environment("HOME")
	var candidates: Array[Dictionary] = [
		{ "command": "x-terminal-emulator", "arguments": PackedStringArray(["--working-directory=%s" % target_dir]) },
		{ "command": "gnome-terminal", "arguments": PackedStringArray(["--working-directory=%s" % target_dir]) },
		{ "command": "konsole", "arguments": PackedStringArray(["--workdir", target_dir]) },
		{ "command": "xterm", "arguments": PackedStringArray(["-e", "/bin/sh", "-c", "cd \"%s\" && exec $SHELL" % target_dir]) },
	]
	for candidate: Dictionary in candidates:
		var command: String = str(candidate.get("command", ""))
		var arguments: PackedStringArray = candidate.get("arguments", PackedStringArray())
		if OS.create_process(command, arguments) != 0:
			return true
	return false

## 提取 version.py 中的整数版本字段（兼容 `major = 4` 与 `"major": 4`）；未找到返回 -1。
static func _version_field_int(content: String, field: String) -> int:
	var regex: RegEx = _version_field_regex_cache.get(field)
	if regex == null:
		regex = RegEx.create_from_string(VERSION_FIELD_PATTERN % field)
		_version_field_regex_cache[field] = regex
	var regex_match: RegExMatch = regex.search(content)
	return int(regex_match.get_string(1)) if regex_match else -1

## 提取 version.py 中的状态字段（如 stable/alpha/beta）；未找到返回空字符串。
static func _version_field_status(content: String) -> String:
	if _version_status_regex == null:
		_version_status_regex = RegEx.create_from_string(VERSION_STATUS_PATTERN)
	var regex_match: RegExMatch = _version_status_regex.search(content)
	return regex_match.get_string(1) if regex_match else ""
