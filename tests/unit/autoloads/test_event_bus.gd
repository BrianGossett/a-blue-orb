extends GutTest

# EventBus is a pure signal-declaration hub (8 signals, no logic). There is
# nothing here to unit-test in isolation:
#
# - "No gameplay logic lives here" is a static/code-review invariant (you can
#   only verify it by reading event_bus.gd and confirming it contains nothing
#   but `signal` declarations) — not an observable runtime behavior, so there
#   is no GUT assertion for it.
#
# - "Every signal listed is actually emitted somewhere" is a repo-wide
#   cross-file property, not a single function's behavior, so it isn't a GUT
#   test either. It was instead checked directly via:
#
#     for sig in mana_changed health_changed familiar_gained upgrade_purchased \
#                health_depleted blackout_ended house_tier_changed confidence_tier_changed; do
#       echo "=== $sig ==="
#       grep -rn "EventBus\.$sig\.emit" --include="*.gd" .
#     done
#
#   Results: 7 of the 8 signals have at least one emitter (mana_changed,
#   health_changed, familiar_gained x2 sites, upgrade_purchased, health_depleted,
#   and confidence_tier_changed all emit from autoloads/game_state.gd;
#   blackout_ended emits from scenes/ui/blackout_overlay.gd).
#
#   house_tier_changed has ZERO emitters anywhere in the codebase, despite
#   being actively *connected to* in two places (scenes/ui/area_tab.gd and
#   scenes/ui/button_action.gd) and GameState carrying a `house_tier` field
#   that's read (data/button_data.gd, area_tab.gd) but never written by any
#   code path that also fires this signal. This looks like exactly the kind
#   of drift Ticket 3's own acceptance criteria warned against ("don't leave
#   a signal declared but never fired") — flagged here, not fixed, per this
#   task's backfill-testing-only scope.

func test_placeholder_see_comment_above_for_signal_emission_check() -> void:
	# Intentionally trivial: keeps this file a valid, discoverable GUT test
	# file while the substantive checks for this ticket are the static
	# code-review note and the repo-wide grep documented above.
	assert_true(true, "See file header for the EventBus emission-coverage findings.")
