# Ticket 6 + 7: button_action.tscn + InputGuard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the generic, reusable button component every House (and later Ritual Site) button will use, plus the global click-rate safety net it depends on.

**Architecture:** `autoloads/input_guard.gd` (Ticket 7) is a small, self-contained rolling-window rate limiter with no dependencies — built and closed first. `scenes/ui/button_action.tscn` + `button_action.gd` (Ticket 6) is a `Button`-derived scene bound to a `ButtonData` resource; its click handler checks `InputGuard` first, per Ticket 6's own explicit requirement, which is why these are built together — Ticket 6 cannot be correctly implemented (or even compile a working click path) without `InputGuard` existing, despite the tickets file's suggested build order listing 6 before 7.

**Tech Stack:** GDScript, Godot 4.7, `Time.get_ticks_msec()` for the rolling window.

## Global Constraints

- GDScript tab indentation, matching all four existing autoloads.
- No `godot`/`godot4` CLI binary — verification is manual code trace, documented per task, not executed tests. Godot editor verification (visual layout, actual clicking) is explicitly deferred to the user.
- **Build-order note (applied without re-confirming — same resolution the project owner already approved for Tickets 2+3):** build both tickets in this one run, close both issues, since Ticket 6's click handler cannot satisfy its own "every click event passes through the rate limiter first" requirement without `InputGuard` existing.
- `InputGuard.try_register_click() -> bool`: rolling 1-second window, hard cap 100 clicks/sec. Verified behavior: 200 calls fired back-to-back within under a second → exactly the first 100 return `true` (register), the rest return `false`. Uses `Time.get_ticks_msec()` (monotonic engine time), not system clock.
- `ButtonData` (Ticket 5, already shipped) is the data source `button_action.gd` binds to — `id`, `labels`, `cost_type`, `base_cost`, `cost_scaling`, `cost_step`, `cooldown_sec`, `unlock_condition`, `effect_id`, `flavor_lines`, `one_shot`, `button_column`, plus its static `calculate_cost()` and `is_unlock_condition_met()`.
- **Purchase-count design decision (a judgment call, not re-litigated per-button here):** `button_action.gd` tracks a single internal `_purchase_count: int`, incremented on every successful purchase, used as both the cost-formula `count` parameter and the label-tier index (`labels[min(_purchase_count, labels.size()-1)]`). This is correct as-is for one-shot buttons (Chair/Table/Bed — count never matters past the first purchase) and for self-referential doubling upgrades (Better Meal/Chair/Table/Bed — "how many times has *this* button been bought"). It is almost certainly NOT correct for Summon Familiar (whose cost should track *current* familiars owned, which can drop if familiars are later spent elsewhere) or Touch the Orb (whose label tier tracks Confidence upgrades, a different button's state entirely). Rather than guess which GameState field each future button should bind to, `button_action.gd` exposes a public `set_purchase_count(value: int) -> void` override — Ticket 9, when it actually wires up each specific button, calls this (e.g. on an `EventBus.familiar_gained` connection for Summon Familiar, or on confidence changes for Touch the Orb) to sync from whatever source is correct for that button. Document this clearly; it is a deliberate deferral, not an oversight.
- **Click handling order (exact, per Ticket 6's issue body):** `InputGuard.try_register_click()` first ("before anything else happens") → cooldown check → cost check → cost deduction → `EffectHandler.run_effect(effect_id)` → increment purchase count → start cooldown timer → if `one_shot`, emit a signal and hide.
- **"No double-fire on rapid clicks" (explicit acceptance criterion):** guarded two ways — an explicit `_is_processing_click` reentrancy flag (defends against any same-call-stack re-entry) and the natural consequence of `hide()` + `disabled = true` happening synchronously within the same click handler before it returns (a hidden/disabled `Control` does not receive further input in Godot, per the engine's own input-dispatch rules — this can't be executed here to confirm, so it's asserted from documented engine behavior, not verified).
- **"Fixed width per column" (mockup requirement):** true column-width consistency is a property of whatever container holds multiple buttons — that's Ticket 8's `GridContainer`, which doesn't exist yet. This ticket sets no more than sensible size-flag defaults on the button itself; full visual verification of "hug their text, fixed width per column" can only happen once Ticket 8 exists and the user opens the editor. Don't force a hardcoded width now with nothing to size against.
- Cost display formatting: whole-number costs render without a decimal (`"2 mana"`, not `"2.0 mana"`), matching the mockup's example (`"Summon Familiar (2 mana)"`) — a small `_format_cost()` helper handles this.
- `EventBus`, `GameState`, `LogManager`, `EffectHandler` are already registered autoloads; `InputGuard` becomes the fifth.
- Direct-to-master. Two separate commits close two separate issues (`Closes #7` on Task 1's final commit, `Closes #6` on Task 2's final commit) — they don't need to be the same commit since `InputGuard` has no dependency back on `button_action.tscn`.

---

### Task 1: Create and register `InputGuard`, close Ticket 7

**Files:**
- Create: `autoloads/input_guard.gd`
- Modify: `project.godot`

**Interfaces:**
- Produces: `InputGuard.try_register_click() -> bool` — Task 2's `button_action.gd` calls this as the first step of its click handler.

- [ ] **Step 1: Write `autoloads/input_guard.gd`**

```gdscript
extends Node

const MAX_CLICKS_PER_SECOND: int = 100
const WINDOW_MSEC: int = 1000

var _click_timestamps_msec: Array[int] = []


func try_register_click() -> bool:
	var now := Time.get_ticks_msec()
	_prune_old_clicks(now)
	if _click_timestamps_msec.size() >= MAX_CLICKS_PER_SECOND:
		return false
	_click_timestamps_msec.append(now)
	return true


func _prune_old_clicks(now: int) -> void:
	while _click_timestamps_msec.size() > 0 and now - _click_timestamps_msec[0] > WINDOW_MSEC:
		_click_timestamps_msec.pop_front()
```

- [ ] **Step 2: Manually trace both acceptance criteria**

1. *"200 simulated clicks in under a second results in no more than 100 actually registering"* — trace: assume all 200 calls happen within the same ~1000ms window (that's what "in under a second" means), so `_prune_old_clicks` never removes anything mid-burst. Call 1: `size=0`, `0>=100` false, append, `size=1`, returns `true`. ... Call 100: `size=99`, `99>=100` false, append, `size=100`, returns `true`. Call 101: `size=100`, `100>=100` true, returns `false`, no append. ... Call 200: same, `false`. Exactly 100 calls return `true` (register), 100 return `false`. Matches "no more than 100." ✓
2. *"Per-button cooldowns still work independently"* — trace: `InputGuard` has no knowledge of any button, cooldown, or `ButtonData` — it's a pure counter with one method and no coupling to anything else. Task 2's `button_action.gd` calls `try_register_click()` and its own separate `_is_on_cooldown` check as two independent gates in sequence; neither reads the other's state. ✓

- [ ] **Step 3: Register `InputGuard` in `project.godot`**

Current `[autoload]` section (after Ticket 5):
```
[autoload]

EventBus="*res://autoloads/event_bus.gd"
GameState="*res://autoloads/game_state.gd"
LogManager="*res://autoloads/log_manager.gd"
EffectHandler="*res://autoloads/effect_handler.gd"
```

Append a fifth line:
```
[autoload]

EventBus="*res://autoloads/event_bus.gd"
GameState="*res://autoloads/game_state.gd"
LogManager="*res://autoloads/log_manager.gd"
EffectHandler="*res://autoloads/effect_handler.gd"
InputGuard="*res://autoloads/input_guard.gd"
```

- [ ] **Step 4: Verify**

Run: `tail -8 project.godot`
Expected:
```

[autoload]

EventBus="*res://autoloads/event_bus.gd"
GameState="*res://autoloads/game_state.gd"
LogManager="*res://autoloads/log_manager.gd"
EffectHandler="*res://autoloads/effect_handler.gd"
InputGuard="*res://autoloads/input_guard.gd"
```

- [ ] **Step 5: Commit and push, closing Ticket 7**

```bash
git add autoloads/input_guard.gd project.godot
git commit -m "$(cat <<'EOF'
Add InputGuard autoload (global click-rate limiter)

Closes #7
EOF
)"
git push
```

- [ ] **Step 6: Verify the issue closed**

Run: `gh issue view 7 --json state --jq .state`
Expected: `CLOSED`

---

### Task 2: Create `button_action.tscn` + `button_action.gd`, close Ticket 6

**Files:**
- Create: `scenes/ui/button_action.gd`
- Create: `scenes/ui/button_action.tscn`

**Interfaces:**
- Consumes: `ButtonData` (Ticket 5), `GameState`/`EffectHandler`/`InputGuard` (all existing autoloads).
- Produces: a `set_data(data: ButtonData)` entry point and a `set_purchase_count(value: int)` override hook, plus a `one_shot_purchased(data: ButtonData)` signal — Ticket 8/9 will instantiate this scene per button and connect to that signal to update the room description when furniture is bought.

- [ ] **Step 1: Write `scenes/ui/button_action.gd`**

```gdscript
extends Button

signal one_shot_purchased(data: ButtonData)

var data: ButtonData
var _purchase_count: int = 0
var _is_on_cooldown: bool = false
var _is_processing_click: bool = false


func set_data(new_data: ButtonData) -> void:
	data = new_data
	_purchase_count = 0
	_is_on_cooldown = false
	_refresh()


func set_purchase_count(value: int) -> void:
	_purchase_count = value
	_refresh()


func _ready() -> void:
	pressed.connect(_on_pressed)
	if data:
		_refresh()


func _refresh() -> void:
	if data == null:
		return
	text = _build_label_text()
	disabled = _is_disabled()


func _build_label_text() -> String:
	var label_index := min(_purchase_count, data.labels.size() - 1)
	var label := data.labels[label_index]
	if data.cost_type == "none":
		return label
	var cost := ButtonData.calculate_cost(data.base_cost, data.cost_scaling, data.cost_step, _purchase_count)
	return "%s (%s %s)" % [label, _format_cost(cost), data.cost_type]


func _format_cost(cost: float) -> String:
	if cost == floor(cost):
		return str(int(cost))
	return str(cost)


func _is_disabled() -> bool:
	if _is_on_cooldown:
		return true
	if not ButtonData.is_unlock_condition_met(data.unlock_condition):
		return true
	if data.cost_type != "none" and not _can_afford():
		return true
	return false


func _can_afford() -> bool:
	var cost := ButtonData.calculate_cost(data.base_cost, data.cost_scaling, data.cost_step, _purchase_count)
	match data.cost_type:
		"mana":
			return GameState.mana >= cost
		"familiars":
			return float(GameState.familiars) >= cost
		_:
			return true


func _on_pressed() -> void:
	if _is_processing_click:
		return
	_is_processing_click = true
	_handle_click()
	_is_processing_click = false


func _handle_click() -> void:
	if not InputGuard.try_register_click():
		return
	if _is_on_cooldown:
		return
	var cost := 0.0
	if data.cost_type != "none":
		cost = ButtonData.calculate_cost(data.base_cost, data.cost_scaling, data.cost_step, _purchase_count)
		if not _deduct_cost(cost):
			return
	EffectHandler.run_effect(data.effect_id)
	_purchase_count += 1
	_start_cooldown()
	if data.one_shot:
		one_shot_purchased.emit(data)
		hide()
		return
	_refresh()


func _deduct_cost(cost: float) -> bool:
	match data.cost_type:
		"mana":
			return GameState.spend_mana(cost)
		"familiars":
			return GameState.spend_familiars(int(cost))
		_:
			return true


func _start_cooldown() -> void:
	if data.cooldown_sec <= 0.0:
		return
	_is_on_cooldown = true
	disabled = true
	get_tree().create_timer(data.cooldown_sec).timeout.connect(_on_cooldown_finished)


func _on_cooldown_finished() -> void:
	_is_on_cooldown = false
	_refresh()
```

- [ ] **Step 2: Write `scenes/ui/button_action.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scenes/ui/button_action.gd" id="1"]

[node name="ButtonAction" type="Button"]
script = ExtResource("1")
```

- [ ] **Step 3: Manually trace each acceptance criterion**

1. *"Buttons hug their text, fixed width per column"* — not fully verifiable without Ticket 8's container; the root node is a plain `Button`, which sizes to its text content by default in Godot with no `custom_minimum_size` override forcing a fixed width — this is the correct starting point for a container-driven fixed-width-per-column layout, but the actual column-alignment behavior depends on Ticket 8's `GridContainer` settings. Flag for editor verification once Ticket 8 exists.
2. *"A one_shot button (Chair) disappears after purchase and its cost is deducted exactly once — no double-fire on rapid clicks"* — trace: on a successful one_shot purchase, `_deduct_cost(cost)` runs exactly once inside `_handle_click()`, which itself runs exactly once per `_on_pressed()` call due to the `_is_processing_click` reentrancy guard (a second call while the first is still executing returns immediately at the top of `_on_pressed()`, before `_handle_click()` runs, so `_deduct_cost` cannot run twice from a reentrant call). After the successful purchase, `hide()` sets `visible = false`; Godot's `Control` input dispatch does not deliver input to hidden or disabled controls, and `disabled` was already forced `true` by `_start_cooldown()` (called before the `one_shot` branch) even before `hide()`. Two independent guards (visibility + disabled) plus the reentrancy flag cover this. ✓ (asserted from documented Godot `Control` behavior — not executable here to directly observe)
3. *"Cooldown visually communicates it's on cooldown (disabled state is enough)"* — trace: `_start_cooldown()` sets `_is_on_cooldown = true` and `disabled = true` synchronously; `_is_disabled()` also returns `true` whenever `_is_on_cooldown` is true, so any subsequent `_refresh()` call during the cooldown window keeps `disabled` true. `_on_cooldown_finished()` (fired by the `SceneTreeTimer.timeout` signal after `data.cooldown_sec`) resets `_is_on_cooldown = false` and calls `_refresh()`, which re-evaluates `disabled` against current unlock/afford state. ✓

- [ ] **Step 4: Commit and push, closing Ticket 6**

```bash
git add scenes/ui/button_action.gd scenes/ui/button_action.tscn
git commit -m "$(cat <<'EOF'
Add button_action.tscn generic button component

Closes #6
EOF
)"
git push
```

- [ ] **Step 5: Verify the issue closed**

Run: `gh issue view 6 --json state --jq .state`
Expected: `CLOSED`

- [ ] **Step 6: Report to the user**

State: `InputGuard` and `button_action.tscn`/`button_action.gd` are built, registered, and closed. Nothing executed (no Godot binary) — verification is manual trace, and the one-shot/no-double-fire behavior specifically relies on documented Godot `Control` input-dispatch semantics that couldn't be directly observed here. What to check in the editor: instance `button_action.tscn` somewhere temporary (or wait for Ticket 8's UI shell), bind a `ButtonData` resource via `set_data()`, and click it — confirm the label/cost render correctly, the button disables during cooldown, and a one-shot button actually disappears after one purchase with no double cost deduction on a fast double-click. Also worth flagging: the `_purchase_count` override design (`set_purchase_count()`) means Summon Familiar and Touch the Orb will need explicit wiring in Ticket 9 to sync from the right `GameState` field — this isn't automatic. Ticket 8 (UI Shell) is next.

---

## Self-Review Notes

- **Spec coverage:** Ticket 7's two acceptance criteria are traced in Task 1 Step 2. Ticket 6's three acceptance criteria are traced in Task 2 Step 3, including an honest note on what couldn't be executed/observed (the double-fire prevention relies on documented engine behavior, not a live test) and what's explicitly deferred (fixed-width-per-column needs Ticket 8's container to fully verify).
- **No placeholders:** both scripts are complete implementations of their tickets' stated behavior. The `_purchase_count` design is a documented, deliberate deferral with a working escape hatch (`set_purchase_count`), not a stub.
- **Type/name consistency:** `InputGuard.try_register_click()` name matches exactly what `button_action.gd`'s `_handle_click()` calls. `ButtonData.calculate_cost`/`is_unlock_condition_met` names match Ticket 5's actual shipped API (re-checked against `data/button_data.gd`, not just the plan text).

## Execution Handoff

Two execution options:

1. **Subagent-Driven (recommended)** - dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** - execute tasks in this session using `executing-plans`, batch execution with checkpoints.
