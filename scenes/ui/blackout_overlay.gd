extends Control

const FADE_DURATION_SEC: float = 0.3

@onready var _fade_rect: ColorRect = $FadeRect

var _timer: Timer


func _ready() -> void:
	visible = false
	_fade_rect.modulate.a = 0.0
	EventBus.health_depleted.connect(_on_health_depleted)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = Constants.BLACKOUT_RECOVERY_SEC
	_timer.timeout.connect(_on_recovery_timeout)
	add_child(_timer)


func _on_health_depleted() -> void:
	if GameState.is_blacked_out:
		return
	GameState.enter_blackout()
	visible = true
	var tween := create_tween()
	tween.tween_property(_fade_rect, "modulate:a", 1.0, FADE_DURATION_SEC)
	_timer.start()


func _on_recovery_timeout() -> void:
	GameState.add_health(1.0)
	GameState.exit_blackout()
	var tween := create_tween()
	tween.tween_property(_fade_rect, "modulate:a", 0.0, FADE_DURATION_SEC)
	tween.tween_callback(func() -> void: visible = false)
	EventBus.blackout_ended.emit()
