# Ticket 11: Save System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `SaveManager` autoload that saves/loads `GameState` as versioned JSON, autosaves on a timer and on purchases, loads automatically on startup, and exposes `export_save()`/`import_save()` as a manual safety net — plus resolving the two reload gaps flagged by Tickets 10 and 9b's final reviews (the blackout soft-lock risk, and Better X upgrades not reconstructing their UI state).

**Architecture:** `GameState.from_dict()` is hardened to never restore `is_blacked_out=true` from a save (a blackout is transient, not worth persisting). `ButtonData` gains a `count_seed_source` field so a button can seed its initial `_purchase_count` from a `GameState` field when created — resolving the Better X reload gap generically, not just patched around it. `button_action.gd`'s `_handle_click()` is hardened to respect `EffectHandler.run_effect()`'s return value and refund the deducted cost on failure — the root-cause fix the issue explicitly called out as worth doing regardless of the specific Better X scenario that surfaced it. `SaveManager` itself is a straightforward JSON-blob autoload following the architecture doc's already-resolved design.

**Tech Stack:** GDScript, Godot 4.7, `FileAccess`/`JSON`/`OS`/`JavaScriptBridge`. A working Godot 4.7.1 binary exists at `/home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64` (not on PATH) — this ticket's save/load logic is pure data serialization, exactly the kind of thing worth a REAL executed round-trip test, not just a manual trace.

## Global Constraints

- **Scope, confirmed with the project owner:** `SaveManager`'s backend logic only — `save_game()`, `load_game()`, autosave, auto-load on startup, `export_save()`/`import_save()` all work correctly as callable functions. **No UI this session** (no Export/Import buttons) — no ticket in the original 12 scopes that UI, and building it now would be new, unscoped work. Verification of export/import is via directly invoking the functions (a headless test script), not clicking a UI that doesn't exist. Flag a minimal Save UI as a natural follow-up ticket in the final report.
- **Web export testing, confirmed scope:** implement `export_save()`'s `OS.has_feature("web")` branch per Godot's documented `JavaScriptBridge.download_buffer()` API, and verify the JSON construction/round-trip logic works via a real headless run — but the actual browser-download behavior CANNOT be verified in this environment (no browser, no export templates configured, no way to build/serve a web export here). State this plainly in the final report; it needs the user to test in a real web export whenever one gets built.
- **Save file format:** a single JSON object, `{"save_version": Constants.SAVE_VERSION, "game_state": GameState.to_dict()}` — nested, not flattened, to avoid any possibility of key collision between a future top-level save field and a `GameState` field. Written to `user://save.json` (per architecture doc §3 — Godot's `user://` maps to IndexedDB automatically in HTML5 exports, no code difference needed for that part).
- **New `Constants` fields** (extending the already-shipped Ticket 10 file): `SAVE_VERSION: int = 1`, `AUTOSAVE_INTERVAL_SEC: float = 20.0` (middle of the ticket's stated 15-30s range).
- **Blackout soft-lock fix (resolves the note left on this issue by Ticket 10's final review):** `GameState.from_dict()` is changed to unconditionally set `is_blacked_out = false`, ignoring whatever the loaded dict says — NOT reading `data.get("is_blacked_out", false)` anymore. `to_dict()` keeps writing the field (useful diagnostic information in a save file, e.g. "was blacked out at save time"), but nothing ever restores it as `true`. This fixes the gap at its single source (`from_dict()`), rather than requiring every caller (`load_game()`, `import_save()`) to remember a follow-up `exit_blackout()` call.
- **Better X reload fix (resolves the note left on this issue by Ticket 9b's final review), done generically, not just patched for these three buttons:**
  - New `ButtonData.count_seed_source: String` field (default `""`). When non-empty, `button_action.gd::set_data()` seeds `_purchase_count` from the named `GameState` field ONCE at creation time — different from `tier_source` (which keeps a button's LABEL continuously synced via a live signal) and `cost_count_source` (which overrides the COST formula's count on every calculation). `count_seed_source` only matters at the moment a button is created — after that, normal play keeps the button's own `_purchase_count` and `GameState`'s tier field in sync 1:1, the same way it already does today within a single session.
  - `set_data()` also gains the same `max_purchases`-reached hide check `_handle_click()` already has — without it, a button seeded at its max level (e.g. `better_chair_level=4` on load) would show up disabled-but-visible instead of correctly hidden, since only a *click* previously triggered that check.
  - `better_chair.tres`/`better_table.tres`/`better_bed.tres` set `count_seed_source` to `"better_chair_level"`/`"better_table_level"`/`"better_bed_level"` respectively.
- **General root-cause fix, explicitly called out in the issue as worth doing regardless of the specific Better X scenario:** `_handle_click()` now checks `EffectHandler.run_effect()`'s return value. On `false` (an effect legitimately failed post-cost-deduction — e.g. a defensive max-level guard firing), the already-deducted cost is refunded via a new `_refund_cost(cost)` helper, and the purchase-count increment / cooldown start / one-shot or max-purchases hide are all skipped entirely — the click is treated as if it never successfully happened, not as a successful purchase of nothing.
- **`SaveManager` auto-loads on `_ready()`** (satisfies "closing and reopening the game restores exact state" without needing a UI trigger) and autosaves via both a `Timer` (`Constants.AUTOSAVE_INTERVAL_SEC`) and `EventBus.upgrade_purchased`/`familiar_gained` connections (per the ticket's explicit instruction — both connected to a single zero-parameter handler, which Godot allows regardless of each signal's own parameter count).
- **`save_game()`/`export_save()` share a `_build_save_json()` helper; `load_game()`/`import_save()` share an `_apply_save_json()` helper** — DRY, and matches the ticket's own framing of import as "version-checked like any other load."
- **Standalone export writes to `user://exported_save.json`** and logs the resolved path via `LogManager.push()` (using `ProjectSettings.globalize_path()` so the logged path is something a player could actually go find) — no interactive native file-save dialog is built (that's real UI work, out of this session's confirmed scope, same reasoning as the Export/Import buttons).
- Direct-to-master. Final commit closes issue #11 (`Closes #11`).

---

### Task 1: Fix `GameState.from_dict()`, extend `Constants`

**Files:**
- Modify: `autoloads/game_state.gd`
- Modify: `data/balancing/constants.gd`

**Interfaces:**
- Produces: `Constants.SAVE_VERSION`, `Constants.AUTOSAVE_INTERVAL_SEC` — Task 4's `SaveManager` reads both.

- [ ] **Step 1: Fix the `is_blacked_out` line in `from_dict()`**

Change:
```gdscript
	is_blacked_out = data.get("is_blacked_out", false)
```
to:
```gdscript
	is_blacked_out = false
```

- [ ] **Step 2: Add the two new `Constants` fields**

Add to `data/balancing/constants.gd`, after the existing `BLACKOUT_RECOVERY_SEC`:

```gdscript
const SAVE_VERSION: int = 1
const AUTOSAVE_INTERVAL_SEC: float = 20.0
```

- [ ] **Step 3: Manually trace**

*A save file claiming `is_blacked_out: true` never restores blackout* — trace: `from_dict({"is_blacked_out": true, ...other fields...})` sets `is_blacked_out = false` unconditionally — the loaded value is never read, regardless of what the dict contains. Combined with `button_action.gd`'s blackout flag defaulting to `false` on scene load (unchanged from before) and no blackout overlay auto-showing on load, a player loading any save — even one written mid-blackout — starts in a normal, non-blacked-out state. ✓

- [ ] **Step 4: Verify with the real Godot binary**

Run: `cd /home/brian/Public/Programming/Godot/a-blue-orb && /home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64 --headless --quit 2>&1`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add autoloads/game_state.gd data/balancing/constants.gd
git commit -m "Never restore is_blacked_out from a save, add save constants (Ticket 11)

Resolves the soft-lock risk flagged by Ticket 10's final review — a
blackout is meant to be a short transient state, not something worth
persisting across a session boundary. Fixed at the single from_dict()
source rather than requiring every future caller to remember a
follow-up exit_blackout()."
```

---

### Task 2: Extend `ButtonData` and `button_action.gd`

**Files:**
- Modify: `data/button_data.gd`
- Modify: `scenes/ui/button_action.gd`

**Interfaces:**
- Produces: `ButtonData.count_seed_source` — Task 3's three `.tres` files set this.

- [ ] **Step 1: Add `count_seed_source` to `ButtonData`**

Add after the existing `cooldown_gate_condition` field:

```gdscript
@export var count_seed_source: String
```

- [ ] **Step 2: Seed `_purchase_count` and hide-if-maxed in `set_data()`**

Change:
```gdscript
func set_data(new_data: ButtonData) -> void:
	data = new_data
	_purchase_count = 0
	_is_on_cooldown = false
	_refresh()
```
to:
```gdscript
func set_data(new_data: ButtonData) -> void:
	data = new_data
	_purchase_count = _seed_purchase_count()
	_is_on_cooldown = false
	if data.max_purchases > 0 and _purchase_count >= data.max_purchases:
		hide()
		return
	_refresh()


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

- [ ] **Step 3: Respect `run_effect()`'s return value in `_handle_click()`, add a refund helper**

Change:
```gdscript
	EffectHandler.run_effect(data.effect_id)
	if data.tier_source == "":
		_purchase_count += 1
	_start_cooldown()
	if data.one_shot:
		one_shot_purchased.emit(data)
		hide()
		return
	if data.max_purchases > 0 and _purchase_count >= data.max_purchases:
		hide()
		return
	_refresh()


func _deduct_cost(cost: float) -> bool:
```
to:
```gdscript
	if not EffectHandler.run_effect(data.effect_id):
		_refund_cost(cost)
		return
	if data.tier_source == "":
		_purchase_count += 1
	_start_cooldown()
	if data.one_shot:
		one_shot_purchased.emit(data)
		hide()
		return
	if data.max_purchases > 0 and _purchase_count >= data.max_purchases:
		hide()
		return
	_refresh()


func _refund_cost(cost: float) -> void:
	if data.cost_type == "none" or cost <= 0.0:
		return
	match data.cost_type:
		"mana":
			GameState.add_mana(cost)
		"familiars":
			GameState.add_familiars(int(cost))


func _deduct_cost(cost: float) -> bool:
```

- [ ] **Step 4: Manually trace each fix**

1. *A Better Chair button created with `GameState.better_chair_level=4` correctly hides immediately, not after a wasted click* — trace: `set_data()` calls `_seed_purchase_count()` → `match "better_chair_level"` → returns `GameState.better_chair_level` = `4`. Then `data.max_purchases > 0 and _purchase_count >= data.max_purchases` → `4 > 0 and 4 >= 4` → `true` → `hide()`, function returns before ever calling `_refresh()`. No click needed to reach this state. ✓
2. *A Better Chair button created with `GameState.better_chair_level=2` (mid-progress) shows the correct next cost* — trace: `_purchase_count` seeds to `2`. `max_purchases` check: `2 >= 4` is `false`, falls through to `_refresh()`, which computes `label_index=min(2, 0)=0` (single-label array, unaffected) and cost via `_cost_count()` → `cost_count_source=""` → falls back to `_purchase_count=2` → `calculate_cost(2.0, "double", 0.0, 2) = 2.0 * 2^2 = 8.0` — the CORRECT next-level cost, not the base `2.0` a fresh `_purchase_count=0` would have wrongly shown. ✓
3. *A failed effect refunds cost and doesn't advance any state* — trace: a hypothetical button clicks with `cost_type="familiars", cost=2.0`; `_deduct_cost(2.0)` succeeds (`GameState.familiars` drops by 2); `EffectHandler.run_effect(...)` returns `false` (e.g. a defensive max-level guard fired unexpectedly). `_refund_cost(2.0)` matches `cost_type="familiars"` → `GameState.add_familiars(2)` — familiars restored to their pre-click value. Function returns immediately after — `_purchase_count` is NOT incremented, `_start_cooldown()` is NOT called, no hide/refresh happens. The click is fully inert except for the refund round-trip. ✓
4. *Every existing successful-purchase path is unaffected* — trace: for any effect that returns `true` (every effect function in the current codebase, in normal play), `not true` is `false`, so the new `if` branch's body never executes — the function falls through to the exact same `_purchase_count += 1` / `_start_cooldown()` / one-shot-or-max-purchases-or-refresh sequence as before this change. ✓

- [ ] **Step 5: Verify with the real Godot binary**

Run: `cd /home/brian/Public/Programming/Godot/a-blue-orb && /home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64 --headless --quit 2>&1`
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add data/button_data.gd scenes/ui/button_action.gd
git commit -m "Add count_seed_source, refund cost on failed effects (Ticket 11)

Resolves the Better X reload gap flagged by Ticket 9b's final review
(a button now correctly seeds its purchase count and hides itself
if already maxed, the moment it's created — not after a wasted
click) and its suggested root-cause fix (run_effect()'s return value
is no longer silently discarded; a failed effect refunds the
already-deducted cost instead of charging for nothing)."
```

---

### Task 3: Set `count_seed_source` on the three Better X `.tres` files

**Files:**
- Modify: `data/buttons/house/better_chair.tres`
- Modify: `data/buttons/house/better_table.tres`
- Modify: `data/buttons/house/better_bed.tres`

**Interfaces:**
- Consumes: `ButtonData.count_seed_source` (Task 2), `button_action.gd::_seed_purchase_count()`'s known string cases (Task 2).

- [ ] **Step 1: Add `count_seed_source` to each file**

Add this line to each `.tres` file's existing `[resource]` block (anywhere among the other field assignments):

`better_chair.tres`:
```
count_seed_source = "better_chair_level"
```

`better_table.tres`:
```
count_seed_source = "better_table_level"
```

`better_bed.tres`:
```
count_seed_source = "better_bed_level"
```

- [ ] **Step 2: Verify**

Run: `grep 'count_seed_source' data/buttons/house/better_chair.tres data/buttons/house/better_table.tres data/buttons/house/better_bed.tres`
Expected: each file shows exactly one line, matching its own tier field name (`better_chair_level`/`better_table_level`/`better_bed_level` respectively — no cross-wiring between the three).

- [ ] **Step 3: Verify with the real Godot binary**

Run: `cd /home/brian/Public/Programming/Godot/a-blue-orb && /home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64 --headless --quit 2>&1`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add data/buttons/house/better_chair.tres data/buttons/house/better_table.tres data/buttons/house/better_bed.tres
git commit -m "Wire count_seed_source on the three Better X buttons (Ticket 11)"
```

---

### Task 4: Create `SaveManager` (save/load/autosave), register

**Files:**
- Create: `autoloads/save_manager.gd`
- Modify: `project.godot`

**Interfaces:**
- Produces: `SaveManager.save_game()`, `SaveManager.load_game() -> bool` — Task 5 extends this same file with `export_save()`/`import_save()`.

- [ ] **Step 1: Write `autoloads/save_manager.gd`**

```gdscript
extends Node

var _autosave_timer: Timer


func _ready() -> void:
	load_game()
	EventBus.upgrade_purchased.connect(_on_purchase)
	EventBus.familiar_gained.connect(_on_purchase)
	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = Constants.AUTOSAVE_INTERVAL_SEC
	_autosave_timer.timeout.connect(save_game)
	add_child(_autosave_timer)
	_autosave_timer.start()


func _on_purchase() -> void:
	save_game()


func save_game() -> void:
	var file := FileAccess.open("user://save.json", FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: failed to open user://save.json for writing")
		return
	file.store_string(_build_save_json())
	file.close()


func load_game() -> bool:
	if not FileAccess.file_exists("user://save.json"):
		return false
	var file := FileAccess.open("user://save.json", FileAccess.READ)
	if file == null:
		push_error("SaveManager: failed to open user://save.json for reading")
		return false
	var text := file.get_as_text()
	file.close()
	return _apply_save_json(text)


func _build_save_json() -> String:
	return JSON.stringify({
		"save_version": Constants.SAVE_VERSION,
		"game_state": GameState.to_dict(),
	})


func _apply_save_json(text: String) -> bool:
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("SaveManager: save data is malformed, ignoring")
		return false
	var save_data: Dictionary = parsed
	if save_data.get("save_version") != Constants.SAVE_VERSION:
		push_warning("SaveManager: save_version mismatch, treating as no save found")
		return false
	var game_state_dict: Variant = save_data.get("game_state")
	if not (game_state_dict is Dictionary):
		push_warning("SaveManager: save data missing game_state, ignoring")
		return false
	GameState.from_dict(game_state_dict)
	return true
```

- [ ] **Step 2: Register `SaveManager` in `project.godot`**

Current `[autoload]` section (after Ticket 10, six entries: EventBus, GameState, LogManager, EffectHandler, InputGuard, RegenManager). Append a seventh line:

```
SaveManager="*res://autoloads/save_manager.gd"
```

- [ ] **Step 3: Verify**

Run: `tail -10 project.godot`
Expected: the seven autoload lines, `SaveManager` last.

- [ ] **Step 4: Manually trace**

1. *Fresh install, no save file, doesn't crash* — trace: `_ready()` calls `load_game()` → `FileAccess.file_exists("user://save.json")` is `false` on a machine with no prior save → returns `false` immediately, no file access attempted, no error. `GameState` stays at its own fresh defaults. ✓
2. *Autosave fires on both the timer and purchases* — trace: `_autosave_timer` fires every `20.0`s calling `save_game()` directly (connected to `timeout`). `EventBus.upgrade_purchased`/`familiar_gained` both connect to `_on_purchase()`, a zero-parameter function — Godot allows connecting a signal to a handler with fewer parameters than the signal provides (excess emitted arguments are simply not passed to a handler that doesn't declare them), so both signals correctly trigger a save regardless of their own differing parameter lists (`upgrade_id: String` vs. `new_total: int`). ✓
3. *`_apply_save_json` correctly rejects malformed/mismatched data without touching `GameState`* — trace: `_apply_save_json("not valid json")` → `JSON.parse_string(...)` returns `null` → `null is Dictionary` is `false` → `push_warning`, `return false`, `GameState.from_dict()` never called, no state change. `_apply_save_json('{"save_version": 999, "game_state": {}}')` → parses fine, but `999 != Constants.SAVE_VERSION (1)` → `push_warning`, `return false`, again `from_dict()` never called. ✓

- [ ] **Step 5: Verify with the real Godot binary**

Run: `cd /home/brian/Public/Programming/Godot/a-blue-orb && /home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64 --headless --quit 2>&1`
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add autoloads/save_manager.gd project.godot
git commit -m "Add SaveManager: save_game/load_game, autosave, auto-load on startup (Ticket 11)"
```

---

### Task 5: Add `export_save()`/`import_save()`

**Files:**
- Modify: `autoloads/save_manager.gd`

- [ ] **Step 1: Add the two functions**

Add after `load_game()`:

```gdscript
func export_save() -> void:
	var json_text := _build_save_json()
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(json_text.to_utf8_buffer(), "a-blue-orb-save.json", "application/json")
	else:
		var file := FileAccess.open("user://exported_save.json", FileAccess.WRITE)
		if file == null:
			push_error("SaveManager: failed to open export file for writing")
			return
		file.store_string(json_text)
		file.close()
		LogManager.push("save exported to %s" % ProjectSettings.globalize_path("user://exported_save.json"))


func import_save(file_data: String) -> bool:
	return _apply_save_json(file_data)
```

- [ ] **Step 2: Manually trace**

*`import_save` correctly reuses `load_game`'s validation, not a separate looser path* — trace: `import_save(file_data)` calls `_apply_save_json(file_data)` — the exact same function `load_game()` uses internally, so a malformed or version-mismatched import is rejected identically to a malformed/mismatched saved file, satisfying "version-checked like any other load." ✓

- [ ] **Step 3: Verify with the real Godot binary**

Run: `cd /home/brian/Public/Programming/Godot/a-blue-orb && /home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64 --headless --quit 2>&1`
Expected: no errors — this specifically confirms `JavaScriptBridge.download_buffer(...)` compiles cleanly even outside a web build (the call is gated behind `OS.has_feature("web")`, but the *reference* to `JavaScriptBridge` must still resolve at compile time regardless of which branch runs — `JavaScriptBridge` is a globally available singleton class in every Godot 4 build, its methods just no-op/warn outside an actual web export).

- [ ] **Step 4: Commit**

```bash
git add autoloads/save_manager.gd
git commit -m "Add SaveManager.export_save/import_save (Ticket 11)

export_save's web branch is implemented per Godot's documented API
but its actual browser-download behavior can't be verified without a
real web export build — flagged in the final report."
```

---

### Task 6: Real executed round-trip test, doc cross-check, commit closing the issue

**Files:** none (verification only, plus the closing commit doesn't need new file changes — it lands on the last real code commit or is a small standalone commit, whichever `git log`/`git status` indicates at the time, matching this project's established pattern from Ticket 9).

**Interfaces:**
- Consumes: everything from Tasks 1-5.

- [ ] **Step 1: Write and run a real headless integration test — not a manual trace**

This is pure data serialization logic, exactly the kind of thing worth actually executing rather than reasoning about on paper. Boot the real project (so autoloads register), drive `GameState` into a distinctive non-default state, save, reset, reload, and assert the state actually round-trips. Use a throwaway script, e.g.:

```gdscript
extends SceneTree

func _init():
	GameState.add_mana(42.0)
	GameState.add_familiars(3)
	GameState.mark_upgrade_purchased("chair")
	GameState.advance_better_chair_level()
	SaveManager.save_game()

	# Reset to fresh defaults, then reload and confirm restoration
	GameState.from_dict({})
	assert(GameState.mana == 0.0)
	SaveManager.load_game()
	assert(GameState.mana == 42.0)
	assert(GameState.familiars == 3)
	assert(GameState.has_upgrade("chair"))
	assert(GameState.better_chair_level == 1)

	# Export/import round-trip via the in-memory JSON, not the user:// file
	var exported := SaveManager._build_save_json()
	GameState.from_dict({})
	assert(GameState.mana == 0.0)
	var ok := SaveManager.import_save(exported)
	assert(ok)
	assert(GameState.mana == 42.0)

	# Malformed/mismatched-version import correctly rejected
	var bad_ok := SaveManager.import_save("not json")
	assert(not bad_ok)
	var mismatch_ok := SaveManager.import_save('{"save_version": 999, "game_state": {}}')
	assert(not mismatch_ok)

	# Blackout never restored from a save
	GameState.enter_blackout()
	SaveManager.save_game()
	GameState.exit_blackout()
	SaveManager.load_game()
	assert(not GameState.is_blacked_out)

	print("ALL SAVE/LOAD ROUND-TRIP ASSERTIONS PASSED")
	quit()
```

Run it via: `cd /home/brian/Public/Programming/Godot/a-blue-orb && /home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64 --headless --script <path-to-throwaway-script>.gd 2>&1`

Expected: `ALL SAVE/LOAD ROUND-TRIP ASSERTIONS PASSED` with no assertion failures. Note: running this script means `_ready()` on the real `SaveManager` autoload will ALSO fire (since `--script` mode with a `SceneTree`-extending script still initializes the project's autoloads unlike a bare `--script` check on an individual file) — if it does, that's fine and expected; it may call `load_game()` once before the test's own explicit calls, which doesn't invalidate any of the assertions above since they all explicitly set up their own state right before checking it. Delete the throwaway script file afterward — it's not part of the shipped project.

Record the actual output in the report — this is real executed evidence, more valuable than any manual trace in this whole ticket.

- [ ] **Step 2: Doc cross-check**

Read `docs/architecture.md` §3's `SaveManager` section and confirm every acceptance-criteria-relevant behavior matches what was actually built: `save_version` field present from day one (✓, `Constants.SAVE_VERSION`), single JSON blob to `user://save.json` (✓), export/import as a manual safety net (✓, functions exist even without UI). State explicitly what was checked.

- [ ] **Step 3: Final full-project headless check**

Run: `cd /home/brian/Public/Programming/Godot/a-blue-orb && /home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64 --headless --quit 2>&1`
Expected: no errors.

- [ ] **Step 4: Commit and push, closing the issue**

Check `git log`/`git status` first — if all of Tasks 1-5's commits are already made and this task's work is verification-only with no file changes, either amend the most recent unpushed commit to add `Closes #11` (matching this project's established pattern from Ticket 9) or, if that commit's already pushed, make a small standalone commit. Push either way.

```bash
git push
```

- [ ] **Step 5: Verify the issue closed**

Run: `gh issue view 11 --json state --jq .state`
Expected: `CLOSED`

- [ ] **Step 6: Report to the user**

State plainly: the save/load round-trip was verified with a REAL executed test (not manual trace) — quote the actual assertion-pass output. Flag clearly: (1) no Export/Import UI exists yet — the functions work, but nothing in the game currently calls them except autosave/auto-load; a minimal Save UI is a natural follow-up ticket. (2) The web export branch (`JavaScriptBridge.download_buffer`) compiles and is implemented per Godot's documented API, but its actual in-browser download behavior is completely unverified — this needs a real web export build and a real browser to confirm, neither of which exist in this environment. Recommend the user open the editor, play for a bit (buy something, gain a familiar), close and reopen the project, and confirm state persisted — the one thing that's now genuinely automatic and doesn't need a UI to observe. Ticket 12 (Polish / Cross-Check Pass) is next in strict ticket order — the last of the original 12 tickets — or issue #14 (Orb Channeling + Better Meal) if the user wants to keep building House tab content first.

---

## Self-Review Notes

- **Spec coverage:** all four of Ticket 11's original acceptance criteria are addressed — state restoration (Task 6's real round-trip test), `save_version` present from day one (Task 1/4), export producing a real file (Task 5, with the browser-specific half of this criterion explicitly flagged as unverifiable here), and version-mismatch rejection (Task 6's test explicitly covers this). Both flagged reload gaps (blackout soft-lock, Better X reconstruction) are resolved with their own dedicated tasks, not just noted.
- **No placeholders:** every function is a complete implementation. The two explicitly out-of-scope items (Save UI, real browser testing) are formally flagged for the user and as follow-up work, not silently dropped.
- **Type/name consistency:** `Constants.SAVE_VERSION`/`AUTOSAVE_INTERVAL_SEC` (Task 1) are used with identical names in Task 4's `SaveManager`. `ButtonData.count_seed_source` (Task 2) is consumed with an identical name in Task 2's own `button_action.gd` changes and set with identical values in Task 3's three `.tres` files, matching the exact `match` cases `_seed_purchase_count()` defines.

## Execution Handoff

Two execution options:

1. **Subagent-Driven (recommended)** - dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** - execute tasks in this session using `executing-plans`, batch execution with checkpoints.
