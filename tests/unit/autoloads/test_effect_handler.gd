extends GutTest

# EffectHandler's effect functions read/write the live GameState singleton
# directly (by autoload name), so before_each resets GameState to a known
# baseline rather than using a fresh non-singleton instance.


func before_each() -> void:
	GameState.from_dict({})


func test_effect_touch_orb() -> void:
	var result: bool = EffectHandler.run_effect("touch_orb")
	assert_true(result)
	assert_eq(GameState.mana, 1.0)
	assert_eq(GameState.health, 45.0)


func test_effect_summon_familiar() -> void:
	var result: bool = EffectHandler.run_effect("summon_familiar")
	assert_true(result)
	assert_eq(GameState.familiars, 1)


func test_effect_eat_food() -> void:
	# Touch the orb twice (health 50 -> 40) so there's enough room below
	# max_health (50) for the full +10 heal to land without being clamped.
	EffectHandler.run_effect("touch_orb")
	EffectHandler.run_effect("touch_orb")
	var health_before: float = GameState.health
	var result: bool = EffectHandler.run_effect("eat_food")
	assert_true(result)
	assert_eq(GameState.health, health_before + 10.0)
	assert_eq(GameState.food_eaten_count, 1)


func test_effect_gain_confidence() -> void:
	var result: bool = EffectHandler.run_effect("gain_confidence")
	assert_true(result)
	assert_eq(GameState.orb_mana_per_click, 4.0)
	assert_eq(GameState.orb_health_cost_per_click, 10.0)
	assert_eq(GameState.confidence_tier, 1)


func test_effect_gain_confidence_fails_at_max_tier() -> void:
	for i in range(4):
		EffectHandler.run_effect("gain_confidence")
	assert_eq(GameState.confidence_tier, 4)

	var result: bool = EffectHandler.run_effect("gain_confidence")
	assert_false(result)
	# The guard push_errors as documented; assert_push_error confirms it
	# fired and marks it expected so it doesn't also fail the test.
	assert_push_error("confidence_tier already at max")


func test_effect_add_chair_does_not_self_deduct_familiars() -> void:
	# Regression test: cost deduction is button_action.gd's job, never the
	# effect's. This bug class (an effect self-deducting a cost that
	# button_action.gd also deducts, causing a double-charge) has been found
	# and fixed twice already in this project's history.
	GameState.add_familiars(1)
	var familiars_before: int = GameState.familiars

	var result: bool = EffectHandler.run_effect("add_chair")

	assert_true(result)
	assert_eq(GameState.familiars, familiars_before, "add_chair must not deduct familiars itself")
	assert_true(GameState.has_upgrade("chair"))
	assert_eq(GameState.orb_mana_per_click, 2.0)
	assert_eq(GameState.health_regen_per_minute, 1.0)
