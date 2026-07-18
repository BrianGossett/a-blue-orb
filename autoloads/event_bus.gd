extends Node

signal mana_changed(new_value: float)
signal health_changed(new_value: float, max_value: float)
signal familiar_gained(new_total: int)
signal upgrade_purchased(upgrade_id: String)
signal health_depleted
signal blackout_ended
signal house_tier_changed(new_tier: int)
signal confidence_tier_changed(new_tier: int)
