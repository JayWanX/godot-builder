class_name ConfigPreviewWindow
extends Window

@export var preview_code_edit: CodeEdit

func setup(store: ConfigStore) -> void:
	var profile_text: String = ProfileConverter.config_to_profile(
		store.get_profile_config(), store.get_options()
	)
	preview_code_edit.text = profile_text
	popup_centered()

func _on_close_requested() -> void:
	preview_code_edit.text = ""
	hide()
