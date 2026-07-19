extends GutTest

# Covers the rest of EffectHandler's Ticket 9 (House button content) effect
# functions not already exercised by test_effect_handler.gd or Task 4's
# unlock-condition tests: add_table, add_bed, better_chair/better_table/
# better_bed's per-level guard, better_meal, and Confidence 4's HP-cost
# growth acceptance criterion. Like test_effect_handler.gd, these read/write
# the live GameState singleton directly, so before_each resets it.


func before_each() -> void:
	GameState.from_dict({})


func test_effect_add_table() -> void:
	var familiars_before: int = GameState.familiars

	var result: bool = EffectHandler.run_effect("add_table")

	assert_true(result)
	assert_eq(GameState.food_heal_bonus, 2.0)
	assert_eq(GameState.orb_mana_per_click, 3.0)
	assert_true(GameState.has_upgrade("table"))
	assert_eq(GameState.familiars, familiars_before, "add_table must not deduct familiars itself")


func test_effect_add_bed() -> void:
	var familiars_before: int = GameState.familiars

	var result: bool = EffectHandler.run_effect("add_bed")

	assert_true(result)
	assert_eq(GameState.max_health, 70.0, "default max_health 50 + 20")
	assert_eq(GameState.orb_mana_per_click, 4.0)
	assert_true(GameState.has_upgrade("bed"))
	assert_eq(GameState.familiars, familiars_before, "add_bed must not deduct familiars itself")


func test_effect_better_chair_accumulates_across_four_calls_then_guards() -> void:
	for i in range(4):
		var result: bool = EffectHandler.run_effect("better_chair")
		assert_true(result, "call %d should succeed" % (i + 1))

	assert_eq(GameState.better_chair_level, 4)
	assert_eq(GameState.health_regen_per_minute, 4.0)
	assert_eq(GameState.orb_mana_per_click, 5.0, "base 1.0 + 4 calls * 1.0")

	var fifth_result: bool = EffectHandler.run_effect("better_chair")
	assert_false(fifth_result)
	assert_push_error("better_chair_level already at max")
	assert_eq(GameState.better_chair_level, 4, "guard must not mutate state further")
	assert_eq(GameState.health_regen_per_minute, 4.0, "guard must not mutate state further")
	assert_eq(GameState.orb_mana_per_click, 5.0, "guard must not mutate state further")


func test_effect_better_table_accumulates_across_four_calls_then_guards() -> void:
	for i in range(4):
		var result: bool = EffectHandler.run_effect("better_table")
		assert_true(result, "call %d should succeed" % (i + 1))

	assert_eq(GameState.better_table_level, 4)
	assert_eq(GameState.food_heal_bonus, 8.0, "4 calls * 2.0")
	assert_eq(GameState.orb_mana_per_click, 9.0, "base 1.0 + 4 calls * 2.0")

	var fifth_result: bool = EffectHandler.run_effect("better_table")
	assert_false(fifth_result)
	assert_push_error("better_table_level already at max")
	assert_eq(GameState.better_table_level, 4, "guard must not mutate state further")
	assert_eq(GameState.food_heal_bonus, 8.0, "guard must not mutate state further")
	assert_eq(GameState.orb_mana_per_click, 9.0, "guard must not mutate state further")


func test_effect_better_bed_accumulates_across_four_calls_then_guards() -> void:
	for i in range(4):
		var result: bool = EffectHandler.run_effect("better_bed")
		assert_true(result, "call %d should succeed" % (i + 1))

	assert_eq(GameState.better_bed_level, 4)
	assert_eq(GameState.max_health, 130.0, "default 50 + 4 calls * 20.0")
	assert_eq(GameState.orb_mana_per_click, 13.0, "base 1.0 + 4 calls * 3.0")

	var fifth_result: bool = EffectHandler.run_effect("better_bed")
	assert_false(fifth_result)
	assert_push_error("better_bed_level already at max")
	assert_eq(GameState.better_bed_level, 4, "guard must not mutate state further")
	assert_eq(GameState.max_health, 130.0, "guard must not mutate state further")
	assert_eq(GameState.orb_mana_per_click, 13.0, "guard must not mutate state further")


func test_effect_better_meal_requires_better_table_level_ahead() -> void:
	GameState.advance_better_table_level()

	var result: bool = EffectHandler.run_effect("better_meal")

	assert_true(result)
	assert_eq(GameState.food_heal_bonus, 5.0)
	assert_eq(GameState.better_meal_level, 1)


func test_effect_better_meal_fails_once_it_catches_up_to_better_table_level() -> void:
	GameState.advance_better_table_level()
	EffectHandler.run_effect("better_meal")
	assert_eq(GameState.better_meal_level, 1)
	assert_eq(GameState.better_table_level, 1)

	var result: bool = EffectHandler.run_effect("better_meal")

	assert_false(result)
	assert_push_error("better_meal_level cannot exceed better_table_level")
	assert_eq(GameState.better_meal_level, 1, "guard must not mutate state further")
	assert_eq(GameState.food_heal_bonus, 5.0, "guard must not mutate state further")


func test_confidence_4_touch_orb_costs_25_hp() -> void:
	# Ticket 9's own explicit acceptance criterion: "at Confidence 4,
	# touching the orb costs 25 HP, not 5" — orb_health_cost_per_click
	# starts at 5.0 and gain_confidence adds +5.0 each of the 4 tiers.
	for i in range(4):
		EffectHandler.run_effect("gain_confidence")
	assert_eq(GameState.confidence_tier, 4)
	assert_eq(GameState.orb_health_cost_per_click, 25.0)

	var health_before: float = GameState.health
	EffectHandler.run_effect("touch_orb")

	assert_eq(GameState.health, health_before - 25.0)
