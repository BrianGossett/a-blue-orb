extends Node

var _autosave_timer: Timer


func _ready() -> void:
	load_game()
	EventBus.upgrade_purchased.connect(_on_purchase)
	EventBus.familiar_gained.connect(_on_purchase)
	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = Constants.AUTOSAVE_INTERVAL_SEC
	_autosave_timer.timeout.connect(save_game)
	add_child(_autosave_timer)
	_autosave_timer.start()


func _on_purchase() -> void:
	save_game()


func save_game() -> void:
	var file := FileAccess.open("user://save.json", FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: failed to open user://save.json for writing")
		return
	file.store_string(_build_save_json())
	file.close()


func load_game() -> bool:
	if not FileAccess.file_exists("user://save.json"):
		return false
	var file := FileAccess.open("user://save.json", FileAccess.READ)
	if file == null:
		push_error("SaveManager: failed to open user://save.json for reading")
		return false
	var text := file.get_as_text()
	file.close()
	return _apply_save_json(text)


func _build_save_json() -> String:
	return JSON.stringify({
		"save_version": Constants.SAVE_VERSION,
		"game_state": GameState.to_dict(),
	})


func _apply_save_json(text: String) -> bool:
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("SaveManager: save data is malformed, ignoring")
		return false
	var save_data: Dictionary = parsed
	if save_data.get("save_version") != Constants.SAVE_VERSION:
		push_warning("SaveManager: save_version mismatch, treating as no save found")
		return false
	var game_state_dict: Variant = save_data.get("game_state")
	if not (game_state_dict is Dictionary):
		push_warning("SaveManager: save data missing game_state, ignoring")
		return false
	GameState.from_dict(game_state_dict)
	return true
