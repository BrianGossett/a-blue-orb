extends Button

signal one_shot_purchased(data: ButtonData)

var data: ButtonData
var _purchase_count: int = 0
var _is_on_cooldown: bool = false
var _is_processing_click: bool = false
var _is_blacked_out: bool = false
var _cooldown_remaining: float = 0.0


func set_data(new_data: ButtonData) -> void:
	data = new_data
	_purchase_count = _seed_purchase_count()
	_is_on_cooldown = false
	if data.max_purchases > 0 and _purchase_count >= data.max_purchases:
		hide()
		return
	_refresh()


func _seed_purchase_count() -> int:
	match data.count_seed_source:
		"better_chair_level":
			return GameState.better_chair_level
		"better_table_level":
			return GameState.better_table_level
		"better_bed_level":
			return GameState.better_bed_level
		_:
			return 0


func set_purchase_count(value: int) -> void:
	_purchase_count = value
	_refresh()


func _ready() -> void:
	pressed.connect(_on_pressed)
	_connect_tier_source()
	EventBus.health_depleted.connect(_on_health_depleted)
	EventBus.blackout_ended.connect(_on_blackout_ended)
	EventBus.state_changed.connect(_on_state_changed)
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


func _on_state_changed() -> void:
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
			return float(GameState.idle_familiars()) >= cost
		_:
			return true


func _on_pressed() -> void:
	if _is_processing_click:
		return
	_is_processing_click = true
	_handle_click()
	_is_processing_click = false


func _handle_click() -> void:
	if not visible:
		return
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
	if not EffectHandler.run_effect(data.effect_id):
		_refund_cost(cost)
		return
	if data.tier_source == "":
		_purchase_count += 1
	_start_cooldown()
	if data.one_shot:
		one_shot_purchased.emit(data)
		hide()
		return
	if data.max_purchases > 0 and _purchase_count >= data.max_purchases:
		hide()
		return
	_refresh()


func _refund_cost(cost: float) -> void:
	if data.cost_type == "none" or cost <= 0.0:
		return
	match data.cost_type:
		"mana":
			GameState.add_mana(cost)
		"familiars":
			GameState.add_familiars(int(cost))


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
	_cooldown_remaining = data.cooldown_sec
	disabled = true


func _process(delta: float) -> void:
	if not _is_on_cooldown:
		return
	if data.cooldown_gate_condition != "" and not ButtonData.is_unlock_condition_met(data.cooldown_gate_condition):
		return
	_cooldown_remaining -= delta
	if _cooldown_remaining <= 0.0:
		_is_on_cooldown = false
		_refresh()
