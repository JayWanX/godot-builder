class_name ProfileHighlighter
extends SyntaxHighlighter
## profile.py（Godot 源码构建选项配置）语法高亮器。[br]
## 支持 `key = "value"` 赋值行、`#region` / `#endregion` 分组标记、
## 行尾 `# 注释`，以及基于 region 标记的代码折叠。

@export var key_color: Color = Color(0.34, 0.7, 1.0)
@export var string_color: Color = Color(1, 0.93, 0.63)
@export var operator_color: Color = Color(0.67, 0.79, 1)
@export var comment_color: Color = Color(0.88, 0.88, 0.88, 0.5)
@export var region_color: Color = Color("#c792ea")

## 赋值行：`key = "value"` 可选行尾注释（字符串值支持 `\"` 转义）。
const _ASSIGN_PATTERN: String = r'^(\s*)([A-Za-z_][A-Za-z0-9_]*)(\s*=\s*)("(?:[^"\\]|\\.)*")(\s*)(#.*)?$'
## region 标记行：`#region X` / `#endregion`。
const _REGION_PATTERN: String = r'^(\s*)(#region|#endregion)(.*)$'

static var _assign_re: RegEx = null
static var _region_re: RegEx = null

static func _get_assign_re() -> RegEx:
	if _assign_re == null:
		_assign_re = RegEx.create_from_string(_ASSIGN_PATTERN)
	return _assign_re

static func _get_region_re() -> RegEx:
	if _region_re == null:
		_region_re = RegEx.create_from_string(_REGION_PATTERN)
	return _region_re

func _get_name() -> String:
	return "Profile"

func _get_line_syntax_highlighting(line: int) -> Dictionary[int, Dictionary]:
	var line_text: String = get_text_edit().get_line(line)
	var result: Dictionary[int, Dictionary] = {}
	var region_match: RegExMatch = _get_region_re().search(line_text)
	if region_match != null:
		result[region_match.get_start(2)] = {"color": region_color}
		return result
	var assign_match: RegExMatch = _get_assign_re().search(line_text)
	if assign_match != null:
		result[assign_match.get_start(2)] = {"color": key_color}
		result[assign_match.get_start(3)] = {"color": operator_color}
		result[assign_match.get_start(4)] = {"color": string_color}
		if assign_match.get_start(6) >= 0:
			result[assign_match.get_start(6)] = {"color": comment_color}
		return result
	var comment_index: int = line_text.find("#")
	if comment_index >= 0:
		result[comment_index] = {"color": comment_color}
	return result

func _get_folding_info(line: int) -> Dictionary:
	var line_text: String = get_text_edit().get_line(line)
	if _get_region_re().search(line_text) != null:
		return {"type": "region", "folded": false}
	return {}
