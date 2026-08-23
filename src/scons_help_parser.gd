@abstract
class_name SconsHelpParser
extends Object
## 解析 `scons --help` 输出文本为结构化选项信息。
##
## 输出结构（字典：选项名 → 选项元信息）：
## {
##   "option_name": {
##     "description": "描述文本",
##     "type": "bool|string|enum|integer|path",
##     "default": "默认值",           # 始终存在（可能为空）
##     "actual": "当前实际值",         # 始终存在（可能为空）
##     "aliases": ["别名"],           # 仅当非空
##     "possible_values": ["值1", "值2"]  # 仅当存在且非空
##   }
## }

## 解析结果修正：个别 SCons 选项在 help 中缺省或无类型，手动补全。
const OPTION_OVERRIDES: Dictionary = {
	"platform": {
		"default": "{actual}"
	},
	"num_jobs": {
		"type": "integer"
	}
}

const BUILD_OPTIONS_ZH = preload("res://build_options_zh.json")

const KEY_GROUPS: String = "groups"
const KEY_OPTIONS: String = "options"
const KEY_DISPLAY_NAME: String = "display_name"
const KEY_DESCRIPTION: String = "description"
const KEY_COMMENT: String = "comment"
const KEY_GROUP: String = "group"

## 分组推断规则：按顺序匹配选项名关键字，首条命中生效。
## 仅覆盖大多数新增选项；个别误判可依赖翻译配置中的人工分组修正。
const GROUP_INFERENCE_RULES: Array = [
	{KEY_GROUP: "modules", "keywords": ["module_"]},
	{KEY_GROUP: "builtin", "keywords": ["builtin_"]},
	{KEY_GROUP: "render", "keywords": ["vulkan", "opengl", "gles", "d3d12", "metal", "shader", "rendering_method", "display"]},
	{KEY_GROUP: "build", "keywords": ["ninja", "ccache", "num_jobs", "compile_db", "sourcepkg"]},
	{KEY_GROUP: "windows", "keywords": ["msvc", "winsdk", "subsystem", "mingw", "win32", "sanitizers"]},
	{KEY_GROUP: "profiler", "keywords": ["tracy", "perfetto", "profiler", "gperftools"]},
	{KEY_GROUP: "toolchain", "keywords": ["compiler", "linker", "lld", "warnings", "werror", "cxx", "extra_suffix"]},
	{KEY_GROUP: "target", "keywords": ["target", "platform", "arch", "bits", "build_name"]},
	{KEY_GROUP: "optimize", "keywords": ["optimize", "debug_symbols", "lto", "dev_build", "production", "precision", "use_static"]},
	{KEY_GROUP: "features", "keywords": ["threads", "physics", "navigation", "xr", "gdscript", "accesskit"]},
]

## 未命中任何推断规则时的回退分组键（保证新选项在 UI 中始终可见、可配置）。
const FALLBACK_GROUP_KEY: String = "other"

const _HEADER_PATTERN: String = r'^([A-Za-z_]\w*):\s*(.*)$'
const _FIELD_PATTERN: String = r'^\s*(default|actual|aliases):\s*(.*)$'
const _ALIAS_PATTERN: String = r"'([^']*)'"
const _PAREN_PATTERN: String = r'\(([^)]+)\)'

static var _regex_cache: Dictionary = {}

static func _get_regex(pattern: String) -> RegEx:
	if not _regex_cache.has(pattern):
		_regex_cache[pattern] = RegEx.create_from_string(pattern)
	return _regex_cache[pattern]

## 主解析入口：返回 { 选项名: 选项元信息 } 字典。
static func parse(text: String) -> Dictionary:
	var parsed: Dictionary = {}
	var option_key: String = ""
	var description: String = ""
	var default_value: String = ""
	var actual_value: String = ""
	var aliases: Array = []

	for line: String in text.split("\n"):
		var is_indented: bool = line.begins_with(" ") or line.begins_with("\t")
		if not is_indented:
			if not option_key.is_empty():
				parsed[option_key] = _build_option_info(description, default_value, actual_value, aliases)
				option_key = ""
				description = ""
				default_value = ""
				actual_value = ""
				aliases = []
			var match: RegExMatch = _get_regex(_HEADER_PATTERN).search(line)
			if match == null or str(match.strings[1]) == "scons":
				continue
			option_key = str(match.strings[1])
			description = str(match.strings[2]).strip_edges()
			continue

		if option_key.is_empty():
			continue
		var field_match: RegExMatch = _get_regex(_FIELD_PATTERN).search(line)
		if field_match == null:
			continue
		var field_value: String = str(field_match.strings[2]).strip_edges()
		match str(field_match.strings[1]):
			"default":
				default_value = field_value
			"actual":
				actual_value = field_value
			"aliases":
				aliases = _parse_aliases(field_value)

	if not option_key.is_empty():
		parsed[option_key] = _build_option_info(description, default_value, actual_value, aliases)

	for overridden_key: String in OPTION_OVERRIDES:
		if parsed.has(overridden_key):
			var option_info: Dictionary = parsed[overridden_key]
			for field_name: String in OPTION_OVERRIDES[overridden_key]:
				var field_value: Variant = OPTION_OVERRIDES[overridden_key][field_name]
				if field_value is String:
					field_value = _expand_placeholders(str(field_value), option_info)
				option_info[field_name] = field_value

	return parsed

## 按规则推断选项所属分组；无规则命中返回回退分组键。[br]
## 仅需在人工分组缺失时调用（BuildOptions 懒推断、本地化模板生成），[br]
## 已翻译选项应优先沿用 build_options_zh.json 中的人工分组。
static func infer_group(option_key: String) -> String:
	for inference_rule: Dictionary in GROUP_INFERENCE_RULES:
		for keyword: String in inference_rule["keywords"]:
			if option_key.contains(keyword):
				return inference_rule[KEY_GROUP]
	return FALLBACK_GROUP_KEY

## 生成本地化模板（build_options_zh.json 文件结构），供源码升级后重建翻译骨架
static func generate_localization_template(source_dir: String, existing_localization: Dictionary = {}) -> Dictionary:
	var localization: Dictionary = existing_localization if not existing_localization.is_empty() else BUILD_OPTIONS_ZH.data
	var godot_builder: GodotBuilder = GodotBuilder.new()
	var scons_help: String = await godot_builder.get_scons_help_cached(source_dir)
	if scons_help.is_empty():
		return {}
	var source_version: String = Utils.parse_godot_version(source_dir)
	var localized_options: Dictionary = localization.get(KEY_OPTIONS, {})
	var template_options: Dictionary = {}
	for option_key: String in parse(scons_help):
		var localized: Dictionary = localized_options.get(option_key, {})
		var localized_group: String = localized.get(KEY_GROUP, "")
		template_options[option_key] = {
			KEY_DISPLAY_NAME: localized.get(KEY_DISPLAY_NAME, ""),
			KEY_COMMENT: localized.get(KEY_COMMENT, ""),
			KEY_GROUP: localized_group if not localized_group.is_empty() else infer_group(option_key),
		}
	var template_groups: Dictionary = (localization.get(KEY_GROUPS, {}) as Dictionary).duplicate()
	if not template_groups.has(FALLBACK_GROUP_KEY):
		template_groups[FALLBACK_GROUP_KEY] = {
			KEY_DISPLAY_NAME: "其他",
			KEY_COMMENT: "未匹配到推断规则的新增选项，请补充翻译并归入合适分组",
		}
	var template: Dictionary = {
		KEY_GROUPS: template_groups,
		KEY_OPTIONS: template_options,
	}
	if not source_version.is_empty():
		template["version"] = "godot-" + source_version
	return template

## 从描述文本中提取可能的值列表（仅处理末尾括号）：[br]
## - 括号内含 '|'：按 '|' 分割为多值列表[br]
## - 布尔提示（yes/no、true/false、on/off）：按 ["yes", "no"] 处理[br]
## - 其余单值候选：仅当与 default 或 actual 相等时才作为有效枚举值返回
static func _extract_possible_values(description: String, default_value: String = "", actual_value: String = "") -> Array:
	var possible_values: Array = []
	var matches: Array[RegExMatch] = _get_regex(_PAREN_PATTERN).search_all(description)
	if matches.is_empty():
		return possible_values
	var paren_content: String = str(matches[-1].strings[1])
	if "|" in paren_content:
		for part: String in paren_content.split("|"):
			var value: String = part.strip_edges()
			if not value.is_empty():
				possible_values.append(value)
	elif paren_content.to_lower() in ["yes/no", "true/false", "on/off"]:
		possible_values = ["yes", "no"]
	else:
		var single_value: String = paren_content.strip_edges()
		if not single_value.is_empty() and (single_value == default_value or single_value == actual_value):
			possible_values.append(single_value)
	return possible_values

## 推断选项类型：bool / enum / integer / path / string。
## 描述无括号候选时回退使用 aliases 作为枚举候选（Godot EnumVariable 的 aliases 即合法值列表）。
static func _infer_type(description: String, default_value: String, actual_value: String, aliases: Array = []) -> String:
	var possible_values: Array = _extract_possible_values(description, default_value, actual_value)
	if possible_values.is_empty() and not aliases.is_empty():
		possible_values = aliases.duplicate()

	if possible_values.size() == 2 and "yes" in possible_values and "no" in possible_values:
		return "bool"
	if default_value.is_valid_int() or actual_value.is_valid_int():
		return "integer"
	if description.containsn("path") or "\\" in default_value or "/" in default_value or "\\" in actual_value or "/" in actual_value:
		return "path"
	if possible_values.size() > 0:
		return "enum"
	return "string"

## 解析 Python 风格别名列表 ['a', 'b'] → ["a", "b"]；空文本返回空数组。
static func _parse_aliases(raw_text: String) -> Array:
	var aliases: Array = []
	if raw_text.is_empty():
		return aliases
	for match: RegExMatch in _get_regex(_ALIAS_PATTERN).search_all(raw_text):
		aliases.append(str(match.strings[1]))
	return aliases

## 展开覆盖值中的占位符：{actual} / {default} 用该选项自身解析出的值替换。
static func _expand_placeholders(template_text: String, option_info: Dictionary) -> String:
	var expanded: String = template_text.replace("{actual}", str(option_info.get("actual", "")))
	return expanded.replace("{default}", str(option_info.get("default", "")))

## 根据收集的字段构建选项元信息；default / actual 始终写入，aliases / possible_values 仅非空时写入。
## SCons 对未赋值选项打印 "None"（Python None），规范化为空字符串，避免其污染完整 profile 的构建命令。
static func _build_option_info(description: String, default_value: String, actual_value: String, aliases: Array) -> Dictionary:
	if default_value == "None":
		default_value = ""
	if actual_value == "None":
		actual_value = ""
	var option_info: Dictionary = {
		"description": description,
		"type": _infer_type(description, default_value, actual_value, aliases),
		"default": default_value,
		"actual": actual_value,
	}
	if not aliases.is_empty():
		option_info["aliases"] = aliases
	var possible_values: Array = _extract_possible_values(description, default_value, actual_value)
	if possible_values.is_empty() and not aliases.is_empty():
		possible_values = aliases.duplicate()
	if not possible_values.is_empty():
		option_info["possible_values"] = possible_values
	return option_info
