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
		_:
			push_error("EffectHandler: unknown effect_id \"%s\"" % effect_id)
			return false


func _effect_touch_orb() -> bool:
	GameState.add_mana(GameState.orb_mana_per_click)
	# Fixed 5 HP cost — confidence's "+5 HP cost" growth per tier isn't
	# wired up yet; needs a new GameState field Ticket 9 should add
	# when it builds confidence_N.tres and touch_orb.tres for real.
	GameState.spend_health(5.0)
	LogManager.push("you gingerly touch the orb.")
	return true


func _effect_summon_familiar() -> bool:
	GameState.add_familiars(1)
	LogManager.push("you summon a familiar.")
	return true


func _effect_eat_food() -> bool:
	GameState.add_health(10.0)
	LogManager.push("you eat the bread. it is simple, but satisfying.")
	return true


func _effect_gain_confidence() -> bool:
	const CONFIDENCE_MANA_BONUS: Array[float] = [3.0, 5.0, 7.0, 10.0]
	var tier_index := GameState.confidence_tier
	if tier_index >= CONFIDENCE_MANA_BONUS.size():
		push_error("EffectHandler: confidence_tier already at max")
		return false
	GameState.add_orb_mana_per_click(CONFIDENCE_MANA_BONUS[tier_index])
	GameState.advance_confidence_tier()
	LogManager.push("you feel a swell of confidence.")
	return true


func _effect_add_chair() -> bool:
	if not GameState.spend_familiars(1):
		return false
	GameState.mark_upgrade_purchased("chair")
	# Instant/one-shot part only. The "+1 HP regen/min" passive part of
	# Chair's effect has no mechanism anywhere in the codebase yet — no
	# ticket in this batch builds a regen-over-time system.
	GameState.add_orb_mana_per_click(1.0)
	LogManager.push("you are no longer sitting on the floor.")
	return true
