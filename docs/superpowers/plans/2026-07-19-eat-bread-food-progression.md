# Eat Bread Food-Name Progression Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix a real bug: `docs/design_doc.md`'s food progression (Bread → Soup → Stew → Roast → Shepherd's Pie, tied to Table tier) was never actually wired up — `eat_bread.tres` has always had a single static label (`"Eat Bread"`) and `tier_source = ""`, so the name never changes no matter how many times Better Table is bought.

**Architecture:** `better_table_level` (0–4, already exists on `GameState`, already advances via `_effect_better_table()`) is the natural tier source — it's exactly the "how upgraded is the table" signal the food progression should track, and it needs no new state. `button_action.gd`'s existing `tier_source` mechanism (already used by `touch_orb.tres` for its 5-tier Confidence-driven labels) is the existing, established pattern for "this button's label progresses with an external stat" — extend it with a `"better_table_level"` case rather than inventing a second mechanism. Unlike `confidence_tier`/`house_tier`, `better_table_level` has no dedicated changed-signal (it only fires the generic `EventBus.state_changed`, added for Bug 13) — the fix threads through the existing generic `state_changed` listener every `button_action.gd` instance already has, rather than adding a second signal subscription.

**Tech Stack:** Godot 4.7 / GDScript, GUT (vendored at `addons/gut/`).

## Global Constraints

- Direct-to-master: no branches, no PRs.
- GDScript: never `var x := min(...)` / `max(...)` — Variant-inference parse error in this engine build.
- Standard test-run command (mandatory flags, not optional):
  ```
  <godot_bin> --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -ginclude_subdirs -gpre_run_script=res://tests/hooks/pre_run_save_guard.gd -gpost_run_script=res://tests/hooks/post_run_save_guard.gd -gexit
  ```
  Godot binary path: `$(cat .claude/godot-binary-path.txt)`.
- Food names, from `docs/design_doc.md` (§ House name progression / Table → Food progression, also mirrored in `docs/architecture.md` §6): tier 0 Bread, tier 1 Soup, tier 2 Stew, tier 3 Roast, tier 4 Shepherd's Pie. These are locked-in doc numbers, not invented here.
- This is a real bug fix (the design doc's own spec was never implemented), not a new feature — treat it with the same rigor as Bug 13: a real GUT test proving the label actually changes as `better_table_level` advances, not just that the mechanism compiles.

---

### Task 1: Wire `better_table_level` as a `tier_source`, update `eat_bread.tres`'s labels and flavor text

**Files:**
- Modify: `scenes/ui/button_action.gd`
- Modify: `data/buttons/house/eat_bread.tres`
- Modify: `autoloads/effect_handler.gd`
- Modify: `tests/unit/ui/test_button_action.gd`
- Modify: `tests/unit/autoloads/test_effect_handler_ticket9.gd`

- [ ] **Step 1: Write the failing test first**

  Add to `tests/unit/ui/test_button_action.gd` (`before_each()` already resets `GameState.from_dict({})`):

  ```gdscript
  func test_eat_bread_tres_label_progresses_with_better_table_level() -> void:
  	var button: Button = add_child_autofree(load("res://scenes/ui/button_action.tscn").instantiate())
  	var data: ButtonData = load("res://data/buttons/house/eat_bread.tres")
  	button.set_data(data)

  	assert_eq(button.text, "Eat Bread", "tier 0 (no Better Table purchases yet) should read Bread")

  	GameState.advance_better_table_level()
  	EventBus.state_changed.emit()
  	assert_eq(button.text, "Eat Soup", "tier 1")

  	GameState.advance_better_table_level()
  	EventBus.state_changed.emit()
  	assert_eq(button.text, "Eat Stew", "tier 2")

  	GameState.advance_better_table_level()
  	EventBus.state_changed.emit()
  	assert_eq(button.text, "Eat Roast", "tier 3")

  	GameState.advance_better_table_level()
  	EventBus.state_changed.emit()
  	assert_eq(button.text, "Eat Shepherd's Pie", "tier 4, the max")
  ```

  (`advance_better_table_level()` itself already calls `EventBus.state_changed.emit()` internally per every `GameState` mutator since Bug 13 — the explicit `EventBus.state_changed.emit()` calls above are redundant but harmless, included only for clarity/robustness against a future refactor; the important thing this test proves is that the *label* — `button.text` — actually follows `better_table_level`, not just that the field changes.)

  Run the suite; confirm this new test fails (the label stays `"Eat Bread (0 mana)"`... actually since `eat_bread.tres` has `cost_type="none"` the label has no cost suffix, so it should read exactly `"Eat Bread"` at every tier before this fix, since nothing currently changes it).

- [ ] **Step 2: Add the `"better_table_level"` `tier_source` case**

  In `scenes/ui/button_action.gd`, extend `_connect_tier_source()`:

  ```gdscript
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
  		"better_table_level":
  			set_purchase_count(GameState.better_table_level)
  ```

  `better_table_level` has no dedicated changed-signal to connect to (only the generic `state_changed`, which every button already listens to via `_on_state_changed()` in `_ready()`) — so instead of a second signal connection, extend `_on_state_changed()` to resync `_purchase_count` for this one `tier_source` case before refreshing:

  ```gdscript
  func _on_state_changed() -> void:
  	if data != null and data.tier_source == "better_table_level":
  		_purchase_count = GameState.better_table_level
  	_refresh()
  ```

  This leaves `confidence_tier`/`house_tier` untouched (they still use their own precise dedicated signals, unchanged) — only the new case rides on the already-existing generic listener.

- [ ] **Step 3: Update `eat_bread.tres`'s labels**

  Change:
  ```
  labels = Array[String](["Eat Bread"])
  tier_source = ""
  ```
  to:
  ```
  labels = Array[String](["Eat Bread", "Eat Soup", "Eat Stew", "Eat Roast", "Eat Shepherd's Pie"])
  tier_source = "better_table_level"
  ```

- [ ] **Step 4: Match the flavor log line to the current food tier**

  `autoloads/effect_handler.gd`'s `_effect_eat_food()` currently always logs `"you eat the bread. it is simple, but satisfying."` regardless of tier — update it to name the actual food being eaten, keeping the button label and the log line consistent:

  ```gdscript
  func _effect_eat_food() -> bool:
  	const FOOD_NAMES: Array[String] = ["bread", "soup", "stew", "roast", "shepherd's pie"]
  	GameState.add_health(10.0 + GameState.food_heal_bonus)
  	GameState.add_food_eaten()
  	var food_index: int = min(GameState.better_table_level, FOOD_NAMES.size() - 1)
  	LogManager.push("you eat the %s. it is simple, but satisfying." % FOOD_NAMES[food_index])
  	return true
  ```

  Add a test to `tests/unit/autoloads/test_effect_handler_ticket9.gd` (this file already covers Ticket 9-era `EffectHandler` functions, including `add_table`/`better_table`):

  ```gdscript
  func test_eat_food_log_line_names_the_current_food_tier() -> void:
  	GameState.advance_better_table_level()
  	GameState.advance_better_table_level()
  	var lines_before: int = LogManager.get_lines().size()

  	EffectHandler.run_effect("eat_food")

  	var last_line: String = LogManager.get_lines()[-1]
  	assert_gt(LogManager.get_lines().size(), lines_before)
  	assert_string_contains(last_line, "stew", "at better_table_level 2, the log should name stew, not bread")
  ```

- [ ] **Step 5: Run the full suite, confirm green**

  ```bash
  BIN=$(cat .claude/godot-binary-path.txt)
  "$BIN" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -ginclude_subdirs -gpre_run_script=res://tests/hooks/pre_run_save_guard.gd -gpost_run_script=res://tests/hooks/post_run_save_guard.gd -gexit
  ```

  Expected: all pre-existing tests plus the 2 new ones pass, exit 0. Also confirm `tests/unit/integration/test_full_playthrough.gd` (from Ticket 12) still passes — it buys Better Table 4 times during its run, which now also exercises this exact label-progression path for real; if it doesn't currently assert anything about the label text, that's fine, just confirm it doesn't newly fail.

- [ ] **Step 6: Full-project headless sanity check**

  ```bash
  "$BIN" --headless --quit
  ```

- [ ] **Step 7: Commit**

  ```bash
  git add scenes/ui/button_action.gd data/buttons/house/eat_bread.tres autoloads/effect_handler.gd tests/unit/ui/test_button_action.gd tests/unit/autoloads/test_effect_handler_ticket9.gd
  git commit -m "Fix Eat Bread's name never progressing with Table tier (Bread/Soup/Stew/Roast/Shepherd's Pie)"
  ```

- [ ] **Step 8: Report to the user**

  State: Eat Bread's button label and its log-line flavor text now both progress through Bread → Soup → Stew → Roast → Shepherd's Pie as Better Table is purchased (0 through 4 levels), matching the design doc. What GUT already confirmed: the label at all 5 tiers, and the log line naming the right food. What's left to check in the editor: buy Better Table a few times and watch the Eat Bread button's own text change without needing to click it or do anything else.
