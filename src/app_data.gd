class_name AppData
extends Resource

const DEFAULT_SAVE_PATH: String = "app_data.tres"
const SCAN_DIR_NAME: String = "sources"

static var executable_path: String = OS.get_executable_path().get_base_dir()

## 自定义源码扫描目录（空串表示使用可执行文件旁的 sources/）
@export_storage var custom_source_scan_dir: String = ""
## 自定义 Python 解释器路径（空串表示使用内置运行时）
@export_storage var custom_python_path: String = ""
## 自定义 SCons 库路径（空串表示使用内置 SCons）
@export_storage var custom_scons_dir: String = ""
## 构建产物输出目录（空串表示不复制，产物保留在源码目录 bin/）
@export_storage var output_dir: String = ""

## 获取源码扫描目录（未配置时回退可执行文件旁的 sources/）。
func get_source_scan_dir() -> String:
	if custom_source_scan_dir.strip_edges().is_empty():
		return executable_path.path_join(SCAN_DIR_NAME)
	return custom_source_scan_dir

static func load() -> AppData:
	var data_path: String = executable_path.path_join(DEFAULT_SAVE_PATH)
	# 磁盘已有且类型正确的数据时直接复用，不重复写盘
	if ResourceLoader.exists(data_path):
		var app_data: Resource = ResourceLoader.load(data_path)
		if app_data is AppData:
			app_data.take_over_path(data_path)
			return app_data
	# 文件缺失或损坏时重建
	var new_app_data: Resource = AppData.new()
	new_app_data.take_over_path(data_path)
	ResourceSaver.save(new_app_data)
	return new_app_data

func save() -> Error:
	return ResourceSaver.save(self, executable_path.path_join(DEFAULT_SAVE_PATH))
