class_name SettingConfirmationDialog
extends ConfirmationDialog

## 路径字段控件场景（复用构建选项表单的路径字段）
const PATH_FIELD_SCENE: PackedScene = preload("../controls/fields/path_field.tscn")
## 字符串字段控件场景（复用构建选项表单的字符串字段）
const STRING_FIELD_SCENE: PackedScene = preload("../controls/fields/string_field.tscn")

## 确认时发出，携带需重新校验的输入值（空串表示使用内置运行时 / 内置 SCons）。
signal settings_changed(python_path: String, scons_dir: String)

## 字段容器（场景内定义）
@export var fields_container: VBoxContainer

## 应用设置数据引用（确认后由调用方同步持久化）
var _app_data: AppData = null
## 引擎源码扫描目录字段
var _scan_dir_field: PathField = null
## Python 解释器路径字段
var _python_field: PathField = null
## SCons 库目录字段
var _scons_field: PathField = null
## 构建产物输出目录字段
var _output_field: PathField = null
## PCK 加密编译密钥字段
var _encryption_key_field: StringField = null

## 注入应用设置数据并创建字段控件。
func setup(app_data: AppData) -> void:
	_app_data = app_data
	_scan_dir_field = _create_path_field(
		"引擎源码扫描目录",
		_app_data.custom_source_scan_dir,
		"",
		"自动扫描该目录下的一级子目录以识别 Godot 源码，留空使用可执行文件旁的 sources/",
		"选择引擎源码扫描目录"
	)
	_python_field = _create_path_field(
		"Python 解释器",
		_app_data.custom_python_path,
		"",
		"自定义 Python 解释器路径，留空使用内置运行时",
		"选择 Python 解释器"
	)
	_scons_field = _create_path_field(
		"SCons 库目录",
		_app_data.custom_scons_dir,
		"",
		"自定义 SCons 库路径，留空使用内置 SCons",
		"选择 SCons 库目录"
	)
	_output_field = _create_path_field(
		"构建产物输出目录",
		_app_data.output_dir,
		"",
		"构建成功后把源码目录 bin/ 下的产物复制到该目录，留空不复制",
		"选择构建产物输出目录"
	)
	_encryption_key_field = _create_string_field(
		"PCK 加密编译密钥",
		SecretStore.get_key(),
		"",
		"SCRIPT_AES256_ENCRYPTION_KEY，构建时以环境变量注入，留空不注入"
	)
	_encryption_key_field.line_edit.secret = true
	_encryption_key_field.line_edit.clear_button_enabled = true

## 弹出前用最新设置回填字段（避免重复打开显示陈旧值）。
func _on_about_to_popup() -> void:
	_refresh_fields()

## 确认：持久化输入值（原始输入，校验回退由 builder 运行时完成）并发出变更信号。
func _on_confirmed() -> void:
	var scan_dir: String = _scan_dir_field.line_edit.text.strip_edges()
	var python_path: String = _python_field.line_edit.text.strip_edges()
	var scons_dir: String = _scons_field.line_edit.text.strip_edges()
	var output_dir: String = _output_field.line_edit.text.strip_edges()
	var encryption_key: String = _encryption_key_field.line_edit.text.strip_edges()
	_persist(scan_dir, python_path, scons_dir, output_dir, encryption_key)
	settings_changed.emit(python_path, scons_dir)

## 以磁盘最新 AppData 为准写入输入值并保存，同时同步内存实例。
func _persist(
	scan_dir: String,
	python_path: String,
	scons_dir: String,
	output_dir: String,
	encryption_key: String
) -> void:
	SecretStore.set_key(encryption_key)
	
	var latest: AppData = AppData.load()
	latest.custom_source_scan_dir = scan_dir
	latest.custom_python_path = python_path
	latest.custom_scons_dir = scons_dir
	latest.output_dir = output_dir
	latest.save()
	
	_app_data.custom_source_scan_dir = scan_dir
	_app_data.custom_python_path = python_path
	_app_data.custom_scons_dir = scons_dir
	_app_data.output_dir = output_dir

## 实例化一个路径字段并加入容器。
func _create_path_field(
	option_name: String, 
	current_value: Variant,
	default_value: Variant,
	tooltip: String, 
	dialog_title: String
) -> PathField:
	var field: PathField = PATH_FIELD_SCENE.instantiate()
	field.setup(option_name, current_value, default_value, tooltip)
	field.file_dialog.title = dialog_title
	fields_container.add_child(field)
	return field

## 实例化一个字符串字段并加入容器。
func _create_string_field(
	option_name: String, 
	current_value: Variant,
	default_value: Variant,
	tooltip: String
) -> StringField:
	var field: StringField = STRING_FIELD_SCENE.instantiate()
	field.setup(option_name, current_value, default_value, tooltip)
	fields_container.add_child(field)
	return field

## 以 AppData 当前值回填字段（静默，不触发 value_changed）。
func _refresh_fields() -> void:
	_scan_dir_field.set_control(_app_data.custom_source_scan_dir)
	_python_field.set_control(_app_data.custom_python_path)
	_scons_field.set_control(_app_data.custom_scons_dir)
	_output_field.set_control(_app_data.output_dir)
	_encryption_key_field.set_control(SecretStore.get_key())
