# Bug 13 — Button Unlock Reactivity Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix Bug 13 (GitHub issue #17) — buttons whose `unlock_condition` depends on a stat that changes via a *different* button's action never re-evaluate until something unrelated (a blackout) happens to trigger their own `_refresh()`.

**Architecture:** Add a generic, argument-less `EventBus.state_changed` signal. Every public `GameState` mutator emits it after mutating (in addition to whatever specific signal it already emits, if any). Every `button_action.gd` instance connects to it unconditionally in `_ready()` and calls `_refresh()` — the same generic re-evaluation `_refresh()` already does for `tier_source`/blackout cases, just triggered on any state change instead of a hand-picked few. This makes the fix fully generic per Bug 13's own acceptance criteria: a future stat referenced by a future `unlock_condition` works automatically as long as its owning `GameState` mutator also emits `state_changed` — `button_action.gd` itself never needs touching again.

**Tech Stack:** Godot 4.7 / GDScript, GUT (already vendored at `addons/gut/`).

## Global Constraints

- Direct-to-master: no branches, no PRs.
- GDScript: never `var x := min(...)` / `max(...)` — Variant-inference parse error in this engine build.
- `.tres` files: not touched by this plan.
- Standard test-run command (mandatory flags, not optional — see `docs/superpowers/plans/2026-07-19-ticket-workflow-bug-support.md` for why):
  ```
  <godot_bin> --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -ginclude_subdirs -gpre_run_script=res://tests/hooks/pre_run_save_guard.gd -gpost_run_script=res://tests/hooks/post_run_save_guard.gd -gexit
  ```
  Godot binary path: `$(cat .claude/godot-binary-path.txt)`.
- Deliberate simplicity-over-micro-optimization choice: some `GameState` mutators call other `GameState` mutators internally (e.g. `assign_familiar_to_orb()` calls `add_orb_mana_per_second()`). Every public mutator gets its own explicit `EventBus.state_changed.emit()` regardless of whether an internal call already transitively triggers one — this means a few methods emit the signal twice per call in practice. That's an accepted, intentional tradeoff: it keeps each method's correctness self-evident at its own call site rather than requiring a reader to trace which internal calls already cover it, and the cost of an extra `_refresh()` pass across ~20 buttons is negligible at this game's scale.
- This is a bug ticket — per `work-ticket`'s regression-test-first pattern, each task's test must be shown failing against the current (buggy) code before the fix, then passing after.

---

### Task 1: `EventBus.state_changed` + emit it from every `GameState` mutator

**Files:**
- Modify: `autoloads/event_bus.gd`
- Modify: `autoloads/game_state.gd`
- Modify: `tests/unit/autoloads/test_game_state.gd` (extend, don't create a new file — it already exists from the ticket-workflow plan's Task 3)

**Interfaces:**
- Produces: `EventBus.state_changed` (no args) — consumed by Task 2.

- [ ] **Step 1: Add the signal**

  In `autoloads/event_bus.gd`, add one line among the existing signal declarations (order doesn't matter functionally; append at the end for a minimal diff):

  ```gdscript
  signal state_changed
  ```

- [ ] **Step 2: Write the failing test first (regression-test-first, per this being a bug fix)**

  Add to `tests/unit/autoloads/test_game_state.gd` (a fresh, non-singleton `gs` instance is already the established pattern in this file — reuse it):

  ```gdscript
  func test_add_mana_emits_state_changed() -> void:
      watch_signals(EventBus)
      gs.add_mana(5.0)
      assert_signal_emitted(EventBus, "state_changed")


  func test_advance_confidence_tier_emits_state_changed() -> void:
      watch_signals(EventBus)
      gs.advance_confidence_tier()
      assert_signal_emitted(EventBus, "state_changed")


  func test_from_dict_emits_state_changed() -> void:
      watch_signals(EventBus)
      gs.from_dict({})
      assert_signal_emitted(EventBus, "state_changed")


  func test_spend_mana_insufficient_does_not_emit_state_changed() -> void:
      watch_signals(EventBus)
      var result: bool = gs.spend_mana(1000.0)
      assert_false(result)
      assert_signal_not_emitted(EventBus, "state_changed")
  ```

  Run the suite; confirm these 4 new tests fail (the signal doesn't exist yet / isn't emitted yet) while the rest of the pre-existing suite stays green.

- [ ] **Step 3: Add `EventBus.state_changed.emit()` to every public mutator in `autoloads/game_state.gd`**

  Replace the whole file with this content (every mutator gets a new `EventBus.state_changed.emit()` call; read-only methods — `has_upgrade`, `idle_familiars`, `to_dict` — are untouched; early-return-without-mutation paths in `spend_mana`/`spend_health`(blackout guard)/`spend_familiars`/`mark_upgrade_purchased`(already-has)/`assign_familiar_to_orb`/`unassign_familiar_from_orb` do NOT emit, since nothing actually changed):

  ```gdscript
  extends Node

  var mana: float = 0.0
  var health: float = 50.0
  var max_health: float = 50.0
  var familiars: int = 0
  var resources: Dictionary = {
  	"stone": 0,
  	"wood": 0,
  	"water": 0,
  	"crystals": 0,
  }
  var confidence_tier: int = 0
  var house_tier: int = 0
  var purchased_upgrades: Array[String] = []
  var orb_mana_per_click: float = 1.0
  var orb_mana_per_second: float = 0.0
  var is_blacked_out: bool = false
  var food_eaten_count: int = 0
  var orb_health_cost_per_click: float = 5.0
  var food_heal_bonus: float = 0.0
  var health_regen_per_minute: float = 0.0
  var better_chair_level: int = 0
  var better_table_level: int = 0
  var better_bed_level: int = 0
  var familiars_assigned_to_orb: int = 0
  var better_meal_level: int = 0


  func add_mana(amount: float) -> void:
  	mana += amount
  	EventBus.mana_changed.emit(mana)
  	EventBus.state_changed.emit()


  func spend_mana(amount: float) -> bool:
  	if mana < amount:
  		return false
  	mana -= amount
  	EventBus.mana_changed.emit(mana)
  	EventBus.state_changed.emit()
  	return true


  func add_health(amount: float) -> void:
  	health = min(health + amount, max_health)
  	EventBus.health_changed.emit(health, max_health)
  	EventBus.state_changed.emit()


  func spend_health(amount: float) -> void:
  	if is_blacked_out:
  		return
  	health = max(health - amount, 0.0)
  	EventBus.health_changed.emit(health, max_health)
  	EventBus.state_changed.emit()
  	if health <= 0.0:
  		EventBus.health_depleted.emit()


  func add_familiars(n: int) -> void:
  	familiars += n
  	EventBus.familiar_gained.emit(familiars)
  	EventBus.state_changed.emit()


  func spend_familiars(n: int) -> bool:
  	if idle_familiars() < n:
  		return false
  	familiars -= n
  	EventBus.familiar_gained.emit(familiars)
  	EventBus.state_changed.emit()
  	return true


  func has_upgrade(id: String) -> bool:
  	return purchased_upgrades.has(id)


  func mark_upgrade_purchased(id: String) -> void:
  	if purchased_upgrades.has(id):
  		return
  	purchased_upgrades.append(id)
  	EventBus.upgrade_purchased.emit(id)
  	EventBus.state_changed.emit()


  func add_orb_mana_per_click(amount: float) -> void:
  	orb_mana_per_click += amount
  	EventBus.state_changed.emit()


  func add_orb_mana_per_second(amount: float) -> void:
  	orb_mana_per_second += amount
  	EventBus.state_changed.emit()


  func advance_confidence_tier() -> void:
  	confidence_tier = min(confidence_tier + 1, 4)
  	EventBus.confidence_tier_changed.emit(confidence_tier)
  	EventBus.state_changed.emit()


  func enter_blackout() -> void:
  	is_blacked_out = true
  	EventBus.state_changed.emit()


  func exit_blackout() -> void:
  	is_blacked_out = false
  	EventBus.state_changed.emit()


  func add_food_eaten() -> void:
  	food_eaten_count += 1
  	EventBus.state_changed.emit()


  func add_orb_health_cost_per_click(amount: float) -> void:
  	orb_health_cost_per_click += amount
  	EventBus.state_changed.emit()


  func add_food_heal_bonus(amount: float) -> void:
  	food_heal_bonus += amount
  	EventBus.state_changed.emit()


  func add_health_regen_per_minute(amount: float) -> void:
  	health_regen_per_minute += amount
  	EventBus.state_changed.emit()


  func add_max_health(amount: float) -> void:
  	max_health += amount
  	EventBus.health_changed.emit(health, max_health)
  	EventBus.state_changed.emit()


  func advance_better_chair_level() -> void:
  	better_chair_level = min(better_chair_level + 1, 4)
  	EventBus.state_changed.emit()


  func advance_better_table_level() -> void:
  	better_table_level = min(better_table_level + 1, 4)
  	EventBus.state_changed.emit()


  func advance_better_bed_level() -> void:
  	better_bed_level = min(better_bed_level + 1, 4)
  	EventBus.state_changed.emit()


  func idle_familiars() -> int:
  	return familiars - familiars_assigned_to_orb


  func assign_familiar_to_orb() -> bool:
  	if idle_familiars() <= 0:
  		return false
  	familiars_assigned_to_orb += 1
  	add_orb_mana_per_second(1.0)
  	EventBus.state_changed.emit()
  	return true


  func unassign_familiar_from_orb() -> bool:
  	if familiars_assigned_to_orb <= 0:
  		return false
  	familiars_assigned_to_orb -= 1
  	add_orb_mana_per_second(-1.0)
  	EventBus.state_changed.emit()
  	return true


  func advance_better_meal_level() -> void:
  	better_meal_level = min(better_meal_level + 1, 4)
  	EventBus.state_changed.emit()


  func to_dict() -> Dictionary:
  	return {
  		"mana": mana,
  		"health": health,
  		"max_health": max_health,
  		"familiars": familiars,
  		"resources": resources.duplicate(),
  		"confidence_tier": confidence_tier,
  		"house_tier": house_tier,
  		"purchased_upgrades": purchased_upgrades.duplicate(),
  		"orb_mana_per_click": orb_mana_per_click,
  		"orb_mana_per_second": orb_mana_per_second,
  		"food_eaten_count": food_eaten_count,
  		"orb_health_cost_per_click": orb_health_cost_per_click,
  		"food_heal_bonus": food_heal_bonus,
  		"health_regen_per_minute": health_regen_per_minute,
  		"better_chair_level": better_chair_level,
  		"better_table_level": better_table_level,
  		"better_bed_level": better_bed_level,
  		"is_blacked_out": is_blacked_out,
  		"familiars_assigned_to_orb": familiars_assigned_to_orb,
  		"better_meal_level": better_meal_level,
  	}


  func from_dict(data: Dictionary) -> void:
  	mana = data.get("mana", 0.0)
  	health = data.get("health", 50.0)
  	max_health = data.get("max_health", 50.0)
  	familiars = data.get("familiars", 0)
  	resources = (data.get("resources", {"stone": 0, "wood": 0, "water": 0, "crystals": 0}) as Dictionary).duplicate()
  	confidence_tier = data.get("confidence_tier", 0)
  	house_tier = data.get("house_tier", 0)
  	purchased_upgrades.assign(data.get("purchased_upgrades", []))
  	orb_mana_per_click = data.get("orb_mana_per_click", 1.0)
  	orb_mana_per_second = data.get("orb_mana_per_second", 0.0)
  	food_eaten_count = data.get("food_eaten_count", 0)
  	orb_health_cost_per_click = data.get("orb_health_cost_per_click", 5.0)
  	food_heal_bonus = data.get("food_heal_bonus", 0.0)
  	health_regen_per_minute = data.get("health_regen_per_minute", 0.0)
  	better_chair_level = data.get("better_chair_level", 0)
  	better_table_level = data.get("better_table_level", 0)
  	better_bed_level = data.get("better_bed_level", 0)
  	familiars_assigned_to_orb = data.get("familiars_assigned_to_orb", 0)
  	better_meal_level = data.get("better_meal_level", 0)
  	is_blacked_out = false
  	EventBus.state_changed.emit()
  ```

  Note: `add_orb_mana_per_second(-1.0)` inside `unassign_familiar_from_orb()` — confirm this still works exactly as before (it's an existing call, unchanged; only the new `EventBus.state_changed.emit()` lines are additions).

- [ ] **Step 4: Run the full suite, confirm the 4 new tests now pass and nothing else broke**

  ```bash
  BIN=$(cat .claude/godot-binary-path.txt)
  "$BIN" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -ginclude_subdirs -gpre_run_script=res://tests/hooks/pre_run_save_guard.gd -gpost_run_script=res://tests/hooks/post_run_save_guard.gd -gexit
  ```

  Expected: all tests pass (62 pre-existing + 4 new = 66), exit 0.

- [ ] **Step 5: Commit**

  ```bash
  git add autoloads/event_bus.gd autoloads/game_state.gd tests/unit/autoloads/test_game_state.gd
  git commit -m "Add EventBus.state_changed, emit from every GameState mutator (Bug 13, part 1)"
  ```

---

### Task 2: Wire `button_action.gd` to `state_changed`, close out Bug 13

**Files:**
- Modify: `scenes/ui/button_action.gd`
- Modify: `tests/unit/ui/test_button_action.gd` (extend, don't create a new file — it already exists)
- Modify: `docs/bugs.md`

**Interfaces:**
- Consumes: `EventBus.state_changed` (Task 1).

- [ ] **Step 1: Write the failing regression test first** — this is Bug 13's own literal acceptance-criteria test: mutate the relevant `GameState` stat directly (not through the gated button), confirm an already-instantiated button with a matching `unlock_condition` becomes enabled without any other trigger.

  Add to `tests/unit/ui/test_button_action.gd`:

  ```gdscript
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
  ```

  Run the suite; confirm this new test **fails** against the current (pre-Task-1... but Task 1 is already committed by the time this task runs, so it would actually pass now) — since Task 1 already shipped the emitting side, the failure this test should demonstrate here is specifically that `button_action.gd` doesn't yet *listen* for `state_changed`. Confirm the failure message shows the button stayed `disabled == true` after the direct `EventBus.state_changed.emit()` call, proving `button_action.gd` has no listener yet.

- [ ] **Step 2: Wire the listener**

  In `scenes/ui/button_action.gd`, modify `_ready()`:

  ```gdscript
  func _ready() -> void:
  	pressed.connect(_on_pressed)
  	_connect_tier_source()
  	EventBus.health_depleted.connect(_on_health_depleted)
  	EventBus.blackout_ended.connect(_on_blackout_ended)
  	EventBus.state_changed.connect(_on_state_changed)
  	if data:
  		_refresh()
  ```

  Add a new handler, placed near `_on_health_depleted()`/`_on_blackout_ended()`:

  ```gdscript
  func _on_state_changed() -> void:
  	_refresh()
  ```

- [ ] **Step 3: Run the full suite, confirm the new test now passes and nothing else broke**

  ```bash
  BIN=$(cat .claude/godot-binary-path.txt)
  "$BIN" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -ginclude_subdirs -gpre_run_script=res://tests/hooks/pre_run_save_guard.gd -gpost_run_script=res://tests/hooks/post_run_save_guard.gd -gexit
  ```

  Expected: all tests pass (66 pre-existing/Task-1 + 1 new = 67), exit 0.

- [ ] **Step 4: Full-project headless sanity check**

  ```bash
  "$BIN" --headless --quit
  ```

  Expected: no errors — confirms the new signal connection doesn't break project load (every `button_action.tscn` instance now connects one more signal in `_ready()`).

- [ ] **Step 5: Manual trace against Bug 13's other three acceptance criteria** (the fix is generic, so these should all follow from the same mechanism — trace, don't just assert):

  1. *Table (`food_eaten_count >= 5 && familiars >= 3`)* — same `unlock_condition` grammar (`&&` compound), same `_is_disabled()` path, same new `state_changed` listener. No button-specific code exists for Table vs. Chair; the fix applies uniformly.
  2. *Confidence 2–4 (`confidence_tier >= N`)* — same. `advance_confidence_tier()` (Task 1) now emits `state_changed`, so Confidence 2 unlocking after Confidence 1 is bought no longer depends on Confidence 2's own click.
  3. *Better Chair/Table/Bed (`has_upgrade(...)`)* — `mark_upgrade_purchased()` (Task 1) now emits `state_changed` on a genuine (non-idempotent) purchase, so Better Chair unlocks the instant Chair is bought, not on some later unrelated trigger.

  Confirm no button-specific exception exists anywhere in `scenes/ui/button_action.gd` that would make any of these three behave differently from the tested Chair case.

- [ ] **Step 6: Close out `docs/bugs.md`'s Bug 13 entry**

  Update the existing entry (added by `make-ticket`, backfilled with the issue number by `sync-tickets`) in place:

  ```
  **Status:** Fixed
  **Root cause (confirmed):** `scenes/ui/button_action.gd`'s `_ready()` only connected to `EventBus.health_depleted`/`blackout_ended` and, for `tier_source` buttons, `confidence_tier_changed`/`house_tier_changed` — there was no general mechanism re-evaluating `unlock_condition` when the specific stats it references changed via a *different* button's action. Matches the original hypothesis exactly; no surprises found during the fix.
  **Fix summary:** Added a generic, argument-less `EventBus.state_changed` signal, emitted from every public `GameState` mutator (`autoloads/event_bus.gd`, `autoloads/game_state.gd`). Every `button_action.gd` instance now connects to it unconditionally in `_ready()` and calls `_refresh()` on it (`scenes/ui/button_action.gd`), so any state change re-evaluates every live button's `unlock_condition`/afford/cooldown state, not just the ones already covered by blackout or `tier_source` signals.
  ```

  Leave every other line (`**Found:**`, `**Description:**`, `**Root cause (hypothesis):**`, `**Ticket:**`) untouched.

- [ ] **Step 7: Commit and push, closing the issue**

  ```bash
  git add scenes/ui/button_action.gd tests/unit/ui/test_button_action.gd docs/bugs.md
  git commit -m "$(cat <<'EOF'
  Fix Bug 13 — buttons now reactively re-evaluate unlock_condition on any state change

  Closes #17
  EOF
  )"
  git push
  ```

- [ ] **Step 8: Verify the issue closed**

  ```bash
  gh issue view 17 --json state --jq .state
  ```

  Expected: `CLOSED`.

- [ ] **Step 9: Report to the user**

  State what was built (the generic `state_changed` signal, wired through every `GameState` mutator and every `button_action.gd` instance), which acceptance criteria GUT already confirmed (the Chair-equivalent regression test, run for real, passing), and what's left to verify in the editor: play through eating bread twice and confirm Chair unlocks live without needing a blackout; confirm Table/Bed/Confidence 2-4/Better X all behave the same way in practice, not just by code-path tracing. Also flag: this fix touches `EventBus.state_changed.emit()` calls added to ~24 `GameState` methods — a future ticket adding a new `GameState` mutator must remember to emit it too if that stat is ever referenced by an `unlock_condition`; nothing enforces this automatically (a GUT test could theoretically assert every public `GameState` method emits `state_changed`, but that's out of scope for this bug fix — worth flagging for Ticket 12's polish pass).
