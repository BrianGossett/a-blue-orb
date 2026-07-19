# Consolidate Gain Confidence Into One Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the four separate `confidence_1.tres`–`confidence_4.tres` buttons with one repeatable button (`confidence.tres`), matching the Better Chair/Table/Bed/Meal pattern exactly — same button, same `id`, label stays put, cost and effect change as it's bought up to `max_purchases`.

**Architecture:** The existing `count_seed_source`/`max_purchases`/`cost_scaling` machinery (built for Better Chair/Table/Bed/Meal) already does everything needed except one thing: none of `ButtonData`'s three existing cost formulas (`linear`/`double`/`fixed`) reproduce the documented 10/20/50/100 mana costs, which the project owner chose to keep exact rather than round to a clean doubling. Task 1 adds a fourth cost-scaling mode, `"table"`, backed by a new `cost_table: Array[float]` field — a direct per-level cost lookup, the smallest addition that fits the existing "small switch/match on known shapes" cost-formula philosophy. Task 2 does the actual consolidation: fixes a real gap found while designing this (`_seed_purchase_count()` is missing cases for `"confidence_tier"` *and*, pre-existing before this ticket, `"better_meal_level"` — `better_meal.tres` already sets `count_seed_source = "better_meal_level"` but nothing reads it, so its purchase count silently resets to 0 on every reload), deletes the four old `.tres` files, and creates the single `confidence.tres`.

**Tech Stack:** Godot 4.7 / GDScript, GUT (vendored at `addons/gut/`).

## Global Constraints

- Direct-to-master: no branches, no PRs.
- GDScript: never `var x := min(...)` / `max(...)` — Variant-inference parse error in this engine build.
- `.tres` files defining custom `Resource` subclasses must use `type="Resource"` header + `script = ExtResource(...)`, matching every existing file in `data/buttons/house/`.
- **Exact costs, not invented ones:** the merged button's costs must be exactly 10, 20, 50, 100 mana (from `docs/architecture.md` §6 / `docs/design_doc.md`), confirmed with the project owner as a deliberate choice over switching to a clean `"double"` progression (which would have been 10/20/40/80). This is a genuine deviation from the Better X buttons' own `cost_scaling`, not an oversight — the plan text below reflects that.
- Standard test-run command (mandatory flags, not optional):
  ```
  <godot_bin> --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -ginclude_subdirs -gpre_run_script=res://tests/hooks/pre_run_save_guard.gd -gpost_run_script=res://tests/hooks/post_run_save_guard.gd -gexit
  ```
  Godot binary path: `$(cat .claude/godot-binary-path.txt)`.
- `EffectHandler._effect_gain_confidence()` (`autoloads/effect_handler.gd`) needs **no changes** — it already reads `GameState.confidence_tier` fresh on every call and guards at tier 4, exactly like a repeatable Better-X effect function. Confirm this during Task 2, don't touch the file speculatively.

---

### Task 1: `ButtonData` — add `cost_table` field and `"table"` cost-scaling mode

**Files:**
- Modify: `data/button_data.gd`
- Modify: `scenes/ui/button_action.gd`
- Modify: `tests/unit/data/test_button_data.gd`

**Interfaces:**
- Produces: `ButtonData.calculate_cost(base_cost, cost_scaling, cost_step, count, cost_table)` — new 5th parameter, defaulted to `[]` so every existing call site and test that doesn't pass it keeps working unchanged. Consumed by Task 2's `confidence.tres`.

- [ ] **Step 1: Add the field**

  In `data/button_data.gd`, add one new `@export` line alongside the existing cost-related fields (after `cost_step`):

  ```gdscript
  @export var cost_table: Array[float] = []
  ```

- [ ] **Step 2: Extend `calculate_cost()`**

  Change the function signature and add a `"table"` case:

  ```gdscript
  static func calculate_cost(base_cost: float, cost_scaling: String, cost_step: float, count: int, cost_table: Array[float] = []) -> float:
  	match cost_scaling:
  		"linear":
  			return base_cost + (cost_step * count)
  		"double":
  			return base_cost * pow(2, count)
  		"fixed":
  			return base_cost
  		"table":
  			if cost_table.is_empty():
  				push_error("ButtonData: cost_scaling \"table\" requires a non-empty cost_table")
  				return base_cost
  			var index: int = min(count, cost_table.size() - 1)
  			return cost_table[index]
  		_:
  			push_error("ButtonData: unknown cost_scaling \"%s\"" % cost_scaling)
  			return base_cost
  ```

  The `min(count, cost_table.size() - 1)` clamp matches the existing pattern in `button_action.gd`'s `_build_label_text()` (`min(_purchase_count, data.labels.size() - 1)`) — once past the table's last entry, cost stays pinned at the final tier's cost rather than erroring (this matches `max_purchases` hiding the button before that point is ever reached in practice, but the clamp is defensive, not load-bearing).

- [ ] **Step 3: Update the 3 call sites in `scenes/ui/button_action.gd`** to pass `data.cost_table`:

  All three currently read:
  ```gdscript
  ButtonData.calculate_cost(data.base_cost, data.cost_scaling, data.cost_step, _cost_count())
  ```
  Change all three to:
  ```gdscript
  ButtonData.calculate_cost(data.base_cost, data.cost_scaling, data.cost_step, _cost_count(), data.cost_table)
  ```
  (Lines: inside `_build_label_text()`, inside `_can_afford()`, inside `_handle_click()`.)

- [ ] **Step 4: GUT test**

  Add to `tests/unit/data/test_button_data.gd`:

  ```gdscript
  func test_calculate_cost_table_uses_exact_per_level_costs() -> void:
  	var table: Array[float] = [10.0, 20.0, 50.0, 100.0]
  	assert_eq(ButtonData.calculate_cost(0.0, "table", 0.0, 0, table), 10.0)
  	assert_eq(ButtonData.calculate_cost(0.0, "table", 0.0, 1, table), 20.0)
  	assert_eq(ButtonData.calculate_cost(0.0, "table", 0.0, 2, table), 50.0)
  	assert_eq(ButtonData.calculate_cost(0.0, "table", 0.0, 3, table), 100.0)


  func test_calculate_cost_table_clamps_past_the_last_entry() -> void:
  	var table: Array[float] = [10.0, 20.0, 50.0, 100.0]
  	assert_eq(ButtonData.calculate_cost(0.0, "table", 0.0, 99, table), 100.0)


  func test_calculate_cost_table_empty_falls_back_to_base_cost() -> void:
  	assert_eq(ButtonData.calculate_cost(5.0, "table", 0.0, 0, []), 5.0)
  	assert_push_error("cost_table")
  ```

- [ ] **Step 5: Run the full suite, confirm green**

  ```bash
  BIN=$(cat .claude/godot-binary-path.txt)
  "$BIN" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -ginclude_subdirs -gpre_run_script=res://tests/hooks/pre_run_save_guard.gd -gpost_run_script=res://tests/hooks/post_run_save_guard.gd -gexit
  ```

  Expected: all pre-existing tests still pass (the new 5th parameter is defaulted, so no existing call site breaks) plus the 3 new tests, exit 0.

- [ ] **Step 6: Full-project headless sanity check**

  ```bash
  "$BIN" --headless --quit
  ```

  Expected: no errors.

- [ ] **Step 7: Commit**

  ```bash
  git add data/button_data.gd scenes/ui/button_action.gd tests/unit/data/test_button_data.gd
  git commit -m "Add ButtonData 'table' cost-scaling mode for exact per-level costs"
  ```

---

### Task 2: Consolidate Gain Confidence into one button, fix the count_seed_source gap

**Files:**
- Modify: `scenes/ui/button_action.gd`
- Delete: `data/buttons/house/confidence_1.tres`, `confidence_2.tres`, `confidence_3.tres`, `confidence_4.tres`
- Create: `data/buttons/house/confidence.tres`
- Modify: `tests/unit/ui/test_button_action.gd`
- Modify: `tests/unit/ui/test_area_tab.gd` (one stale comment)

**Interfaces:**
- Consumes: `ButtonData.cost_table`/`"table"` scaling (Task 1), the existing `count_seed_source`/`max_purchases` machinery (Ticket 11), `EffectHandler`'s unchanged `_effect_gain_confidence()`.

- [ ] **Step 1: Fix `_seed_purchase_count()`'s missing cases**

  Current (`scenes/ui/button_action.gd`):
  ```gdscript
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
  ```

  `better_meal.tres` already sets `count_seed_source = "better_meal_level"`, and this ticket is about to give `confidence.tres` `count_seed_source = "confidence_tier"` — neither is handled, so both would silently reset their purchase count to 0 on every reload (the exact bug class `count_seed_source` was built to prevent). Fix by adding both missing cases:

  ```gdscript
  func _seed_purchase_count() -> int:
  	match data.count_seed_source:
  		"better_chair_level":
  			return GameState.better_chair_level
  		"better_table_level":
  			return GameState.better_table_level
  		"better_bed_level":
  			return GameState.better_bed_level
  		"better_meal_level":
  			return GameState.better_meal_level
  		"confidence_tier":
  			return GameState.confidence_tier
  		_:
  			return 0
  ```

- [ ] **Step 2: Delete the four old files**

  ```bash
  git rm data/buttons/house/confidence_1.tres data/buttons/house/confidence_2.tres data/buttons/house/confidence_3.tres data/buttons/house/confidence_4.tres
  ```

- [ ] **Step 3: Create the merged `confidence.tres`**

  `data/buttons/house/confidence.tres`:

  ```
  [gd_resource type="Resource" load_steps=2 format=3]

  [ext_resource type="Script" path="res://data/button_data.gd" id="1"]

  [resource]
  script = ExtResource("1")
  id = "confidence"
  labels = Array[String](["Gain Confidence"])
  cost_type = "mana"
  base_cost = 10.0
  cost_scaling = "table"
  cost_step = 0.0
  cooldown_sec = 0.0
  unlock_condition = ""
  effect_id = "gain_confidence"
  flavor_lines = Array[String]([])
  one_shot = false
  button_column = 2
  sort_order = 1
  tier_source = ""
  cost_count_source = ""
  count_seed_source = "confidence_tier"
  room_description_fragment = ""
  max_purchases = 4
  cooldown_gate_condition = ""
  cost_table = Array[float]([10.0, 20.0, 50.0, 100.0])
  ```

  Notes on the fields that differ from the old per-tier files: `id`/`sort_order`/`button_column` match `confidence_1.tres`'s original position (this button takes its slot). `unlock_condition` is empty — the old `confidence_1.tres` had `"confidence_tier >= 0"`, which is unconditionally true from a fresh game (`confidence_tier` starts at 0 and never decreases), so this preserves identical from-game-start availability, just without a vacuous condition string. `labels` is a single static entry (`"Gain Confidence"`, no per-tier number), matching how `better_chair.tres`/`better_table.tres`/etc. all use one static label regardless of purchase count. `base_cost` is set to `10.0` (the tier-0 cost) purely for the `push_error` fallback path in `calculate_cost()`'s `"table"` case — normal operation always resolves through `cost_table`.

- [ ] **Step 4: GUT test — full purchase sequence against the real shipped file**

  Add to `tests/unit/ui/test_button_action.gd` (`before_each()` already resets `GameState.from_dict({})`):

  ```gdscript
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
  ```

- [ ] **Step 5: Update the stale file-count comment**

  In `tests/unit/ui/test_area_tab.gd`, the comment near `test_buttons_are_loaded_in_ascending_sort_order_per_column()` says "14 of them" (referring to the number of `.tres` files in `data/buttons/house/`). After this task, there are 11 (14 − 4 old confidence files + 1 merged). Update the comment's number; the test's own logic doesn't hardcode a count, so no assertion changes.

- [ ] **Step 6: Run the full suite, confirm green**

  ```bash
  BIN=$(cat .claude/godot-binary-path.txt)
  "$BIN" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -ginclude_subdirs -gpre_run_script=res://tests/hooks/pre_run_save_guard.gd -gpost_run_script=res://tests/hooks/post_run_save_guard.gd -gexit
  ```

  Expected: all pre-existing tests plus the 2 new ones pass, exit 0. Confirm `test_buttons_are_loaded_in_ascending_sort_order_per_column` (Column 2's `sort_order` sequence is now `1, 5, 6, 7, 8` — gaps are fine, only strict ascension is checked) still passes.

- [ ] **Step 7: Full-project headless sanity check**

  ```bash
  "$BIN" --headless --quit
  ```

  Expected: no errors — confirms `area_tab.gd`'s directory scan handles the file removal/addition cleanly.

- [ ] **Step 8: Doc cross-check**

  Read `docs/architecture.md` §6's Confidence rows and `docs/design_doc.md`'s Gain Confidence entries — confirm the merged button's `cost_table` (10/20/50/100) and the unchanged `_effect_gain_confidence()` deltas (+3/+5/+7/+10 orb mana, +5 HP cost per tier) still match exactly. No doc edits needed — this is a UI/data consolidation, not a balancing change.

- [ ] **Step 9: Commit**

  ```bash
  git add scenes/ui/button_action.gd data/buttons/house/confidence.tres tests/unit/ui/test_button_action.gd tests/unit/ui/test_area_tab.gd
  git commit -m "Consolidate Gain Confidence into one repeatable button, like Better Table/Bed

  Also fixes a pre-existing gap: _seed_purchase_count() had no case for
  better_meal_level (set on better_meal.tres since Ticket 9c) or the new
  confidence_tier case this consolidation needs, so both would have
  silently reset to 0 on every reload instead of resuming at the correct
  tier."
  ```

- [ ] **Step 10: Report to the user**

  State: Gain Confidence is now one button (`confidence.tres`), costs stay exactly 10/20/50/100 mana via the new `"table"` cost-scaling mode, and it now correctly resumes its tier after a save reload (Better Chair/Table/Bed already had this; the old per-tier confidence buttons never did — this was flagged as a known gap back in Ticket 9's own final review and is now closed as a side effect). What to check in the editor: buy Gain Confidence up through all 4 levels in one session and confirm costs/effects match 10/20/50/100 and +3/+5/+7/+10 as before; if a save/reload round-trip is easy to test, confirm the button resumes at the right tier rather than resetting.
