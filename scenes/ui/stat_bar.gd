extends HBoxContainer

@onready var _mana_label: Label = $ManaLabel
@onready var _health_label: Label = $HealthLabel


func _ready() -> void:
	EventBus.mana_changed.connect(_on_mana_changed)
	EventBus.health_changed.connect(_on_health_changed)
	_on_mana_changed(GameState.mana)
	_on_health_changed(GameState.health, GameState.max_health)


func _on_mana_changed(new_value: float) -> void:
	_mana_label.text = "Mana: %s" % _format_number(new_value)


func _on_health_changed(new_value: float, max_value: float) -> void:
	_health_label.text = "Health: %s / %s" % [_format_number(new_value), _format_number(max_value)]


func _format_number(value: float) -> String:
	if value == floor(value):
		return str(int(value))
	return str(value)
