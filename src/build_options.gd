class_name BuildOptions
extends RefCounted

const BUILD_OPTIONS_ZH = SconsHelpParser.BUILD_OPTIONS_ZH
const KEY_GROUPS: String = "groups"
const KEY_OPTIONS: String = "options"
const KEY_GROUP: String = "group"
const KEY_DISPLAY_NAME: String = "display_name"
const KEY_DESCRIPTION: String = "description"
const KEY_COMMENT: String = "comment"

## 模块总开关选项名：false 时所有模块选项派生默认值为 no
const KEY_MODULES_SWITCH: String = "modules_enabled_by_default"

## 未命中推断规则的回退分组（与 SconsHelpParser.FALLBACK_GROUP_KEY 一致）：
## 需保证其存在于分组表，否则落入该组的选项无法被分组遍历枚举、UI 不可见。
const FALLBACK_GROUP_KEY: String = "other"
const FALLBACK_GROUP_ENTRY: Dictionary = {
	KEY_DISPLAY_NAME: "其他",
	KEY_COMMENT: "未匹配到推断规则的新增选项，请补充翻译并归入合适分组",
}

const DEFAULT_GROUPS: Dictionary[String, Dictionary] = {
	"target": {"display_name": "基础构建目标", "comment": "构建目标、目标平台、CPU 架构及产物命名等基础选项"},
	"optimize": {"display_name": "优化与性能", "comment": "编译优化级别、链接优化、浮点精度及调试符号等性能相关选项"},
	"features": {"display_name": "功能开关", "comment": "线程、3D/2D 物理、导航、XR 等引擎功能模块的启用与禁用"},
	"render": {"display_name": "渲染与图形驱动", "comment": "Vulkan / OpenGL / D3D12 / Metal 等渲染驱动及图形相关选项"},
	"build": {"display_name": "构建加速与产物", "comment": "Ninja 后端、并行任务数、缓存、编译数据库等构建流程选项"},
	"profiler": {"display_name": "性能分析器", "comment": "Tracy / Perfetto 等性能分析器集成选项"},
	"toolchain": {"display_name": "编译器与工具链", "comment": "C/C++ 编译器、链接器及额外编译 / 链接标志"},
	"windows": {"display_name": "Windows 平台特定", "comment": "Windows 平台专属选项：子系统、MSVC/SDK 版本、消毒器等"},
	"modules": {"display_name": "模块", "comment": "各功能模块（Mono、物理、导入器、音频等）的启用开关"},
	"builtin": {"display_name": "内置库", "comment": "zlib、FreeType、SDL 等内置第三方库的选择"}
}

var _groups: Dictionary[String, Dictionary] = {}
var _options: Dictionary[String, Dictionary] = {}

## 判断是否为模块开关选项（module_<name>_enabled）。
static func is_module_option(option_key: String) -> bool:
	return option_key.begins_with("module_") and option_key.ends_with("_enabled")

func _init(scons_help: String, localization_template: Dictionary = {}) -> void:
	var localization_data: Dictionary = (
		BUILD_OPTIONS_ZH.data if localization_template.is_empty() else localization_template
	)
	_groups.assign(localization_data.get(KEY_GROUPS, DEFAULT_GROUPS))
	var localized_options: Dictionary = localization_data.get(KEY_OPTIONS, {})
	var parsed_options: Dictionary = SconsHelpParser.parse(scons_help)
	_options.assign(parsed_options)
	for option_key: String in _options.keys():
		var option: Dictionary = _options[option_key]
		if localized_options.has(option_key):
			option.merge(localized_options[option_key])
		# 懒推断分组：仅当人工分组缺失时按名称推断，保证所有选项在 UI 中可见
		if str(option.get(KEY_GROUP, "")).is_empty():
			option[KEY_GROUP] = SconsHelpParser.infer_group(option_key)
			if not _groups.has(str(option[KEY_GROUP])):
				_groups[str(option[KEY_GROUP])] = FALLBACK_GROUP_ENTRY.duplicate()

## 获取指定选项的元数据；未知选项返回空字典。
func get_option(option_key: String) -> Dictionary:
	return _options.get(option_key, {})

## 检查是否存在指定选项。
func has_option(option_key: String) -> bool:
	return _options.has(option_key)

## 获取全部分组列表（分组 key → { display_name, comment }）。
func get_all_groups() -> Dictionary[String, Dictionary]:
	return _groups

## 获取指定分组下的所有选项，返回 { 选项名: 选项字典 } 的映射。
func get_options_of(group_key: String) -> Dictionary[String, Dictionary]:
	var group_options: Dictionary = {}
	for option_key: String in _options:
		var option: Dictionary = _options[option_key]
		if option.get(KEY_GROUP) == group_key:
			group_options[option_key] = option
	return group_options

## 获取字段显示名：优先中文配置名，回退英文原词。
func get_display_name(option_key: String) -> String:
	var display_name: String = get_option(option_key).get(KEY_DISPLAY_NAME, "")
	return option_key if display_name.is_empty() else display_name

## 字段 tooltip：描述 + 注释。
func get_tooltip_text(option_key: String) -> String:
	var description: String = get_option(option_key).get(KEY_DESCRIPTION, "")
	var comment: String = get_option(option_key).get(KEY_COMMENT, "")
	return description if comment.is_empty() else description + "\n" + comment
