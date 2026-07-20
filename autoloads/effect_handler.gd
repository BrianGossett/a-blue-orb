extends Node
# Autoload (not a static class): effect functions call other autoloads
# (GameState, LogManager) by singleton name, which reads most naturally
# from a Node in the same autoload family.


func run_effect(effect_id: String) -> bool:
	match effect_id:
		"touch_orb":
			return _effect_touch_orb()
		"summon_familiar":
			return _effect_summon_familiar()
		"eat_food":
			return _effect_eat_food()
		"gain_confidence":
			return _effect_gain_confidence()
		"add_chair":
			return _effect_add_chair()
		"add_table":
			return _effect_add_table()
		"add_bed":
			return _effect_add_bed()
		"better_chair":
			return _effect_better_chair()
		"better_table":
			return _effect_better_table()
		"better_bed":
			return _effect_better_bed()
		"better_meal":
			return _effect_better_meal()
		_:
			push_error("EffectHandler: unknown effect_id \"%s\"" % effect_id)
			return false


func _effect_touch_orb() -> bool:
	GameState.add_mana(GameState.orb_mana_per_click)
	GameState.spend_health(GameState.orb_health_cost_per_click)
	LogManager.push("you gingerly touch the orb.")
	return true


func _effect_summon_familiar() -> bool:
	GameState.add_familiars(1)
	LogManager.push("you summon a familiar.")
	return true


func _effect_eat_food() -> bool:
	const FOOD_NAMES: Array[String] = ["bread", "soup", "stew", "roast", "shepherd's pie"]
	GameState.add_health(10.0 + GameState.food_heal_bonus)
	GameState.add_food_eaten()
	var food_index: int = min(GameState.better_table_level, FOOD_NAMES.size() - 1)
	LogManager.push("you eat the %s. it is simple, but satisfying." % FOOD_NAMES[food_index])
	return true


func _effect_gain_confidence() -> bool:
	const CONFIDENCE_MANA_BONUS: Array[float] = [3.0, 5.0, 7.0, 10.0]
	const CONFIDENCE_HP_COST_INCREASE: float = 5.0
	var tier_index := GameState.confidence_tier
	if tier_index >= CONFIDENCE_MANA_BONUS.size():
		push_error("EffectHandler: confidence_tier already at max")
		return false
	GameState.add_orb_mana_per_click(CONFIDENCE_MANA_BONUS[tier_index])
	GameState.add_orb_health_cost_per_click(CONFIDENCE_HP_COST_INCREASE)
	GameState.advance_confidence_tier()
	LogManager.push("you feel a swell of confidence.")
	return true


func _effect_add_chair() -> bool:
	GameState.mark_upgrade_purchased("chair")
	GameState.add_orb_mana_per_click(1.0)
	GameState.add_health_regen_per_minute(1.0)
	LogManager.push("you are no longer sitting on the floor.")
	return true


func _effect_add_table() -> bool:
	GameState.mark_upgrade_purchased("table")
	GameState.add_food_heal_bonus(2.0)
	GameState.add_orb_mana_per_click(2.0)
	LogManager.push("you now have something to eat on.")
	return true


func _effect_add_bed() -> bool:
	GameState.mark_upgrade_purchased("bed")
	GameState.add_max_health(20.0)
	GameState.add_orb_mana_per_click(3.0)
	LogManager.push("you now have somewhere to rest.")
	return true


func _effect_better_chair() -> bool:
	if GameState.better_chair_level >= 4:
		push_error("EffectHandler: better_chair_level already at max")
		return false
	GameState.add_health_regen_per_minute(1.0)
	GameState.add_orb_mana_per_click(1.0)
	GameState.advance_better_chair_level()
	LogManager.push("your chair creaks contentedly.")
	return true


func _effect_better_table() -> bool:
	if GameState.better_table_level >= 4:
		push_error("EffectHandler: better_table_level already at max")
		return false
	GameState.add_food_heal_bonus(2.0)
	GameState.add_orb_mana_per_click(2.0)
	GameState.advance_better_table_level()
	LogManager.push("your table gleams a little brighter.")
	return true


func _effect_better_bed() -> bool:
	if GameState.better_bed_level >= 4:
		push_error("EffectHandler: better_bed_level already at max")
		return false
	GameState.add_max_health(20.0)
	GameState.add_orb_mana_per_click(3.0)
	GameState.advance_better_bed_level()
	LogManager.push("your bed looks even more inviting.")
	return true


func _effect_better_meal() -> bool:
	if GameState.better_meal_level >= GameState.better_table_level:
		push_error("EffectHandler: better_meal_level cannot exceed better_table_level")
		return false
	GameState.add_food_heal_bonus(5.0)
	GameState.advance_better_meal_level()
	LogManager.push("the meal tastes a little better.")
	return true
