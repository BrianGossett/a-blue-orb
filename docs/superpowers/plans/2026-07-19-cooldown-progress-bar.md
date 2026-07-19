# Cooldown Progress Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every button with a cooldown (`data.cooldown_sec > 0.0`) shows a thin fill bar along its bottom edge while recharging, so it's visually obvious the button isn't just "disabled" — it's coming back.

**Architecture:** `button_action.tscn` gains one new child node, a `ProgressBar` anchored to the button's bottom edge, hidden by default. `button_action.gd` shows it and resets it to empty the moment a cooldown starts (`_start_cooldown()`), fills it toward full as `_process()`'s existing per-frame countdown ticks (`value = 1.0 - remaining/total`), and hides it the moment the cooldown ends. Buttons with no cooldown (`cooldown_sec <= 0.0`, the majority — `_start_cooldown()` already early-returns for them) never show it at all. The existing `cooldown_gate_condition` pause mechanic (Eat Bread's cooldown only ticks while `familiars >= 1`) naturally freezes the bar's fill level too, since the same early-return in `_process()` already skips the countdown during a pause — no separate handling needed.

**Tech Stack:** Godot 4.7 / GDScript, GUT (vendored at `addons/gut/`).

## Global Constraints

- Direct-to-master: no branches, no PRs.
- GDScript: never `var x := min(...)` / `max(...)` — Variant-inference parse error in this engine build.
- This is a visual feature, but its *state* (bar value, visibility) is logic and belongs in GUT; the actual on-screen look is not GUT-testable and needs an editor check, per this project's established "GUT covers logic, not feel" rule.
- Standard test-run command (mandatory flags, not optional):
  ```
  <godot_bin> --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -ginclude_subdirs -gpre_run_script=res://tests/hooks/pre_run_save_guard.gd -gpost_run_script=res://tests/hooks/post_run_save_guard.gd -gexit
  ```
  Godot binary path: `$(cat .claude/godot-binary-path.txt)`.

---

### Task 1: Cooldown progress bar on `button_action.tscn`

**Files:**
- Modify: `scenes/ui/button_action.tscn`
- Modify: `scenes/ui/button_action.gd`
- Modify: `tests/unit/ui/test_button_action.gd` (extend — already exists)

- [ ] **Step 1: Add the `ProgressBar` node**

  In `scenes/ui/button_action.tscn`, add a child of the root `ButtonAction` node:

  ```
  [node name="CooldownBar" type="ProgressBar" parent="."]
  visible = false
  anchors_preset = 12
  anchor_top = 1.0
  anchor_right = 1.0
  anchor_bottom = 1.0
  offset_top = -6.0
  offset_bottom = 0.0
  mouse_filter = 2
  min_value = 0.0
  max_value = 1.0
  value = 0.0
  show_percentage = false
  ```

  `anchors_preset = 12` is Godot's "bottom wide" preset (matches the explicit anchor/offset values given, included for editor-consistency — the explicit anchors are what actually take effect). `mouse_filter = 2` is `MOUSE_FILTER_IGNORE`, so the bar never intercepts clicks meant for the button underneath it. `show_percentage = false` hides `ProgressBar`'s default "0%" text overlay — this is meant to read as a bare fill strip, not a numeric readout.

- [ ] **Step 2: Wire it up in `scenes/ui/button_action.gd`**

  Add a new `@onready` var alongside the existing `data`/`_purchase_count` fields:
  ```gdscript
  @onready var _cooldown_bar: ProgressBar = $CooldownBar
  ```

  Update `_start_cooldown()` to show and reset the bar:
  ```gdscript
  func _start_cooldown() -> void:
  	if data.cooldown_sec <= 0.0:
  		return
  	_is_on_cooldown = true
  	_cooldown_remaining = data.cooldown_sec
  	disabled = true
  	_cooldown_bar.value = 0.0
  	_cooldown_bar.visible = true
  ```

  Update `_process()` to fill the bar as the cooldown counts down, and hide it when the cooldown ends:
  ```gdscript
  func _process(delta: float) -> void:
  	if not _is_on_cooldown:
  		return
  	if data.cooldown_gate_condition != "" and not ButtonData.is_unlock_condition_met(data.cooldown_gate_condition):
  		return
  	_cooldown_remaining -= delta
  	_cooldown_bar.value = clampf(1.0 - (_cooldown_remaining / data.cooldown_sec), 0.0, 1.0)
  	if _cooldown_remaining <= 0.0:
  		_is_on_cooldown = false
  		_cooldown_bar.visible = false
  		_refresh()
  ```

  `clampf(...)` guards the one frame where `_cooldown_remaining` goes slightly negative before the `_is_on_cooldown = false` branch fires — without it, `value` could briefly exceed `1.0` on that exact frame (harmless numerically, since `ProgressBar` clamps its own display range internally, but the explicit clamp keeps the value's *meaning* — "fraction recharged" — always literally correct, not just visually harmless).

- [ ] **Step 3: GUT tests**

  Add to `tests/unit/ui/test_button_action.gd` (`before_each()` already resets `GameState.from_dict({})`):

  ```gdscript
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
  ```

- [ ] **Step 4: Run the full suite, confirm green**

  ```bash
  BIN=$(cat .claude/godot-binary-path.txt)
  "$BIN" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -ginclude_subdirs -gpre_run_script=res://tests/hooks/pre_run_save_guard.gd -gpost_run_script=res://tests/hooks/post_run_save_guard.gd -gexit
  ```

  Expected: all pre-existing tests plus the 3 new ones pass, exit 0.

- [ ] **Step 5: Full-project headless sanity check**

  ```bash
  "$BIN" --headless --quit
  ```

  Expected: no errors — confirms the new `ProgressBar` child doesn't break scene load for any of the real shipped buttons (several of which — Touch the Orb, Eat Bread — actually have a nonzero `cooldown_sec` and will exercise this for real in play).

- [ ] **Step 6: Commit**

  ```bash
  git add scenes/ui/button_action.tscn scenes/ui/button_action.gd tests/unit/ui/test_button_action.gd
  git commit -m "Add a fill-bar to show cooldown recharge progress on buttons"
  ```

- [ ] **Step 7: Report to the user**

  State: every button with a real cooldown (Touch the Orb: 1s, Eat Bread: 5s, plus any future one) now shows a thin fill bar along its bottom edge while disabled from cooldown, filling from empty to full as it recharges. Buttons with no cooldown never show it. What GUT already confirmed: the bar's value/visibility state transitions, run for real. What's left to check in the editor: click Touch the Orb or Eat Bread and watch the bar actually fill and disappear — GUT proves the numbers are right, not that it looks good at a glance.
