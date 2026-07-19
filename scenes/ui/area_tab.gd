extends Control

@export var area_data: AreaData

const BUTTON_ACTION_SCENE := preload("res://scenes/ui/button_action.tscn")

@onready var _column_actions: VBoxContainer = $Root/Content/ColumnActions
@onready var _column_upgrades: VBoxContainer = $Root/Content/ColumnUpgrades
@onready var _description_label: RichTextLabel = $Root/Content/RoomInfo/Description

var _furniture_fragments: Array[String] = []


func _ready() -> void:
	EventBus.house_tier_changed.connect(_on_house_tier_changed)
	if area_data:
		_apply_area_data()


func set_area_data(new_data: AreaData) -> void:
	area_data = new_data
	if is_inside_tree():
		_apply_area_data()


func _apply_area_data() -> void:
	_furniture_fragments.clear()
	_description_label.text = area_data.base_description
	_update_tab_title()
	_load_buttons()


func _update_tab_title() -> void:
	var tab_container := get_parent() as TabContainer
	if tab_container == null:
		return
	var tier := clampi(GameState.house_tier, 0, area_data.name_progression.size() - 1)
	tab_container.set_tab_title(get_index(), area_data.name_progression[tier])


func _on_house_tier_changed(_new_tier: int) -> void:
	_update_tab_title()


func _load_buttons() -> void:
	var dir_path := "res://data/buttons/%s/" % area_data.id
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	var button_datas: Array[ButtonData] = []
	for file_name in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		button_datas.append(load(dir_path + file_name))
	button_datas.sort_custom(func(a: ButtonData, b: ButtonData) -> bool: return a.sort_order < b.sort_order)
	for button_data in button_datas:
		if button_data.one_shot and GameState.has_upgrade(button_data.id):
			if button_data.room_description_fragment != "":
				_furniture_fragments.append(button_data.room_description_fragment)
			continue
		var instance: Button = BUTTON_ACTION_SCENE.instantiate()
		instance.set_data(button_data)
		instance.one_shot_purchased.connect(_on_one_shot_purchased)
		if button_data.button_column == 1:
			_column_actions.add_child(instance)
		else:
			_column_upgrades.add_child(instance)
	_rebuild_description()


func _on_one_shot_purchased(purchased_data: ButtonData) -> void:
	if purchased_data.room_description_fragment == "":
		return
	_furniture_fragments.append(purchased_data.room_description_fragment)
	_rebuild_description()


func _rebuild_description() -> void:
	if _furniture_fragments.is_empty():
		_description_label.text = area_data.base_description
		return
	_description_label.text = "%s The room has %s." % [area_data.base_description, _join_with_commas_and(_furniture_fragments)]


func _join_with_commas_and(items: Array[String]) -> String:
	if items.size() == 1:
		return items[0]
	if items.size() == 2:
		return "%s and %s" % [items[0], items[1]]
	var all_but_last := items.slice(0, items.size() - 1)
	return "%s, and %s" % [", ".join(all_but_last), items[items.size() - 1]]
