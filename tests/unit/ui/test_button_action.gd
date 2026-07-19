extends GutTest

# button_action.gd extends Button and reads the live GameState/EventBus/
# InputGuard singletons directly by autoload name, so each test instantiates
# the real button_action.tscn into the scene tree (add_child_autofree) and
# before_each resets GameState to a known baseline. ButtonData fixtures are
# built inline with explicit field assignment (not loaded from .tres) so
# each test's exact cost/cooldown/effect values are self-evident.


func before_each() -> void:
	GameState.from_dict({})


func test_one_shot_purchase_does_not_double_fire() -> void:
	var button = add_child_autofree(load("res://scenes/ui/button_action.tscn").instantiate())
	var data := ButtonData.new()
	data.cost_type = "mana"
	data.base_cost = 0.0
	data.cost_scaling = "fixed"
	data.effect_id = "summon_familiar"
	data.one_shot = true
	data.labels = ["Test"]
	button.set_data(data)

	# Calling the private _handle_click() directly (rather than
	# .pressed.emit()) bypasses the _is_processing_click re-entrancy guard on
	# purpose, to isolate whatever protection the button's own hidden/
	# one-shot state provides against a second effect firing.
	#
	# FORMERLY FAILING, NOW FIXED: this test originally caught a real gap —
	# Ticket 6's acceptance criterion is "A one_shot button ... disappears
	# after purchase and its cost is deducted exactly once — no double-fire
	# on rapid clicks" (docs/tickets.md), but _handle_click() had no internal
	# check of `visible`/`_purchase_count`/an "already purchased" flag;
	# hide() only set the Control's visible property, and the only thing
	# actually stopping a real double-click in production was Godot's own
	# input system refusing to deliver further "pressed" signals to a
	# hidden Button — not anything button_action.gd itself enforced. A
	# second direct call to _handle_click() (bypassing that engine-level
	# gate, exactly as this test does) used to re-run the full purchase path
	# and fire the effect again. Fixed by adding `if not visible: return` at
	# the top of _handle_click() so the guarantee is enforced by the script,
	# not by an external actor's dispatch behavior. See task-5-report.md for
	# the original finding.
	button._handle_click()
	button._handle_click()

	assert_eq(GameState.familiars, 1, "second _handle_click() must not re-fire the effect")
	assert_false(button.visible, "one_shot purchase should hide the button")


func test_afford_gating_mana_cost() -> void:
	var button = add_child_autofree(load("res://scenes/ui/button_action.tscn").instantiate())
	var data := ButtonData.new()
	data.cost_type = "mana"
	data.base_cost = 5.0
	data.cost_scaling = "fixed"
	data.effect_id = "touch_orb"
	data.labels = ["Test"]
	button.set_data(data)

	assert_true(button._is_disabled(), "can't afford 5 mana with 0 mana")

	GameState.add_mana(5.0)
	assert_false(button._is_disabled(), "can afford once mana >= cost")


func test_afford_gating_familiars_cost_respects_reservation_model() -> void:
	var button = add_child_autofree(load("res://scenes/ui/button_action.tscn").instantiate())
	var data := ButtonData.new()
	data.cost_type = "familiars"
	data.base_cost = 2.0
	data.cost_scaling = "fixed"
	data.effect_id = "summon_familiar"
	data.labels = ["Test"]
	button.set_data(data)

	# Ticket 9c fix: _can_afford() checks idle_familiars(), not raw
	# familiars, so fully-reserved familiars must not count as affordable.
	GameState.add_familiars(2)
	GameState.familiars_assigned_to_orb = 2

	assert_true(button._is_disabled(), "all 2 familiars are reserved to the orb, 0 idle")


func test_cooldown_blocks_further_clicks_after_purchase() -> void:
	var button = add_child_autofree(load("res://scenes/ui/button_action.tscn").instantiate())
	var data := ButtonData.new()
	data.cost_type = "mana"
	data.base_cost = 1.0
	data.cost_scaling = "fixed"
	data.cooldown_sec = 5.0
	data.effect_id = "touch_orb"
	data.labels = ["Test"]
	button.set_data(data)

	GameState.add_mana(1.0)
	button._handle_click()

	assert_true(button._is_on_cooldown, "cooldown should start after a successful purchase")
	assert_true(button._is_disabled(), "button should be disabled while on cooldown")


func test_refund_on_effect_failure() -> void:
	var button = add_child_autofree(load("res://scenes/ui/button_action.tscn").instantiate())
	var data := ButtonData.new()
	data.cost_type = "mana"
	data.base_cost = 1.0
	data.cost_scaling = "fixed"
	data.cooldown_sec = 5.0
	data.effect_id = "better_chair"
	data.labels = ["Test"]
	button.set_data(data)

	# _effect_better_chair() returns false once better_chair_level is already
	# at its max (4), guaranteeing effect failure so the refund-on-failure
	# path (Ticket 11) is exercised.
	GameState.better_chair_level = 4
	GameState.add_mana(1.0)

	button._handle_click()

	assert_eq(GameState.mana, 1.0, "cost must be refunded when the effect fails")
	assert_eq(button._purchase_count, 0, "purchase count must not advance on a failed effect")
	assert_false(button._is_on_cooldown, "cooldown must not start on a failed effect")
	assert_push_error("better_chair_level already at max")


func test_unlock_condition_reevaluates_on_unrelated_state_change() -> void:
	var button: Button = add_child_autofree(load("res://scenes/ui/button_action.tscn").instantiate())
	var data := ButtonData.new()
	data.id = "test_chair_like"
	data.labels = ["Test"]
	data.cost_type = "none"
	data.unlock_condition = "food_eaten_count >= 2"
	data.effect_id = "summon_familiar"
	button.set_data(data)

	assert_true(button.disabled, "Should start disabled — food_eaten_count is 0.")

	# Mutate the stat directly — NOT through this button, NOT through Eat Bread's
	# own button — simulating a different action satisfying this button's condition.
	GameState.food_eaten_count = 2
	EventBus.state_changed.emit()

	assert_false(button.disabled, "Should re-evaluate and enable once food_eaten_count >= 2, without any other trigger.")


func test_max_purchases_hides_the_button() -> void:
	var button = add_child_autofree(load("res://scenes/ui/button_action.tscn").instantiate())
	var data := ButtonData.new()
	data.cost_type = "none"
	data.max_purchases = 1
	data.effect_id = "summon_familiar"
	data.one_shot = false
	data.labels = ["Test"]
	button.set_data(data)

	button._handle_click()

	assert_false(button.visible, "reaching max_purchases should hide the button, same as one_shot")


func test_confidence_tres_full_purchase_sequence() -> void:
	var button: Button = add_child_autofree(load("res://scenes/ui/button_action.tscn").instantiate())
	var data: ButtonData = load("res://data/buttons/house/confidence.tres")
	button.set_data(data)

	var expected_costs: Array[float] = [10.0, 20.0, 50.0, 100.0]
	for i in range(4):
		GameState.add_mana(expected_costs[i])
		var mana_before: float = GameState.mana
		button._handle_click()
		assert_eq(mana_before - GameState.mana, expected_costs[i], "level %d should cost %s mana" % [i, expected_costs[i]])

	assert_eq(GameState.confidence_tier, 4, "4 purchases should max out confidence_tier")
	assert_false(button.visible, "button should hide once max_purchases (4) is reached")


func test_confidence_tres_seeds_purchase_count_on_reload() -> void:
	GameState.confidence_tier = 2
	var button: Button = add_child_autofree(load("res://scenes/ui/button_action.tscn").instantiate())
	var data: ButtonData = load("res://data/buttons/house/confidence.tres")
	button.set_data(data)

	# Regression check for the _seed_purchase_count() gap fixed in this same
	# task: before the fix, "confidence_tier" wasn't a recognized
	# count_seed_source, so a reloaded save's confidence_tier=2 would be
	# silently ignored and this button would re-seed at 0 (tier-0 cost,
	# 10 mana) instead of correctly resuming at tier 2 (50 mana).
	GameState.add_mana(50.0)
	var mana_before: float = GameState.mana
	button._handle_click()
	assert_eq(mana_before - GameState.mana, 50.0, "should resume at tier-2 cost (50 mana), not reset to tier-0 cost (10 mana)")
	assert_eq(GameState.confidence_tier, 3)


func test_cooldown_bar_hidden_until_a_cooldown_actually_starts() -> void:
	var button: Button = add_child_autofree(load("res://scenes/ui/button_action.tscn").instantiate())
	var data := ButtonData.new()
	data.cost_type = "none"
	data.cooldown_sec = 5.0
	data.effect_id = "summon_familiar"
	data.labels = ["Test"]
	button.set_data(data)

	assert_false(button._cooldown_bar.visible, "no cooldown has started yet")


func test_cooldown_bar_fills_as_the_cooldown_counts_down() -> void:
	var button: Button = add_child_autofree(load("res://scenes/ui/button_action.tscn").instantiate())
	var data := ButtonData.new()
	data.cost_type = "none"
	data.cooldown_sec = 10.0
	data.effect_id = "summon_familiar"
	data.labels = ["Test"]
	button.set_data(data)

	button._handle_click()
	assert_true(button._cooldown_bar.visible, "cooldown just started")
	assert_eq(button._cooldown_bar.value, 0.0, "freshly started cooldown should read empty")

	button._process(5.0)  # half of cooldown_sec
	assert_eq(button._cooldown_bar.value, 0.5, "halfway through a 10s cooldown after 5s")

	button._process(5.0)  # the remaining half
	assert_false(button._is_on_cooldown, "cooldown should be over")
	assert_false(button._cooldown_bar.visible, "bar should hide once the cooldown ends")


func test_cooldown_bar_never_shows_for_buttons_with_no_cooldown() -> void:
	var button: Button = add_child_autofree(load("res://scenes/ui/button_action.tscn").instantiate())
	var data := ButtonData.new()
	data.cost_type = "none"
	data.cooldown_sec = 0.0
	data.effect_id = "summon_familiar"
	data.labels = ["Test"]
	button.set_data(data)

	button._handle_click()
	assert_false(button._cooldown_bar.visible, "no cooldown_sec means no cooldown, so no bar ever")
