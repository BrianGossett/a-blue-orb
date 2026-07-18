extends Control

@onready var _lines_label: RichTextLabel = $Lines


func _ready() -> void:
	for line in LogManager.get_lines():
		_append_line(line)
	LogManager.line_added.connect(_append_line)


func _append_line(timestamped_text: String) -> void:
	_lines_label.text += timestamped_text + "\n"
