extends Node

const TICK_INTERVAL_SEC: float = 1.0

var _timer: Timer


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = TICK_INTERVAL_SEC
	_timer.timeout.connect(_on_tick)
	add_child(_timer)
	_timer.start()


func _on_tick() -> void:
	if GameState.orb_mana_per_second > 0.0:
		GameState.add_mana(GameState.orb_mana_per_second)
