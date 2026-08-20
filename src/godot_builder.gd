class_name GodotBuilder
extends RefCounted

#region 常量：运行时目录结构
## 嵌入式运行时根目录（embeddings 与 site-packages 的父级）
const RUNTIME_ROOT: String = "res://python"
## 嵌入式运行时基础目录（宿主平台运行时位于其子目录）
const RUNTIME_BASE: String = "res://python/embeddings"
## 内置 SCons 安装目录（bootstrap 时注入 sys.path 优先加载）
const BUILT_IN_SCONS_DIR: String = "res://python/site-packages"
## 各平台运行时子目录名
const EMBEDDINGS_DIR_NAME: String = "embeddings"
const SITE_PACKAGES_DIR_NAME: String = "site-packages"
## SCons 包目录名（scons 各命令由该包提供）
const SCONS_PACKAGE_DIR_NAME: String = "SCons"
## Python 解释器文件名（Windows 为 python.exe，Unix 系为 bin/python3）
const PYTHON_EXECUTABLE_WINDOWS: String = "python.exe"
const PYTHON_EXECUTABLE_UNIX: String = "bin/python3"
## 标准库目录名（Windows 大写 Lib，Unix 系小写 lib）
const STDLIB_DIR_WINDOWS: String = "Lib"
const STDLIB_DIR_UNIX: String = "lib"
#endregion

#region 常量：平台名（与运行时目录名一致）
const PLATFORM_WINDOWS: String = "windows"
const PLATFORM_LINUX: String = "linux"
const PLATFORM_MACOS: String = "macos"
#endregion

#region 常量：资源文件与缓存
## SCons 引导编码补丁脚本（修复 Windows 下 SCons 输出编码）
const SCONS_BOOTSTRAP_PATCH_SCRIPT: String = "res://src/scons_bootstrap_encoding_patch.py"
## 编译配置文件（profile）文件名（SConstruct 自动加载）
const PROFILE_FILE_NAME: String = "custom.py"
## Godot 源码目录中的关键文件
const FILE_SCONSTRUCT: String = "SConstruct"
const FILE_VERSION_PY: String = "version.py"
## scons --help 磁盘缓存目录名（位于可执行文件旁，与 app_data.tres 同级）
const HELP_CACHE_DIR_NAME: String = "scons_help"
## 缓存文件扩展名
const HELP_CACHE_FILE_EXTENSION: String = ".txt"
#endregion

#region 常量：进程参数与输出标记
const ARG_VERSION: String = "--version"
const ARG_HELP: String = "--help"
const ARG_PLATFORM_LIST: String = "platform=list"
const ARG_DIRECTORY_TEMPLATE: String = "--directory=%s"
const ARG_PROFILE_TEMPLATE: String = "profile=%s"
## 版本输出前缀（python --version / scons --version）
const PYTHON_VERSION_PREFIX: String = "Python"
const SCONS_VERSION_PREFIX: String = "SCons: v"
## scons platform=list 输出的列表起止标记
const PLATFORM_LIST_MARKER: String = "The following platforms are available:"
const PLATFORM_LIST_END_MARKER: String = "Please run SCons"
## 版本号保留段数（如 4.11.0 → 3 段）
const VERSION_SEGMENT_COUNT: int = 3
#endregion

#region 常量：进程环境变量
## 强制 UTF-8 文本模式、无缓冲输出、禁用用户级 site-packages（隔离依赖）
const ENV_PYTHON_UTF8: String = "PYTHONUTF8"
const ENV_PYTHON_UNBUFFERED: String = "PYTHONUNBUFFERED"
const ENV_PYTHON_NO_USER_SITE: String = "PYTHONNOUSERSITE"
## 注入 SCons 子进程的解密密钥（PCK 加密场景下 SCons 读取加密资源需要）
const ENV_SCRIPT_ENCRYPTION_KEY: String = "SCRIPT_AES256_ENCRYPTION_KEY"
## 共享库搜索路径（内置运行时 lib 目录注入）
const ENV_LD_LIBRARY_PATH: String = "LD_LIBRARY_PATH"
const ENV_DYLD_LIBRARY_PATH: String = "DYLD_LIBRARY_PATH"
## 共享库搜索路径分隔符
const PATH_LIST_SEPARATOR: String = ":"

## SCons -c 引导代码模板：注入本地 SCons 目录、应用编码补丁后调用主入口
const SCONS_BOOTSTRAP_CODE_TEMPLATE: String = "import sys; sys.path.insert(0, '%s')\n%simport SCons.Script; SCons.Script.main()"
#endregion

#region 状态
## 本地 SCons 目录（构建时注入 sys.path 优先加载；可改为可写数据目录）
var scons_dir: String = BUILT_IN_SCONS_DIR
## 自定义 Python 解释器路径（空串表示使用内置运行时）
var python_path: String = ""

## 已探测的 Python 解释器路径（探测缓存键）
var _probed_python_path: String = ""
## 已探测的 Python 版本缓存
var _probed_python_version: String = ""
## 已探测的 SCons 目录（探测缓存键）
var _probed_scons_dir: String = ""
## 已探测的 SCons 版本缓存
var _probed_scons_version: String = ""

## 底层进程运行器
var _runner: PipeProcessRunner
#endregion

#region 工厂与生命周期
## 创建构建器实例并应用持久化配置（校验失败时由 setter 回退内置并打印警告）。
static func create(
	custom_python_path: String = "",
	custom_scons_dir: String = ""
) -> GodotBuilder:
	var builder: GodotBuilder = GodotBuilder.new()
	if not custom_python_path.is_empty():
		await builder.set_custom_python(custom_python_path)
	if not custom_scons_dir.is_empty():
		await builder.set_scons_dir(custom_scons_dir)
	return builder

func _init() -> void:
	var config: PipeProcessConfig = PipeProcessConfig.new()
	config.enable_data_bridge = false
	_runner = PipeProcessRunner.new(config)
	_runner.process_stdout_received.connect(_on_process_stdout_received)
	_runner.process_stderr_received.connect(_on_process_stderr_received)
#endregion

#region 配置
## 设置 scons 工具目录；验证失败时回退内置 SCons 并打印警告。[br][br]
## [param dir] SCons 安装目录（res:// 或绝对路径）
## [return] 验证通过并生效时返回 true
func set_scons_dir(dir: String) -> bool:
	var global_path: String = ProjectSettings.globalize_path(dir)
	if global_path.is_empty() or (await check_scons(global_path)).is_empty():
		scons_dir = BUILT_IN_SCONS_DIR
		Console.log_warning("自定义 SCons 目录无效，已回退内置 SCons：%s" % dir)
		return false
	
	scons_dir = global_path
	return true

## 设置自定义 Python 解释器路径；验证失败时回退内置解释器并打印警告。[br][br]
## [param path] Python 解释器路径（res:// 或绝对路径）
## [return] 验证通过并生效时返回 true
func set_custom_python(path: String) -> bool:
	var global_path: String = ProjectSettings.globalize_path(path)
	var version: String = await _probe_python_version(global_path)
	if version.is_empty():
		python_path = ""
		Console.log_warning("自定义 Python 解释器不可用，已回退内置解释器：%s" % path)
		return false
	
	python_path = global_path
	_probed_python_path = global_path
	_probed_python_version = version
	return true
#endregion

#region 运行时解压
## 确保嵌入式 Python 运行时与 SCons 已落盘：打包模式首次运行从 PCK 解压到
## 可执行文件旁（引擎将工作目录固定为 exe 目录），开发模式使用资源目录即就绪。
## [return] 就绪返回 true
static func ensure_runtime_extracted() -> bool:
	var platform: String = _get_platform_name()
	if _runtime_ready(platform):
		return true
	var dest_root: String = _runtime_root()
	if DirAccess.dir_exists_absolute(dest_root):
		_delete_tree(dest_root)
	# 源路径保留 res:// 前缀：打包模式下从 PCK 虚拟文件系统读取
	if not _copy_tree(RUNTIME_BASE.path_join(platform), dest_root.path_join(EMBEDDINGS_DIR_NAME).path_join(platform)):
		Console.log_error("运行时解压失败：%s" % RUNTIME_BASE.path_join(platform))
		return false
	if not _copy_tree(BUILT_IN_SCONS_DIR, dest_root.path_join(SITE_PACKAGES_DIR_NAME)):
		Console.log_error("SCons 解压失败：%s" % BUILT_IN_SCONS_DIR)
		return false
	Console.log_info("[color=#65d98b]嵌入式运行时已解压到：%s[/color]" % dest_root)
	return true

## 运行时根目录：res://python 全局化后的路径。开发模式为资源目录绝对路径；
## 打包模式下引擎将工作目录固定为 exe 目录（main.cpp 模板构建无条件 set_cwd），
## 相对路径同样解析到 exe 旁 python/，两种模式路径结构完全同构。
static func _runtime_root() -> String:
	return ProjectSettings.globalize_path(RUNTIME_ROOT)

## 运行时是否已就绪：解释器、标准库、SCons 均存在（幂等检查解压目标/资源目录）。
static func _runtime_ready(platform: String) -> bool:
	var embedding_base: String = _runtime_root().path_join(EMBEDDINGS_DIR_NAME).path_join(platform)
	var interpreter: String = embedding_base.path_join(PYTHON_EXECUTABLE_WINDOWS if platform == PLATFORM_WINDOWS else PYTHON_EXECUTABLE_UNIX)
	if not FileAccess.file_exists(interpreter):
		return false
	var stdlib: String = embedding_base.path_join(STDLIB_DIR_WINDOWS if platform == PLATFORM_WINDOWS else STDLIB_DIR_UNIX)
	if not DirAccess.dir_exists_absolute(stdlib):
		return false
	return DirAccess.dir_exists_absolute(_runtime_root().path_join(SITE_PACKAGES_DIR_NAME).path_join(SCONS_PACKAGE_DIR_NAME))

## 递归复制目录树（保留隐藏文件，不跟随链接）；源为 res:// 时经 PCK 虚拟文件系统读取。
static func _copy_tree(src: String, dst: String) -> bool:
	if not DirAccess.dir_exists_absolute(src):
		return false
	if DirAccess.make_dir_recursive_absolute(dst) != OK:
		return false
	var dir: DirAccess = DirAccess.open(src)
	if dir == null:
		return false
	for file_name: String in dir.get_files():
		if not _copy_file(src.path_join(file_name), dst.path_join(file_name)):
			return false
	for sub_dir: String in dir.get_directories():
		if not _copy_tree(src.path_join(sub_dir), dst.path_join(sub_dir)):
			return false
	return true

## 复制单个文件（FileAccess 直读直写，兼容打包模式下 res:// 源）。
static func _copy_file(src: String, dst: String) -> bool:
	var src_file: FileAccess = FileAccess.open(src, FileAccess.READ)
	if src_file == null:
		return false
	var dst_file: FileAccess = FileAccess.open(dst, FileAccess.WRITE)
	if dst_file == null:
		return false
	dst_file.store_buffer(src_file.get_buffer(src_file.get_length()))
	return true

## 递归删除目录树。
static func _delete_tree(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for file_name: String in dir.get_files():
		dir.remove(file_name)
	for sub_dir: String in dir.get_directories():
		_delete_tree(path.path_join(sub_dir))
	DirAccess.remove_absolute(path)
#endregion

#region 构建执行
## 执行一次构建。[br]
## [param source_path] Godot 引擎源码根目录（res:// 或绝对路径）[br]
## [param profile_path] 编译配置文件路径（res:// 或绝对路径）；为空时使用源码目录下 PROFILE_FILE_NAME（SConstruct 自动加载）
func build(source_path: String, profile_path: String = "") -> PipeProcessHandle:
	var global_source_path: String = ProjectSettings.globalize_path(source_path)
	var full_args: PackedStringArray = PackedStringArray(
		["-c", _scons_bootstrap_code(_resolve_scons_dir()), ARG_DIRECTORY_TEMPLATE % global_source_path]
	)
	if not profile_path.is_empty():
		full_args.append(ARG_PROFILE_TEMPLATE % ProjectSettings.globalize_path(profile_path))
	
	var environments: Dictionary[String, String] = _python_environments()
	var encryption_key: String = SecretStore.get_key()
	if not encryption_key.is_empty():
		environments[ENV_SCRIPT_ENCRYPTION_KEY] = encryption_key
	
	return _runner.run(_resolve_interpreter(), full_args, environments)

## 以指定参数直接运行 SCons（使用 scons_dir），立即返回进程句柄。[br]
## [param args] SCons 命令行参数（如 ["--version"]、["--directory=...", "target=editor"]）
## [return] 已启动进程的句柄；进程启动失败时返回 null
func run_scons(args: PackedStringArray) -> PipeProcessHandle:
	return _run_scons_in(_resolve_scons_dir(), args)

## 在指定 SCons 安装目录下以参数运行 SCons（内部实现）。
func _run_scons_in(global_scons_dir: String, args: PackedStringArray) -> PipeProcessHandle:
	var full_args: PackedStringArray = PackedStringArray(["-c", _scons_bootstrap_code(global_scons_dir)])
	full_args.append_array(args)
	return _runner.run(_resolve_interpreter(), full_args, _python_environments())

## 取消正在运行的构建：先发送中断（Ctrl+C，让 SCons 清理子进程后优雅退出），失败则强制终止。[br]
## [param handle] 构建返回的进程句柄
func cancel_build(handle: PipeProcessHandle) -> Error:
	if handle == null:
		return Error.ERR_INVALID_PARAMETER
	var interrupt_error: Error = _runner.interrupt(handle.pid)
	if interrupt_error != OK:
		return _runner.kill(handle.pid)
	return OK

## 强制终止构建进程（中断无效时的兜底）。[br]
## [param handle] 构建返回的进程句柄
func kill_build(handle: PipeProcessHandle) -> Error:
	if handle == null:
		return Error.ERR_INVALID_PARAMETER
	return _runner.kill(handle.pid)
#endregion

#region 环境探测
## 检查 python 环境，返回版本号（如 "3.14.7"）；不可用返回空字符串。
## 同一解释器已探测过时直接返回缓存，不重复启动进程。
func check_python() -> String:
	var interpreter: String = _resolve_interpreter()
	if interpreter == _probed_python_path:
		return _probed_python_version
	_probed_python_version = await _probe_python_version(interpreter, _python_environments())
	_probed_python_path = interpreter
	return _probed_python_version

## 探测指定 Python 解释器版本；不可用返回空字符串。[br][br]
## [param interpreter_path] 解释器路径（已全局化）[br]
## [param environments] 进程环境变量（默认空，不注入运行时 lib 目录）
func _probe_python_version(interpreter_path: String, environments: Dictionary[String, String] = {}) -> String:
	var handle: PipeProcessHandle = _runner.run(interpreter_path, [ARG_VERSION], environments)
	if handle == null:
		return ""
	var record: PipeProcessRecord = await handle.exited
	if record.exit_code != 0:
		return ""
	# 取首个以 "Python" 开头的输出行，如 "Python 3.14.7"
	for line: String in record.output_lines:
		var text: String = line.strip_edges()
		if text.begins_with(PYTHON_VERSION_PREFIX):
			return text.trim_prefix(PYTHON_VERSION_PREFIX).strip_edges()
	return ""

## 检查指定目录的 SCons 是否可用，返回版本号（如 "4.11.0"）；不可用返回空字符串。
## 同一目录已探测过时直接返回缓存，不重复启动进程。
## [param scons_directory] SCons 安装目录（res:// 或绝对路径）；传空串用 scons_dir
func check_scons(scons_directory: String = "") -> String:
	var target_global: String = _resolve_scons_dir() if scons_directory.is_empty() else ProjectSettings.globalize_path(scons_directory)
	if target_global == _probed_scons_dir:
		return _probed_scons_version
	var handle: PipeProcessHandle = _run_scons_in(target_global, PackedStringArray([ARG_VERSION]))
	if handle == null:
		return ""
	var record: PipeProcessRecord = await handle.exited
	if record.exit_code != 0:
		return ""
	# 取首个以 "SCons: v" 开头的输出行，如 "SCons: v4.11.0.511b69a, ..."
	for line: String in record.output_lines:
		var text: String = line.strip_edges()
		if text.begins_with(SCONS_VERSION_PREFIX):
			var version_part: String = text.trim_prefix(SCONS_VERSION_PREFIX).split(",")[0].strip_edges()
			var version: String = ".".join(version_part.split(".").slice(0, VERSION_SEGMENT_COUNT))
			_probed_scons_dir = target_global
			_probed_scons_version = version
			return version
	return ""

## 检测 Godot 源码目录在当前环境可构建的平台列表（等价 `scons platform=list`）。[br]
## [param source_dir] Godot 引擎源码根目录（res:// 或绝对路径）
## [return] 平台名数组（如 ["windows"]）；检测失败返回空数组
func check_supported_platforms(source_dir: String) -> PackedStringArray:
	var global_source_dir: String = ProjectSettings.globalize_path(source_dir)
	var handle: PipeProcessHandle = run_scons(PackedStringArray([ARG_PLATFORM_LIST, ARG_DIRECTORY_TEMPLATE % global_source_dir]))
	if handle == null:
		return PackedStringArray()
	var record: PipeProcessRecord = await handle.exited
	if record.exit_code != 0:
		return PackedStringArray()
	var platforms: PackedStringArray = PackedStringArray()
	var in_list: bool = false
	# 从 "The following platforms are available:" 到空行/结束标记之间的每行即为一个平台
	for line: String in record.output_lines:
		if line.contains(PLATFORM_LIST_MARKER):
			in_list = true
			continue
		if in_list:
			var text: String = line.strip_edges()
			if text.is_empty():
				continue
			if text.begins_with(PLATFORM_LIST_END_MARKER):
				break
			platforms.append(text)
	return platforms

## 获取 Godot 源码目录的 SCons 选项帮助全文（等价 `scons --help`）。[br]
## [param source_dir] Godot 引擎源码根目录（res:// 或绝对路径）。[br]
## [param extra_args] 附加 SCons 参数（如 ["accesskit=no", "d3d12=no"]）[br]
## [return] 进程记录；进程启动失败返回 null
func scons_help(source_dir: String, extra_args: PackedStringArray = PackedStringArray()) -> PipeProcessRecord:
	var global_source_dir: String = ProjectSettings.globalize_path(source_dir)
	var args: PackedStringArray = PackedStringArray([ARG_HELP, ARG_DIRECTORY_TEMPLATE % global_source_dir])
	args.append_array(extra_args)
	var handle: PipeProcessHandle = run_scons(args)
	if handle == null:
		return null
	return await handle.exited
#endregion

#region scons --help 磁盘缓存
## 获取 Godot 源码目录的 scons --help 全文，优先读磁盘缓存，未命中则运行子进程并写缓存。[br]
## 缓存键为「源码目录 + 版本 + SConstruct/version.py 内容哈希」：第三方改动 SConstruct 后自动失效。[br]
## [param source_dir] Godot 引擎源码根目录（res:// 或绝对路径）
## [return] 帮助全文；获取失败返回空字符串
func get_scons_help_cached(source_dir: String) -> String:
	var global_source_dir: String = ProjectSettings.globalize_path(source_dir)
	var cache_path: String = _help_cache_path(global_source_dir)
	if FileAccess.file_exists(cache_path):
		var cached: String = FileAccess.get_file_as_string(cache_path)
		if not cached.is_empty():
			return cached
	var record: PipeProcessRecord = await scons_help(source_dir)
	if record == null or record.exit_code != 0:
		return ""
	var output: String = "\n".join(record.output_lines)
	if output.is_empty():
		return ""
	var cache_dir: String = cache_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(cache_dir)
	var file: FileAccess = FileAccess.open(cache_path, FileAccess.WRITE)
	if file == null:
		return output
	file.store_string(output)
	file.close()
	return output

## 清空 scons --help 磁盘缓存（缓存键失效异常时的兜底）。
static func clear_scons_help_cache() -> void:
	var cache_dir: String = AppData.executable_path.path_join(HELP_CACHE_DIR_NAME)
	var dir: DirAccess = DirAccess.open(cache_dir)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)

## 计算 scons --help 缓存文件路径：目录 + 版本 + SConstruct/version.py 内容哈希。
static func _help_cache_path(global_source_dir: String) -> String:
	var sconstruct_path: String = global_source_dir.path_join(FILE_SCONSTRUCT)
	var version_path: String = global_source_dir.path_join(FILE_VERSION_PY)
	var payload: String = global_source_dir + "\n" + Utils.parse_godot_version(global_source_dir)
	payload += "\n" + FileAccess.get_file_as_string(sconstruct_path)
	payload += "\n" + FileAccess.get_file_as_string(version_path)
	return AppData.executable_path.path_join(HELP_CACHE_DIR_NAME).path_join(payload.sha256_text() + HELP_CACHE_FILE_EXTENSION)
#endregion

#region 路径与环境解析
## 获取当前生效的 Python 解释器路径：自定义路径优先，否则内置运行时。
func _resolve_interpreter() -> String:
	if not python_path.is_empty():
		return python_path
	var executable_name: String = PYTHON_EXECUTABLE_WINDOWS if _get_platform_name() == PLATFORM_WINDOWS else PYTHON_EXECUTABLE_UNIX
	return _runtime_root().path_join(EMBEDDINGS_DIR_NAME).path_join(_get_platform_name()).path_join(executable_name)

## 获取当前生效的 SCons 目录（res:// 或绝对路径全局化；打包模式下相对路径基于 exe 目录解析）。
func _resolve_scons_dir() -> String:
	return ProjectSettings.globalize_path(scons_dir)

## 构造运行 SCons 的 -c 引导代码：把本地 SCons 目录注入 sys.path 首位，再调用 SCons 主入口。
static func _scons_bootstrap_code(global_scons_dir: String) -> String:
	var escaped: String = global_scons_dir.replace("\\", "/").replace("'", "\\'")
	var patch_code: String = FileAccess.get_file_as_string(SCONS_BOOTSTRAP_PATCH_SCRIPT).dedent().trim_prefix("\n")
	return SCONS_BOOTSTRAP_CODE_TEMPLATE % [escaped, patch_code]

## 构建嵌入式 Python 运行所需的环境变量：UTF-8 文本模式、无缓冲输出、禁用用户级
## site-packages（隔离依赖），并在使用内置运行时（linux/macos）注入其 lib 目录。
func _python_environments() -> Dictionary[String, String]:
	var environments: Dictionary[String, String] = {
		ENV_PYTHON_UTF8: "1",
		ENV_PYTHON_UNBUFFERED: "1",
		ENV_PYTHON_NO_USER_SITE: "1",
	}
	if not python_path.is_empty():
		return environments
	var platform_name: String = _get_platform_name()
	var library_dir: String = _runtime_root().path_join(EMBEDDINGS_DIR_NAME).path_join(platform_name).path_join(STDLIB_DIR_UNIX)
	match platform_name:
		PLATFORM_LINUX:
			_append_library_path(environments, ENV_LD_LIBRARY_PATH, library_dir)
		PLATFORM_MACOS:
			_append_library_path(environments, ENV_DYLD_LIBRARY_PATH, library_dir)
	return environments

## 将运行时 lib 目录追加到共享库搜索路径环境变量（保留已有条目）。
static func _append_library_path(environments: Dictionary[String, String], env_name: String, library_dir: String) -> void:
	var current: String = OS.get_environment(env_name)
	if current.is_empty():
		environments[env_name] = library_dir
	else:
		environments[env_name] = library_dir + PATH_LIST_SEPARATOR + current

## 获取当前宿主平台名（小写，与运行时目录名一致）。
static func _get_platform_name() -> String:
	match OS.get_name():
		"Windows":
			return PLATFORM_WINDOWS
		"Linux":
			return PLATFORM_LINUX
		"macOS":
			return PLATFORM_MACOS
		_:
			return PLATFORM_WINDOWS
#endregion

#region 输出回调
func _on_process_stdout_received(_pid: int, output: String) -> void:
	Console.log_info(output)

func _on_process_stderr_received(_pid: int, output: String) -> void:
	Console.log_error(output)
#endregion
