extends Node

const TICK_INTERVAL_SEC: float = 60.0

var _timer: Timer


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = TICK_INTERVAL_SEC
	_timer.timeout.connect(_on_tick)
	add_child(_timer)
	_timer.start()


func _on_tick() -> void:
	if GameState.health_regen_per_minute > 0.0 and not GameState.is_blacked_out:
		GameState.add_health(GameState.health_regen_per_minute)
