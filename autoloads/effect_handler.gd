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
	GameState.add_health(10.0 + GameState.food_heal_bonus)
	GameState.add_food_eaten()
	LogManager.push("you eat the bread. it is simple, but satisfying.")
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
