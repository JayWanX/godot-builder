class_name GroupNavPanel
extends PanelContainer

const ICON_RESET = preload("uid://bjfjlm6avdnng")

## 分组元数据字典键（与 BuildOptions 分组结构对应）
const KEY_DISPLAY_NAME: String = "display_name"
const KEY_COMMENT: String = "comment"

## 选中分组时发出，携带分组 group_key。[br]
## 由主界面连接，用于切换右侧配置表单的显示分组。
signal group_selected(group_key: String)
## 请求重置指定分组（TreeItem 重置按钮点击时发出，实际重置由外部执行）。
signal reset_group_requested(group_key: String)
## 搜索关键字变化时发出（由主界面转发为右侧选项过滤）。
signal search_text_changed(query: String)

@export var search_line_edit: LineEdit
@export var group_tree: Tree

## 分组映射
var _groups: Dictionary[String, Dictionary] = {}
## 各分组已修改字段数 { group_key: count }
var _modified_counts: Dictionary = {}
## 分组 group_key → TreeItem 映射
var _group_to_item: Dictionary[String, TreeItem] = {}
## 当前选中的分组 group_key
var _current_group_key: String = ""
## 搜索命中统计 { group_key: count }（空字典表示未搜索）
var _search_match_counts: Dictionary = {}
## 程序化选中时抑制 group_selected 信号，避免回环
var _syncing_selection: bool = false

## 初始化分组数据并重建导航树；构建完成后选中第一个分组并发出 group_selected。
func setup(groups: Dictionary[String, Dictionary]) -> void:
	_groups = groups
	_search_match_counts.clear()
	search_line_edit.clear()
	_rebuild_group_tree()
	if not _groups.is_empty():
		var first_key: String = str(_groups.keys()[0])
		select_group(first_key)
		group_selected.emit(first_key)

## 更新各分组的已修改字段计数，并刷新分组项文本。
func set_modified_counts(counts: Dictionary) -> void:
	_modified_counts = counts
	_refresh_item_labels()
	_refresh_reset_buttons()

## 程序化选中指定分组（只更新选中态，不触发 group_selected 信号）。
func select_group(group_key: String) -> void:
	_current_group_key = group_key
	if not _group_to_item.has(group_key):
		return
	var item: TreeItem = _group_to_item[group_key]
	if not is_instance_valid(item):
		return
	_syncing_selection = true
	group_tree.set_selected(item, 0)
	group_tree.scroll_to_item(item)
	_syncing_selection = false

## 重建分组导航树：每个分组一个 TreeItem，文本为中文名，metadata 存分组 group_key。
func _rebuild_group_tree() -> void:
	group_tree.clear()
	_group_to_item.clear()
	var root: TreeItem = group_tree.create_item()
	for group_key: String in _groups:
		var item: TreeItem = group_tree.create_item(root)
		item.set_text(0, _display_text(group_key))
		item.set_tooltip_text(0, _groups[group_key][KEY_COMMENT])
		item.set_metadata(0, group_key)
		_group_to_item[group_key] = item
	# 重置按钮由 _refresh_reset_buttons 按需添加（仅在有修改项时显示）
	_refresh_reset_buttons()

## 分组显示文本：搜索时显示命中数徽标，否则显示修改计数徽标。
func _display_text(group_key: String) -> String:
	var display_name: String = _groups[group_key][KEY_DISPLAY_NAME]
	if not _search_match_counts.is_empty():
		var match_count: int = int(_search_match_counts.get(group_key, 0))
		return ("%s (命中%d)" % [display_name, match_count]) if match_count > 0 else display_name
	var count: int = int(_modified_counts.get(group_key, 0))
	return ("%s (%d)" % [display_name, count]) if count > 0 else display_name

## 应用搜索命中统计：组树仅显示含命中的分组，并刷新命中数徽标；空统计恢复全量显示。
func set_search_match_counts(counts: Dictionary) -> void:
	_search_match_counts = counts
	for group_key: String in _group_to_item:
		var item: TreeItem = _group_to_item[group_key]
		if not is_instance_valid(item):
			continue
		item.visible = counts.is_empty() or int(counts.get(group_key, 0)) > 0
	_refresh_item_labels()

## 用最新修改计数刷新所有分组项文本。
func _refresh_item_labels() -> void:
	for group_key: String in _groups:
		if not _group_to_item.has(group_key):
			continue
		var item: TreeItem = _group_to_item[group_key]
		if is_instance_valid(item):
			item.set_text(0, _display_text(group_key))

## 刷新各分组项重置按钮：仅在有修改字段时显示（无修改时移除按钮）。
func _refresh_reset_buttons() -> void:
	for group_key: String in _groups:
		if not _group_to_item.has(group_key):
			continue
		var item: TreeItem = _group_to_item[group_key]
		if not is_instance_valid(item):
			continue
		var has_modified: bool = int(_modified_counts.get(group_key, 0)) > 0
		if has_modified and item.get_button_count(0) == 0:
			item.add_button(0, ICON_RESET, 0, false, "重置本组")
		elif not has_modified and item.get_button_count(0) > 0:
			item.erase_button(0, 0)

func _on_search_line_edit_text_changed(new_text: String) -> void:
	search_text_changed.emit(new_text)

func _on_group_tree_item_selected() -> void:
	if _syncing_selection:
		return
	var item: TreeItem = group_tree.get_selected()
	if item == null:
		return
	var group_key: String = str(item.get_metadata(0))
	if group_key.is_empty():
		return
	_current_group_key = group_key
	group_selected.emit(group_key)

func _on_group_tree_button_clicked(item: TreeItem, _column: int, id: int, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	if id != 0:
		return
	if item == null:
		return
	var group_key: String = str(item.get_metadata(0))
	if group_key.is_empty():
		return
	reset_group_requested.emit(group_key)
