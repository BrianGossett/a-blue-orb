extends GutTest

# calculate_cost is a pure static function (no GameState involvement), so no
# reset is needed for those tests. is_unlock_condition_met reads the live
# GameState singleton via _get_stat_value/has_upgrade, so before_each resets
# it to a known baseline.


func before_each() -> void:
	GameState.from_dict({})


func test_calculate_cost_linear_matches_ticket_5_acceptance_criterion() -> void:
	assert_eq(ButtonData.calculate_cost(1.0, "linear", 1.0, 0), 1.0)
	assert_eq(ButtonData.calculate_cost(1.0, "linear", 1.0, 1), 2.0)
	assert_eq(ButtonData.calculate_cost(1.0, "linear", 1.0, 5), 6.0)


func test_calculate_cost_double() -> void:
	assert_eq(ButtonData.calculate_cost(10.0, "double", 0.0, 0), 10.0)
	assert_eq(ButtonData.calculate_cost(10.0, "double", 0.0, 2), 40.0)


func test_calculate_cost_fixed_ignores_count() -> void:
	assert_eq(ButtonData.calculate_cost(5.0, "fixed", 999.0, 7), 5.0)


func test_is_unlock_condition_met_empty_string_always_true() -> void:
	assert_true(ButtonData.is_unlock_condition_met(""))


func test_is_unlock_condition_met_familiars_threshold() -> void:
	assert_false(ButtonData.is_unlock_condition_met("familiars >= 1"))
	GameState.add_familiars(1)
	assert_true(ButtonData.is_unlock_condition_met("familiars >= 1"))


func test_is_unlock_condition_met_has_upgrade() -> void:
	assert_false(ButtonData.is_unlock_condition_met("has_upgrade(\"chair\")"))
	GameState.mark_upgrade_purchased("chair")
	assert_true(ButtonData.is_unlock_condition_met("has_upgrade(\"chair\")"))


func test_is_unlock_condition_met_compound_and() -> void:
	var condition := "familiars >= 1 && has_upgrade(\"chair\")"
	assert_false(ButtonData.is_unlock_condition_met(condition))

	GameState.add_familiars(1)
	assert_false(ButtonData.is_unlock_condition_met(condition))

	GameState.mark_upgrade_purchased("chair")
	assert_true(ButtonData.is_unlock_condition_met(condition))


func test_is_unlock_condition_met_stat_vs_stat() -> void:
	var condition := "better_meal_level < better_table_level"
	assert_false(ButtonData.is_unlock_condition_met(condition))
	GameState.advance_better_table_level()
	assert_true(ButtonData.is_unlock_condition_met(condition))


func test_is_unlock_condition_met_unknown_stat_fails_closed() -> void:
	# _get_stat_value push_errors on an unknown stat name as documented; that
	# error is expected here, so assert_push_error both confirms it fired and
	# marks it as expected so it doesn't also fail the test.
	assert_false(ButtonData.is_unlock_condition_met("nonexistent_stat >= 0"))
	assert_push_error("unknown stat")
