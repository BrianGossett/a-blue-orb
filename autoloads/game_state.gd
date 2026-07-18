extends Node

var mana: float = 0.0
var health: float = 50.0
var max_health: float = 50.0
var familiars: int = 0
var resources: Dictionary = {
	"stone": 0,
	"wood": 0,
	"water": 0,
	"crystals": 0,
}
var confidence_tier: int = 0
var house_tier: int = 0
var purchased_upgrades: Array[String] = []
var orb_mana_per_click: float = 1.0
var orb_mana_per_second: float = 0.0
var is_blacked_out: bool = false
var food_eaten_count: int = 0
var orb_health_cost_per_click: float = 5.0
var food_heal_bonus: float = 0.0
var health_regen_per_minute: float = 0.0
var better_chair_level: int = 0
var better_table_level: int = 0
var better_bed_level: int = 0


func add_mana(amount: float) -> void:
	mana += amount
	EventBus.mana_changed.emit(mana)


func spend_mana(amount: float) -> bool:
	if mana < amount:
		return false
	mana -= amount
	EventBus.mana_changed.emit(mana)
	return true


func add_health(amount: float) -> void:
	health = min(health + amount, max_health)
	EventBus.health_changed.emit(health, max_health)


func spend_health(amount: float) -> void:
	if is_blacked_out:
		return
	health = max(health - amount, 0.0)
	EventBus.health_changed.emit(health, max_health)
	if health <= 0.0:
		EventBus.health_depleted.emit()


func add_familiars(n: int) -> void:
	familiars += n
	EventBus.familiar_gained.emit(familiars)


func spend_familiars(n: int) -> bool:
	if familiars < n:
		return false
	familiars -= n
	EventBus.familiar_gained.emit(familiars)
	return true


func has_upgrade(id: String) -> bool:
	return purchased_upgrades.has(id)


func mark_upgrade_purchased(id: String) -> void:
	if purchased_upgrades.has(id):
		return
	purchased_upgrades.append(id)
	EventBus.upgrade_purchased.emit(id)


func add_orb_mana_per_click(amount: float) -> void:
	orb_mana_per_click += amount


func add_orb_mana_per_second(amount: float) -> void:
	orb_mana_per_second += amount


func advance_confidence_tier() -> void:
	confidence_tier = min(confidence_tier + 1, 4)
	EventBus.confidence_tier_changed.emit(confidence_tier)


func enter_blackout() -> void:
	is_blacked_out = true


func exit_blackout() -> void:
	is_blacked_out = false


func add_food_eaten() -> void:
	food_eaten_count += 1


func add_orb_health_cost_per_click(amount: float) -> void:
	orb_health_cost_per_click += amount


func add_food_heal_bonus(amount: float) -> void:
	food_heal_bonus += amount


func add_health_regen_per_minute(amount: float) -> void:
	health_regen_per_minute += amount


func add_max_health(amount: float) -> void:
	max_health += amount
	EventBus.health_changed.emit(health, max_health)


func advance_better_chair_level() -> void:
	better_chair_level = min(better_chair_level + 1, 4)


func advance_better_table_level() -> void:
	better_table_level = min(better_table_level + 1, 4)


func advance_better_bed_level() -> void:
	better_bed_level = min(better_bed_level + 1, 4)


func to_dict() -> Dictionary:
	return {
		"mana": mana,
		"health": health,
		"max_health": max_health,
		"familiars": familiars,
		"resources": resources.duplicate(),
		"confidence_tier": confidence_tier,
		"house_tier": house_tier,
		"purchased_upgrades": purchased_upgrades.duplicate(),
		"orb_mana_per_click": orb_mana_per_click,
		"orb_mana_per_second": orb_mana_per_second,
		"food_eaten_count": food_eaten_count,
		"orb_health_cost_per_click": orb_health_cost_per_click,
		"food_heal_bonus": food_heal_bonus,
		"health_regen_per_minute": health_regen_per_minute,
		"better_chair_level": better_chair_level,
		"better_table_level": better_table_level,
		"better_bed_level": better_bed_level,
		"is_blacked_out": is_blacked_out,
	}


func from_dict(data: Dictionary) -> void:
	mana = data.get("mana", 0.0)
	health = data.get("health", 50.0)
	max_health = data.get("max_health", 50.0)
	familiars = data.get("familiars", 0)
	resources = (data.get("resources", {"stone": 0, "wood": 0, "water": 0, "crystals": 0}) as Dictionary).duplicate()
	confidence_tier = data.get("confidence_tier", 0)
	house_tier = data.get("house_tier", 0)
	purchased_upgrades.assign(data.get("purchased_upgrades", []))
	orb_mana_per_click = data.get("orb_mana_per_click", 1.0)
	orb_mana_per_second = data.get("orb_mana_per_second", 0.0)
	food_eaten_count = data.get("food_eaten_count", 0)
	orb_health_cost_per_click = data.get("orb_health_cost_per_click", 5.0)
	food_heal_bonus = data.get("food_heal_bonus", 0.0)
	health_regen_per_minute = data.get("health_regen_per_minute", 0.0)
	better_chair_level = data.get("better_chair_level", 0)
	better_table_level = data.get("better_table_level", 0)
	better_bed_level = data.get("better_bed_level", 0)
	is_blacked_out = false
