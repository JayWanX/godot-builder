class_name ProfileConverter
extends RefCounted
## `profile` 与配置字典的双向转换工具。

const KEY_TYPE: String = "type"
const KEY_DEFAULT: String = "default"
const KEY_ACTUAL: String = "actual"
const KEY_COMMENT: String = "comment"
const KEY_DISPLAY_NAME: String = "display_name"

## 行首 `key = "value"` 匹配（忽略 region 标记、注释行等）；value 支持转义序列（\\、\"）。
const _LINE_PATTERN: String = r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"((?:[^"\\]|\\.)*)"'

static var _line_re: RegEx = null

static func _get_line_re() -> RegEx:
	if _line_re == null:
		_line_re = RegEx.create_from_string(_LINE_PATTERN)
	return _line_re

## 编译配置 → profile 文本
static func config_to_profile(config: Dictionary, build_options: BuildOptions, only_diff: bool = true) -> String:
	var group_keys: Dictionary = {}
	var all_keys: Array[String] = []
	for group_key: String in build_options.get_all_groups():
		var option_keys: Array[String] = []
		for option_key: String in build_options.get_options_of(group_key):
			if only_diff and not config.has(option_key):
				continue
			option_keys.append(option_key)
			all_keys.append(option_key)
		if not option_keys.is_empty():
			group_keys[group_key] = option_keys
	if all_keys.is_empty():
		return ""
	var comment_column: int = _comment_column(all_keys, config, build_options)
	var lines: PackedStringArray = []
	for group_key: String in group_keys:
		var group_display: String = build_options.get_all_groups()[group_key][KEY_DISPLAY_NAME]
		lines.append("#region " + group_display)
		for option_key: String in group_keys[group_key]:
			var value: Variant = config.get(option_key, _default_value(build_options.get_option(option_key)))
			lines.append(_format_option_line(option_key, value, build_options, comment_column))
		lines.append("#endregion")
		lines.append("")
	return "\n".join(lines).trim_suffix("\n")

## 解析 profile 文本为配置差异项（与元数据默认相同的值不入配置）。
static func profile_to_config(profile_text: String, build_options: BuildOptions) -> Dictionary:
	var config: Dictionary = {}
	# 预扫描模块总开关（行序无关：先取开关值，再判定模块选项差异）
	var switch_value: Variant = _parse_switch_value(profile_text, build_options)
	var line_re: RegEx = _get_line_re()
	for line: String in profile_text.split("\n"):
		var match: RegExMatch = line_re.search(line)
		if match == null:
			continue
		var option_key: String = match.get_string(1)
		if not build_options.has_option(option_key):
			continue
		var option: Dictionary = build_options.get_option(option_key)
		var raw_value: String = _unescape_value(match.get_string(2))
		var typed_value: Variant = _typed_value(str(option.get(KEY_TYPE, "string")), raw_value)
		if not _is_diff(option_key, typed_value, option, switch_value):
			continue
		config[option_key] = typed_value
	return config

## 差异判定：模块选项按有效默认值（开关=no 时为 no），其余按元数据默认值。
static func _is_diff(option_key: String, typed_value: Variant, option: Dictionary, switch_value: Variant) -> bool:
	if BuildOptions.is_module_option(option_key) and switch_value == false:
		return typed_value != false
	return typed_value != _default_value(option)

## 提取模块总开关值；未出现或元数据缺失时返回 null。
static func _parse_switch_value(profile_text: String, build_options: BuildOptions) -> Variant:
	var line_re: RegEx = _get_line_re()
	for line: String in profile_text.split("\n"):
		var match: RegExMatch = line_re.search(line)
		if match == null:
			continue
		if match.get_string(1) != BuildOptions.KEY_MODULES_SWITCH:
			continue
		var option: Dictionary = build_options.get_option(BuildOptions.KEY_MODULES_SWITCH)
		if option.is_empty():
			return null
		return _typed_value(str(option.get(KEY_TYPE, "string")), match.get_string(2))
	return null

## 单行格式化：`key = "value"` 补空格至 comment_column 后接 `# 注释`（comment 优先，空则用显示名）。
static func _format_option_line(option_key: String, value: Variant, build_options: BuildOptions, comment_column: int) -> String:
	var option: Dictionary = build_options.get_option(option_key)
	var comment: String = str(option.get(KEY_COMMENT, ""))
	if comment.is_empty():
		comment = build_options.get_display_name(option_key)
	var base: String = _base_line(option_key, value, option)
	return base + " ".repeat(comment_column - base.length()) + "# " + comment

## 全局注释起始列：所有输出项中最长赋值行长度 + 2 空格（整个文件统一列，跨 region 垂直对齐）。
static func _comment_column(option_keys: Array[String], config: Dictionary, build_options: BuildOptions) -> int:
	var max_length: int = 0
	for option_key: String in option_keys:
		var option: Dictionary = build_options.get_option(option_key)
		var value: Variant = config.get(option_key, _default_value(option))
		max_length = maxi(max_length, _base_line(option_key, value, option).length())
	return max_length + 2

## 赋值行主体（不含注释）：`key = "value"`。
static func _base_line(option_key: String, value: Variant, option: Dictionary) -> String:
	var text_value: String = _to_script_value(value, str(option.get(KEY_TYPE, "string")))
	return "%s = \"%s\"" % [option_key, text_value]

## 配置值 → Python 字符串字面量内容（bool 转 yes/no，转义反斜杠与内部引号）。
static func _to_script_value(value: Variant, type: String) -> String:
	if type == "bool":
		return "yes" if bool(value) else "no"
	return str(value).replace("\\", "\\\\").replace('"', '\\"')

## Python 字符串字面量内容还原：`\\` → `\`，`\"` → `"`。
static func _unescape_value(raw_text: String) -> String:
	return raw_text.replace("\\\\", "\\").replace("\\\"", "\"")

## 元数据默认值（default 为空时回退 actual，按类型转换）。
static func _default_value(option: Dictionary) -> Variant:
	var raw_value: String = str(option.get(KEY_DEFAULT, ""))
	if raw_value.is_empty():
		raw_value = str(option.get(KEY_ACTUAL, ""))
	return _typed_value(str(option.get(KEY_TYPE, "string")), raw_value)

## 原始字符串值 → 按字段类型转换为原生值（bool / integer / 其余原样）。
static func _typed_value(type: String, raw_value: String) -> Variant:
	match type:
		"bool":
			return raw_value.to_lower() in ["yes", "true", "1", "on"]
		"integer":
			return int(raw_value) if raw_value.is_valid_int() else 0
		_:
			return raw_value
