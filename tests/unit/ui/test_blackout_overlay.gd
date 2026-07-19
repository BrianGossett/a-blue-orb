extends GutTest

# blackout_overlay.gd reads/writes the live GameState/EventBus singletons
# directly by autoload name (not a locally constructed instance), so each
# test instantiates the real scene into the tree (add_child_autofree) and
# before_each() resets GameState to a known baseline, matching the
# convention used by test_button_action.gd.


func before_each() -> void:
	GameState.from_dict({})


func test_health_depleted_triggers_blackout_via_production_path() -> void:
	var overlay = add_child_autofree(load("res://scenes/ui/blackout_overlay.tscn").instantiate())

	# Fresh state has health == 50 (GameState.from_dict({}) default). Calling
	# spend_health() directly is the real production path: it's what
	# actually emits EventBus.health_depleted at exactly 0, which the
	# overlay's _ready() connects _on_health_depleted() to.
	GameState.spend_health(50.0)

	assert_true(overlay.visible, "overlay should become visible once health hits exactly 0")
	assert_true(GameState.is_blacked_out, "GameState should record the blackout")


func test_health_depleted_reentrancy_guard_is_a_no_op() -> void:
	var overlay = add_child_autofree(load("res://scenes/ui/blackout_overlay.tscn").instantiate())
	GameState.spend_health(50.0)
	assert_true(GameState.is_blacked_out, "sanity: should already be blacked out from the real path")

	# _on_health_depleted() guards with `if GameState.is_blacked_out: return`
	# at the top, so a second call (direct, bypassing the signal) must be a
	# complete no-op — not toggle or re-enter the blackout state.
	overlay._on_health_depleted()

	assert_true(GameState.is_blacked_out, "still simply true, not toggled/re-entered")


func test_recovery_restores_health_and_emits_blackout_ended() -> void:
	var overlay = add_child_autofree(load("res://scenes/ui/blackout_overlay.tscn").instantiate())
	GameState.spend_health(50.0)
	var health_before: float = GameState.health
	watch_signals(EventBus)

	# Bypasses the real Timer's wait by calling the timeout handler directly.
	overlay._on_recovery_timeout()

	assert_eq(GameState.health, health_before + 1.0, "recovery should add exactly 1.0 health")
	assert_false(GameState.is_blacked_out, "recovery should clear the blackout flag")
	assert_signal_emitted(EventBus, "blackout_ended")


func test_blackout_fully_blocks_health_spending_through_the_real_object_graph() -> void:
	var overlay = add_child_autofree(load("res://scenes/ui/blackout_overlay.tscn").instantiate())
	GameState.spend_health(50.0)
	assert_eq(GameState.health, 0.0, "sanity: fully depleted via the real path")

	# Re-asserts Ticket 10's own full-blockage acceptance criterion in
	# integration context (not just at the GameState-unit level Task 3
	# already covered): the guard must genuinely block HP-spending through
	# the same object graph the real game uses (overlay wired to the live
	# GameState/EventBus singletons), not just in isolation.
	GameState.spend_health(10.0)

	assert_eq(GameState.health, 0.0, "blackout guard must block further health spending")


func test_recovery_timer_wait_time_wired_to_constant() -> void:
	var overlay = add_child_autofree(load("res://scenes/ui/blackout_overlay.tscn").instantiate())

	# GDScript has no enforced privacy; the leading underscore on `_timer`
	# is convention only, so the instance property is directly reachable
	# from the test without a debugger-style workaround.
	assert_eq(overlay._timer.wait_time, Constants.BLACKOUT_RECOVERY_SEC,
		"the Timer created in _ready() should be wired to Constants.BLACKOUT_RECOVERY_SEC")
