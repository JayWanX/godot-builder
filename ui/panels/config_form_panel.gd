class_name ConfigFormPanel
extends PanelContainer

## 字段配置值变化时发出，携带字段 option_key。
signal config_changed(option_key: String)

const KEY_TYPE: String = "type"
const KEY_POSSIBLE_VALUES: String = "possible_values"

const BOOL_FIELD_SCENE: PackedScene = preload("../controls/fields/bool_field.tscn")
const ENUM_FIELD_SCENE: PackedScene = preload("../controls/fields/enum_field.tscn")
const INTEGER_FIELD_SCENE: PackedScene = preload("../controls/fields/integer_field.tscn")
const PATH_FIELD_SCENE: PackedScene = preload("../controls/fields/path_field.tscn")
const STRING_FIELD_SCENE: PackedScene = preload("../controls/fields/string_field.tscn")

## 每帧最多创建的字段行数（分帧建行，避免整组同步实例化 + 布局导致卡顿）
const ROWS_PER_FRAME: int = 20

@export var fields_container: VBoxContainer
@export var scroll_container: ScrollContainer

## 配置与选项元数据仓库
var _store: ConfigStore
## 当前分组 key
var _current_group_key: String = ""
## 分组 → 选项 key 列表缓存 { group_key: Array[String] }
var _group_to_option_keys: Dictionary = {}
## 分组容器缓存 { group_key: VBoxContainer }（节点名 = 分组键）
var _group_containers: Dictionary[String, VBoxContainer] = {}
## 已创建的字段行缓存 { option_key: FieldControl }
var _rows: Dictionary = {}
## 分帧建行任务代号：切换分组或重建界面时递增，使未完成的任务失效
var _row_build_generation: int = 0
## 当前搜索关键字（小写，空串表示未搜索）
var _search_query: String = ""

## 初始化：预计算各分组选项，并按分组创建 VBoxContainer（节点名为分组键）。
func setup(store: ConfigStore) -> void:
	_store = store
	_search_query = ""
	_row_build_generation += 1
	_group_to_option_keys.clear()
	_group_containers.clear()
	_rows.clear()
	for child: Node in fields_container.get_children():
		# 先脱离布局树再释放，避免旧行当帧仍参与布局
		fields_container.remove_child(child)
		child.queue_free()
	for group_key: String in store.get_options().get_all_groups():
		_group_to_option_keys[group_key] = store.get_options().get_options_of(group_key).keys()
		var container: VBoxContainer = VBoxContainer.new()
		container.name = group_key
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.visible = false
		fields_container.add_child(container)
		_group_containers[group_key] = container
	_sync_initial_actuals()
	
	config_changed.emit("")

## 显示指定分组：仅切换对应分组 VBoxContainer 的 visible，行按需分帧创建。
## 搜索模式下保持全部分组容器展开（跨组聚合显示），仅更新当前分组标记。
func show_group(group_key: String) -> void:
	_current_group_key = group_key
	if _search_query.is_empty():
		for key: String in _group_containers:
			_group_containers[key].visible = key == group_key
	await _build_rows_chunked(group_key)

## 设置选项搜索过滤：按 option_key 或 display_name 大小写不敏感匹配。[br]
## 关键字非空时进入搜索模式：分组容器全部展开、仅保留匹配行（跨组聚合显示）。[br]
## 清空关键字后恢复常规分组视图。
func set_search_filter(query: String) -> void:
	_search_query = query.strip_edges().to_lower()
	_row_build_generation += 1
	if _search_query.is_empty():
		for key: String in _group_containers:
			_group_containers[key].visible = key == _current_group_key
		_apply_search_to_rows()
		return
	for key: String in _group_containers:
		_group_containers[key].visible = true
	_apply_search_to_rows()
	_build_all_rows_filtered()

## 跨组聚合建行：搜索模式下分帧创建全部分组的行并应用过滤（已建行直接复用）。
func _build_all_rows_filtered() -> void:
	var generation: int = _row_build_generation
	var built: int = 0
	for group_key: String in _group_to_option_keys:
		if _row_build_generation != generation:
			return
		for option_key: Variant in _group_to_option_keys[group_key]:
			var key: String = str(option_key)
			_ensure_row(key, group_key).visible = _matches_search(key)
			built += 1
			if built % ROWS_PER_FRAME == 0:
				await get_tree().process_frame
				if _row_build_generation != generation:
					return

## 对已创建的所有行应用搜索过滤（刷新可见性）。
func _apply_search_to_rows() -> void:
	for key: String in _rows:
		_rows[key].visible = _matches_search(key)

## 判断选项是否匹配当前搜索关键字（key 或 display_name 大小写不敏感；空关键字全匹配）。
func _matches_search(option_key: String) -> bool:
	if _search_query.is_empty():
		return true
	return option_key.to_lower().contains(_search_query) \
		or _store.get_display_name(option_key).to_lower().contains(_search_query)

## 当前搜索过滤下各分组命中数 { group_key: count }（仅含命中大于 0 的分组；空关键字返回空字典）。
func get_search_match_counts() -> Dictionary:
	var counts: Dictionary = {}
	if _search_query.is_empty():
		return counts
	for group_key: String in _group_to_option_keys:
		var count: int = 0
		for option_key: Variant in _group_to_option_keys[group_key]:
			if _matches_search(str(option_key)):
				count += 1
		if count > 0:
			counts[group_key] = count
	return counts

## 滚动右侧面板，使指定分组的顶部对齐视口顶部（搜索模式点击分组时定位）。[br]
## 不用 ensure_control_visible：其对超出视口的控件采用底部对齐策略，会把滚动条直接滚到底部。[br]
## 先等一帧让分组容器完成布局再读取准确位置；内容缩短后滚动条可见性不会自动刷新（滚一下才隐藏），
## 通过 queue_sort 强制重排刷新。
func scroll_to_group(group_key: String) -> void:
	var container: VBoxContainer = _group_containers.get(group_key)
	if container == null or scroll_container == null:
		return
	var offset: float = container.get_global_rect().position.y - scroll_container.get_global_rect().position.y
	scroll_container.scroll_vertical = int(offset)

## 重置指定分组全部字段为默认值（移除差异项）。[br]
## [param group_key] 目标分组 key；为空时重置当前显示分组。
func reset_group(group_key: String = "") -> void:
	var target_key: String = group_key if not group_key.is_empty() else _current_group_key
	if target_key.is_empty():
		return
	var option_keys: Array = _group_to_option_keys.get(target_key, [])
	for option_key: Variant in option_keys:
		var key: String = str(option_key)
		if _store.has_value(key):
			_store.erase(key)
			if _rows.has(key):
				_rows[key].reset_control()
				_rows[key].reset_button.hide()
	_refresh_module_defaults()
	config_changed.emit("")

## 以差异字典整体应用配置。[br][br]
## [param overrides] 与默认值的差异字典[br]
## [param merge] 为 true 时保留现有差异项，否则整体替换
func apply_config(overrides: Dictionary, merge: bool = false) -> void:
	if not merge:
		_store.clear()
	for option_key: Variant in overrides:
		var key: String = str(option_key)
		if not _store.has_option(key):
			continue
		_store.set_value(key, overrides[option_key])
	_sync_initial_actuals()
	_refresh_module_defaults()
	for key: String in _rows:
		_rows[key].set_control(_current_value(key))
	config_changed.emit("")

## 分帧批量创建指定分组的行：每帧最多 ROWS_PER_FRAME 行，容器即时显示、行逐步填充。
## 切换分组或重建界面（generation 递增）时，未完成的建行任务立即停止。
func _build_rows_chunked(group_key: String) -> void:
	var generation: int = _row_build_generation + 1
	_row_build_generation = generation
	var option_keys: Array = _group_to_option_keys.get(group_key, [])
	var index: int = 0
	while index < option_keys.size():
		# 任务已被更新的分组切换/重建取代时停止
		if _row_build_generation != generation:
			return
		var end: int = mini(index + ROWS_PER_FRAME, option_keys.size())
		for i in range(index, end):
			_ensure_row(str(option_keys[i]), group_key)
		index = end
		if index < option_keys.size():
			await get_tree().process_frame

## 获取指定选项的字段行；未创建则实例化并挂到所属分组容器（缓存复用，仅切换 visible）。
func _ensure_row(option_key: String, group_key: String) -> FieldControl:
	if _rows.has(option_key):
		return _rows[option_key]
	var option: Dictionary = _store.get_option(option_key)
	var type: String = str(option.get(KEY_TYPE, "string"))
	var field: FieldControl = _scene_for_type(type).instantiate()
	if field is EnumField:
		var values: PackedStringArray = PackedStringArray()
		for value: Variant in option.get(KEY_POSSIBLE_VALUES, []):
			values.append(str(value))
		(field as EnumField).setup_enum(values)
	field.setup(
		_store.get_display_name(option_key),
		_current_value(option_key),
		_store.get_default_value(option_key),
		_store.get_tooltip_text(option_key)
	)
	field.value_changed.connect(_on_field_value_changed.bind(option_key))
	field.reset_button.pressed.connect(_on_field_reset.bind(option_key))
	_group_containers[group_key].add_child(field)
	_rows[option_key] = field
	field.visible = _matches_search(option_key)
	return field

## 读取当前应显示的值：配置差异项优先，否则按类型转换的 actual（并同步初始差异）。
func _current_value(option_key: String) -> Variant:
	if _store.has_value(option_key):
		return _store.get_value(option_key)
	var current_value: Variant = _store.get_actual_value(option_key)
	if _store.sync_initial_actual(option_key):
		config_changed.emit(option_key)
	return current_value

## 遍历所有分组的全部选项，预扫描初始差异（未访问的分组也能正确计数）。
func _sync_initial_actuals() -> void:
	for group_key: String in _group_to_option_keys:
		for option_key: Variant in _group_to_option_keys[group_key]:
			_store.sync_initial_actual(str(option_key))

## 按字段类型选择行预制场景。
func _scene_for_type(type: String) -> PackedScene:
	match type:
		"bool":
			return BOOL_FIELD_SCENE
		"enum":
			return ENUM_FIELD_SCENE
		"integer":
			return INTEGER_FIELD_SCENE
		"path":
			return PATH_FIELD_SCENE
		_:
			return STRING_FIELD_SCENE

## 字段值变化回调：写入配置状态并通知外部。
func _on_field_value_changed(value: Variant, option_key: String) -> void:
	var option: Dictionary = _store.get_option(option_key)
	var stored: Variant = value
	if str(option.get(KEY_TYPE, "string")) == "integer":
		stored = int(value)
	_store.set_value(option_key, stored)
	_refresh_module_defaults()
	config_changed.emit(option_key)

## 字段重置回调：移除差异项并发送信号。
func _on_field_reset(option_key: String) -> void:
	_store.erase(option_key)
	_refresh_module_defaults()
	config_changed.emit(option_key)

## 模块总开关变化后刷新已建模块行的派生默认值（行创建时捕获的默认值可能已过期）。
func _refresh_module_defaults() -> void:
	for key: String in _rows:
		if BuildOptions.is_module_option(key):
			_rows[key].set_default(_store.get_default_value(key))
			_rows[key].set_control(_current_value(key))
