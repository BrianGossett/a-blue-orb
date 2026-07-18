extends Node

signal line_added(timestamped_text: String)

const MAX_LINES: int = 200

var _lines: Array[String] = []


func push(text: String) -> void:
	var line := "[%s] %s" % [Time.get_time_string_from_system(), text.to_lower()]
	_lines.append(line)
	if _lines.size() > MAX_LINES:
		_lines.pop_front()
	line_added.emit(line)


func get_lines() -> Array[String]:
	return _lines.duplicate()
