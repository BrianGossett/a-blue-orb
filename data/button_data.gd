class_name ButtonData
extends Resource

@export var id: String
@export var labels: Array[String]
@export var cost_type: String
@export var base_cost: float
@export var cost_scaling: String
@export var cost_step: float
@export var cooldown_sec: float
@export var unlock_condition: String
@export var effect_id: String
@export var flavor_lines: Array[String]
@export var one_shot: bool
@export var button_column: int


static func calculate_cost(base_cost: float, cost_scaling: String, cost_step: float, count: int) -> float:
	match cost_scaling:
		"linear":
			return base_cost + (cost_step * count)
		"double":
			return base_cost * pow(2, count)
		"fixed":
			return base_cost
		_:
			push_error("ButtonData: unknown cost_scaling \"%s\"" % cost_scaling)
			return base_cost


static func is_unlock_condition_met(condition: String) -> bool:
	if condition.is_empty():
		return true
	if condition.begins_with("has_upgrade("):
		var inner := condition.trim_prefix("has_upgrade(").trim_suffix(")")
		var id := inner.trim_prefix("\"").trim_suffix("\"")
		return GameState.has_upgrade(id)
	if ">=" in condition:
		var parts := condition.split(">=")
		if parts.size() == 2:
			var stat_name := parts[0].strip_edges()
			var threshold := parts[1].strip_edges().to_float()
			return _get_stat_value(stat_name) >= threshold
	push_error("ButtonData: unrecognized unlock_condition shape \"%s\"" % condition)
	return false


static func _get_stat_value(stat_name: String) -> float:
	match stat_name:
		"mana":
			return GameState.mana
		"familiars":
			return float(GameState.familiars)
		"confidence_tier":
			return float(GameState.confidence_tier)
		"house_tier":
			return float(GameState.house_tier)
		_:
			push_error("ButtonData: unknown stat \"%s\" in unlock_condition" % stat_name)
			return 0.0
