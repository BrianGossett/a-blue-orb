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
var orb_mana_per_click: float = 0.0
var orb_mana_per_second: float = 0.0
var is_blacked_out: bool = false


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
	orb_mana_per_click = data.get("orb_mana_per_click", 0.0)
	orb_mana_per_second = data.get("orb_mana_per_second", 0.0)
	is_blacked_out = data.get("is_blacked_out", false)
