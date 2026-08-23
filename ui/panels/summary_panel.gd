class_name SummaryPanel
extends PanelContainer

## 摘要行选项 key（顺序即显示顺序）
@export var summary_option_keys: Array[String] = [
	"target", 
	"platform", 
	"arch", 
	"optimize", 
	"lto", 
	"precision", 
	"production"
]

@export var summary_rows: VBoxContainer
@export var change_quantity_label: Label

## 配置与选项元数据仓库
var _store: ConfigStore
## 摘要行选项 key → 值标签映射
var _value_labels: Dictionary[String, Label] = {}

## 初始化：绑定配置仓库，程序化创建摘要行并刷新。
func setup(store: ConfigStore) -> void:
	_store = store
	_build_summary_rows()
	refresh()

## 程序化创建摘要行：Label（display_name）+ 值标签（expand 右对齐、tooltip）。
func _build_summary_rows() -> void:
	for child: Node in summary_rows.get_children():
		child.queue_free()
	_value_labels.clear()
	for option_key: String in summary_option_keys:
		var row: HBoxContainer = HBoxContainer.new()
		row.tooltip_text = _store.get_tooltip_text(option_key)
		var label: Label = Label.new()
		label.text = _store.get_display_name(option_key)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)
		var value_label: Label = Label.new()
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(value_label)
		summary_rows.add_child(row)
		_value_labels[option_key] = value_label

## 刷新摘要：更新各核心选项当前值与修改总数（配置变更后由外部调用）。
## 无修改时隐藏修改数量标签。
func refresh() -> void:
	for option_key: String in _value_labels:
		_value_labels[option_key].text = _display_value(option_key)
	var count: int = _store.count_modified()
	change_quantity_label.text = "共 %d 项修改" % count
	change_quantity_label.visible = count > 0

## 摘要显示文本：bool 显示为是/否，其余按字符串显示。
## 注意：不读 actual——无差异项时选项处于"未修改（默认）"状态，应显示 default；
## platform 等无默认值的选项，其 default 已由解析层（SconsHelpParser OPTION_OVERRIDES）修正为实际值。
func _display_value(option_key: String) -> String:
	var value: Variant = _store.get_value(option_key)
	return ("是" if value else "否") if value is bool else str(value)
