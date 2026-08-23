class_name ConfigStore
extends RefCounted
## 配置差异字典与选项元数据仓库的统一入口。

const KEY_TYPE: String = "type"
const KEY_DEFAULT: String = "default"
const KEY_ACTUAL: String = "actual"

## 构建选项依赖规则注册表：选项间存在强制依赖时自动补全导出配置，避免生成无法链接的 profile.py。[br]
## 规则结构：[br]
## - conditions：{ 选项: 值 }，须显式存在于配置且值相等（全部满足规则才生效）[br]
## - defaults：{ 选项: 值 }，选项缺失时视为该默认值参与条件判断[br]
## - set：{ 选项: 值 }，规则生效时强制写入的选项键值[br]
## - preserve_existing（可选，默认 true）：导出时目标选项已在配置中则不覆盖[br]
## 例：libANGLE 预编译库引用 astcenc_* 解压符号；模块全禁（modules_enabled_by_default=no）
## 且 ANGLE 未禁（angle 默认 yes）时 astcenc 必须保留，否则链接报 LNK2019。
const OPTION_DEPENDENCY_RULES: Array[Dictionary] = [
	{
		"conditions": { "modules_enabled_by_default": false },
		"defaults": { "angle": true },
		"set": { "module_astcenc_enabled": true },
	},
]

var _config: Dictionary = {}
var _build_options: BuildOptions

func _init(config: Dictionary, build_options: BuildOptions) -> void:
	_config = config
	_build_options = build_options

## 读取共享差异字典（与外部共享同一实例）。
func get_config() -> Dictionary:
	return _config

## 读取选项元数据仓库。
func get_options() -> BuildOptions:
	return _build_options

## 读取指定选项的元数据；未知选项返回空字典。
func get_option(option_key: String) -> Dictionary:
	return _build_options.get_option(option_key)

## 检查是否存在指定选项。
func has_option(option_key: String) -> bool:
	return _build_options.has_option(option_key)

## 读取字段显示名。
func get_display_name(option_key: String) -> String:
	return _build_options.get_display_name(option_key)

## 读取字段 tooltip 文本。
func get_tooltip_text(option_key: String) -> String:
	return _build_options.get_tooltip_text(option_key)

## 当前配置中是否存在指定选项的差异项。
func has_value(option_key: String) -> bool:
	return _config.has(option_key)

## 读取字段当前值：差异项优先，否则按类型转换的元数据默认值。
func get_value(option_key: String) -> Variant:
	if _config.has(option_key):
		return _config[option_key]
	return get_default_value(option_key)

## 读取字段当前值：差异项优先，否则按类型转换的元数据实际值（actual）。
## 依赖规则强制值优先于模块开关派生（modules_enabled_by_default=false 时模块选项无差异项视为 no）。
func get_actual_value(option_key: String) -> Variant:
	if _config.has(option_key):
		return _config[option_key]
	var forced: Variant = _get_forced_value(option_key)
	if forced != null:
		return forced
	if _modules_switched_off(option_key):
		return false
	var option: Dictionary = get_option(option_key)
	return _typed_value(str(option.get(KEY_TYPE, "string")), str(option.get(KEY_ACTUAL, "")))

## 按类型转换的元数据默认值。
## 依赖规则强制值优先，其次模块开关派生默认（modules_enabled_by_default=false 时模块选项默认 no）。
func get_default_value(option_key: String) -> Variant:
	var forced: Variant = _get_forced_value(option_key)
	if forced != null:
		return forced
	var option: Dictionary = get_option(option_key)
	if _modules_switched_off(option_key):
		return false
	return _typed_value(str(option.get(KEY_TYPE, "string")), str(option.get(KEY_DEFAULT, "")))

## 模块总开关为 false 且选项为模块开关选项时，派生默认值生效。
func _modules_switched_off(option_key: String) -> bool:
	return BuildOptions.is_module_option(option_key) and _config.get(BuildOptions.KEY_MODULES_SWITCH, true) == false

## 写入字段值；与默认相同时移除差异项。
func set_value(option_key: String, value: Variant) -> void:
	if value == get_default_value(option_key):
		_config.erase(option_key)
	else:
		_config[option_key] = value
	if option_key == BuildOptions.KEY_MODULES_SWITCH:
		_erase_redundant_module_entries()

## 导出用完整配置：显式差异项 + 命中规则的强制项（ProfileConverter 原样转换，不再隐式补全）。
func get_profile_config() -> Dictionary:
	var result: Dictionary = _config.duplicate()
	for rule: Dictionary in OPTION_DEPENDENCY_RULES:
		if not _rule_matches(rule):
			continue
		var sets: Dictionary = rule.get("set", {})
		var preserve_existing: bool = bool(rule.get("preserve_existing", true))
		for option_key: String in sets:
			if preserve_existing and result.has(option_key):
				continue
			result[option_key] = sets[option_key]
	return result

## 完整配置：全部分组所有选项 → 当前生效值（差异项优先，否则按派生默认值）。
## 供编译用完整 profile 文件（ProfileConverter.config_to_profile only_diff=false）使用。
func get_full_config() -> Dictionary:
	var result: Dictionary = {}
	for group_key: String in _build_options.get_all_groups():
		for option_key: String in _build_options.get_options_of(group_key):
			result[option_key] = get_value(option_key)
	return result

## 规则强制值：条件命中即返回强制值（与目标选项是否显式无关，避免默认值自引用震荡）；未命中返回 null。
func _get_forced_value(option_key: String) -> Variant:
	for rule: Dictionary in OPTION_DEPENDENCY_RULES:
		var sets: Dictionary = rule.get("set", {})
		if not sets.has(option_key):
			continue
		if _rule_matches(rule):
			return sets[option_key]
	return null

## 校验规则前提：conditions 须显式存在且值相等；defaults 缺失时视为其默认值再比较。
func _rule_matches(rule: Dictionary) -> bool:
	var conditions: Dictionary = rule.get("conditions", {})
	for option_key: String in conditions:
		if not _config.has(option_key) or _config[option_key] != conditions[option_key]:
			return false
	var defaults: Dictionary = rule.get("defaults", {})
	for option_key: String in defaults:
		if _config.get(option_key, defaults[option_key]) != defaults[option_key]:
			return false
	return true

## 模块总开关翻转后，清理与派生默认值相同的模块显式项（不再是差异项）。
## 开关被重置为默认（yes）时同样生效：按当前生效开关值比较。
func _erase_redundant_module_entries() -> void:
	var switch_value: Variant = _config.get(BuildOptions.KEY_MODULES_SWITCH, get_default_value(BuildOptions.KEY_MODULES_SWITCH))
	var redundant: Array[String] = []
	for option_key: String in _config.keys():
		if BuildOptions.is_module_option(option_key) and _config[option_key] == switch_value:
			redundant.append(option_key)
	for option_key: String in redundant:
		_config.erase(option_key)

## 移除指定选项的差异项。
func erase(option_key: String) -> void:
	_config.erase(option_key)

## 清空全部差异项。
func clear() -> void:
	_config.clear()

## 差异项总数。
func count_modified() -> int:
	return _config.size()

## 统计各分组偏离默认的字段数。[return] { group_key: count }
func count_modified_by_group() -> Dictionary:
	var counts: Dictionary = {}
	for group_key: String in _build_options.get_all_groups():
		var count: int = 0
		for option_key: String in _build_options.get_options_of(group_key):
			if _config.has(option_key):
				count += 1
		counts[group_key] = count
	return counts

## 初始差异检测：actual ≠ default 且未记录时写入 _config，返回是否新增差异项。
func sync_initial_actual(option_key: String) -> bool:
	if _config.has(option_key):
		return false
	var option: Dictionary = get_option(option_key)
	var type: String = str(option.get(KEY_TYPE, "string"))
	var current_value: Variant = _typed_value(type, str(option.get(KEY_ACTUAL, "")))
	if current_value == _typed_value(type, str(option.get(KEY_DEFAULT, ""))):
		return false
	_config[option_key] = current_value
	return true

## 原始字符串值 → 按字段类型转换为原生值（bool / integer / 其余原样）。
func _typed_value(type: String, raw_value: String) -> Variant:
	match type:
		"bool":
			return raw_value.to_lower() in ["yes", "true", "1", "on"]
		"integer":
			return int(raw_value) if raw_value.is_valid_int() else 0
		_:
			return raw_value
