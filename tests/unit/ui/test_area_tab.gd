extends GutTest

# area_tab.gd reads/writes GameState (house_tier, has_upgrade) directly by
# autoload name, so before_each resets it to a known baseline.


func before_each() -> void:
	GameState.from_dict({})


func test_set_area_data_drives_title_and_description_from_the_bound_resource_not_hardcoded() -> void:
	# Deferred Ticket 8 criterion: nothing about "House" should be
	# hardcoded in area_tab.gd — swapping the bound AreaData resource must
	# change the tab title and description to match, proving it's entirely
	# resource-driven.
	var tab_container: TabContainer = add_child_autofree(TabContainer.new())
	var tab = load("res://scenes/ui/area_tab.tscn").instantiate()
	tab_container.add_child(tab)

	var data_a := AreaData.new()
	data_a.id = "test_area_alpha"
	data_a.name_progression = ["Alpha Room"]
	data_a.base_description = "This is the alpha test room."

	var data_b := AreaData.new()
	data_b.id = "test_area_beta"
	data_b.name_progression = ["Beta Chamber"]
	data_b.base_description = "This is the beta test chamber."

	tab.set_area_data(data_a)
	assert_eq(tab_container.get_tab_title(tab.get_index()), "Alpha Room")
	assert_eq(tab._description_label.text, "This is the alpha test room.")

	tab.set_area_data(data_b)
	assert_eq(tab_container.get_tab_title(tab.get_index()), "Beta Chamber")
	assert_eq(tab._description_label.text, "This is the beta test chamber.")


func test_buttons_are_loaded_in_ascending_sort_order_per_column() -> void:
	# Ticket 9's flagged gap from Ticket 8's review: _load_buttons() sorts
	# by ButtonData.sort_order before appending, independent of filesystem
	# enumeration order. Use the real shipped house AreaData/ButtonData
	# files (11 of them) to prove the comparator is wired in.
	var tab = add_child_autofree(load("res://scenes/ui/area_tab.tscn").instantiate())
	var house_data: AreaData = load("res://data/areas/house.tres")

	tab.set_area_data(house_data)

	_assert_children_ascending_by_sort_order(tab._column_actions.get_children())
	_assert_children_ascending_by_sort_order(tab._column_upgrades.get_children())


func _assert_children_ascending_by_sort_order(children: Array) -> void:
	# Filter to actual button_action instances (they carry a ButtonData in
	# `data`); ColumnUpgrades also has a pre-existing OrbChanneling scene
	# child that isn't part of the sorted set.
	var sort_orders: Array[int] = []
	for child in children:
		var button_data = child.get("data")
		if button_data == null:
			continue
		sort_orders.append(button_data.sort_order)

	assert_gt(sort_orders.size(), 0, "expected at least one button in this column")
	for i in range(1, sort_orders.size()):
		assert_lt(sort_orders[i - 1], sort_orders[i], "sort_order must be strictly ascending")


func test_room_description_rebuilds_as_one_shot_purchases_accumulate() -> void:
	var tab = add_child_autofree(load("res://scenes/ui/area_tab.tscn").instantiate())
	var data := AreaData.new()
	data.id = "test_area_no_buttons"
	data.name_progression = ["Test Room"]
	data.base_description = "This is a bare test room."

	tab.set_area_data(data)
	assert_eq(tab._description_label.text, "This is a bare test room.", "fresh area with no purchases shows the base description")

	var chair := ButtonData.new()
	chair.room_description_fragment = "a chair"
	tab._on_one_shot_purchased(chair)
	assert_eq(tab._description_label.text, "This is a bare test room. The room has a chair.")

	var table := ButtonData.new()
	table.room_description_fragment = "a table"
	tab._on_one_shot_purchased(table)
	assert_eq(tab._description_label.text, "This is a bare test room. The room has a chair and a table.", "two-item join uses \"and\", no comma")

	var bed := ButtonData.new()
	bed.room_description_fragment = "a bed"
	tab._on_one_shot_purchased(bed)
	assert_eq(tab._description_label.text, "This is a bare test room. The room has a chair, a table, and a bed.", "three-item join uses an Oxford comma")
