extends HBoxContainer

@onready var _mana_label: Label = $ManaLabel
@onready var _health_label: Label = $HealthLabel
@onready var _reset_button: Button = $ResetButton
@onready var _reset_confirm_dialog: ConfirmationDialog = $ResetConfirmDialog


func _ready() -> void:
	EventBus.mana_changed.connect(_on_mana_changed)
	EventBus.health_changed.connect(_on_health_changed)
	EventBus.state_changed.connect(_on_state_changed)
	_reset_button.pressed.connect(_on_reset_button_pressed)
	_reset_confirm_dialog.confirmed.connect(_on_reset_confirmed)
	_on_mana_changed(GameState.mana)
	_on_health_changed(GameState.health, GameState.max_health)


func _on_mana_changed(new_value: float) -> void:
	_mana_label.text = "Mana: %s" % _format_number(new_value)


func _on_health_changed(new_value: float, max_value: float) -> void:
	_health_label.text = "Health: %s / %s" % [_format_number(new_value), _format_number(max_value)]


func _on_state_changed() -> void:
	_on_mana_changed(GameState.mana)
	_on_health_changed(GameState.health, GameState.max_health)


func _on_reset_button_pressed() -> void:
	_reset_confirm_dialog.popup_centered()


func _on_reset_confirmed() -> void:
	SaveManager.reset_game()


func _format_number(value: float) -> String:
	if value == floor(value):
		return str(int(value))
	return str(value)
