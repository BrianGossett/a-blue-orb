extends GutTest

# GameState's own code never references the GameState singleton by name
# internally (it only calls EventBus.*.emit), so each test gets a fresh,
# non-singleton instance for full isolation from the live autoload and from
# other tests. Signals are declared on EventBus (not on GameState itself),
# so signal assertions watch the live EventBus singleton rather than `gs`.

var gs


func before_each() -> void:
	gs = load("res://autoloads/game_state.gd").new()
	watch_signals(EventBus)


func after_each() -> void:
	gs.free()


func test_add_mana() -> void:
	gs.add_mana(5.0)
	assert_eq(gs.mana, 5.0)
	assert_signal_emitted_with_parameters(EventBus, "mana_changed", [5.0])


func test_spend_mana_insufficient_funds() -> void:
	var result: bool = gs.spend_mana(1000.0)
	assert_false(result)
	assert_eq(gs.mana, 0.0)
	assert_signal_not_emitted(EventBus, "mana_changed")


func test_spend_mana_success() -> void:
	gs.add_mana(5.0)
	var result: bool = gs.spend_mana(3.0)
	assert_true(result)
	assert_eq(gs.mana, 2.0)
	assert_signal_emitted_with_parameters(EventBus, "mana_changed", [2.0])


func test_add_health_clamps_to_max() -> void:
	gs.add_health(100.0)
	assert_eq(gs.health, 50.0)
	assert_signal_emitted_with_parameters(EventBus, "health_changed", [50.0, 50.0])


func test_spend_health_guarded_by_blackout() -> void:
	gs.enter_blackout()
	gs.spend_health(10.0)
	assert_eq(gs.health, 50.0)
	assert_signal_not_emitted(EventBus, "health_changed")


func test_spend_health_depletes_and_clamps() -> void:
	gs.spend_health(60.0)
	assert_eq(gs.health, 0.0)
	assert_signal_emitted_with_parameters(EventBus, "health_changed", [0.0, 50.0])
	assert_signal_emitted(EventBus, "health_depleted")


func test_add_familiars() -> void:
	gs.add_familiars(3)
	assert_eq(gs.familiars, 3)
	assert_signal_emitted_with_parameters(EventBus, "familiar_gained", [3])


func test_spend_familiars_reservation_model() -> void:
	gs.add_familiars(3)
	gs.familiars_assigned_to_orb = 2

	# only 1 idle familiar available; asking for 2 should fail
	var over_result: bool = gs.spend_familiars(2)
	assert_false(over_result)
	assert_eq(gs.familiars, 3)

	# asking for the 1 idle familiar should succeed
	var ok_result: bool = gs.spend_familiars(1)
	assert_true(ok_result)
	assert_eq(gs.familiars, 2)


func test_mark_upgrade_purchased_idempotent() -> void:
	gs.mark_upgrade_purchased("chair")
	assert_true(gs.has_upgrade("chair"))
	assert_signal_emitted_with_parameters(EventBus, "upgrade_purchased", ["chair"])

	gs.mark_upgrade_purchased("chair")
	assert_signal_emit_count(EventBus, "upgrade_purchased", 1)


func test_advance_confidence_tier_clamps_and_emits_every_call() -> void:
	for i in range(5):
		gs.advance_confidence_tier()
	assert_eq(gs.confidence_tier, 4)
	assert_signal_emit_count(EventBus, "confidence_tier_changed", 5)
	assert_signal_emitted_with_parameters(EventBus, "confidence_tier_changed", [4])


func test_to_dict_from_dict_round_trip_never_restores_blackout() -> void:
	gs.add_mana(7.0)
	gs.add_familiars(2)
	gs.mark_upgrade_purchased("bed")
	gs.enter_blackout()

	var data: Dictionary = gs.to_dict()
	assert_true(gs.is_blacked_out)
	assert_true(data["is_blacked_out"])

	var gs2 = autofree(load("res://autoloads/game_state.gd").new())
	gs2.from_dict(data)

	var expected: Dictionary = gs.to_dict()
	expected["is_blacked_out"] = false
	assert_eq(gs2.to_dict(), expected)
	assert_eq(gs2.is_blacked_out, false)


func test_from_dict_duplicates_resources_dict() -> void:
	var input := {"stone": 1, "wood": 0, "water": 0, "crystals": 0}
	gs.from_dict({"resources": input})
	input["stone"] = 999
	assert_eq(gs.resources["stone"], 1)

# Skipped: "no public field is ever set directly from outside this script" is
# a code-review/static invariant (about call-site discipline elsewhere in the
# codebase), not an observable runtime behavior of GameState itself — there is
# no GUT assertion that can verify it.
