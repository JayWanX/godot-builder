@tool
extends EditorPlugin

const ExportTrimmer = preload("uid://c6thfs6ex4x6b")

var _trimmer: EditorExportPlugin

func _enter_tree() -> void:
	_trimmer = ExportTrimmer.new()
	add_export_plugin(_trimmer)

func _exit_tree() -> void:
	remove_export_plugin(_trimmer)
	_trimmer = null
