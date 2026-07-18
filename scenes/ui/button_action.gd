extends Button

signal one_shot_purchased(data: ButtonData)

var data: ButtonData
var _purchase_count: int = 0
var _is_on_cooldown: bool = false
var _is_processing_click: bool = false
var _is_blacked_out: bool = false


func set_data(new_data: ButtonData) -> void:
	data = new_data
	_purchase_count = 0
	_is_on_cooldown = false
	_refresh()


func set_purchase_count(value: int) -> void:
	_purchase_count = value
	_refresh()


func _ready() -> void:
	pressed.connect(_on_pressed)
	_connect_tier_source()
	EventBus.health_depleted.connect(_on_health_depleted)
	EventBus.blackout_ended.connect(_on_blackout_ended)
	if data:
		_refresh()


func _connect_tier_source() -> void:
	if data == null or data.tier_source == "":
		return
	match data.tier_source:
		"confidence_tier":
			EventBus.confidence_tier_changed.connect(_on_tier_source_changed)
			set_purchase_count(GameState.confidence_tier)
		"house_tier":
			EventBus.house_tier_changed.connect(_on_tier_source_changed)
			set_purchase_count(GameState.house_tier)


func _on_tier_source_changed(new_tier: int) -> void:
	set_purchase_count(new_tier)


func _on_health_depleted() -> void:
	_is_blacked_out = true
	_refresh()


func _on_blackout_ended() -> void:
	_is_blacked_out = false
	_refresh()


func _cost_count() -> int:
	match data.cost_count_source:
		"familiars":
			return GameState.familiars
		_:
			return _purchase_count


func _refresh() -> void:
	if data == null:
		return
	text = _build_label_text()
	disabled = _is_disabled()


func _build_label_text() -> String:
	var label_index: int = min(_purchase_count, data.labels.size() - 1)
	var label := data.labels[label_index]
	if data.cost_type == "none":
		return label
	var cost := ButtonData.calculate_cost(data.base_cost, data.cost_scaling, data.cost_step, _cost_count())
	return "%s (%s %s)" % [label, _format_cost(cost), data.cost_type]


func _format_cost(cost: float) -> String:
	if cost == floor(cost):
		return str(int(cost))
	return str(cost)


func _is_disabled() -> bool:
	if _is_blacked_out:
		return true
	if _is_on_cooldown:
		return true
	if not ButtonData.is_unlock_condition_met(data.unlock_condition):
		return true
	if data.cost_type != "none" and not _can_afford():
		return true
	return false


func _can_afford() -> bool:
	var cost := ButtonData.calculate_cost(data.base_cost, data.cost_scaling, data.cost_step, _cost_count())
	match data.cost_type:
		"mana":
			return GameState.mana >= cost
		"familiars":
			return float(GameState.familiars) >= cost
		_:
			return true


func _on_pressed() -> void:
	if _is_processing_click:
		return
	_is_processing_click = true
	_handle_click()
	_is_processing_click = false


func _handle_click() -> void:
	if not InputGuard.try_register_click():
		return
	if _is_blacked_out:
		return
	if _is_on_cooldown:
		return
	var cost := 0.0
	if data.cost_type != "none":
		cost = ButtonData.calculate_cost(data.base_cost, data.cost_scaling, data.cost_step, _cost_count())
		if not _deduct_cost(cost):
			return
	EffectHandler.run_effect(data.effect_id)
	if data.tier_source == "":
		_purchase_count += 1
	_start_cooldown()
	if data.one_shot:
		one_shot_purchased.emit(data)
		hide()
		return
	_refresh()


func _deduct_cost(cost: float) -> bool:
	match data.cost_type:
		"mana":
			return GameState.spend_mana(cost)
		"familiars":
			return GameState.spend_familiars(int(cost))
		_:
			return true


func _start_cooldown() -> void:
	if data.cooldown_sec <= 0.0:
		return
	_is_on_cooldown = true
	disabled = true
	get_tree().create_timer(data.cooldown_sec).timeout.connect(_on_cooldown_finished)


func _on_cooldown_finished() -> void:
	_is_on_cooldown = false
	_refresh()
