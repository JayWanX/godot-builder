class_name SettingConfirmationDialog
extends ConfirmationDialog

## 路径字段控件场景（复用构建选项表单的路径字段）
const PATH_FIELD_SCENE: PackedScene = preload("../controls/fields/path_field.tscn")
## 字符串字段控件场景（复用构建选项表单的字符串字段）
const STRING_FIELD_SCENE: PackedScene = preload("../controls/fields/string_field.tscn")

## 确认时发出，携带输入值（空串表示使用内置运行时 / 内置 SCons）。
signal settings_changed(python_path: String, scons_dir: String)

## 字段容器（场景内定义）
@export var fields_container: VBoxContainer

## 应用设置数据引用（确认后由调用方同步持久化）
var _app_data: AppData = null
## Python 解释器路径字段
var _python_field: PathField = null
## SCons 库目录字段
var _scons_field: PathField = null
## PCK 加密编译密钥字段
var _encryption_key_field: StringField = null

## 注入应用设置数据并创建字段控件。
func setup(app_data: AppData) -> void:
	_app_data = app_data
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
	var python_path: String = _python_field.line_edit.text.strip_edges()
	var scons_dir: String = _scons_field.line_edit.text.strip_edges()
	var encryption_key: String = _encryption_key_field.line_edit.text.strip_edges()
	_persist(python_path, scons_dir, encryption_key)
	settings_changed.emit(python_path, scons_dir)

## 以磁盘最新 AppData 为准写入输入值并保存，同时同步内存实例。
func _persist(python_path: String, scons_dir: String, encryption_key: String) -> void:
	SecretStore.set_key(encryption_key)
	
	var latest: AppData = AppData.load()
	latest.custom_python_path = python_path
	latest.custom_scons_dir = scons_dir
	latest.save()
	
	_app_data.custom_python_path = python_path
	_app_data.custom_scons_dir = scons_dir

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
	_python_field.set_control(_app_data.custom_python_path)
	_scons_field.set_control(_app_data.custom_scons_dir)
	_encryption_key_field.set_control(SecretStore.get_key())
