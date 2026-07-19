extends GutTest

# RegenManager's _ready() wires a real 60-second Timer, which isn't
# practical to wait out in a test. Instead, instantiate the script fresh
# (bypassing _ready()/the Timer entirely, since we never add it to the
# tree) and call _on_tick() directly to test the tick logic in isolation.
# Task 2's smoke test / full-project headless check already proves the
# Timer plumbing itself doesn't error.
#
# _on_tick() reads/writes the live GameState singleton directly, so
# before_each resets it to a known baseline.

var _regen_manager: Node


func before_each() -> void:
	GameState.from_dict({})
	_regen_manager = load("res://autoloads/regen_manager.gd").new()


func after_each() -> void:
	_regen_manager.free()


func test_tick_does_nothing_when_regen_rate_is_zero() -> void:
	assert_eq(GameState.health_regen_per_minute, 0.0, "default regen rate")
	GameState.spend_health(10.0)
	var health_before: float = GameState.health

	_regen_manager._on_tick()

	assert_eq(GameState.health, health_before, "no regen configured, tick should be a no-op")


func test_tick_adds_regen_amount_to_health() -> void:
	GameState.add_health_regen_per_minute(1.0)
	GameState.spend_health(10.0)
	var health_before: float = GameState.health

	_regen_manager._on_tick()

	assert_eq(GameState.health, health_before + 1.0)


func test_tick_does_nothing_while_blacked_out() -> void:
	GameState.add_health_regen_per_minute(1.0)
	GameState.spend_health(10.0)
	GameState.enter_blackout()
	var health_before: float = GameState.health

	_regen_manager._on_tick()

	assert_eq(GameState.health, health_before, "regen must not tick during blackout")
