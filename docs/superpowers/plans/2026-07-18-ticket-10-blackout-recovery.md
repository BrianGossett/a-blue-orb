# Ticket 10: Health Depletion / Blackout Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When health hits 0, fade to black, disable every button, wait a fixed recovery time, then grant +1 HP and resume — with `is_blacked_out` genuinely blocking further HP-spending, not just a cosmetic overlay.

**Architecture:** `blackout_overlay.tscn` (new, instanced as a top-level sibling in `main.tscn` so it renders above both tabs and the log panel) owns the whole state machine: listens for `EventBus.health_depleted`, shows/fades a full-screen black `ColorRect`, runs a `Timer` for `Constants.BLACKOUT_RECOVERY_SEC`, grants recovery HP, fades out, and fires `EventBus.blackout_ended`. `GameState` gains `enter_blackout()`/`exit_blackout()` methods and `spend_health()` becomes a no-op while blacked out (the authoritative guarantee, not just a UI-level one). `button_action.gd` and `RegenManager` (Ticket 9) both react to the same two `EventBus` signals to disable/pause themselves.

**Tech Stack:** GDScript, Godot 4.7. A working Godot 4.7.1 binary now exists at `/home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64` (found mid-Ticket-9) — every task below gets a real headless load check, not just manual trace, though gameplay sequencing (signal timing across a Timer) still needs manual trace since `--headless --quit` doesn't run the game loop.

## Global Constraints

- `GameState.is_blacked_out`, `EventBus.health_depleted`, and `EventBus.blackout_ended` already exist (Tickets 2 and 3) — this ticket wires them up, it doesn't create them.
- **`spend_health()` becomes the authoritative blocker**, not just disabled buttons: add `if is_blacked_out: return` as the first line. This satisfies the ticket's explicit "make sure `is_blacked_out` genuinely blocks all HP-spending actions" requirement at the state layer, not only the UI layer — protects against any future effect function or system that might call `spend_health()` during blackout, not just buttons a player could theoretically click through.
- **New `GameState` methods:** `enter_blackout() -> void` (sets `is_blacked_out = true`), `exit_blackout() -> void` (sets `is_blacked_out = false`). No new signal — `blackout_overlay.tscn` calls these directly as part of its own sequence; nothing else needs to react to the raw boolean flip beyond what `health_depleted`/`blackout_ended` already provide.
- **New `data/balancing/constants.gd`:** `class_name Constants extends RefCounted` holding `const BLACKOUT_RECOVERY_SEC: float = 5.0`, with a comment stating it's a balancing placeholder — per the ticket's own explicit instruction to include that comment (not a general house style choice; the ticket asks for it directly). `Constants.BLACKOUT_RECOVERY_SEC` is then referenceable from anywhere without an autoload, the same way `ButtonData.calculate_cost()` is called as a static-style member on its class.
- **`button_action.gd` gains a fourth disabling condition**, alongside cooldown/unlock/afford: `_is_blacked_out: bool`, set by listening to `EventBus.health_depleted` (true) and `EventBus.blackout_ended` (false) in `_ready()`, checked first in `_is_disabled()` and defensively re-checked at the top of `_handle_click()` (mirroring the existing cooldown check's belt-and-suspenders pattern) — this makes "no way to click through it early" true at both the visual-disabled layer and the click-handler layer, on top of `spend_health()`'s own guard.
- **`RegenManager` (Ticket 9) pauses during blackout** — resolves the note Ticket 9's final review left on this issue. `_on_tick()` gains `and not GameState.is_blacked_out` alongside its existing rate check. Decided here (not deferred further): passive regen ticking silently in the background while the blackout overlay is up would undermine the mechanic's meaning, and the two timers (60s regen vs. a `BLACKOUT_RECOVERY_SEC` placeholder of `5.0`s) barely interact in practice anyway, so gating is low-risk and more coherent than not gating.
- **`blackout_overlay.tscn` owns the full sequence**, not split across files: on `health_depleted` → `GameState.enter_blackout()`, show + fade in a black `ColorRect` (a small `Tween`, `0.3`s — cheap, matches the ticket's literal "fade to black" language, not over-engineering), start a one-shot `Timer` (`Constants.BLACKOUT_RECOVERY_SEC`). On timeout → `GameState.add_health(1.0)`, `GameState.exit_blackout()`, fade the `ColorRect` back out, then hide, then emit `EventBus.blackout_ended`.
- **Instanced in `main.tscn` as a new top-level child of `Main`, after `Root`** (Godot renders `Control` siblings in child order, later siblings on top — this is what makes it render above both the tab content and the log panel without needing a `CanvasLayer`).
- Direct-to-master. Final commit closes issue #10 (`Closes #10`).

---

### Task 1: Create `data/balancing/constants.gd`

**Files:**
- Create: `data/balancing/constants.gd`

**Interfaces:**
- Produces: `Constants.BLACKOUT_RECOVERY_SEC` — Task 4's `blackout_overlay.gd` reads this.

- [ ] **Step 1: Write the file**

```gdscript
class_name Constants
extends RefCounted

# Balancing placeholder — not a locked number, tune freely.
const BLACKOUT_RECOVERY_SEC: float = 5.0
```

- [ ] **Step 2: Verify with the real Godot binary**

Run: `/home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64 --headless --check-only --script data/balancing/constants.gd 2>&1`
Expected: no output after the version line (no `SCRIPT ERROR`/`ERROR` — this file has no autoload dependencies, so unlike most other scripts in this project, a standalone `--script` check is a fully valid check here, not a false positive).

- [ ] **Step 3: Commit**

```bash
git add data/balancing/constants.gd
git commit -m "Add Constants (Ticket 10)

BLACKOUT_RECOVERY_SEC placeholder, per the ticket's explicit request
for a comment flagging it as not a locked number."
```

---

### Task 2: Extend `GameState`

**Files:**
- Modify: `autoloads/game_state.gd`

**Interfaces:**
- Produces: `GameState.enter_blackout()`, `GameState.exit_blackout()` — Task 4's `blackout_overlay.gd` calls both.

- [ ] **Step 1: Guard `spend_health()`**

Change:
```gdscript
func spend_health(amount: float) -> void:
	health = max(health - amount, 0.0)
	EventBus.health_changed.emit(health, max_health)
	if health <= 0.0:
		EventBus.health_depleted.emit()
```
to:
```gdscript
func spend_health(amount: float) -> void:
	if is_blacked_out:
		return
	health = max(health - amount, 0.0)
	EventBus.health_changed.emit(health, max_health)
	if health <= 0.0:
		EventBus.health_depleted.emit()
```

- [ ] **Step 2: Add the two new methods**

Add after `advance_confidence_tier()` (or any existing location among the other `add_*`/`mark_*` methods — exact position doesn't matter, just keep them together with the other mutator methods, before `to_dict()`):

```gdscript
func enter_blackout() -> void:
	is_blacked_out = true


func exit_blackout() -> void:
	is_blacked_out = false
```

- [ ] **Step 3: Manually trace**

1. *`spend_health` is blocked during blackout, not before* — trace: health at `1.0`, `is_blacked_out=false`. Player clicks an action costing `5.0` HP: `spend_health(5.0)` — guard check `is_blacked_out` is false, so it proceeds: `health = max(1-5,0) = 0.0`, fires `health_changed`, then `health<=0` fires `health_depleted`. This is the call that TRIGGERS blackout — it must succeed, and it does, since `is_blacked_out` isn't set to `true` until `blackout_overlay.gd`'s handler (Task 4) calls `enter_blackout()` in response to that same `health_depleted` signal, which happens synchronously but AFTER this guard check already passed. Any subsequent `spend_health()` call while still blacked out now hits the guard and no-ops (no mutation, no signals). ✓
2. *Recovery clears the flag correctly* — trace: `exit_blackout()` sets `is_blacked_out = false`; the next `spend_health()` call proceeds normally again. ✓

- [ ] **Step 4: Verify with the real Godot binary**

Run: `cd /home/brian/Public/Programming/Godot/a-blue-orb && /home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64 --headless --quit 2>&1`
Expected: no `ERROR:`/`SCRIPT ERROR:` lines (this checks the whole project, correctly resolving `EventBus`/other autoloads — a standalone `--script` check on `game_state.gd` alone would show false-positive "Identifier not found" errors for `EventBus`, same as every prior ticket's experience with this file).

- [ ] **Step 5: Commit**

```bash
git add autoloads/game_state.gd
git commit -m "Guard spend_health against blackout, add enter/exit_blackout (Ticket 10)

is_blacked_out now genuinely blocks HP spending at the state layer,
not just via disabled buttons — protects any future caller of
spend_health, not only clicks."
```

---

### Task 3: Wire blackout into `RegenManager` and `button_action.gd`

**Files:**
- Modify: `autoloads/regen_manager.gd`
- Modify: `scenes/ui/button_action.gd`

**Interfaces:**
- Consumes: `EventBus.health_depleted`/`blackout_ended` (Tickets 2/3), `GameState.is_blacked_out`.

- [ ] **Step 1: Gate `RegenManager._on_tick()`**

Change:
```gdscript
func _on_tick() -> void:
	if GameState.health_regen_per_minute > 0.0:
		GameState.add_health(GameState.health_regen_per_minute)
```
to:
```gdscript
func _on_tick() -> void:
	if GameState.health_regen_per_minute > 0.0 and not GameState.is_blacked_out:
		GameState.add_health(GameState.health_regen_per_minute)
```

- [ ] **Step 2: Add blackout disabling to `button_action.gd`**

Add a new field near the top, alongside the existing `_is_on_cooldown`/`_is_processing_click` fields:
```gdscript
var _is_blacked_out: bool = false
```

Change `_ready()` from:
```gdscript
func _ready() -> void:
	pressed.connect(_on_pressed)
	_connect_tier_source()
	if data:
		_refresh()
```
to:
```gdscript
func _ready() -> void:
	pressed.connect(_on_pressed)
	_connect_tier_source()
	EventBus.health_depleted.connect(_on_health_depleted)
	EventBus.blackout_ended.connect(_on_blackout_ended)
	if data:
		_refresh()
```

Add two new handler functions:
```gdscript
func _on_health_depleted() -> void:
	_is_blacked_out = true
	_refresh()


func _on_blackout_ended() -> void:
	_is_blacked_out = false
	_refresh()
```

Change `_is_disabled()` from:
```gdscript
func _is_disabled() -> bool:
	if _is_on_cooldown:
		return true
```
to:
```gdscript
func _is_disabled() -> bool:
	if _is_blacked_out:
		return true
	if _is_on_cooldown:
		return true
```

Change `_handle_click()`'s opening guard from:
```gdscript
func _handle_click() -> void:
	if not InputGuard.try_register_click():
		return
	if _is_on_cooldown:
		return
```
to:
```gdscript
func _handle_click() -> void:
	if not InputGuard.try_register_click():
		return
	if _is_blacked_out:
		return
	if _is_on_cooldown:
		return
```

- [ ] **Step 3: Manually trace**

1. *Regen pauses during blackout* — trace: `health_regen_per_minute=1.0`, `is_blacked_out=true` (mid-blackout): `_on_tick()`'s condition `1.0 > 0.0 and not true` = `1.0 > 0.0 and false` = `false` → `add_health` not called, health stays at `0.0` (or wherever the blackout left it) until the overlay's own recovery grant. ✓
2. *Every button disables the instant blackout starts, independent of its own cooldown state* — trace: a button with `_is_on_cooldown=false` (fully available) receives `_on_health_depleted()` → `_is_blacked_out=true` → `_refresh()` → `_is_disabled()` now returns `true` at the first check, before even reaching the cooldown/unlock/afford checks — `disabled=true` regardless of any other state. Matches the ticket's explicit "every button_action.tscn instance goes disabled (regardless of its own cooldown state)." ✓
3. *No click-through even in the same frame the flag flips* — trace: `_handle_click()`'s `if _is_blacked_out: return` sits before the cost/effect logic, so even a click event that somehow reaches `_handle_click()` in the instant blackout begins is rejected before any `EffectHandler`/`GameState` mutation happens. ✓

- [ ] **Step 4: Verify with the real Godot binary**

Run: `cd /home/brian/Public/Programming/Godot/a-blue-orb && /home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64 --headless --quit 2>&1`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add autoloads/regen_manager.gd scenes/ui/button_action.gd
git commit -m "Pause regen and disable all buttons during blackout (Ticket 10)

Resolves the RegenManager/blackout interaction flagged on this issue
by Ticket 9's final review. Every button independently listens for
health_depleted/blackout_ended rather than requiring something to
enumerate and reach into every instance."
```

---

### Task 4: Create `blackout_overlay.tscn`, wire into `main.tscn`, close the issue

**Files:**
- Create: `scenes/ui/blackout_overlay.gd`
- Create: `scenes/ui/blackout_overlay.tscn`
- Modify: `scenes/main.tscn`

**Interfaces:**
- Consumes: `EventBus.health_depleted` (Tickets 2/3), `Constants.BLACKOUT_RECOVERY_SEC` (Task 1), `GameState.enter_blackout()`/`exit_blackout()`/`add_health()` (Task 2, Ticket 2).
- Produces: `EventBus.blackout_ended` emission — Task 3's `button_action.gd`/`RegenManager` already listen for it.

- [ ] **Step 1: Write `scenes/ui/blackout_overlay.gd`**

```gdscript
extends Control

const FADE_DURATION_SEC: float = 0.3

@onready var _fade_rect: ColorRect = $FadeRect

var _timer: Timer


func _ready() -> void:
	visible = false
	_fade_rect.modulate.a = 0.0
	EventBus.health_depleted.connect(_on_health_depleted)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = Constants.BLACKOUT_RECOVERY_SEC
	_timer.timeout.connect(_on_recovery_timeout)
	add_child(_timer)


func _on_health_depleted() -> void:
	if GameState.is_blacked_out:
		return
	GameState.enter_blackout()
	visible = true
	var tween := create_tween()
	tween.tween_property(_fade_rect, "modulate:a", 1.0, FADE_DURATION_SEC)
	_timer.start()


func _on_recovery_timeout() -> void:
	GameState.add_health(1.0)
	GameState.exit_blackout()
	var tween := create_tween()
	tween.tween_property(_fade_rect, "modulate:a", 0.0, FADE_DURATION_SEC)
	tween.tween_callback(func() -> void: visible = false)
	EventBus.blackout_ended.emit()
```

Note: `_on_health_depleted`'s `if GameState.is_blacked_out: return` guard is defensive redundancy — `spend_health()` (Task 2) already prevents `health_depleted` from firing again while blacked out, so this should be unreachable in practice, matching the same "belt and suspenders, confirmed harmless" pattern already used elsewhere in this codebase (e.g. `EffectHandler._effect_gain_confidence()`'s max-tier guard).

- [ ] **Step 2: Write `scenes/ui/blackout_overlay.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scenes/ui/blackout_overlay.gd" id="1"]

[node name="BlackoutOverlay" type="Control"]
anchor_right = 1.0
anchor_bottom = 1.0
mouse_filter = 2
script = ExtResource("1")

[node name="FadeRect" type="ColorRect" parent="."]
anchor_right = 1.0
anchor_bottom = 1.0
color = Color(0, 0, 0, 1)
mouse_filter = 2
```

(`mouse_filter = 2` is `Control.MOUSE_FILTER_IGNORE` — the overlay covers the full screen but must not itself block input when transparent/hidden. Buttons are independently disabled via Task 3's signal wiring, not by this overlay intercepting clicks, so it doesn't need to capture mouse input at all, even while visible.)

- [ ] **Step 3: Wire it into `scenes/main.tscn`**

Change the `[ext_resource]` block from:
```
[ext_resource type="Script" path="res://scenes/main.gd" id="1"]
[ext_resource type="PackedScene" path="res://scenes/ui/area_tab.tscn" id="2"]
[ext_resource type="Resource" path="res://data/areas/house.tres" id="3"]
[ext_resource type="PackedScene" path="res://scenes/ui/log_panel.tscn" id="4"]
```
to:
```
[ext_resource type="Script" path="res://scenes/main.gd" id="1"]
[ext_resource type="PackedScene" path="res://scenes/ui/area_tab.tscn" id="2"]
[ext_resource type="Resource" path="res://data/areas/house.tres" id="3"]
[ext_resource type="PackedScene" path="res://scenes/ui/log_panel.tscn" id="4"]
[ext_resource type="PackedScene" path="res://scenes/ui/blackout_overlay.tscn" id="5"]
```

And update `load_steps=5` to `load_steps=6` on the `[gd_scene]` line.

Add a new node at the end of the file, as a child of `Main` (a sibling of `Root`, added AFTER it so it renders on top):
```
[node name="BlackoutOverlay" parent="." instance=ExtResource("5")]
```

- [ ] **Step 4: Verify**

Run: `cat scenes/main.tscn`
Expected: `load_steps=6`, five `[ext_resource]` lines, and `BlackoutOverlay` as the last `[node]` entry, with `parent="."` (a direct child of `Main`, same level as `Root`, positioned after it).

Run: `cd /home/brian/Public/Programming/Godot/a-blue-orb && /home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64 --headless --quit 2>&1`
Expected: no errors — this is the most important check in this task, since it's the first real confirmation that `blackout_overlay.tscn`'s node tree, its `$FadeRect` path, and its `main.tscn` integration are all structurally sound.

- [ ] **Step 5: Manually trace the full sequence and both acceptance criteria**

1. *"Spending health down to exactly 0 triggers the full sequence with no way to click through it early"* — trace: health `5.0`, player clicks something costing `5.0`+ HP. `spend_health()` (not yet blacked out) clamps `health` to `0.0`, fires `health_changed` then `health_depleted`. `blackout_overlay.gd._on_health_depleted()` fires: `GameState.enter_blackout()` (now `is_blacked_out=true`), overlay becomes visible and fades in, recovery `Timer` starts. Simultaneously, every `button_action.gd` instance's `_on_health_depleted()` (Task 3) also fires from the same signal, setting `_is_blacked_out=true` and disabling itself. From this point, `spend_health()` no-ops (Task 2) AND every button is visually disabled AND `_handle_click()` bails early even if somehow invoked — three independent layers, matching "no way to click through it early." ✓
2. *"After recovery, the player has exactly 1 HP and normal play resumes, doesn't chain into an immediate soft-lock"* — trace: after `Constants.BLACKOUT_RECOVERY_SEC` (`5.0`s placeholder) elapses, `_on_recovery_timeout()` fires: `GameState.add_health(1.0)` → `health = min(0+1, max_health) = 1.0`; `GameState.exit_blackout()` → `is_blacked_out=false`; overlay fades out and hides; `EventBus.blackout_ended` emits, which every button's `_on_blackout_ended()` (Task 3) receives, clearing `_is_blacked_out` and re-enabling itself (subject to its own normal cooldown/unlock/afford checks — a button on cooldown stays disabled for that separate reason, correctly). If the player's very next click costs more than `1.0` HP, `spend_health()` proceeds normally (not blacked out anymore) and could trigger blackout again immediately — per the ticket's own acceptance criterion, this is expected and NOT a soft-lock, since actions costing `0` HP remain available (Summon Familiar, Eat Bread) to recover further without re-entering blackout. ✓

- [ ] **Step 6: Commit and push, closing the issue**

```bash
git add scenes/ui/blackout_overlay.gd scenes/ui/blackout_overlay.tscn scenes/main.tscn
git commit -m "$(cat <<'EOF'
Add blackout_overlay.tscn, wire into main.tscn

Closes #10
EOF
)"
git push
```

- [ ] **Step 7: Verify the issue closed**

Run: `gh issue view 10 --json state --jq .state`
Expected: `CLOSED`

- [ ] **Step 8: Report to the user**

State: the whole blackout sequence is built and the project loads clean under real headless execution (confirms every file structurally sound), but — same as always — the actual timing/fade/disable behavior across a real 5-second wait needs the user to trigger it in the editor to truly confirm (deplete health via repeated Touch the Orb clicks, watch the overlay fade in, confirm every button greys out, wait 5 seconds, confirm the overlay fades out and one button re-enables with 1 HP shown on the stat bar). Ticket 11 (Save System) is next.

---

## Self-Review Notes

- **Spec coverage:** both of Ticket 10's acceptance criteria are traced explicitly in Task 4 Step 5. The RegenManager/blackout note left by Ticket 9's review is resolved in Task 3, not just acknowledged.
- **No placeholders:** every function is complete. `BLACKOUT_RECOVERY_SEC = 5.0` is an intentional placeholder per the ticket's own explicit request (with the required comment), not an unrequested one.
- **Type/name consistency:** `GameState.enter_blackout`/`exit_blackout` (Task 2) are called with those exact names from `blackout_overlay.gd` (Task 4). `Constants.BLACKOUT_RECOVERY_SEC` (Task 1) is referenced with that exact name from Task 4. `_is_blacked_out` as a field name is used identically in both `button_action.gd` (Task 3) and is conceptually mirrored (not literally shared) by `blackout_overlay.gd`'s own state, which correctly derives from `GameState.is_blacked_out` rather than duplicating a separate flag.

## Execution Handoff

Two execution options:

1. **Subagent-Driven (recommended)** - dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** - execute tasks in this session using `executing-plans`, batch execution with checkpoints.
