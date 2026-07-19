class_name ButtonData
extends Resource

@export var id: String
@export var labels: Array[String]
@export var cost_type: String
@export var base_cost: float
@export var cost_scaling: String
@export var cost_step: float
@export var cost_table: Array[float] = []
@export var cooldown_sec: float
@export var unlock_condition: String
@export var effect_id: String
@export var flavor_lines: Array[String]
@export var one_shot: bool
@export var button_column: int
@export var sort_order: int
@export var tier_source: String
@export var cost_count_source: String
@export var room_description_fragment: String
@export var max_purchases: int
@export var cooldown_gate_condition: String
@export var count_seed_source: String


static func calculate_cost(base_cost: float, cost_scaling: String, cost_step: float, count: int, cost_table: Array[float] = []) -> float:
	match cost_scaling:
		"linear":
			return base_cost + (cost_step * count)
		"double":
			return base_cost * pow(2, count)
		"fixed":
			return base_cost
		"table":
			if cost_table.is_empty():
				push_error("ButtonData: cost_scaling \"table\" requires a non-empty cost_table")
				return base_cost
			var index: int = min(count, cost_table.size() - 1)
			return cost_table[index]
		_:
			push_error("ButtonData: unknown cost_scaling \"%s\"" % cost_scaling)
			return base_cost


static func is_unlock_condition_met(condition: String) -> bool:
	if condition.is_empty():
		return true
	if "&&" in condition:
		for sub_condition in condition.split("&&"):
			if not is_unlock_condition_met(sub_condition.strip_edges()):
				return false
		return true
	if condition.begins_with("has_upgrade("):
		var inner := condition.trim_prefix("has_upgrade(").trim_suffix(")")
		var upgrade_id := inner.trim_prefix("\"").trim_suffix("\"")
		return GameState.has_upgrade(upgrade_id)
	if ">=" in condition:
		var parts := condition.split(">=")
		if parts.size() == 2:
			return _resolve_operand(parts[0].strip_edges()) >= _resolve_operand(parts[1].strip_edges())
	if "<" in condition:
		var parts := condition.split("<")
		if parts.size() == 2:
			return _resolve_operand(parts[0].strip_edges()) < _resolve_operand(parts[1].strip_edges())
	push_error("ButtonData: unrecognized unlock_condition shape \"%s\"" % condition)
	return false


static func _resolve_operand(token: String) -> float:
	if token.is_valid_float():
		return token.to_float()
	return _get_stat_value(token)


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
		"food_eaten_count":
			return float(GameState.food_eaten_count)
		"better_chair_level":
			return float(GameState.better_chair_level)
		"better_table_level":
			return float(GameState.better_table_level)
		"better_bed_level":
			return float(GameState.better_bed_level)
		"better_meal_level":
			return float(GameState.better_meal_level)
		_:
			push_error("ButtonData: unknown stat \"%s\" in unlock_condition" % stat_name)
			return -INF
