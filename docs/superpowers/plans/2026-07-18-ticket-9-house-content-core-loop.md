# Ticket 9 (Core Loop): House Button Content Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the House tab fully playable end-to-end for the scope the project owner approved: touch the orb, summon familiars, eat, buy chair/table/bed, max out Confidence — with correct costs, correct unlock gates, correct room-description updates, and the two GameState gaps Ticket 5's review flagged (confidence's HP-cost growth, chair's passive regen) actually working. Orb Channeling, the four "Better X" doubling upgrades, and Better Bed's undefined effect are explicitly OUT of scope for this plan — filed as a separate follow-up issue instead of guessed at here.

**Architecture:** Ten `ButtonData` `.tres` files under `data/buttons/house/`, three new `ButtonData` fields to make them expressible as data (`tier_source`, `cost_count_source`, `room_description_fragment`), new `GameState` fields/methods for mechanics that didn't exist yet (food-eaten tracking, a growing per-click health cost, a regen rate, max-health growth), a new `RegenManager` autoload for the actual per-minute tick, extensions to `EffectHandler` (plus a real bug fix), and small extensions to `button_action.gd`/`area_tab.gd` to wire cross-button reactivity (a button's label tier following a *different* button's state) and room-description rebuilding.

**Tech Stack:** GDScript, Godot 4.7, hand-written `.tres` resource files (no Godot editor available to generate them).

## Global Constraints

- No `godot`/`godot4` CLI binary — verification is manual trace, not executed tests. This ticket is the first one that's actually meant to be *played*, so the final report must be explicit that a real playthrough in the editor is the only way to truly confirm this works, more so than any prior ticket.
- **Scope boundary (explicitly approved by the project owner):** Column 1 items 1-6 (touch_orb, summon_familiar, eat_bread, chair, table, bed) and Column 2 item 8 (confidence_1 through confidence_4) only. Orb Channeling (`orb_plinth.tres`), the four "Better X" upgrades, and Better Bed are OUT of scope — a separate GitHub issue tracks them, filed alongside this plan, not part of it.
- **Pre-existing bug fix (found while designing this plan, not by an automated test):** `EffectHandler._effect_add_chair()` (Ticket 5) calls `GameState.spend_familiars(1)` itself. `button_action.gd._handle_click()` (Ticket 6) *already* deducts cost generically (via `_deduct_cost()`) before calling `EffectHandler.run_effect()`. Wiring `chair.tres` into a real scene for the first time would have silently charged 2 familiars instead of 1. Fix: remove the self-deduction from `_effect_add_chair()` — effect functions apply only the *gain* side of an effect; cost deduction is `button_action.gd`'s job, done exactly once, for every `cost_type`. None of the other four existing effect functions have this bug (checked each one individually) — this fix and this constraint both apply to the two new effect functions this plan adds (`_effect_add_table`, `_effect_add_bed`) too.
- **New `GameState` fields/methods** (extending the already-shipped Ticket 2 file, same precedent as Tickets 5 and 8 already established):
  - `food_eaten_count: int = 0`, method `add_food_eaten() -> void` — drives chair/table's "after eating food Nx" unlock conditions. No matching `EventBus` signal (none needed by anything in this plan).
  - `orb_health_cost_per_click: float = 5.0` (mirrors `orb_mana_per_click`'s existing pattern exactly), method `add_orb_health_cost_per_click(amount: float) -> void`. Confidence adds a flat `+5.0` per tier (not tier-indexed like the mana bonus array) — verified against architecture doc §6: every confidence tier's HP-cost line reads the same "+5 HP cost", unlike the mana-gain column which is 3/5/7/10.
  - `food_heal_bonus: float = 0.0`, method `add_food_heal_bonus(amount: float) -> void` — Table's "+2 HP from food" effect. `_effect_eat_food()` heals `10.0 + food_heal_bonus`, not a flat `10.0`.
  - `health_regen_per_minute: float = 0.0`, method `add_health_regen_per_minute(amount: float) -> void` — Chair's "+1 HP regen/min" effect. Consumed by the new `RegenManager` autoload (Task 3), not by any effect function directly.
  - `add_max_health(amount: float) -> void` — Bed's "+20 max HP" effect. `max_health` currently has no mutator at all. This method must ALSO emit `EventBus.health_changed.emit(health, max_health)` (like every other method that changes a value `stat_bar.tscn` displays) so the stat bar updates immediately — none of the other new methods above need a signal (nothing in this plan's scope displays them live), but this one does, since `stat_bar.gd` already reads `max_health` for its "Health: X / Y" display.
  - `to_dict()`/`from_dict()` must include all four new fields (`food_eaten_count`, `orb_health_cost_per_click` — default `5.0` not `0.0`, `food_heal_bonus`, `health_regen_per_minute`), matching the existing pattern for every other field.
- **New `EventBus` signal:** `confidence_tier_changed(new_tier: int)`, added to the fixed 7-signal list from Ticket 3 (this is the second addition since Ticket 3 shipped — `house_tier_changed` already existed unused; this establishes the same "declared and emitted, not necessarily consumed by everything yet" pattern is fine). Emitted by `GameState.advance_confidence_tier()` (already exists — add one `EventBus.confidence_tier_changed.emit(confidence_tier)` line to it).
- **New `RegenManager` autoload** (`autoloads/regen_manager.gd`): owns a `Timer` that fires every 60 seconds and calls `GameState.add_health(GameState.health_regen_per_minute)` if that rate is above zero. Kept as its own autoload rather than folded into `GameState` — `GameState`'s established design is passive data behind validated setters, not an active ticking system; isolating the "side-effecting timer" into its own single-responsibility autoload matches the project's existing pattern (`EventBus`, `LogManager`, `EffectHandler`, `InputGuard` each do exactly one job).
- **Three new `ButtonData` fields** (extending the already-shipped Ticket 5 file, plus its `_get_stat_value`/`is_unlock_condition_met` static functions):
  - `tier_source: String` — when non-empty, the button's *label* tier index (and only the label tier — NOT its cost) is driven by an external stat instead of the button's own self-referential click count. `button_action.gd` matches this against a small, explicit set of known sources (`"confidence_tier"` → `EventBus.confidence_tier_changed`, `"house_tier"` → `EventBus.house_tier_changed`) and calls its own `set_purchase_count()` when that signal fires, plus once immediately on `_ready()` to correctly reflect a tier that was already non-zero before this button existed (matters once Ticket 11's save/load exists; harmless now). `touch_orb.tres` is the only user of this in this plan (`tier_source = "confidence_tier"`).
  - `cost_count_source: String` — same idea, but for the `count` parameter fed into `ButtonData.calculate_cost()`, independent of the label-tier index. Necessary because Summon Familiar's cost must track *live* `GameState.familiars` (dropping back down if familiars are later spent on Chair/Table/Bed, per the design doc's literal "1 mana... for each familiar owned"), while its *label* ("Make Something" → "Summon Familiar") must be a one-time, non-reverting flip driven by its own click count — these are two different pieces of state that would conflict if forced into the same counter. `summon_familiar.tres` sets `cost_count_source = "familiars"`; its `tier_source` stays empty (label uses the default self-referential counter, which is correct here since it only ever increments).
  - `room_description_fragment: String` — the noun phrase a one-shot furniture purchase adds to the room description (e.g. `"a chair"`). Empty for non-furniture buttons. Consumed by `area_tab.gd`'s new `_on_one_shot_purchased` handler (Task 7), not by `EffectHandler`.
- **`ButtonData.flavor_lines` stays unused/dead** in this plan, same as it's been since Ticket 5 — `EffectHandler`'s functions already push correct, working flavor text as hardcoded strings, and reconciling `flavor_lines` into that path (a Minor finding flagged in Ticket 5's final review) is a separate cleanup, not blocking core-loop playability. Every `.tres` in this plan sets `flavor_lines = []`.
- **`is_unlock_condition_met` gains compound-AND support** for Table's "after eating food 5x + 3 familiars" (two independent conditions): split on `"&&"` and require every sub-condition true, checked before the existing single-condition shapes. `table.tres`'s `unlock_condition = "food_eaten_count >= 5 && familiars >= 3"`.
- **`_get_stat_value` gains a `"food_eaten_count"` case.**
- **`button_action.gd`'s cost calculation switches from `_purchase_count` to a new `_cost_count()` helper** everywhere `calculate_cost` is invoked (label-cost display, `_can_afford`, `_handle_click`'s deduction) — `_cost_count()` returns `GameState.familiars` when `data.cost_count_source == "familiars"`, else falls back to the existing `_purchase_count` (unchanged behavior for every button that doesn't set this field, i.e. everything already shipped). Label-tier indexing (`_build_label_text`'s `label_index`) is UNCHANGED — still always `_purchase_count`, never `_cost_count()`.
- **`area_tab.gd` connects `one_shot_purchased` on every button it instantiates** (Ticket 8 built the signal but nothing consumed it yet), rebuilding the description as `"{base_description} The room has {fragments joined with commas and \"and\"}."` — matches the mockup's `"You are in a small room. The room has a chair, a bed, and a table."` exactly for the 3-furniture case, and degrades correctly for 0/1/2 items.
- **Explicitly deferred within this ticket's own scope (not asked about — low-risk, clearly reversible, doesn't block "no dead ends"):**
  - Eat Bread's cooldown is a flat 5 seconds. The design doc's "cooldown only recharges while familiars >= 1" nuance is not implemented — it would need `button_action.tscn`'s cooldown timer to become pausable against an arbitrary live condition, which is a bigger, more speculative change than this one pacing nuance justifies. A flat cooldown is *more* permissive, not less, so it cannot create a dead end.
  - Confidence buttons don't call `mark_upgrade_purchased()` — after Ticket 11 (Save System, not yet built) exists, reloading a save mid-game would make `confidence_1` (whose `unlock_condition` is unconditionally true) reappear as a clickable button even though it was already bought, since nothing but its own transient one-shot `hide()` state (lost on scene reload) currently prevents that. `confidence_2`/`3`/`4` are self-protecting via their `confidence_tier >= N` gates, which correctly persist. This is a real gap but only matters once save/load exists — flag it in this ticket's final report and in the new follow-up issue for Ticket 11's attention, don't build save-compatible one-shot tracking now for a save system that doesn't exist yet.
- Godot 4 `.tres` syntax conventions consistent with prior tickets (see Ticket 5/8 plans for the established pattern).
- Direct-to-master. Final commit closes issue #9 (`Closes #9`).

---

### Task 1: Extend `GameState`

**Files:**
- Modify: `autoloads/game_state.gd`

**Interfaces:**
- Produces: `add_food_eaten()`, `add_orb_health_cost_per_click(amount)`, `add_food_heal_bonus(amount)`, `add_health_regen_per_minute(amount)`, `add_max_health(amount)` — Task 6's `EffectHandler` calls these; Task 3's `RegenManager` reads `health_regen_per_minute` directly.

- [ ] **Step 1: Add the four new fields**

Add after the existing `var is_blacked_out: bool = false` line in `autoloads/game_state.gd`:

```gdscript
var food_eaten_count: int = 0
var orb_health_cost_per_click: float = 5.0
var food_heal_bonus: float = 0.0
var health_regen_per_minute: float = 0.0
```

- [ ] **Step 2: Add the five new methods**

Add after `advance_confidence_tier()` (added in the Ticket 5 plan), before `to_dict()`:

```gdscript
func add_food_eaten() -> void:
	food_eaten_count += 1


func add_orb_health_cost_per_click(amount: float) -> void:
	orb_health_cost_per_click += amount


func add_food_heal_bonus(amount: float) -> void:
	food_heal_bonus += amount


func add_health_regen_per_minute(amount: float) -> void:
	health_regen_per_minute += amount


func add_max_health(amount: float) -> void:
	max_health += amount
	EventBus.health_changed.emit(health, max_health)
```

- [ ] **Step 3: Update `to_dict()` and `from_dict()`**

In `to_dict()`, add four entries (insert after the existing `"orb_mana_per_second": orb_mana_per_second,` line, before `"is_blacked_out": is_blacked_out,`):

```gdscript
		"food_eaten_count": food_eaten_count,
		"orb_health_cost_per_click": orb_health_cost_per_click,
		"food_heal_bonus": food_heal_bonus,
		"health_regen_per_minute": health_regen_per_minute,
```

In `from_dict()`, add four matching lines (insert after the existing `orb_mana_per_second = data.get("orb_mana_per_second", 0.0)` line, before `is_blacked_out = data.get(...)`):

```gdscript
	food_eaten_count = data.get("food_eaten_count", 0)
	orb_health_cost_per_click = data.get("orb_health_cost_per_click", 5.0)
	food_heal_bonus = data.get("food_heal_bonus", 0.0)
	health_regen_per_minute = data.get("health_regen_per_minute", 0.0)
```

- [ ] **Step 4: Manually trace**

1. *`add_max_health` fires the right signal* — trace: `add_max_health(20.0)` on a fresh state: `max_health` goes `50.0 → 70.0`, then `EventBus.health_changed.emit(health, max_health)` fires with `(50.0, 70.0)` — `stat_bar.gd`'s existing `_on_health_changed` handler (Ticket 8) already listens to this exact signal and will correctly redraw `"Health: 50 / 70"`. ✓
2. *`to_dict()`/`from_dict()` round-trip the new fields* — trace: `to_dict()` on a state with `food_eaten_count=3, orb_health_cost_per_click=15.0, food_heal_bonus=2.0, health_regen_per_minute=1.0` produces a dict with all four keys; `from_dict()` on that same dict restores all four values exactly, and on a dict MISSING those keys (an old save from before this ticket), falls back to the correct fresh-state defaults (`0`, `5.0`, `0.0`, `0.0`) rather than crashing on a missing key. ✓

- [ ] **Step 5: Commit**

```bash
git add autoloads/game_state.gd
git commit -m "Extend GameState for Ticket 9 core-loop mechanics

Adds food_eaten_count, orb_health_cost_per_click, food_heal_bonus,
health_regen_per_minute, and add_max_health — none of these existed
in Ticket 2's original scope, but Chair/Table/Bed/Confidence's real
effects need them."
```

---

### Task 2: Add `EventBus.confidence_tier_changed` and wire it

**Files:**
- Modify: `autoloads/event_bus.gd`
- Modify: `autoloads/game_state.gd`

**Interfaces:**
- Produces: `EventBus.confidence_tier_changed(new_tier: int)` — Task 5's `button_action.gd` connects to this for `tier_source = "confidence_tier"`.

- [ ] **Step 1: Add the signal**

Add to `autoloads/event_bus.gd`, after the existing `signal house_tier_changed(new_tier: int)` line:

```gdscript
signal confidence_tier_changed(new_tier: int)
```

- [ ] **Step 2: Emit it from `advance_confidence_tier()`**

In `autoloads/game_state.gd`, change:
```gdscript
func advance_confidence_tier() -> void:
	confidence_tier = min(confidence_tier + 1, 4)
```
to:
```gdscript
func advance_confidence_tier() -> void:
	confidence_tier = min(confidence_tier + 1, 4)
	EventBus.confidence_tier_changed.emit(confidence_tier)
```

- [ ] **Step 3: Manually trace**

*Signal fires with the post-increment value* — trace: `advance_confidence_tier()` on `confidence_tier = 0` sets it to `1`, THEN emits `confidence_tier_changed(1)` — a listener receives the NEW tier, not the old one, matching `house_tier_changed`'s existing documented convention (`new_tier` parameter name) and what `button_action.gd`'s `set_purchase_count(new_tier)` (Task 5) needs to receive directly. ✓

- [ ] **Step 4: Commit**

```bash
git add autoloads/event_bus.gd autoloads/game_state.gd
git commit -m "Add EventBus.confidence_tier_changed, emit from GameState

touch_orb.tres's label needs to react to confidence upgrades, which
are a different button's state — this signal is how."
```

---

### Task 3: Create `RegenManager` autoload

**Files:**
- Create: `autoloads/regen_manager.gd`
- Modify: `project.godot`

**Interfaces:**
- Consumes: `GameState.health_regen_per_minute`, `GameState.add_health()`.

- [ ] **Step 1: Write `autoloads/regen_manager.gd`**

```gdscript
extends Node

const TICK_INTERVAL_SEC: float = 60.0

var _timer: Timer


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = TICK_INTERVAL_SEC
	_timer.timeout.connect(_on_tick)
	add_child(_timer)
	_timer.start()


func _on_tick() -> void:
	if GameState.health_regen_per_minute > 0.0:
		GameState.add_health(GameState.health_regen_per_minute)
```

- [ ] **Step 2: Register it in `project.godot`**

Current `[autoload]` section (after Ticket 8, five entries: EventBus, GameState, LogManager, EffectHandler, InputGuard). Append a sixth line:

```
RegenManager="*res://autoloads/regen_manager.gd"
```

- [ ] **Step 3: Verify**

Run: `tail -9 project.godot`
Expected: the six autoload lines, `RegenManager` last.

- [ ] **Step 4: Manually trace**

*Regen only applies when a rate is set* — trace: on a fresh state, `health_regen_per_minute = 0.0`; `_on_tick()`'s `if GameState.health_regen_per_minute > 0.0` guard is false, so `add_health()` is never called — no spurious healing before Chair is ever bought. Once Chair's effect calls `add_health_regen_per_minute(1.0)` (Task 6), every subsequent tick (60 real seconds apart) heals `1.0` HP, clamped to `max_health` by `add_health()`'s own existing clamp (Ticket 2) — no double-clamping logic needed here. ✓

- [ ] **Step 5: Commit**

```bash
git add autoloads/regen_manager.gd project.godot
git commit -m "Add RegenManager autoload (Ticket 9)

Owns the actual per-minute health-regen tick. Kept separate from
GameState, which stays passive data behind validated setters rather
than becoming an active ticking system."
```

---

### Task 4: Extend `ButtonData`

**Files:**
- Modify: `data/button_data.gd`

**Interfaces:**
- Produces: `tier_source`, `cost_count_source`, `room_description_fragment` fields; `is_unlock_condition_met` compound-AND support; `_get_stat_value("food_eaten_count")` — Task 5's `button_action.gd` and Task 8's `.tres` files depend on all of these.

- [ ] **Step 1: Add the three new fields**

Add after the existing `@export var sort_order: int` line:

```gdscript
@export var tier_source: String
@export var cost_count_source: String
@export var room_description_fragment: String
```

- [ ] **Step 2: Add compound-AND support to `is_unlock_condition_met`**

Change:
```gdscript
static func is_unlock_condition_met(condition: String) -> bool:
	if condition.is_empty():
		return true
	if condition.begins_with("has_upgrade("):
```
to:
```gdscript
static func is_unlock_condition_met(condition: String) -> bool:
	if condition.is_empty():
		return true
	if "&&" in condition:
		for sub_condition in condition.split("&&"):
			if not is_unlock_condition_met(sub_condition.strip_edges()):
				return false
		return true
	if condition.begins_with("has_upgrade("):
```

(The rest of the function is unchanged.)

- [ ] **Step 3: Add `food_eaten_count` to `_get_stat_value`**

Change:
```gdscript
static func _get_stat_value(stat_name: String) -> float:
	match stat_name:
		"mana":
			return GameState.mana
		"familiars":
			return float(GameState.familiars)
		"confidence_tier":
			return float(GameState.confidence_tier)
		"house_tier":
			return float(GameState.house_tier)
		_:
```
to:
```gdscript
static func _get_stat_value(stat_name: String) -> float:
	match stat_name:
		"mana":
			return GameState.mana
		"familiars":
			return float(GameState.familiars)
		"confidence_tier":
			return float(GameState.confidence_tier)
		"house_tier":
			return float(GameState.house_tier)
		"food_eaten_count":
			return float(GameState.food_eaten_count)
		_:
```

(The rest of the function, including the `-INF` fail-closed fallback, is unchanged.)

- [ ] **Step 4: Manually trace**

1. *Compound AND, both true* — trace: `is_unlock_condition_met("food_eaten_count >= 5 && familiars >= 3")` with `food_eaten_count=5, familiars=3`: splits into `["food_eaten_count >= 5", " familiars >= 3"]`, each recursively evaluated true (`5>=5`, `3>=3`), both true → returns `true`. ✓
2. *Compound AND, one false* — same condition with `familiars=2`: second sub-condition `2>=3` is false → the loop returns `false` immediately without evaluating further. ✓
3. *`food_eaten_count` stat lookup* — trace: `_get_stat_value("food_eaten_count")` returns `float(GameState.food_eaten_count)`, an existing, real field as of Task 1. ✓

- [ ] **Step 5: Commit**

```bash
git add data/button_data.gd
git commit -m "Extend ButtonData for Ticket 9 (tier_source, cost_count_source, room_description_fragment, compound unlock conditions)

tier_source and cost_count_source separate two different notions of
\"count\" that would otherwise conflict for Summon Familiar (whose
cost must track live familiars, but whose label must be a one-time
non-reverting flip). Compound unlock conditions are needed for
Table's food-count-AND-familiars gate."
```

---

### Task 5: Extend `button_action.gd`

**Files:**
- Modify: `scenes/ui/button_action.gd`

**Interfaces:**
- Consumes: `EventBus.confidence_tier_changed` (Task 2), `ButtonData.tier_source`/`cost_count_source` (Task 4).

- [ ] **Step 1: Add `_cost_count()` and use it everywhere `calculate_cost` is called**

Add a new function:
```gdscript
func _cost_count() -> int:
	match data.cost_count_source:
		"familiars":
			return GameState.familiars
		_:
			return _purchase_count
```

Change `_build_label_text()`'s cost line from:
```gdscript
	var cost := ButtonData.calculate_cost(data.base_cost, data.cost_scaling, data.cost_step, _purchase_count)
```
to:
```gdscript
	var cost := ButtonData.calculate_cost(data.base_cost, data.cost_scaling, data.cost_step, _cost_count())
```

Change `_can_afford()`'s cost line the same way (from `_purchase_count` to `_cost_count()`).

Change `_handle_click()`'s cost line the same way (from `_purchase_count` to `_cost_count()`).

Do NOT change `_build_label_text()`'s `label_index` line — it stays `min(_purchase_count, data.labels.size() - 1)`, unaffected by `_cost_count()`.

- [ ] **Step 2: Add tier-source wiring**

Change `_ready()` from:
```gdscript
func _ready() -> void:
	pressed.connect(_on_pressed)
	if data:
		_refresh()
```
to:
```gdscript
func _ready() -> void:
	pressed.connect(_on_pressed)
	_connect_tier_source()
	if data:
		_refresh()
```

Add two new functions:
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


func _on_tier_source_changed(new_tier: int) -> void:
	set_purchase_count(new_tier)
```

- [ ] **Step 3: Manually trace**

1. *Summon Familiar's cost tracks live familiars, its label doesn't revert* — trace: `summon_familiar.tres` has `cost_count_source = "familiars"`, `tier_source = ""`. After summoning 3 familiars then spending 1 on Chair: `_purchase_count = 3` (incremented on each of the 3 successful clicks, never decremented), `GameState.familiars = 2` (3 summoned, 1 spent). `_cost_count()` returns `GameState.familiars = 2` (since `cost_count_source == "familiars"`) → next summon costs `1 + 1*2 = 3` mana, correctly reflecting CURRENT familiars owned, not the button's own click history. Label index uses `_purchase_count = 3`, `min(3, 1) = 1` → still shows `labels[1] = "Summon Familiar"`, correctly NOT reverting even though familiars dropped. ✓
2. *Touch the Orb's label follows Confidence, not its own clicks* — trace: `touch_orb.tres` has `tier_source = "confidence_tier"`. On `_ready()`, `_connect_tier_source()` connects to `EventBus.confidence_tier_changed` AND immediately calls `set_purchase_count(GameState.confidence_tier)` (handles a tier that's already non-zero when this button is created). Every touch-the-orb click increments the button's OWN `_purchase_count` too (in `_handle_click()`, unconditionally) — but that's harmless here because `label_index` uses `min(_purchase_count, labels.size()-1)` which clamps at `4` (5 labels, indices 0-4) almost immediately regardless, and every `confidence_tier_changed` emission OVERWRITES `_purchase_count` back to the correct confidence-driven value via `set_purchase_count()`, so the two write paths don't fight in any way that produces a wrong displayed label. ✓
3. *No `tier_source`/`cost_count_source` set (every other existing button)* — trace: `data.tier_source == ""` → `_connect_tier_source()` returns immediately, no behavior change. `_cost_count()`'s `match` falls to `_:` → returns `_purchase_count`, identical to the pre-Task-5 behavior. Chair, Table, Bed, Confidence buttons (none of which set either field) are completely unaffected by this task. ✓

- [ ] **Step 4: Commit**

```bash
git add scenes/ui/button_action.gd
git commit -m "Extend button_action.gd for tier_source and cost_count_source (Ticket 9)

Lets a button's label-tier and its cost-scaling count be driven by
different (or external) sources, resolving a conflict where Summon
Familiar's cost needs to track live familiars-owned while its label
needs a one-time non-reverting flip."
```

---

### Task 6: Fix the chair double-deduction bug, extend `EffectHandler`

**Files:**
- Modify: `autoloads/effect_handler.gd`

**Interfaces:**
- Produces: `add_table`, `add_bed` effect_ids added to `run_effect()`'s dispatch — Task 8's `table.tres`/`bed.tres` reference these.

- [ ] **Step 1: Fix `_effect_add_chair()`'s double-deduction bug**

Change:
```gdscript
func _effect_add_chair() -> bool:
	if not GameState.spend_familiars(1):
		return false
	GameState.mark_upgrade_purchased("chair")
	# Instant/one-shot part only. The "+1 HP regen/min" passive part of
	# Chair's effect has no mechanism anywhere in the codebase yet — no
	# ticket in this batch builds a regen-over-time system.
	GameState.add_orb_mana_per_click(1.0)
	LogManager.push("you are no longer sitting on the floor.")
	return true
```
to:
```gdscript
func _effect_add_chair() -> bool:
	GameState.mark_upgrade_purchased("chair")
	GameState.add_orb_mana_per_click(1.0)
	GameState.add_health_regen_per_minute(1.0)
	LogManager.push("you are no longer sitting on the floor.")
	return true
```

(The familiar cost is already deducted generically by `button_action.gd` before this function ever runs — that's the bug fix. The "+1 HP regen/min" TODO comment is resolved by the new `add_health_regen_per_minute` call, now that `RegenManager` — Task 3 — exists to consume it.)

- [ ] **Step 2: Update `_effect_touch_orb()` to use the growing HP cost**

Change:
```gdscript
func _effect_touch_orb() -> bool:
	GameState.add_mana(GameState.orb_mana_per_click)
	# Fixed 5 HP cost — confidence's "+5 HP cost" growth per tier isn't
	# wired up yet; needs a new GameState field Ticket 9 should add
	# when it builds confidence_N.tres and touch_orb.tres for real.
	GameState.spend_health(5.0)
	LogManager.push("you gingerly touch the orb.")
	return true
```
to:
```gdscript
func _effect_touch_orb() -> bool:
	GameState.add_mana(GameState.orb_mana_per_click)
	GameState.spend_health(GameState.orb_health_cost_per_click)
	LogManager.push("you gingerly touch the orb.")
	return true
```

- [ ] **Step 3: Update `_effect_gain_confidence()` to also grow the HP cost**

Change:
```gdscript
func _effect_gain_confidence() -> bool:
	const CONFIDENCE_MANA_BONUS: Array[float] = [3.0, 5.0, 7.0, 10.0]
	var tier_index := GameState.confidence_tier
	if tier_index >= CONFIDENCE_MANA_BONUS.size():
		push_error("EffectHandler: confidence_tier already at max")
		return false
	GameState.add_orb_mana_per_click(CONFIDENCE_MANA_BONUS[tier_index])
	GameState.advance_confidence_tier()
	LogManager.push("you feel a swell of confidence.")
	return true
```
to:
```gdscript
func _effect_gain_confidence() -> bool:
	const CONFIDENCE_MANA_BONUS: Array[float] = [3.0, 5.0, 7.0, 10.0]
	const CONFIDENCE_HP_COST_INCREASE: float = 5.0
	var tier_index := GameState.confidence_tier
	if tier_index >= CONFIDENCE_MANA_BONUS.size():
		push_error("EffectHandler: confidence_tier already at max")
		return false
	GameState.add_orb_mana_per_click(CONFIDENCE_MANA_BONUS[tier_index])
	GameState.add_orb_health_cost_per_click(CONFIDENCE_HP_COST_INCREASE)
	GameState.advance_confidence_tier()
	LogManager.push("you feel a swell of confidence.")
	return true
```

- [ ] **Step 4: Update `_effect_eat_food()` to use the food heal bonus**

Change:
```gdscript
func _effect_eat_food() -> bool:
	GameState.add_health(10.0)
	LogManager.push("you eat the bread. it is simple, but satisfying.")
	return true
```
to:
```gdscript
func _effect_eat_food() -> bool:
	GameState.add_health(10.0 + GameState.food_heal_bonus)
	GameState.add_food_eaten()
	LogManager.push("you eat the bread. it is simple, but satisfying.")
	return true
```

- [ ] **Step 5: Add `_effect_add_table()` and `_effect_add_bed()`**

Add after `_effect_add_chair()`:

```gdscript
func _effect_add_table() -> bool:
	GameState.mark_upgrade_purchased("table")
	GameState.add_food_heal_bonus(2.0)
	GameState.add_orb_mana_per_click(2.0)
	LogManager.push("you now have something to eat on.")
	return true


func _effect_add_bed() -> bool:
	GameState.mark_upgrade_purchased("bed")
	GameState.add_max_health(20.0)
	GameState.add_orb_mana_per_click(3.0)
	LogManager.push("you now have somewhere to rest.")
	return true
```

- [ ] **Step 6: Add the two new effect_ids to `run_effect()`'s dispatch**

Change:
```gdscript
func run_effect(effect_id: String) -> bool:
	match effect_id:
		"touch_orb":
			return _effect_touch_orb()
		"summon_familiar":
			return _effect_summon_familiar()
		"eat_food":
			return _effect_eat_food()
		"gain_confidence":
			return _effect_gain_confidence()
		"add_chair":
			return _effect_add_chair()
		_:
```
to:
```gdscript
func run_effect(effect_id: String) -> bool:
	match effect_id:
		"touch_orb":
			return _effect_touch_orb()
		"summon_familiar":
			return _effect_summon_familiar()
		"eat_food":
			return _effect_eat_food()
		"gain_confidence":
			return _effect_gain_confidence()
		"add_chair":
			return _effect_add_chair()
		"add_table":
			return _effect_add_table()
		"add_bed":
			return _effect_add_bed()
		_:
```

- [ ] **Step 7: Manually trace**

1. *Chair no longer double-spends* — trace: clicking a `chair.tres`-bound button with `cost_type="familiars", base_cost=1.0`: `button_action.gd._handle_click()` computes `cost=1.0`, calls `_deduct_cost(1.0)` → `GameState.spend_familiars(1)` (familiars `N → N-1`), THEN calls `EffectHandler.run_effect("add_chair")` → `_effect_add_chair()` now touches ONLY `mark_upgrade_purchased`/`add_orb_mana_per_click`/`add_health_regen_per_minute` — no second `spend_familiars` call. Total familiars spent: exactly `1`. ✓ (Previously this would have spent `2`.)
2. *Confidence's HP cost matches the required acceptance criterion* — trace (already partially covered in Task 2's design, re-verified here against the actual code): fresh state `orb_health_cost_per_click = 5.0`. Four `_effect_gain_confidence()` calls (via four separate confidence_N.tres purchases, Task 8) each add `5.0` → after all four: `5.0 + 5.0*4 = 25.0`. `_effect_touch_orb()` spends `GameState.orb_health_cost_per_click`, so at max confidence, touching the orb costs exactly `25.0` HP. ✓ Matches Ticket 9's acceptance criterion exactly ("at Confidence 4, touching the orb costs 25 HP, not 5").
3. *Table's food-heal bonus applies to subsequent eats* — trace: before Table is bought, `_effect_eat_food()` heals `10.0 + 0.0 = 10.0`. After `_effect_add_table()` calls `add_food_heal_bonus(2.0)`, `food_heal_bonus = 2.0`, so the NEXT `_effect_eat_food()` call heals `10.0 + 2.0 = 12.0`. ✓
4. *Bed's max-health growth is visible* — already traced in Task 1 Step 4.1; re-confirmed here that `_effect_add_bed()` is the actual caller in the real flow.

- [ ] **Step 8: Commit**

```bash
git add autoloads/effect_handler.gd
git commit -m "Fix chair double-deduction bug, extend EffectHandler (Ticket 9)

_effect_add_chair() was spending familiars itself on top of
button_action.gd's already-generic cost deduction — a latent bug
from Ticket 5 that only surfaced now that chair.tres is being wired
into a real scene for the first time. Also wires confidence's HP-cost
growth, chair's regen rate, table's food-heal bonus, and adds
_effect_add_table/_effect_add_bed."
```

---

### Task 7: Extend `area_tab.gd` for room-description rebuilding

**Files:**
- Modify: `scenes/ui/area_tab.gd`

**Interfaces:**
- Consumes: `button_action.gd`'s `one_shot_purchased(data: ButtonData)` signal (Ticket 6, unused until now), `ButtonData.room_description_fragment` (Task 4).

- [ ] **Step 1: Connect the signal on every instantiated button**

In `_load_buttons()`, change:
```gdscript
		var instance: Button = BUTTON_ACTION_SCENE.instantiate()
		instance.set_data(button_data)
		if button_data.button_column == 1:
			_column_actions.add_child(instance)
		else:
			_column_upgrades.add_child(instance)
```
to:
```gdscript
		var instance: Button = BUTTON_ACTION_SCENE.instantiate()
		instance.set_data(button_data)
		instance.one_shot_purchased.connect(_on_one_shot_purchased)
		if button_data.button_column == 1:
			_column_actions.add_child(instance)
		else:
			_column_upgrades.add_child(instance)
```

(`Button` doesn't declare `one_shot_purchased` — but `instance` is actually a `button_action.tscn` instance whose root script IS `button_action.gd`, which does declare it. The static type annotation `Button` on `instance` is Ticket 6's existing choice reflecting the SCENE's root node type; Godot resolves the signal at runtime against the actual attached script, so this connects correctly despite the narrower static type. This mirrors how `instance.set_data(...)` on the very next line already works today.)

- [ ] **Step 2: Add the description-rebuilding logic**

Add a new field near the top of the file, after the existing `@onready` declarations:

```gdscript
var _furniture_fragments: Array[String] = []
```

Add two new functions:

```gdscript
func _on_one_shot_purchased(purchased_data: ButtonData) -> void:
	if purchased_data.room_description_fragment == "":
		return
	_furniture_fragments.append(purchased_data.room_description_fragment)
	_rebuild_description()


func _rebuild_description() -> void:
	if _furniture_fragments.is_empty():
		_description_label.text = area_data.base_description
		return
	_description_label.text = "%s The room has %s." % [area_data.base_description, _join_with_commas_and(_furniture_fragments)]


func _join_with_commas_and(items: Array[String]) -> String:
	if items.size() == 1:
		return items[0]
	if items.size() == 2:
		return "%s and %s" % [items[0], items[1]]
	var all_but_last := items.slice(0, items.size() - 1)
	return "%s, and %s" % [", ".join(all_but_last), items[items.size() - 1]]
```

- [ ] **Step 3: Manually trace against Ticket 9's room-description acceptance criterion**

*"One-shot buttons update the room description text when purchased"* — trace, purchasing chair then bed then table in that order (their `room_description_fragment`s: `"a chair"`, `"a bed"`, `"a table"`):
1. Chair purchased: `_furniture_fragments = ["a chair"]` → `_join_with_commas_and(["a chair"])` returns `"a chair"` (size 1 branch) → description becomes `"You are in a small room. The room has a chair."`
2. Bed purchased: `_furniture_fragments = ["a chair", "a bed"]` → size-2 branch → `"a chair and a bed"` → `"You are in a small room. The room has a chair and a bed."`
3. Table purchased: `_furniture_fragments = ["a chair", "a bed", "a table"]` → size-3+ branch → `all_but_last = ["a chair", "a bed"]`, joined `"a chair, a bed"`, then `"a chair, a bed, and a table"` → `"You are in a small room. The room has a chair, a bed, and a table."`

Matches the mockup's exact example text for the 3-furniture case. ✓ Non-furniture one-shot purchases (none in this ticket's scope, but confidence_N.tres IS `one_shot=true` with an empty `room_description_fragment`) correctly no-op via the early `return` in `_on_one_shot_purchased`. ✓

- [ ] **Step 4: Commit**

```bash
git add scenes/ui/area_tab.gd
git commit -m "Wire room-description rebuilding on one-shot purchases (Ticket 9)

button_action.tscn's one_shot_purchased signal (Ticket 8) had no
listener until now. Produces the exact mockup phrasing for 1, 2, and
3+ furniture items."
```

---

### Task 8: Create the ten `ButtonData` `.tres` files

**Files:**
- Create: `data/buttons/house/touch_orb.tres`
- Create: `data/buttons/house/summon_familiar.tres`
- Create: `data/buttons/house/eat_bread.tres`
- Create: `data/buttons/house/chair.tres`
- Create: `data/buttons/house/table.tres`
- Create: `data/buttons/house/bed.tres`
- Create: `data/buttons/house/confidence_1.tres`
- Create: `data/buttons/house/confidence_2.tres`
- Create: `data/buttons/house/confidence_3.tres`
- Create: `data/buttons/house/confidence_4.tres`

**Interfaces:**
- Consumes: `ButtonData` (Task 4), matching `effect_id`s from `EffectHandler` (Task 6).

Every file uses this exact header/footer pattern (matching `data/areas/house.tres`'s established convention from Ticket 8, adapted for `ButtonData`):
```
[gd_resource type="ButtonData" load_steps=2 format=3]

[ext_resource type="Script" path="res://data/button_data.gd" id="1"]

[resource]
script = ExtResource("1")
<fields>
```

- [ ] **Step 1: `data/buttons/house/touch_orb.tres`**

```
[gd_resource type="ButtonData" load_steps=2 format=3]

[ext_resource type="Script" path="res://data/button_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "touch_orb"
labels = Array[String](["Gingerly touch the orb", "Carefully touch the orb", "Place your hand on the orb", "Place both hands on the orb", "Hold the orb for a moment"])
cost_type = "none"
base_cost = 0.0
cost_scaling = "fixed"
cost_step = 0.0
cooldown_sec = 1.0
unlock_condition = ""
effect_id = "touch_orb"
flavor_lines = Array[String]([])
one_shot = false
button_column = 1
sort_order = 1
tier_source = "confidence_tier"
cost_count_source = ""
room_description_fragment = ""
```

- [ ] **Step 2: `data/buttons/house/summon_familiar.tres`**

```
[gd_resource type="ButtonData" load_steps=2 format=3]

[ext_resource type="Script" path="res://data/button_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "summon_familiar"
labels = Array[String](["Make Something", "Summon Familiar"])
cost_type = "mana"
base_cost = 1.0
cost_scaling = "linear"
cost_step = 1.0
cooldown_sec = 0.0
unlock_condition = ""
effect_id = "summon_familiar"
flavor_lines = Array[String]([])
one_shot = false
button_column = 1
sort_order = 2
tier_source = ""
cost_count_source = "familiars"
room_description_fragment = ""
```

- [ ] **Step 3: `data/buttons/house/eat_bread.tres`**

```
[gd_resource type="ButtonData" load_steps=2 format=3]

[ext_resource type="Script" path="res://data/button_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "eat_bread"
labels = Array[String](["Eat Bread"])
cost_type = "none"
base_cost = 0.0
cost_scaling = "fixed"
cost_step = 0.0
cooldown_sec = 5.0
unlock_condition = "familiars >= 1"
effect_id = "eat_food"
flavor_lines = Array[String]([])
one_shot = false
button_column = 1
sort_order = 3
tier_source = ""
cost_count_source = ""
room_description_fragment = ""
```

- [ ] **Step 4: `data/buttons/house/chair.tres`**

```
[gd_resource type="ButtonData" load_steps=2 format=3]

[ext_resource type="Script" path="res://data/button_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "chair"
labels = Array[String](["Stop Sitting on the Floor"])
cost_type = "familiars"
base_cost = 1.0
cost_scaling = "fixed"
cost_step = 0.0
cooldown_sec = 0.0
unlock_condition = "food_eaten_count >= 2"
effect_id = "add_chair"
flavor_lines = Array[String]([])
one_shot = true
button_column = 1
sort_order = 4
tier_source = ""
cost_count_source = ""
room_description_fragment = "a chair"
```

- [ ] **Step 5: `data/buttons/house/table.tres`**

```
[gd_resource type="ButtonData" load_steps=2 format=3]

[ext_resource type="Script" path="res://data/button_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "table"
labels = Array[String](["Something to Eat On"])
cost_type = "familiars"
base_cost = 2.0
cost_scaling = "fixed"
cost_step = 0.0
cooldown_sec = 0.0
unlock_condition = "food_eaten_count >= 5 && familiars >= 3"
effect_id = "add_table"
flavor_lines = Array[String]([])
one_shot = true
button_column = 1
sort_order = 5
tier_source = ""
cost_count_source = ""
room_description_fragment = "a table"
```

- [ ] **Step 6: `data/buttons/house/bed.tres`**

```
[gd_resource type="ButtonData" load_steps=2 format=3]

[ext_resource type="Script" path="res://data/button_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "bed"
labels = Array[String](["Somewhere to Rest"])
cost_type = "familiars"
base_cost = 4.0
cost_scaling = "fixed"
cost_step = 0.0
cooldown_sec = 0.0
unlock_condition = "familiars >= 5"
effect_id = "add_bed"
flavor_lines = Array[String]([])
one_shot = true
button_column = 1
sort_order = 6
tier_source = ""
cost_count_source = ""
room_description_fragment = "a bed"
```

- [ ] **Step 7: `data/buttons/house/confidence_1.tres`**

```
[gd_resource type="ButtonData" load_steps=2 format=3]

[ext_resource type="Script" path="res://data/button_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "confidence_1"
labels = Array[String](["Gain confidence"])
cost_type = "mana"
base_cost = 10.0
cost_scaling = "fixed"
cost_step = 0.0
cooldown_sec = 0.0
unlock_condition = "confidence_tier >= 0"
effect_id = "gain_confidence"
flavor_lines = Array[String]([])
one_shot = true
button_column = 2
sort_order = 1
tier_source = ""
cost_count_source = ""
room_description_fragment = ""
```

- [ ] **Step 8: `data/buttons/house/confidence_2.tres`**

```
[gd_resource type="ButtonData" load_steps=2 format=3]

[ext_resource type="Script" path="res://data/button_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "confidence_2"
labels = Array[String](["Gain confidence 2"])
cost_type = "mana"
base_cost = 20.0
cost_scaling = "fixed"
cost_step = 0.0
cooldown_sec = 0.0
unlock_condition = "confidence_tier >= 1"
effect_id = "gain_confidence"
flavor_lines = Array[String]([])
one_shot = true
button_column = 2
sort_order = 2
tier_source = ""
cost_count_source = ""
room_description_fragment = ""
```

- [ ] **Step 9: `data/buttons/house/confidence_3.tres`**

```
[gd_resource type="ButtonData" load_steps=2 format=3]

[ext_resource type="Script" path="res://data/button_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "confidence_3"
labels = Array[String](["Gain confidence 3"])
cost_type = "mana"
base_cost = 50.0
cost_scaling = "fixed"
cost_step = 0.0
cooldown_sec = 0.0
unlock_condition = "confidence_tier >= 2"
effect_id = "gain_confidence"
flavor_lines = Array[String]([])
one_shot = true
button_column = 2
sort_order = 3
tier_source = ""
cost_count_source = ""
room_description_fragment = ""
```

- [ ] **Step 10: `data/buttons/house/confidence_4.tres`**

```
[gd_resource type="ButtonData" load_steps=2 format=3]

[ext_resource type="Script" path="res://data/button_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "confidence_4"
labels = Array[String](["Gain confidence 4"])
cost_type = "mana"
base_cost = 100.0
cost_scaling = "fixed"
cost_step = 0.0
cooldown_sec = 0.0
unlock_condition = "confidence_tier >= 3"
effect_id = "gain_confidence"
flavor_lines = Array[String]([])
one_shot = true
button_column = 2
sort_order = 4
tier_source = ""
cost_count_source = ""
room_description_fragment = ""
```

- [ ] **Step 11: Verify all ten files**

Run: `ls data/buttons/house/*.tres | wc -l`
Expected: `10`

Run: `grep -L 'type="ButtonData"' data/buttons/house/*.tres`
Expected: no output (every file has the correct header).

Run: `for f in data/buttons/house/*.tres; do echo "== $f =="; grep -E '^(id|effect_id|button_column|sort_order|unlock_condition) = ' "$f"; done`
Expected: spot-check each file's `id` matches its filename, every `effect_id` matches one of the seven dispatched in Task 6 (`touch_orb`, `summon_familiar`, `eat_food`, `gain_confidence`, `add_chair`, `add_table`, `add_bed`), `sort_order` is unique within each `button_column`, and every `unlock_condition` matches what's documented above.

- [ ] **Step 12: Commit**

```bash
git add data/buttons/house/
git commit -m "Add the ten core-loop House button .tres files (Ticket 9)

touch_orb, summon_familiar, eat_bread, chair, table, bed,
confidence_1 through confidence_4. Orb Channeling, the four Better X
upgrades, and Better Bed are tracked in a separate follow-up issue."
```

---

### Task 9: Full playthrough trace, commit closing the issue

**Files:** none (verification only).

**Interfaces:**
- Consumes: everything from Tasks 1-8.

- [ ] **Step 1: Trace a complete fresh-save playthrough against Ticket 9's core acceptance criterion**

*"A player can go from a fresh save (0 mana, 0 familiars, 50 HP) all the way through summoning familiars, eating, buying chair/table/bed, and maxing all 4 Confidence tiers, using only this ticket's content — no dead ends, no button that never becomes clickable."*

Trace step by step (state after each action):

1. Fresh: `mana=0, familiars=0, health=50, food_eaten_count=0, orb_mana_per_click=1.0, orb_health_cost_per_click=5.0`.
2. Click Touch the Orb (unlock_condition `""`, always clickable): `mana=1, health=45`.
3. Click Touch the Orb 3 more times (cooldown 1 sec — assume enough real time passes between clicks): `mana=4, health=30`.
4. Click Summon Familiar (`cost = calculate_cost(1.0,"linear",1.0, GameState.familiars=0) = 1.0`; `mana=4 >= 1` affordable): `mana=3, familiars=1`.
5. Eat Bread now unlocks (`unlock_condition="familiars >= 1"`, `familiars=1` ✓). Click it: `health=40, food_eaten_count=1`.
6. Click Eat Bread again (cooldown 5s, assume elapsed): `health=50` (clamped at max_health), `food_eaten_count=2`.
7. Chair now unlocks (`unlock_condition="food_eaten_count >= 2"`, `2>=2` ✓; `cost_type="familiars", base_cost=1.0`, `familiars=1 >= 1` affordable). Click it: `familiars=0` (spent exactly 1 — bug fix from Task 6 confirmed), `purchased_upgrades=["chair"]`, `orb_mana_per_click=2.0`, `health_regen_per_minute=1.0`. Room description updates to include "a chair".
8. Click Summon Familiar three more times to reach `familiars=3` (cost recalculates each time from LIVE `familiars`, per Task 5's `cost_count_source`): costs `1+1*0=1`, `1+1*1=2`, `1+1*2=3` mana respectively (assume enough mana accumulated via more Touch-the-Orb clicks between summons — no dead end, since Touch the Orb has no cost and always available).
9. Eat Bread three more times to reach `food_eaten_count=5` (cooldown-gated but always eventually clickable since `familiars=3 >= 1` throughout).
10. Table now unlocks (`unlock_condition="food_eaten_count >= 5 && familiars >= 3"`, both true; `cost_type="familiars", base_cost=2.0`, `familiars=3 >= 2` affordable). Click it: `familiars=1`, `purchased_upgrades=["chair","table"]`, `food_heal_bonus=2.0`, `orb_mana_per_click=4.0`. Description updates to "a chair and a table".
11. Continue summoning familiars (cost now scales off `familiars=1` again, dropping back down since Table spent 2 — confirms the `cost_count_source="familiars"` live-tracking behavior from Task 5 works as intended, not a dead end) up to `familiars=5`.
12. Bed unlocks (`unlock_condition="familiars >= 5"`, true; cost 4 familiars, affordable at `familiars=5`). Click it: `familiars=1`, `max_health` becomes `70`, `orb_mana_per_click=7.0`. Description updates to "a chair, a table, and a bed" (order reflects purchase order, not a fixed list order — acceptable, mockup doesn't mandate a specific furniture-listing order).
13. Confidence 1 (`unlock_condition="confidence_tier >= 0"`, always true; cost 10 mana — reachable via continued Touch the Orb clicks, each still giving `+orb_mana_per_click` which has been growing from furniture bonuses, so mana accumulates faster than at the start, not slower — no dead end). Click it: `confidence_tier=1`, `orb_mana_per_click += 3`, `orb_health_cost_per_click=10.0`. Touch the Orb's label updates to "Carefully touch the orb" (via `tier_source` wiring, Task 5).
14. Confidence 2 (`confidence_tier >= 1` ✓, cost 20 mana): `confidence_tier=2`, `orb_health_cost_per_click=15.0`.
15. Confidence 3 (`confidence_tier >= 2` ✓, cost 50 mana): `confidence_tier=3`, `orb_health_cost_per_click=20.0`.
16. Confidence 4 (`confidence_tier >= 3` ✓, cost 100 mana): `confidence_tier=4`, `orb_health_cost_per_click=25.0`. Touch the Orb's label reaches "Hold the orb for a moment" (index `min(4,4)=4`).

No step in this trace requires an already-exhausted resource with no way to replenish it (mana and familiars both have an always-available, no-cost-or-low-cost regeneration path via Touch the Orb / Summon Familiar respectively), and every unlock condition becomes satisfiable through actions available earlier in the trace. ✓ No dead ends found in this trace.

- [ ] **Step 2: Cross-check every `unlock_condition` against architecture doc §6**

Read `docs/architecture.md` §6 and confirm each of the ten `.tres` files' `unlock_condition`/cost/effect numbers match the table exactly (this doc is the living balancing reference per this project's established convention). Record any drift found — if the numbers already match (expected, since this plan's Global Constraints were written directly from that doc), state that explicitly rather than leaving the check unperformed.

- [ ] **Step 3: File the follow-up issue for the deferred scope**

Create a new GitHub issue (NOT part of this plan's commits — a `gh issue create` action) titled `Ticket 9b — Orb Channeling, Better X Upgrades, Better Bed`, labeled `ticket`, body covering exactly what this plan's Global Constraints scoped out: `orb_plinth.tres` + its custom allocator UI (flagging that it needs its own component, doesn't fit `button_action.tscn`), `better_meal.tres`/`better_chair.tres`/`better_table.tres`/`better_bed.tres` (each needing their own new GameState tier-tracking fields — NOT the same fields this plan added, which are for the base one-shot furniture, not the repeatable upgrades), Better Bed's TBD effect (still needs an actual design decision, don't invent one), the deferred "Eat Bread cooldown only recharges while familiars >= 1" pacing nuance, and the confidence-one-shot-reappearing-after-save-reload gap flagged in this plan's Global Constraints (relevant once Ticket 11 exists).

- [ ] **Step 4: Commit and push, closing the issue**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Complete Ticket 9 core-loop verification

Closes #9
EOF
)"
git push
```

(If Step 1-2's trace found no code changes needed, this commit may be empty of file changes beyond what Task 8 already committed — in that case, skip an empty commit and instead push whatever's pending, then note in the report that closing happens via the last real commit's message needing amendment, OR simply add `Closes #9` as a trailing note when pushing Task 8's commit instead. Prefer: if Task 8's commit hasn't been pushed yet, amend ITS message to include `Closes #9` rather than creating an empty commit — check `git log` and `git status` first to decide which applies before choosing.)

- [ ] **Step 5: Verify the issue closed**

Run: `gh issue view 9 --json state --jq .state`
Expected: `CLOSED`

Run: `gh issue list --label ticket --state open --json number,title --jq '.[] | "\(.number): \(.title)"'`
Expected: Tickets 10, 11, 12, plus the new follow-up issue filed in Step 3.

- [ ] **Step 6: Report to the user**

This is the point where a real editor playthrough matters most of anything built so far. State plainly: nothing in this ticket has been executed — the trace in Step 1 is careful manual reasoning, not a test run, and a scene/resource file typo anywhere in the ten new `.tres` files or the seven modified/created scripts could break the whole chain in a way only the editor's console would reveal. Ask the user to: open the project, press Play, and actually click through the fresh-save playthrough traced in Step 1 — touch the orb a few times, summon a familiar, eat until Chair unlocks, keep going through Table, Bed, and all four Confidence tiers. Confirm the room description updates as furniture is bought, the touch-the-orb label progresses with Confidence, and nothing throws a console error. Also mention: a new follow-up issue now exists for Orb Channeling / Better X upgrades / Better Bed, and Ticket 10 (Health Depletion / Blackout Recovery) is next after that if they want to keep going in ticket order — or the follow-up issue, if they'd rather finish out the House tab's stretch content first.

---

## Self-Review Notes

- **Spec coverage:** every item in the approved core-loop scope (Column 1 items 1-6, Column 2 item 8) has a `.tres` file in Task 8, with every field cross-referenced against the mechanics built in Tasks 1-7. Both acceptance criteria carried over from Ticket 5's review (confidence HP-cost growth, chair regen) are explicitly traced in Task 6 Step 7. The room-description acceptance criterion is traced in Task 7 Step 3. The full-playthrough criterion is traced end-to-end in Task 9 Step 1.
- **No placeholders:** every function and `.tres` field is complete. The explicitly out-of-scope items (Orb Channeling, Better X, Better Bed) are formally handed off to a new tracked issue in Task 9 Step 3, not silently dropped — this is different from a bare deferral, since it produces a concrete, assignable GitHub issue.
- **Type/name consistency:** every `effect_id` used across the ten `.tres` files (Task 8) matches exactly one case in `EffectHandler.run_effect()`'s dispatch (Task 6) — cross-checked in Task 8 Step 11's verification command. `GameState` field/method names introduced in Task 1 are used with identical names in Task 6's `EffectHandler` edits and Task 2's `EventBus` wiring. `ButtonData` field names introduced in Task 4 (`tier_source`, `cost_count_source`, `room_description_fragment`) are used identically in Task 5's `button_action.gd` edits, Task 7's `area_tab.gd` edits, and every Task 8 `.tres` file.
- **Bug found and fixed, not just noted:** the chair double-deduction bug (Task 6 Step 1) was caught during design, before it ever shipped into a real playable scene, and is fixed as part of this same plan rather than filed as a separate ticket — it's a defect in already-closed Ticket 5's code, but fixing forward is more appropriate than reopening a ticket for a one-line bug caught before it ever affected a real player.

## Execution Handoff

Two execution options:

1. **Subagent-Driven (recommended)** - dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** - execute tasks in this session using `executing-plans`, batch execution with checkpoints.
