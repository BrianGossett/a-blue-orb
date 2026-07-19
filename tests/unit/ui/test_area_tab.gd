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


func test_game_reset_reloads_buttons_without_duplicating_or_destroying_orb_channeling() -> void:
	var tab: Control = add_child_autofree(load("res://scenes/ui/area_tab.tscn").instantiate())
	var area_data: AreaData = load("res://data/areas/house.tres")
	tab.set_area_data(area_data)

	var orb_channeling_before: Node = tab._column_upgrades.get_node("OrbChanneling")
	assert_not_null(orb_channeling_before, "OrbChanneling should exist before any reset")

	# Buy Chair so it hides (one_shot) — confirms the reset actually
	# brings a purchased, hidden furniture button back.
	GameState.add_familiars(1)
	GameState.add_food_eaten()
	GameState.add_food_eaten()
	var chair_button: Button = _find_button_by_id(tab._column_actions, "chair")
	assert_not_null(chair_button, "Chair button should exist and be visible before purchase")
	chair_button._handle_click()
	assert_null(_find_button_by_id(tab._column_actions, "chair"), "Chair should be gone (hidden+freed on next reload) after purchase")

	var actions_count_before_reset: int = tab._column_actions.get_child_count()

	# EventBus.game_reset alone carries no state-reset behavior — in
	# production it's SaveManager.reset_game() that resets GameState
	# *before* emitting the signal. Mirror that ordering here (without
	# calling reset_game() itself, to keep this test focused on
	# area_tab.gd's reload behavior, not Task 1's already-covered logic)
	# so the chair's purchased-upgrade flag is actually cleared and it can
	# genuinely reappear.
	GameState.from_dict({})
	EventBus.game_reset.emit()
	await get_tree().process_frame  # let queue_free()'d nodes actually leave the tree

	var orb_channeling_after: Node = tab._column_upgrades.get_node_or_null("OrbChanneling")
	assert_eq(orb_channeling_after, orb_channeling_before, "the same OrbChanneling instance must survive a reload, not be destroyed and never recreated")

	assert_not_null(_find_button_by_id(tab._column_actions, "chair"), "Chair should reappear after reset, since it's no longer purchased")
	# The hidden-but-not-yet-freed Chair from before the reset already
	# counted toward actions_count_before_reset (hide() doesn't remove it
	# from the tree — only the reload's clearing loop does that). So a
	# clean, duplicate-free reload swaps it 1-for-1 with a fresh, visible
	# Chair: the total count stays the same, it doesn't grow by one.
	assert_eq(tab._column_actions.get_child_count(), actions_count_before_reset, "same button count after reload — the old hidden Chair is replaced 1-for-1, not duplicated")


func _find_button_by_id(container: Node, id: String) -> Button:
	# A one-shot button is hidden (visible = false) immediately on purchase
	# but only actually removed from the tree on the *next* _load_buttons()
	# call, so "gone" here must mean "not currently shown", not just
	# "not present as a node" — otherwise a freshly-hidden-but-not-yet-freed
	# purchased button would still be found.
	for child in container.get_children():
		if child is Button and child.visible and "data" in child and child.data != null and child.data.id == id:
			return child
	return null
