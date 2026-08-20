extends Control

const BuildStatus = BuildStatusBar.Status
const ICON_FOLDER_OPEN = preload("uid://bmj7pj12ibi5r")
const ICON_SOURCE_DIR = preload("uid://ij71g4ykokhq")
const ICON_COG = preload("uid://da81yjbhyxym")
const ICON_CLEAR = preload("uid://br3cdi5g07ytx")
const ICON_TERMINAL = preload("uid://de6go24h2tgw2")

const KEY_STATUS_TEXT: StringName = &"status_text"
const KEY_STATUS_TOOLTIP: StringName = &"status_tooltip"
const PROFILE_FILE_NAME: String = GodotBuilder.PROFILE_FILE_NAME
## 配置变更刷新防抖时长（秒）：合并相邻字段变更，避免每个按键全量重算
const CONFIG_UPDATE_DEBOUNCE: float = 0.15
## 取消构建中断超时（秒）：中断后仍未退出则强制终止
const CANCEL_FALLBACK_TIMEOUT: float = 3.0
## 构建日志目录名（位于可执行文件旁）
const LOG_DIR_NAME: String = "logs"

enum MoreOptionPopupMenuAction {
	CLEAR_CACHE,
	OPEN_TERMINAL,
	SETTING,
}

@export var source_button: Button
@export var source_popup_menu: PopupMenu
@export var more_option_button: Button
@export var more_option_popup_menu: PopupMenu
@export var setting_confirmation_dialog: ConfirmationDialog
@export var source_info_label: RichTextLabel
@export var build_status_bar: BuildStatusBar
@export var config_preview_button: Button
@export var config_preview_window: ConfigPreviewWindow
@export var config_import_button: Button
@export var config_export_button: Button

@export var build_button: Button
@export var cancel_button: Button

@export var group_nav_panel: GroupNavPanel
@export var config_form_panel: ConfigFormPanel
@export var summary_panel: SummaryPanel
@export var console_panel: ConsolePanel

@export var file_dialog: FileDialog

var app_data: AppData = null
var builder: GodotBuilder = null
var config_store: ConfigStore = null

var file_dialog_delegate: Callable = Callable()

var _env_ready: bool = false
var _env_status: Dictionary[StringName, String] = {}
var _loading: bool = false
var _building: bool = false
var _current_source_dir: String = ""
## 当前构建进程句柄（取消构建用）
var _build_handle: PipeProcessHandle = null
## 是否已请求取消当前构建
var _build_cancelled: bool = false
## 配置变更防抖计时器（合并连续变更，避免每按键全量刷新）
var _config_update_timer: SceneTreeTimer = null
## 当前构建日志记录器
var _build_logger: BuildLogger = null

func _ready() -> void:
	app_data = AppData.load()
	build_status_bar.set_status(BuildStatus.PROGRESS, "准备嵌入式运行时...")
	if not GodotBuilder.ensure_runtime_extracted():
		build_status_bar.set_status(BuildStatus.ERROR, "嵌入式运行时异常")
		Console.log_error("嵌入式运行时准备失败：请确认程序目录可写")
	builder = await GodotBuilder.create(
		app_data.custom_python_path,
		app_data.custom_scons_dir
	)
	setting_confirmation_dialog.setup(app_data)
	_setup_source_popup_menu()
	_setup_more_option_popup_menu()
	_env_ready = await _check_env()

func _setup_source_popup_menu() -> void:
	source_popup_menu.clear()
	var scanned_source_dirs: Dictionary[String, String] = Utils.scan_godot_source_dir(app_data.source_scan_dir)
	if scanned_source_dirs.is_empty():
		return
	source_popup_menu.add_icon_item(ICON_FOLDER_OPEN, "打开...", 0)
	source_popup_menu.set_item_tooltip(0, "从文件系统选择源码目录")
	source_popup_menu.add_separator()
	for source_path: String in scanned_source_dirs:
		var item_index: int = source_popup_menu.item_count
		source_popup_menu.add_icon_item(ICON_SOURCE_DIR, source_path)
		source_popup_menu.set_item_tooltip(item_index, scanned_source_dirs.get(source_path))

func _setup_more_option_popup_menu() -> void:
	more_option_popup_menu.clear()
	more_option_popup_menu.add_icon_item(ICON_CLEAR, "清除缓存    ", MoreOptionPopupMenuAction.CLEAR_CACHE)
	more_option_popup_menu.add_icon_item(ICON_TERMINAL, "打开终端    ", MoreOptionPopupMenuAction.OPEN_TERMINAL)
	more_option_popup_menu.add_icon_item(ICON_COG, "设置    ", MoreOptionPopupMenuAction.SETTING)

## 加载源码目录并构建选项界面。[br][br]
## [param source_dir] Godot 源码目录路径（res:// 或绝对路径）
func _load_source(source_dir: String) -> void:
	if _loading: return
	_loading = true

	# 1. 环境未就绪则中止（python / SCons 已在启动时检查）
	if not _env_ready:
		return

	# 2. 校验目录并获取版本
	build_status_bar.staging_status()
	build_status_bar.set_status(BuildStatus.PROGRESS, "校验源码目录...")
	var godot_version: String = Utils.parse_godot_version(source_dir)
	if godot_version.is_empty():
		Console.log_error("所选目录不是有效的 Godot 源码目录或源码已损坏: %s" % source_dir)
		build_status_bar.restore_status()
		_loading = false
		return

	# 3. 检测可构建平台
	if (await _check_supported_platforms(source_dir)).is_empty():
		Console.log_error("无可构建的平台，请下载相关的编译工具链！")
	build_status_bar.staging_status()

	# 4. 解析 scons --help 构建选项元数据（磁盘缓存，缓存键含源码内容哈希，第三方改动自动失效）
	build_status_bar.set_status(BuildStatus.PROGRESS, "解析源码构建选项元数据...")
	var scons_help_output: String = await builder.get_scons_help_cached(source_dir)
	if scons_help_output.is_empty():
		Console.log_error("获取 scons --help 失败: %s" % source_dir)
		build_status_bar.restore_status()
		_loading = false
		return
	var new_options: BuildOptions = BuildOptions.new(scons_help_output)

	# 5. 加载源码目录 custom.py 构建配置
	build_status_bar.set_status(BuildStatus.PROGRESS, "加载默认编译配置...")
	var new_config: Dictionary = {}
	var profile_text: String = FileAccess.get_file_as_string(
		source_dir.path_join(PROFILE_FILE_NAME)
	)
	if not profile_text.is_empty():
		new_config = ProfileConverter.profile_to_config(
			profile_text, new_options
		)

	# 6. 构建界面
	build_status_bar.set_status(BuildStatus.PROGRESS, "构建用户界面...")
	config_store = ConfigStore.new(new_config, new_options)
	summary_panel.setup(config_store)
	config_form_panel.setup(config_store)
	group_nav_panel.setup(new_options.get_all_groups())
	Console.log_info("[color=#65d98b]构建选项加载完成（%d 个分组）[/color]" % new_options.get_all_groups().size())

	# 7. 更新源码路径显示
	_current_source_dir = source_dir
	source_info_label.text = "[url=%s]%s[/url]" % [source_dir, godot_version]
	source_info_label.tooltip_text = source_dir

	build_status_bar.restore_status()
	_loading = false

## 检查编译环境（python / SCons）是否就绪。
func _check_env() -> bool:
	build_status_bar.set_status(BuildStatus.PROGRESS, "检测 Python 环境...")
	var python_version: String = await builder.check_python()
	if python_version.is_empty():
		build_status_bar.set_status(BuildStatus.ERROR, "Python 环境异常")
		build_status_bar.set_tooltip("")
		_env_status = {
			KEY_STATUS_TEXT: build_status_bar.get_current_status_text(),
			KEY_STATUS_TOOLTIP: build_status_bar.get_current_status_tooltip()
		}
		return false
	build_status_bar.set_status(BuildStatus.OK, "Python 已就绪")
	build_status_bar.set_tooltip("[color=#65d98b]✓ Python %s[/color]" % python_version)

	build_status_bar.set_status(BuildStatus.PROGRESS, "检测 SCons 构建工具...")
	var scons_version: String = await builder.check_scons()
	if scons_version.is_empty():
		build_status_bar.set_status(BuildStatus.ERROR, "SCons 构建工具异常")
		_env_status = {
			KEY_STATUS_TEXT: build_status_bar.get_current_status_text(),
			KEY_STATUS_TOOLTIP: build_status_bar.get_current_status_tooltip()
		}
		return false
	build_status_bar.set_status(BuildStatus.OK, "SCons 已就绪")
	build_status_bar.append_tooltip("\n[color=#65d98b]✓ SCons %s[/color]" % scons_version)
	_env_status = {
		KEY_STATUS_TEXT: build_status_bar.get_current_status_text(),
		KEY_STATUS_TOOLTIP: build_status_bar.get_current_status_tooltip()
	}
	return true

## 检测源码目录可构建的平台列表（失败仅降级提示，不中止流程）。
func _check_supported_platforms(source_dir: String) -> PackedStringArray:
	var supported_platforms: PackedStringArray = PackedStringArray()
	if source_dir.is_empty() or not DirAccess.dir_exists_absolute(source_dir):
		return supported_platforms

	build_status_bar.set_status(BuildStatus.PROGRESS, "检测可构建平台...")
	supported_platforms = await builder.check_supported_platforms(ProjectSettings.globalize_path(source_dir))
	if supported_platforms.is_empty():
		build_status_bar.set_status(BuildStatus.ERROR, "构建环境异常")
		return supported_platforms

	build_status_bar.set_tooltip(_env_status.get(KEY_STATUS_TOOLTIP))
	for platform_name: String in supported_platforms:
		build_status_bar.append_tooltip("\n[color=#65d98b]✓ %s[/color]" % platform_name)
	build_status_bar.set_status(BuildStatus.OK, "环境就绪 · 可构建 %d 个平台" % supported_platforms.size())
	return supported_platforms

func _reset_file_dialog_state() -> void:
	file_dialog_delegate = Callable()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_ANY
	file_dialog.filters = PackedStringArray()
	file_dialog.current_file = ""

func _on_config_changed(_option_key: String) -> void:
	# 防抖：合并相邻变更（如字符串字段逐键触发），超时后一次性刷新
	if _config_update_timer:
		return
	_config_update_timer = get_tree().create_timer(CONFIG_UPDATE_DEBOUNCE)
	_config_update_timer.timeout.connect(_flush_config_update)

## 防抖刷新回调：重算分组修改计数与摘要。
func _flush_config_update() -> void:
	_config_update_timer = null
	if not is_instance_valid(config_store):
		return
	group_nav_panel.set_modified_counts(config_store.count_modified_by_group())
	summary_panel.refresh()

func _on_more_option_button_pressed() -> void:
	var anchor: Vector2 = more_option_button.global_position + Vector2(0, more_option_button.size.y)
	more_option_popup_menu.popup(Rect2i(anchor, more_option_button.size))

func _on_source_button_pressed() -> void:
	if source_popup_menu.item_count == 0:
		file_dialog_delegate = _load_source
		file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		file_dialog.popup_file_dialog()
		return
	var anchor: Vector2 = source_button.global_position + Vector2(0, source_button.size.y)
	source_popup_menu.popup(Rect2i(anchor, source_button.size))

func _on_file_dialog_selected(context: String) -> void:
	if file_dialog_delegate.is_valid():
		file_dialog_delegate.call(context)
	_reset_file_dialog_state()

func _on_file_dialog_close_requested() -> void:
	_reset_file_dialog_state()

func _on_build_button_pressed() -> void:
	if _building or _current_source_dir.is_empty():
		Console.log_warning("未加载源码")
		return

	_building = true
	_build_cancelled = false
	build_status_bar.staging_status()
	build_status_bar.set_status(BuildStatus.PROGRESS, "写入临时编译配置文件...")
	var profile_text: String = ProfileConverter.config_to_profile(
		config_store.get_full_config(), config_store.get_options(), true
	)
	var profile_file: FileAccess = FileAccess.create_temp(
		FileAccess.WRITE, "godot_build_profile", ".py"
	)
	if profile_file == null:
		Console.log_error("写入临时编译配置文件失败：%s" % FileAccess.get_open_error())
		build_status_bar.restore_status()
		_building = false
		return
	profile_file.store_string(profile_text)
	profile_file.close()
	var profile_path: String = profile_file.get_path_absolute()

	build_status_bar.set_status(BuildStatus.PROGRESS, "正在构建源码...")
	# 重新加载 PCK 加密编译密钥（设置保存后立即生效），并在构建时注入环境变量
	SecretStore.reload()
	if SecretStore.get_key().is_empty():
		Console.log_info("未注入 PCK 加密编译密钥")
	else:
		Console.log_info("已注入 PCK 加密编译密钥")
	var handle: PipeProcessHandle = builder.build(_current_source_dir, profile_path)
	if handle == null:
		Console.log_error("启动构建进程失败")
		build_status_bar.restore_status()
		_building = false
		return
	_build_handle = handle
	_set_building_controls(true)
	# 启动构建日志：捕获进程 stdout/stderr 原始输出
	_build_logger = BuildLogger.new()
	if _build_logger.start(AppData.executable_path.path_join(LOG_DIR_NAME)):
		handle.stdout_received.connect(_build_logger.append)
		handle.stderr_received.connect(_build_logger.append)
	else:
		_build_logger = null
	var record: PipeProcessRecord = await handle.exited
	_build_handle = null
	_set_building_controls(false)
	if _build_cancelled:
		build_status_bar.set_status(BuildStatus.WARNING, "构建已取消")
		Console.log_warning("构建已取消")
		_finish_build()
		return
	if record.exit_code != 0:
		build_status_bar.set_status(BuildStatus.ERROR, "构建失败")
		Console.log_error("构建失败: %s" % record.exit_code)
		_finish_build()
		return

	build_status_bar.set_status(BuildStatus.OK, "构建成功")
	var output_dir: String = _current_source_dir.path_join("bin")
	Console.log_info(
		"[color=#65d98b]构建成功：[url=%s]%s[/url][/color]" % [output_dir, output_dir]
	)
	_finish_build()

## 收尾构建：关闭日志文件、恢复构建前状态并解锁构建入口。
func _finish_build() -> void:
	if _build_logger:
		_build_logger.stop()
		Console.log_info(
			"[color=#65d98b]构建日志：[url=%s]%s[/url][/color]" % [_build_logger.get_path(), _build_logger.get_path()]
		)
		_build_logger = null
	build_status_bar.restore_status()
	_building = false

## 构建期间禁用构建按钮、启用取消按钮；构建结束反向切换。[br]
## 两按钮常驻避免工具栏布局跳动，禁用态即状态提示。
func _set_building_controls(building: bool) -> void:
	build_button.disabled = building
	cancel_button.disabled = not building

## 取消当前构建：发送中断信号，超时未退出则强制终止。
func _on_cancel_build_requested() -> void:
	if not _building or _build_handle == null:
		return
	_build_cancelled = true
	build_status_bar.set_status(BuildStatus.WARNING, "正在取消构建...")
	var cancel_error: Error = builder.cancel_build(_build_handle)
	if cancel_error != OK:
		Console.log_error("中断构建进程失败：%s" % cancel_error)
	var fallback: SceneTreeTimer = get_tree().create_timer(CANCEL_FALLBACK_TIMEOUT)
	fallback.timeout.connect(
		func() -> void:
			if _build_handle != null and OS.is_process_running(_build_handle.pid):
				Console.log_warning("中断超时，强制终止构建进程")
				builder.kill_build(_build_handle)
	)

func _on_source_info_label_meta_clicked(meta: Variant) -> void:
	OS.shell_show_in_file_manager(str(meta))

func _on_source_popup_menu_id_pressed(id: int) -> void:
	if id == 0:
		file_dialog_delegate = _load_source
		file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		file_dialog.popup_file_dialog()
		return
	var source_path: String = source_popup_menu.get_item_text(id)
	await _load_source(source_path)

func _on_config_preview_button_pressed() -> void:
	if _current_source_dir.is_empty() or not is_instance_valid(config_store):
		Console.log_warning("未加载源码")
		return
	await get_tree().process_frame
	config_preview_window.setup(config_store)

func _on_config_import_button_pressed() -> void:
	if _current_source_dir.is_empty() or not is_instance_valid(config_store):
		Console.log_warning("未加载源码")
		return
	file_dialog_delegate = (
		func(file_path: String) -> void:
			var profile_text: String = FileAccess.get_file_as_string(file_path)
			var config: Dictionary = ProfileConverter.profile_to_config(profile_text, config_store.get_options())
			if config.is_empty():
				Console.log_warning("导入的配置为空")
				return
			config_form_panel.apply_config(config)
			Console.log_info("[color=#65d98b]已导入配置（%d 项差异）[/color]" % config.size())
	)
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = ["*.py"]
	file_dialog.popup_file_dialog()

func _on_config_export_button_pressed() -> void:
	if _current_source_dir.is_empty() or not is_instance_valid(config_store):
		Console.log_warning("未加载源码")
		return
	file_dialog_delegate = (
		func(file_path: String) -> void:
			var profile_text: String = ProfileConverter.config_to_profile(config_store.get_profile_config(), config_store.get_options())
			var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
			if file == null:
				Console.log_error("文件写入失败： %s" % FileAccess.get_open_error())
				return
			file.store_string(profile_text)
			file.close()
			Console.log_info("[color=#65d98b]已导出配置：[url=%s]%s[/url][/color]" % [file_path, file_path])
	)
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.filters = ["*.py"]
	file_dialog.current_file = PROFILE_FILE_NAME
	file_dialog.popup_file_dialog()

func _on_more_option_popup_menu_id_pressed(id: int) -> void:
	match id:
		MoreOptionPopupMenuAction.CLEAR_CACHE:
			GodotBuilder.clear_scons_help_cache()
			Console.log_info("已清除 scons --help 缓存")
		MoreOptionPopupMenuAction.OPEN_TERMINAL:
			if _current_source_dir.is_empty():
				Utils.open_terminal(AppData.executable_path)
				return
			Utils.open_terminal(_current_source_dir)
		MoreOptionPopupMenuAction.SETTING:
			setting_confirmation_dialog.popup_centered()

func _on_setting_confirmation_dialog_settings_changed(python_path: String, scons_dir: String) -> void:
	if not python_path.is_empty():
		await builder.set_custom_python(python_path)
	if not scons_dir.is_empty():
		await builder.set_scons_dir(scons_dir)
	Console.log_info("[color=#65d98b]设置已保存[/color]")
	_env_ready = await _check_env()

func _on_group_nav_panel_group_selected(group_key: String) -> void:
	await config_form_panel.show_group(group_key)
	# 搜索模式下点击分组：滚动右侧面板定位到该分组的命中区段
	if not group_nav_panel.search_line_edit.text.is_empty():
		config_form_panel.scroll_to_group(group_key)

func _on_group_nav_panel_search_text_changed(query: String) -> void:
	config_form_panel.set_search_filter(query)
	group_nav_panel.set_search_match_counts(config_form_panel.get_search_match_counts())

func _on_group_nav_panel_reset_group_requested(group_key: String) -> void:
	config_form_panel.reset_group(group_key)
