# Reset Game Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a real, visible "Reset Game" button (with a confirmation dialog, since it's destructive) that wipes all progress back to a fresh game — both the live `GameState` and the persisted save file — making manual testing of a full playthrough repeatable without restarting the editor or hand-deleting the save file.

**Architecture:** `autoloads/save_manager.gd` gains a `reset_game()` method that resets `GameState` (reusing `from_dict({})`, which already restores every field to its documented default), immediately persists that reset state, and emits a new `EventBus.game_reset` signal. `scenes/ui/area_tab.gd` listens for it and fully reloads its button columns — which requires fixing a latent bug first: `_load_buttons()` isn't currently safe to call twice (it would append duplicate buttons on top of the old ones, and a naive "clear all children" fix would also destroy the pre-placed `OrbChanneling` scene child, which isn't one of the dynamically-loaded buttons). `scenes/ui/stat_bar.gd` gets the actual button/dialog UI, plus a fix for the same class of gap `button_action.gd` already had before Bug 13: its mana/health labels only listen to the specific `mana_changed`/`health_changed` signals, not the generic `state_changed`, so they'd silently show stale numbers after a reset (or any other bulk state change, like a save load) until some unrelated action happened to fire one of those specific signals.

**Tech Stack:** Godot 4.7 / GDScript, GUT (vendored at `addons/gut/`).

## Global Constraints

- Direct-to-master: no branches, no PRs.
- GDScript: never `var x := min(...)` / `max(...)` — Variant-inference parse error in this engine build.
- Standard test-run command (mandatory flags, not optional — the `-gpre_run_script`/`-gpost_run_script` pair protects the real `user://save.json`, which this plan's own `SaveManager.reset_game()` writes to directly during tests):
  ```
  <godot_bin> --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -ginclude_subdirs -gpre_run_script=res://tests/hooks/pre_run_save_guard.gd -gpost_run_script=res://tests/hooks/post_run_save_guard.gd -gexit
  ```
  Godot binary path: `$(cat .claude/godot-binary-path.txt)`.
- This is a real, permanent, player-facing feature (not a dev-only/editor-only tool) — the project owner explicitly wants a visible button, not a hidden shortcut. It doesn't need to live in a dedicated menu system yet (none exists) — the `StatBar` (visible whenever the House tab is active, which today is effectively always) is an acceptable home for now.
- `EventBus.state_changed` (added for Bug 13) already covers "something in `GameState` changed, re-check yourself" for any listener that already reads `GameState` fresh on each call — `stat_bar.gd`'s fix in Task 2 follows that same established pattern, not a new mechanism.

---

### Task 1: `EventBus.game_reset` + `SaveManager.reset_game()`

**Files:**
- Modify: `autoloads/event_bus.gd`
- Modify: `autoloads/save_manager.gd`
- Modify: `tests/unit/autoloads/test_save_manager.gd` (extend — already exists)

**Interfaces:**
- Produces: `EventBus.game_reset` (no args), `SaveManager.reset_game() -> void`. Consumed by Task 2.

- [ ] **Step 1: Add the signal**

  In `autoloads/event_bus.gd`, add one line (order doesn't matter functionally; append at the end):

  ```gdscript
  signal game_reset
  ```

- [ ] **Step 2: Add `reset_game()`**

  In `autoloads/save_manager.gd`, add a new method (placement: anywhere among the other public methods, e.g. right after `save_game()`):

  ```gdscript
  func reset_game() -> void:
  	GameState.from_dict({})
  	save_game()
  	LogManager.push("everything resets. you start anew.")
  	EventBus.game_reset.emit()
  ```

  Order matters: reset `GameState` first (so `save_game()` immediately persists the fresh-default state, not the pre-reset one), then log the flavor line, then emit `game_reset` last (so anything reacting to it — Task 2's `area_tab.gd` — sees fully-reset, fully-saved state).

- [ ] **Step 3: GUT tests**

  Add to `tests/unit/autoloads/test_save_manager.gd` (this file already has the mandatory real-file backup/restore pattern established for `SaveManager` tests — follow it):

  ```gdscript
  func test_reset_game_restores_defaults_and_persists_them() -> void:
  	GameState.add_mana(50.0)
  	GameState.add_familiars(3)
  	GameState.mark_upgrade_purchased("chair")

  	SaveManager.reset_game()

  	assert_eq(GameState.mana, 0.0)
  	assert_eq(GameState.familiars, 0)
  	assert_false(GameState.has_upgrade("chair"))

  	# Confirm it was actually persisted, not just reset in memory — load
  	# into a second reset first, to prove the file itself now reflects
  	# the reset state rather than the pre-reset values.
  	GameState.add_mana(999.0)
  	SaveManager.load_game()
  	assert_eq(GameState.mana, 0.0, "the save file itself must already reflect the reset, not just live memory")


  func test_reset_game_emits_game_reset_and_a_log_line() -> void:
  	watch_signals(EventBus)
  	var lines_before: int = LogManager.get_lines().size()

  	SaveManager.reset_game()

  	assert_signal_emitted(EventBus, "game_reset")
  	assert_gt(LogManager.get_lines().size(), lines_before, "reset should push a flavor line")
  ```

- [ ] **Step 4: Run the full suite, confirm green**

  ```bash
  BIN=$(cat .claude/godot-binary-path.txt)
  "$BIN" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -ginclude_subdirs -gpre_run_script=res://tests/hooks/pre_run_save_guard.gd -gpost_run_script=res://tests/hooks/post_run_save_guard.gd -gexit
  ```

  Expected: all pre-existing tests plus the 2 new ones pass, exit 0.

- [ ] **Step 5: Full-project headless sanity check**

  ```bash
  "$BIN" --headless --quit
  ```

  Expected: no errors.

- [ ] **Step 6: Commit**

  ```bash
  git add autoloads/event_bus.gd autoloads/save_manager.gd tests/unit/autoloads/test_save_manager.gd
  git commit -m "Add SaveManager.reset_game() + EventBus.game_reset"
  ```

---

### Task 2: Make `area_tab.gd` safely reloadable, wire the Reset button, fix `stat_bar.gd`'s stale-display gap

**Files:**
- Modify: `scenes/ui/area_tab.gd`
- Modify: `scenes/ui/stat_bar.gd`
- Modify: `scenes/ui/stat_bar.tscn`
- Modify: `tests/unit/ui/test_area_tab.gd`

**Interfaces:**
- Consumes: `EventBus.game_reset` (Task 1).

- [ ] **Step 1: Fix `_load_buttons()` — track dynamically-created buttons separately from pre-placed scene children**

  Current `scenes/ui/area_tab.gd` has no way to safely re-run `_load_buttons()`: calling it twice would append duplicate buttons, and naively clearing *all* of `_column_upgrades`'s children would also destroy the pre-placed `OrbChanneling` scene instance (it's not one of the dynamically-`.tres`-loaded buttons). Fix by tracking only what `_load_buttons()` itself creates:

  Add a new instance variable near the top of the file (alongside `_furniture_fragments`):
  ```gdscript
  var _dynamic_buttons: Array[Node] = []
  ```

  Change `_load_buttons()` to clear its own previously-created buttons first, and track new ones as it creates them:
  ```gdscript
  func _load_buttons() -> void:
  	for button in _dynamic_buttons:
  		button.queue_free()
  	_dynamic_buttons.clear()
  	var dir_path := "res://data/buttons/%s/" % area_data.id
  	var dir := DirAccess.open(dir_path)
  	if dir == null:
  		return
  	var button_datas: Array[ButtonData] = []
  	for file_name in dir.get_files():
  		if not file_name.ends_with(".tres"):
  			continue
  		button_datas.append(load(dir_path + file_name))
  	button_datas.sort_custom(func(a: ButtonData, b: ButtonData) -> bool: return a.sort_order < b.sort_order)
  	for button_data in button_datas:
  		if button_data.one_shot and GameState.has_upgrade(button_data.id):
  			if button_data.room_description_fragment != "":
  				_furniture_fragments.append(button_data.room_description_fragment)
  			continue
  		var instance: Button = BUTTON_ACTION_SCENE.instantiate()
  		instance.set_data(button_data)
  		instance.one_shot_purchased.connect(_on_one_shot_purchased)
  		_dynamic_buttons.append(instance)
  		if button_data.button_column == 1:
  			_column_actions.add_child(instance)
  		else:
  			_column_upgrades.add_child(instance)
  	_rebuild_description()
  ```

  On the very first call (fresh scene, `_dynamic_buttons` starts as `[]`), the new clearing loop is a no-op — behavior is unchanged from today. `OrbChanneling` (a pre-placed `.tscn` child of `ColumnUpgrades`, never added to `_dynamic_buttons`) is never touched by the clearing loop, so it survives every reload untouched — its own `_refresh()` already reacts correctly to `EventBus.state_changed` (fired by `GameState.from_dict()` inside `reset_game()`), no changes needed there.

- [ ] **Step 2: Listen for `game_reset`, reload on it**

  In `_ready()`, add a new connection:
  ```gdscript
  func _ready() -> void:
  	EventBus.house_tier_changed.connect(_on_house_tier_changed)
  	EventBus.game_reset.connect(_on_game_reset)
  	if area_data:
  		_apply_area_data()
  ```

  Add a new handler (placed near `_on_house_tier_changed()`):
  ```gdscript
  func _on_game_reset() -> void:
  	if area_data:
  		_apply_area_data()
  ```

  `_apply_area_data()` already clears `_furniture_fragments`, resets the description text, and calls `_load_buttons()` — combined with Step 1's fix, a second call is now fully safe: stale dynamic buttons are freed, previously-hidden one-shot furniture buttons (Chair/Table/Bed) reappear since `GameState.has_upgrade(...)` is false again post-reset, and the description resets to the base text with no furniture fragments.

- [ ] **Step 3: Fix `stat_bar.gd`'s stale-display gap**

  `GameState.from_dict()` (used by both `SaveManager.load_game()` and, via Task 1, `reset_game()`) only emits the generic `EventBus.state_changed` — not `mana_changed`/`health_changed` — so `stat_bar.gd`'s labels currently have no way to learn about a bulk reset/load while the game is already running (they only got the right values at startup because `_ready()` explicitly reads `GameState` directly once, before any of this matters). Fix by having `stat_bar.gd` also listen to `state_changed`, mirroring the pattern already established in `button_action.gd` for Bug 13:

  ```gdscript
  func _ready() -> void:
  	EventBus.mana_changed.connect(_on_mana_changed)
  	EventBus.health_changed.connect(_on_health_changed)
  	EventBus.state_changed.connect(_on_state_changed)
  	_on_mana_changed(GameState.mana)
  	_on_health_changed(GameState.health, GameState.max_health)


  func _on_state_changed() -> void:
  	_on_mana_changed(GameState.mana)
  	_on_health_changed(GameState.health, GameState.max_health)
  ```

- [ ] **Step 4: Add the Reset button + confirmation dialog**

  In `scenes/ui/stat_bar.tscn`, add two new nodes as children of the root `StatBar` (an `HBoxContainer`):

  ```
  [node name="ResetButton" type="Button" parent="."]
  text = "Reset Game"

  [node name="ResetConfirmDialog" type="ConfirmationDialog" parent="."]
  dialog_text = "Reset all progress? This cannot be undone."
  ```

  In `scenes/ui/stat_bar.gd`, wire it up:

  ```gdscript
  @onready var _reset_button: Button = $ResetButton
  @onready var _reset_confirm_dialog: ConfirmationDialog = $ResetConfirmDialog
  ```
  (add alongside the existing `_mana_label`/`_health_label` `@onready` vars)

  ```gdscript
  func _ready() -> void:
  	EventBus.mana_changed.connect(_on_mana_changed)
  	EventBus.health_changed.connect(_on_health_changed)
  	EventBus.state_changed.connect(_on_state_changed)
  	_reset_button.pressed.connect(_on_reset_button_pressed)
  	_reset_confirm_dialog.confirmed.connect(_on_reset_confirmed)
  	_on_mana_changed(GameState.mana)
  	_on_health_changed(GameState.health, GameState.max_health)


  func _on_reset_button_pressed() -> void:
  	_reset_confirm_dialog.popup_centered()


  func _on_reset_confirmed() -> void:
  	SaveManager.reset_game()
  ```

  (This replaces the `_ready()` shown in Step 3 — the two are additive, shown separately above only to isolate the `state_changed` fix from the button wiring; write `_ready()` once with all five connections.)

- [ ] **Step 5: GUT test — full reload-without-duplication, without destroying OrbChanneling**

  Add to `tests/unit/ui/test_area_tab.gd`:

  ```gdscript
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

  	EventBus.game_reset.emit()
  	await get_tree().process_frame  # let queue_free()'d nodes actually leave the tree

  	var orb_channeling_after: Node = tab._column_upgrades.get_node_or_null("OrbChanneling")
  	assert_eq(orb_channeling_after, orb_channeling_before, "the same OrbChanneling instance must survive a reload, not be destroyed and never recreated")

  	assert_not_null(_find_button_by_id(tab._column_actions, "chair"), "Chair should reappear after reset, since it's no longer purchased")
  	assert_eq(tab._column_actions.get_child_count(), actions_count_before_reset + 1, "exactly one more button (Chair reappearing) — no duplicates")


  func _find_button_by_id(container: Node, id: String) -> Button:
  	for child in container.get_children():
  		if child is Button and "data" in child and child.data != null and child.data.id == id:
  			return child
  	return null
  ```

  This directly exercises `EventBus.game_reset` (not `SaveManager.reset_game()` itself, to keep this test focused on `area_tab.gd`'s reload behavior rather than re-testing Task 1's own already-covered reset logic) — confirms no duplicate buttons, confirms `OrbChanneling` survives by identity (not just by node-name existing again), and confirms a previously-hidden one-shot button genuinely reappears.

- [ ] **Step 6: Run the full suite, confirm green**

  ```bash
  BIN=$(cat .claude/godot-binary-path.txt)
  "$BIN" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -ginclude_subdirs -gpre_run_script=res://tests/hooks/pre_run_save_guard.gd -gpost_run_script=res://tests/hooks/post_run_save_guard.gd -gexit
  ```

  Expected: all pre-existing tests plus the 1 new test pass, exit 0.

- [ ] **Step 7: Full-project headless sanity check**

  ```bash
  "$BIN" --headless --quit
  ```

  Expected: no errors — confirms the new `ConfirmationDialog`/`ResetButton` nodes and the new signal connections don't break scene load.

- [ ] **Step 8: Commit**

  ```bash
  git add scenes/ui/area_tab.gd scenes/ui/stat_bar.gd scenes/ui/stat_bar.tscn tests/unit/ui/test_area_tab.gd
  git commit -m "Add a Reset Game button; make area_tab.gd safely reloadable on reset

  Also fixes stat_bar.gd's mana/health labels not updating on a bulk
  state change (reset or a save load happening while already running) —
  they only listened to mana_changed/health_changed, not the generic
  state_changed EventBus.state_changed added for Bug 13."
  ```

- [ ] **Step 9: Report to the user**

  State: a "Reset Game" button now sits in the StatBar (visible above the House tab's button grid), with a confirmation dialog before it actually wipes anything. Resetting clears `GameState` to defaults, immediately overwrites the save file (so a crash right after reset doesn't un-reset on next launch), re-shows any previously-purchased one-shot furniture buttons, and doesn't duplicate or destroy the Orb Channeling widget. What GUT already confirmed: the full reset-and-reload cycle, run for real against the actual scene tree. What's left to check in the editor: click Reset mid-playthrough and confirm the whole House tab visually snaps back to a fresh game — buttons, room description, log line, stat bar numbers all at once, not just some of them.
