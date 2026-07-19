extends GutTest

# InputGuard has no external dependencies (it only reads Time.get_ticks_msec()
# and its own internal timestamp array), so each test instantiates a fresh,
# non-singleton instance rather than touching the live InputGuard autoload.
# This also keeps this test from polluting the real singleton's rate-limit
# window for any other test in the suite that clicks through the real
# button_action.tscn -> InputGuard autoload path.


func test_rate_limits_to_100_clicks_per_rolling_second() -> void:
	var guard = autofree(load("res://autoloads/input_guard.gd").new())

	# Ticket 7's acceptance criterion: fire try_register_click() 200 times in
	# a tight loop with no real time passing between calls (they all land in
	# the same Time.get_ticks_msec() millisecond or close to it, which is the
	# point of exercising the 1-second rolling window). No more than 100 of
	# the 200 calls should return true.
	var true_count := 0
	for i in range(200):
		if guard.try_register_click():
			true_count += 1

	# All 200 calls happen well within one second, so the first 100 succeed
	# and the 101st onward all see _click_timestamps_msec.size() >= 100 and
	# return false -- exactly 100, not merely "at most" 100.
	assert_eq(true_count, 100, "no more than 100 clicks should register within the rolling 1-second window")

# Note: InputGuard's rate limiter and button_action.gd's own per-button
# _is_on_cooldown are independent mechanisms -- neither reads the other's
# state. The per-button cooldown is already covered by
# tests/unit/ui/test_button_action.gd
# (test_cooldown_blocks_further_clicks_after_purchase), and this test covers
# the rate limiter in isolation; no combined test is needed.
