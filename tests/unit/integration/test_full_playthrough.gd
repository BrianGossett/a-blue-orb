extends GutTest

# Ticket 12 "Polish/Cross-Check Pass" checklist item: a real, executed
# full-playthrough of the House tab through the actual UI-reachable path.
#
# This instantiates the real area_tab.tscn with the real house.tres AreaData
# and drives it exactly the way a player would: finding the real
# button_action instances the scene builds from the real .tres files in
# data/buttons/house/, and calling their _handle_click() (never
# EffectHandler.run_effect() directly). If a button is unreachable or a
# purchase sequence hits a genuine dead end, this test would fail to
# progress -- that's the point.
#
# Two "fast-forward" mechanics are used throughout, both surfacing real
# production code paths rather than papering over them:
#  - Per-button cooldowns (touch_orb: 1s, eat_bread: 5s) are skipped by
#    calling _process(cooldown_sec) directly on the button instance right
#    after a click, exactly as tests/unit/ui/test_button_action.gd already
#    does elsewhere in this suite.
#  - InputGuard (autoloads/input_guard.gd) rate-limits to 100 clicks per
#    rolling real-world second, measured via Time.get_ticks_msec(). A tight
#    GDScript loop with no real time elapsing between clicks would trip this
#    limiter (silently no-op the click, since try_register_click() returning
#    false makes _handle_click() a no-op with no error) and this test would
#    spin forever waiting for state that can never change. Clearing
#    InputGuard's internal timestamp array before every click simulates real
#    time having passed between clicks, the same way _process(delta) already
#    simulates real time passing for a button's own cooldown.
#
# The purchase sequence itself is driven generically off the live
# button.disabled state and each button's own ButtonData (cost_type,
# unlock_condition), not off hand-traced literal mana/familiar numbers: a
# button costing familiars recursively grinds mana to summon familiars,
# which recursively grinds mana via Touch the Orb, healing via Eat Bread
# between clicks to avoid ever blacking out. This mirrors the brief's
# instruction to work out the exact numbers by running the test rather than
# by hand-tracing them.

const AREA_TAB_SCENE := preload("res://scenes/ui/area_tab.tscn")
const HOUSE_AREA_DATA := preload("res://data/areas/house.tres")

# Generous per-loop safety cap so a genuine dead end (a button that can never
# become affordable/unlocked) fails the test loudly instead of hanging the
# whole GUT run forever.
const MAX_GRIND_ITERATIONS := 20000

var _tab: Control
var _touch_orb: Button
var _summon_familiar: Button
var _eat_bread: Button
var _chair: Button
var _table: Button
var _bed: Button
var _confidence: Button
var _better_chair: Button
var _better_table: Button
var _better_bed: Button
var _better_meal: Button


func before_each() -> void:
	GameState.from_dict({})
	InputGuard._click_timestamps_msec.clear()
	_tab = add_child_autofree(AREA_TAB_SCENE.instantiate())
	_tab.set_area_data(HOUSE_AREA_DATA)

	_touch_orb = _find_button("touch_orb")
	_summon_familiar = _find_button("summon_familiar")
	_eat_bread = _find_button("eat_bread")
	_chair = _find_button("chair")
	_table = _find_button("table")
	_bed = _find_button("bed")
	_confidence = _find_button("confidence")
	_better_chair = _find_button("better_chair")
	_better_table = _find_button("better_table")
	_better_bed = _find_button("better_bed")
	_better_meal = _find_button("better_meal")

	assert_not_null(_touch_orb, "touch_orb button should be found in the real area_tab instance")
	assert_not_null(_summon_familiar, "summon_familiar button should be found in the real area_tab instance")
	assert_not_null(_eat_bread, "eat_bread button should be found in the real area_tab instance")
	assert_not_null(_chair, "chair button should be found in the real area_tab instance")
	assert_not_null(_table, "table button should be found in the real area_tab instance")
	assert_not_null(_bed, "bed button should be found in the real area_tab instance")
	assert_not_null(_confidence, "confidence button should be found in the real area_tab instance")
	assert_not_null(_better_chair, "better_chair button should be found in the real area_tab instance")
	assert_not_null(_better_table, "better_table button should be found in the real area_tab instance")
	assert_not_null(_better_bed, "better_bed button should be found in the real area_tab instance")
	assert_not_null(_better_meal, "better_meal button should be found in the real area_tab instance")


func _find_button(id: String) -> Button:
	for button in _tab._dynamic_buttons:
		if button.data.id == id:
			return button
	return null


# Clicks a real button instance, bypassing the two purely time-based gates
# (InputGuard's real-msec rate limiter, and this button's own cooldown) the
# same way a player spacing clicks out over real time would naturally clear
# them -- never bypassing cost/unlock gating, which stays fully live.
func _click(button: Button) -> void:
	InputGuard._click_timestamps_msec.clear()
	button._handle_click()
	if button._is_on_cooldown:
		button._process(button.data.cooldown_sec)


func _top_up_health() -> void:
	if _eat_bread == null:
		return
	var iterations := 0
	while GameState.health < GameState.max_health and not _eat_bread.disabled:
		iterations += 1
		if iterations > MAX_GRIND_ITERATIONS:
			fail_test("Eat Bread never topped up health to max -- possible genuine dead end")
			return
		_click(_eat_bread)


# Generic "make this button affordable and unlocked" grinder, driven purely
# off the button's own live .disabled state and its ButtonData -- not off
# any hand-traced literal cost numbers. A familiars-cost button recursively
# grinds mana to summon familiars; a mana-cost button (including
# summon_familiar itself) grinds mana via Touch the Orb, topping up health
# with Eat Bread between clicks so the playthrough never blacks out.
func _grind_to_afford(button: Button) -> void:
	var iterations := 0
	while button.disabled:
		iterations += 1
		if iterations > MAX_GRIND_ITERATIONS:
			fail_test("Button \"%s\" never became affordable/enabled -- genuine dead end, not a sequencing issue" % button.data.id)
			return
		if not ButtonData.is_unlock_condition_met(button.data.unlock_condition):
			fail_test("Button \"%s\" is not unlocked yet (unlock_condition \"%s\") -- test sequencing issue, prerequisite step must run first" % [button.data.id, button.data.unlock_condition])
			return
		if button._is_blacked_out:
			fail_test("Button \"%s\" is disabled by blackout with no recovery mechanism instantiated in this scene -- genuine dead end" % button.data.id)
			return
		if button._is_on_cooldown:
			fail_test("Button \"%s\" is stuck on cooldown -- should have been cleared by _click()" % button.data.id)
			return
		match button.data.cost_type:
			"mana":
				_top_up_health()
				assert_false(_touch_orb.disabled, "Touch the Orb should never itself be blocked by cost (cost_type 'none')")
				_click(_touch_orb)
			"familiars":
				_grind_to_afford(_summon_familiar)
				_click(_summon_familiar)
			_:
				fail_test("Button \"%s\" (cost_type \"%s\") is disabled for an unhandled reason" % [button.data.id, button.data.cost_type])
				return


func _grind_familiars_to(target: int) -> void:
	var iterations := 0
	while GameState.familiars < target:
		iterations += 1
		if iterations > MAX_GRIND_ITERATIONS:
			fail_test("Could not grind familiars up to %d -- genuine dead end" % target)
			return
		_grind_to_afford(_summon_familiar)
		_click(_summon_familiar)


func test_full_house_playthrough_via_real_ui_buttons() -> void:
	# --- Step 1: Touch the Orb once (baseline action always works) ---
	assert_false(_touch_orb.disabled, "Touch the Orb should be enabled from an empty save")
	var health_before := GameState.health
	_click(_touch_orb)
	assert_eq(GameState.mana, 1.0, "first Touch the Orb click should grant orb_mana_per_click (1.0) mana")
	assert_lt(GameState.health, health_before, "Touch the Orb should have a health cost")

	# --- Step 2: Summon Familiar enough times to reach >= 5 familiars ---
	_grind_familiars_to(5)
	assert_gte(GameState.familiars, 5, "should have summoned at least 5 familiars")
	assert_gt(GameState.health, 0.0, "should not have blacked out while grinding familiars")

	# --- Step 3: Eat Bread (fast-forwarding its 5s cooldown) until food_eaten_count >= 5 ---
	while GameState.food_eaten_count < 5:
		assert_false(_eat_bread.disabled, "Eat Bread should be affordable/unlocked with familiars >= 1")
		_click(_eat_bread)
	assert_gte(GameState.food_eaten_count, 5, "should have eaten bread at least 5 times")

	# --- Step 4: Buy Chair (food_eaten_count >= 2, costs 1 familiar, one-shot) ---
	_grind_to_afford(_chair)
	assert_false(_chair.disabled, "Chair should be affordable and unlocked by now")
	_click(_chair)
	assert_true(GameState.has_upgrade("chair"), "Chair purchase should mark the upgrade purchased")
	assert_false(_chair.visible, "one-shot Chair button should disappear after purchase")

	# --- Step 5: Buy Table (food_eaten_count >= 5 && familiars >= 3, costs 2 familiars) ---
	_grind_familiars_to(3)
	_grind_to_afford(_table)
	assert_false(_table.disabled, "Table should be affordable and unlocked by now")
	_click(_table)
	assert_true(GameState.has_upgrade("table"), "Table purchase should mark the upgrade purchased")
	assert_false(_table.visible, "one-shot Table button should disappear after purchase")

	# --- Step 6: Buy Bed (familiars >= 5, costs 4 familiars) ---
	_grind_familiars_to(5)
	_grind_to_afford(_bed)
	assert_false(_bed.disabled, "Bed should be affordable and unlocked by now")
	_click(_bed)
	assert_true(GameState.has_upgrade("bed"), "Bed purchase should mark the upgrade purchased")
	assert_false(_bed.visible, "one-shot Bed button should disappear after purchase")

	# --- Step 7: Buy Confidence through all 4 levels (10/20/50/100 mana) ---
	for level in range(4):
		_grind_to_afford(_confidence)
		var tier_before := GameState.confidence_tier
		_click(_confidence)
		assert_eq(GameState.confidence_tier, tier_before + 1, "confidence_tier should advance by exactly 1 per purchase")
	assert_eq(GameState.confidence_tier, 4, "confidence_tier should be maxed at 4")
	assert_false(_confidence.visible, "Confidence button should disappear once max_purchases (4) is reached")

	# --- Step 8: Buy Better Chair, Better Table, Better Bed through all 4 levels each ---
	var better_furniture_buttons: Array[Button] = [_better_chair, _better_table, _better_bed]
	for button in better_furniture_buttons:
		for level in range(4):
			_grind_to_afford(button)
			_click(button)
		assert_false(button.visible, "Better-furniture button \"%s\" should disappear once max_purchases (4) is reached" % button.data.id)
	assert_eq(GameState.better_chair_level, 4, "better_chair_level should be maxed at 4")
	assert_eq(GameState.better_table_level, 4, "better_table_level should be maxed at 4")
	assert_eq(GameState.better_bed_level, 4, "better_bed_level should be maxed at 4")

	# --- Step 9: Buy Better Meal through all 4 levels (mana, gated on already having Table) ---
	for level in range(4):
		_grind_to_afford(_better_meal)
		_click(_better_meal)
	assert_eq(GameState.better_meal_level, 4, "better_meal_level should be maxed at 4")
	assert_false(_better_meal.visible, "Better Meal button should disappear once max_purchases (4) is reached")

	# --- End-state assertions: the whole House tab has been fully cleared out ---
	assert_eq(GameState.confidence_tier, 4, "confidence_tier should end at 4")
	assert_eq(GameState.better_chair_level, 4, "better_chair_level should end at 4")
	assert_eq(GameState.better_table_level, 4, "better_table_level should end at 4")
	assert_eq(GameState.better_bed_level, 4, "better_bed_level should end at 4")
	assert_eq(GameState.better_meal_level, 4, "better_meal_level should end at 4")
	assert_true(GameState.has_upgrade("chair"), "chair upgrade should be present at end state")
	assert_true(GameState.has_upgrade("table"), "table upgrade should be present at end state")
	assert_true(GameState.has_upgrade("bed"), "bed upgrade should be present at end state")
	assert_true(GameState.health > 0.0, "the playthrough should not have blacked out and gotten stuck")
