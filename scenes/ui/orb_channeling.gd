extends Control

@onready var _count_label: Label = $Root/CountLabel
@onready var _info_label: Label = $Root/InfoLabel
@onready var _up_button: Button = $Root/UpButton
@onready var _down_button: Button = $Root/DownButton


func _ready() -> void:
	_up_button.pressed.connect(_on_up_pressed)
	_down_button.pressed.connect(_on_down_pressed)
	EventBus.familiar_gained.connect(_on_familiar_gained)
	_refresh()


func _on_familiar_gained(_new_total: int) -> void:
	_refresh()


func _on_up_pressed() -> void:
	if not InputGuard.try_register_click():
		return
	GameState.assign_familiar_to_orb()
	_refresh()


func _on_down_pressed() -> void:
	if not InputGuard.try_register_click():
		return
	GameState.unassign_familiar_from_orb()
	_refresh()


func _refresh() -> void:
	visible = GameState.familiars >= 1
	_count_label.text = str(GameState.familiars_assigned_to_orb)
	_info_label.text = "(%d idle)" % GameState.idle_familiars()
	_up_button.disabled = GameState.idle_familiars() <= 0
	_down_button.disabled = GameState.familiars_assigned_to_orb <= 0
