# Ticket 9b: Better Chair/Table/Bed + Eat Bread Cooldown + Save-Reload Defensive Fix

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the three repeatable "Better X" furniture upgrades (Chair/Table/Bed), fix Eat Bread's cooldown to pause when familiars hit 0, and add a defensive fix so one-shot furniture doesn't reappear on a future reload — the narrowed scope of issue #13, with Orb Channeling and Better Meal split into a separate follow-up (#14) since both need real design decisions this plan doesn't make.

**Architecture:** Three new `GameState` tier fields (one per upgrade, separate from the one-shot `purchased_upgrades` set). A new `ButtonData.max_purchases` field generalizes "this button disappears after N purchases" beyond the existing one-shot (`N=1`) case — `button_action.gd` hides itself once its own click count reaches it. A new `ButtonData.cooldown_gate_condition` field reuses the *existing* `is_unlock_condition_met` parser to pause a button's cooldown while a condition doesn't hold, replacing the fire-and-forget `SceneTreeTimer` cooldown with a per-frame countdown. Three new `EffectHandler` functions each read/increment their own `GameState` tier field directly (matching the established Confidence pattern), independent of `button_action.gd`'s own click counter. `area_tab.gd` gains a defensive skip for already-purchased one-shot buttons.

**Tech Stack:** GDScript, Godot 4.7. A working Godot 4.7.1 binary exists at `/home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64` (not on PATH) — every task gets a real headless load check.

## Global Constraints

- **Per-level effect magnitudes, derived from an established pattern, not invented:** Better Chair/Table already show "per-level bonus = the matching one-shot furniture's own bonus" in the design doc (Chair one-shot: +1 HP regen/min +1 orb mana gain; Better Chair per level: the same). Applied to Bed (whose one-shot is +20 max HP +3 orb mana gain) per the project owner's explicit direction to mirror this pattern rather than invent a fresh number for Better Bed.
- **All three upgrades cap at 4 levels.** Only Better Chair states "This can happen 4 times" explicitly in the design doc; Better Table and Better Bed don't state a cap. Capping all three at 4 is the same judgment call already made for Better Table back in Ticket 9's design work (matching the 5-tier food-name-progression list's implicit ceiling) — applied consistently to Bed here rather than leaving it uncapped.
- **New `GameState` fields:** `better_chair_level: int = 0`, `better_table_level: int = 0`, `better_bed_level: int = 0` (each capped at 4). New methods: `advance_better_chair_level()`, `advance_better_table_level()`, `advance_better_bed_level()` — each `min(x + 1, 4)`, no `EventBus` signal (nothing displays these live, same reasoning as `confidence_tier`/other tier fields). All three fields added to `to_dict()`/`from_dict()`.
- **New `ButtonData.max_purchases: int` field** (default `0` = unlimited). Distinct from `one_shot` (hides after exactly 1 purchase) — this hides a button after its own click count reaches an arbitrary cap. Does NOT need a new `cost_count_source` value: each upgrade's own self-referential `_purchase_count` (the existing default behavior) is already the correct "count" for both its cost formula and its cap check, since — unlike Summon Familiar — nothing external ever reduces how many times Better Chair has been bought.
- **New `ButtonData.cooldown_gate_condition: String` field** (default `""` = no gate, cooldown always counts down). Reuses `ButtonData.is_unlock_condition_met()` verbatim — no new condition grammar. `eat_bread.tres` sets this to `"familiars >= 1"`.
- **Cooldown mechanism changes from `SceneTreeTimer` to per-frame `_process()`** for every button, not just Eat Bread — this is a mechanism swap, not a per-button special case, since a gate condition needs something that can be checked repeatedly rather than a fire-and-forget timer. Behavior for every OTHER button (whose `cooldown_gate_condition` stays empty) is externally identical: still counts down exactly `cooldown_sec` real seconds, since an empty gate condition never blocks the countdown.
- **Unlock conditions for all three upgrades use the existing `has_upgrade(id)` shape** (`has_upgrade("chair")`, `has_upgrade("table")`, `has_upgrade("bed")`) — no new condition grammar needed for this ticket's scope (unlike Better Meal's "matching table tier" gate, which is exactly why Better Meal was split into #14).
- **Effect functions read `GameState`'s own tier field directly**, not `button_action.gd`'s internal `_purchase_count` — `EffectHandler.run_effect()` only receives a bare `effect_id` string, with no access to the clicking button's own state, matching the established `_effect_gain_confidence()` pattern exactly.
- **Defensive max-level guards in each new effect function** (`if <field> >= 4: push_error(...); return false`), matching the established pattern from `_effect_gain_confidence()` — expected to be unreachable in normal play (the button hides itself first via `max_purchases`), kept as the same "confirmed harmless belt-and-suspenders" pattern used elsewhere in this codebase.
- **Save/reload defensive fix, scoped narrowly:** `area_tab.gd::_load_buttons()` skips instantiating a one-shot button whose `id` is already in `GameState.purchased_upgrades`, and seeds `_furniture_fragments` from any such skipped button's `room_description_fragment` before rebuilding the description once at the end of `_load_buttons()`. This does NOT fix `_load_buttons()` being called a second time on an already-populated node (duplicate button instances) — not exercised by anything today, and is Ticket 11's concern if its reload flow ever needs it.
- `sort_order` for the three new buttons: `5`, `6`, `7` respectively (column 2, continuing after `confidence_1`-`confidence_4`'s `1`-`4`).
- Direct-to-master. Final commit closes issue #13 (`Closes #13`).

---

### Task 1: Extend `GameState`

**Files:**
- Modify: `autoloads/game_state.gd`

**Interfaces:**
- Produces: `GameState.better_chair_level`/`better_table_level`/`better_bed_level`, `advance_better_chair_level()`/`advance_better_table_level()`/`advance_better_bed_level()` — Task 4's `EffectHandler` functions call these.

- [ ] **Step 1: Add the three new fields**

Add after the existing `var health_regen_per_minute: float = 0.0` line:

```gdscript
var better_chair_level: int = 0
var better_table_level: int = 0
var better_bed_level: int = 0
```

- [ ] **Step 2: Add the three new methods**

Add after `add_max_health()` (or alongside the other `add_*`/`advance_*` methods, before `to_dict()`):

```gdscript
func advance_better_chair_level() -> void:
	better_chair_level = min(better_chair_level + 1, 4)


func advance_better_table_level() -> void:
	better_table_level = min(better_table_level + 1, 4)


func advance_better_bed_level() -> void:
	better_bed_level = min(better_bed_level + 1, 4)
```

- [ ] **Step 3: Update `to_dict()` and `from_dict()`**

In `to_dict()`, add three entries (anywhere among the other plain-field entries, before the closing `}`):

```gdscript
		"better_chair_level": better_chair_level,
		"better_table_level": better_table_level,
		"better_bed_level": better_bed_level,
```

In `from_dict()`, add three matching lines:

```gdscript
	better_chair_level = data.get("better_chair_level", 0)
	better_table_level = data.get("better_table_level", 0)
	better_bed_level = data.get("better_bed_level", 0)
```

- [ ] **Step 4: Manually trace**

*Cap holds after repeated calls* — trace: `advance_better_chair_level()` called 5 times from `better_chair_level=0`: `0→1→2→3→4→4` (5th call: `min(4+1,4)=4`, clamped). Matches the established `advance_confidence_tier()` pattern exactly. ✓

- [ ] **Step 5: Verify with the real Godot binary**

Run: `cd /home/brian/Public/Programming/Godot/a-blue-orb && /home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64 --headless --quit 2>&1`
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add autoloads/game_state.gd
git commit -m "Add Better Chair/Table/Bed tier fields to GameState (Ticket 9b)

Separate from purchased_upgrades, which tracks 'do I own it' not
'what level is the upgrade at.'"
```

---

### Task 2: Extend `ButtonData`

**Files:**
- Modify: `data/button_data.gd`

**Interfaces:**
- Produces: `max_purchases: int`, `cooldown_gate_condition: String` — Task 3's `button_action.gd` reads both.

- [ ] **Step 1: Add the two new fields**

Add after the existing `@export var room_description_fragment: String` line:

```gdscript
@export var max_purchases: int
@export var cooldown_gate_condition: String
```

- [ ] **Step 2: Manually trace**

*Fields default correctly for every existing button* — trace: `max_purchases` defaults to `0` (GDScript `int` default), `cooldown_gate_condition` defaults to `""` — every one of the ten `.tres` files from Ticket 9 leaves both unset, so `0`/`""` apply, matching "unlimited purchases, no cooldown gate" for all of them. No existing `.tres` file needs editing for this step (`eat_bread.tres` gets its `cooldown_gate_condition` set explicitly in Task 6). ✓

- [ ] **Step 3: Verify with the real Godot binary**

Run: `cd /home/brian/Public/Programming/Godot/a-blue-orb && /home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64 --headless --quit 2>&1`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add data/button_data.gd
git commit -m "Add max_purchases and cooldown_gate_condition to ButtonData (Ticket 9b)

max_purchases generalizes one_shot's 'hide after 1' to 'hide after N.'
cooldown_gate_condition reuses is_unlock_condition_met's existing
grammar rather than adding a new parser."
```

---

### Task 3: Extend `button_action.gd`

**Files:**
- Modify: `scenes/ui/button_action.gd`

**Interfaces:**
- Consumes: `ButtonData.max_purchases`/`cooldown_gate_condition` (Task 2).

- [ ] **Step 1: Add the max-purchases hide check in `_handle_click()`**

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
	_refresh()
```
to:
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
```

- [ ] **Step 2: Replace the `SceneTreeTimer` cooldown with a per-frame, gate-aware countdown**

Add a new field alongside the existing ones (`_purchase_count`, `_is_on_cooldown`, etc.):
```gdscript
var _cooldown_remaining: float = 0.0
```

Change:
```gdscript
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
to:
```gdscript
func _start_cooldown() -> void:
	if data.cooldown_sec <= 0.0:
		return
	_is_on_cooldown = true
	_cooldown_remaining = data.cooldown_sec
	disabled = true


func _process(delta: float) -> void:
	if not _is_on_cooldown:
		return
	if data.cooldown_gate_condition != "" and not ButtonData.is_unlock_condition_met(data.cooldown_gate_condition):
		return
	_cooldown_remaining -= delta
	if _cooldown_remaining <= 0.0:
		_is_on_cooldown = false
		_refresh()
```

- [ ] **Step 3: Manually trace each acceptance criterion this task touches**

1. *Max-purchases hide, generalized beyond one_shot* — trace: `better_chair.tres` (`max_purchases=4`, `one_shot=false`). After the 4th successful click: `_purchase_count` goes `3→4` (via the `data.tier_source == ""` increment, which fires since `better_chair.tres` doesn't set `tier_source`), THEN the new check `data.max_purchases > 0 and _purchase_count >= data.max_purchases` → `4 > 0 and 4 >= 4` → `true` → `hide()`, button gone. A 5th click is now impossible (hidden buttons don't receive input). ✓ A button with `max_purchases=0` (every other existing button) never satisfies `data.max_purchases > 0`, so this new branch never fires for them — no behavior change. ✓
2. *Eat Bread's cooldown pauses at 0 familiars* — trace: `eat_bread.tres` sets `cooldown_gate_condition="familiars >= 1"` (Task 6). After a click, `_is_on_cooldown=true`, `_cooldown_remaining=5.0`. Each frame, `_process()` checks the gate: while `GameState.familiars == 0`, `is_unlock_condition_met("familiars >= 1")` returns `false`, so the function returns immediately WITHOUT decrementing `_cooldown_remaining` — the cooldown genuinely stalls, not just visually. The instant `familiars` rises to `1+` again, the very next frame's `_process()` call passes the gate and resumes decrementing from wherever `_cooldown_remaining` was left. ✓
3. *Every other button's cooldown behaves identically to before* — trace: a button with `cooldown_gate_condition=""` (every button from Tickets 9 and earlier): `_process()`'s gate check `data.cooldown_gate_condition != ""` is `false`, so the `and`'s short-circuit never even evaluates `is_unlock_condition_met` — falls straight through to decrementing `_cooldown_remaining` every frame, reaching `<=0.0` after exactly `cooldown_sec` real seconds of accumulated `delta`, same externally-observable timing as the old `SceneTreeTimer` approach. ✓

- [ ] **Step 4: Verify with the real Godot binary**

Run: `cd /home/brian/Public/Programming/Godot/a-blue-orb && /home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64 --headless --quit 2>&1`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add scenes/ui/button_action.gd
git commit -m "Add max_purchases hiding and gate-aware cooldown (Ticket 9b)

Cooldown mechanism switches from SceneTreeTimer to per-frame
_process() so it can pause on a live condition (needed for Eat
Bread's 'only recharges with >=1 familiar' nuance) — externally
identical timing for every button that doesn't set a gate condition."
```

---

### Task 4: Extend `EffectHandler`

**Files:**
- Modify: `autoloads/effect_handler.gd`

**Interfaces:**
- Produces: `better_chair`, `better_table`, `better_bed` effect_ids — Task 6's three new `.tres` files reference these.

- [ ] **Step 1: Add the three new effect functions**

Add after `_effect_add_bed()`:

```gdscript
func _effect_better_chair() -> bool:
	if GameState.better_chair_level >= 4:
		push_error("EffectHandler: better_chair_level already at max")
		return false
	GameState.add_health_regen_per_minute(1.0)
	GameState.add_orb_mana_per_click(1.0)
	GameState.advance_better_chair_level()
	LogManager.push("your chair creaks contentedly.")
	return true


func _effect_better_table() -> bool:
	if GameState.better_table_level >= 4:
		push_error("EffectHandler: better_table_level already at max")
		return false
	GameState.add_food_heal_bonus(2.0)
	GameState.add_orb_mana_per_click(2.0)
	GameState.advance_better_table_level()
	LogManager.push("your table gleams a little brighter.")
	return true


func _effect_better_bed() -> bool:
	if GameState.better_bed_level >= 4:
		push_error("EffectHandler: better_bed_level already at max")
		return false
	GameState.add_max_health(20.0)
	GameState.add_orb_mana_per_click(3.0)
	GameState.advance_better_bed_level()
	LogManager.push("your bed looks even more inviting.")
	return true
```

- [ ] **Step 2: Add the three new effect_ids to `run_effect()`'s dispatch**

Change:
```gdscript
		"add_table":
			return _effect_add_table()
		"add_bed":
			return _effect_add_bed()
		_:
```
to:
```gdscript
		"add_table":
			return _effect_add_table()
		"add_bed":
			return _effect_add_bed()
		"better_chair":
			return _effect_better_chair()
		"better_table":
			return _effect_better_table()
		"better_bed":
			return _effect_better_bed()
		_:
```

- [ ] **Step 3: Manually trace against the acceptance criteria**

1. *Better Chair's cumulative bonus after 4 levels* — trace: each of 4 calls to `_effect_better_chair()` (guard passes each time since `better_chair_level` is `0,1,2,3` on entry, all `<4`) adds `+1.0` to `health_regen_per_minute` and `+1.0` to `orb_mana_per_click`, then advances the level. After 4 calls: `+4.0` total on each — matches "total bonus is +4 HP regen/min +4 orb mana gain." A 5th call (if it somehow occurred despite the button hiding itself per Task 3) would see `better_chair_level=4`, guard fires, `push_error` + `return false`, no further mutation — unreachable in normal play but confirmed harmless. ✓
2. *Better Table / Better Bed, same shape* — trace: 4 calls each add `+2.0` `food_heal_bonus` / `+2.0` `orb_mana_per_click` (table) → totals `+8.0`/`+8.0`; 4 calls each add `+20.0` `max_health` / `+3.0` `orb_mana_per_click` (bed) → totals `+80.0`/`+12.0`. Matches the acceptance criteria's stated totals exactly. ✓
3. *No self-deduction (the Ticket 5/9 bug class doesn't recur)* — trace: none of the three new functions call `spend_familiars`/`spend_mana`/`spend_health` — cost deduction is left entirely to `button_action.gd`'s generic `_deduct_cost()`, matching the established fix pattern. ✓

- [ ] **Step 4: Verify with the real Godot binary**

Run: `cd /home/brian/Public/Programming/Godot/a-blue-orb && /home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64 --headless --quit 2>&1`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add autoloads/effect_handler.gd
git commit -m "Add Better Chair/Table/Bed effect functions (Ticket 9b)

Each reads/increments its own GameState tier field directly,
matching the established gain_confidence pattern — EffectHandler
only receives a bare effect_id string, no access to the clicking
button's own state."
```

---

### Task 5: Extend `area_tab.gd` (save/reload defensive fix)

**Files:**
- Modify: `scenes/ui/area_tab.gd`

**Interfaces:**
- Consumes: `GameState.purchased_upgrades`/`has_upgrade()` (Ticket 2).

- [ ] **Step 1: Skip already-purchased one-shot buttons, seed furniture fragments**

Change:
```gdscript
func _apply_area_data() -> void:
	_description_label.text = area_data.base_description
	_update_tab_title()
	_load_buttons()
```
to:
```gdscript
func _apply_area_data() -> void:
	_furniture_fragments.clear()
	_description_label.text = area_data.base_description
	_update_tab_title()
	_load_buttons()
```

Change:
```gdscript
	for button_data in button_datas:
		var instance: Button = BUTTON_ACTION_SCENE.instantiate()
		instance.set_data(button_data)
		instance.one_shot_purchased.connect(_on_one_shot_purchased)
		if button_data.button_column == 1:
			_column_actions.add_child(instance)
		else:
			_column_upgrades.add_child(instance)
```
to:
```gdscript
	for button_data in button_datas:
		if button_data.one_shot and GameState.has_upgrade(button_data.id):
			if button_data.room_description_fragment != "":
				_furniture_fragments.append(button_data.room_description_fragment)
			continue
		var instance: Button = BUTTON_ACTION_SCENE.instantiate()
		instance.set_data(button_data)
		instance.one_shot_purchased.connect(_on_one_shot_purchased)
		if button_data.button_column == 1:
			_column_actions.add_child(instance)
		else:
			_column_upgrades.add_child(instance)
	_rebuild_description()
```

- [ ] **Step 2: Manually trace against this ticket's acceptance criterion**

*Already-purchased one-shot furniture is skipped and its description fragment is seeded* — trace: assume `GameState.purchased_upgrades = ["chair"]` before `_load_buttons()` runs (simulating what a future Ticket 11 load would restore). Iterating the sorted `button_datas`, when `chair.tres` (`one_shot=true`, `id="chair"`) is reached: `button_data.one_shot and GameState.has_upgrade("chair")` → `true and true` → `true` → its `room_description_fragment` (`"a chair"`) is appended to `_furniture_fragments`, then `continue` skips instantiating a `button_action` instance for it entirely — no Chair button appears in the grid. Every other button_data (not purchased, or not one_shot) proceeds through the normal instantiation path unaffected. After the loop, `_rebuild_description()` runs once: `_furniture_fragments = ["a chair"]` (non-empty) → description becomes `"{base_description} The room has a chair."` — matches the acceptance criterion's expected text, without needing a real purchase click in this session to produce it. ✓ On a genuinely fresh save (`purchased_upgrades = []`), every one_shot check is `true and false = false`, nothing is skipped, `_furniture_fragments` stays empty, `_rebuild_description()`'s empty-fragments branch resets text to `base_description` (already set moments earlier in `_apply_area_data()`, so this is a harmless no-op re-assignment, not a behavior change). ✓

- [ ] **Step 3: Verify with the real Godot binary**

Run: `cd /home/brian/Public/Programming/Godot/a-blue-orb && /home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64 --headless --quit 2>&1`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add scenes/ui/area_tab.gd
git commit -m "Skip already-purchased one-shot buttons on load (Ticket 9b)

Defensive fix for Ticket 11's eventual save/reload — a one-shot
furniture button whose id is already in GameState.purchased_upgrades
is no longer re-instantiated, and its room description fragment is
seeded before the first _rebuild_description() call rather than only
building up reactively. Does not fix _load_buttons() being called a
second time on an already-populated node — not exercised today."
```

---

### Task 6: Add `cooldown_gate_condition` to `eat_bread.tres`, create the three new `.tres` files, cross-check, commit closing the issue

**Files:**
- Modify: `data/buttons/house/eat_bread.tres`
- Create: `data/buttons/house/better_chair.tres`
- Create: `data/buttons/house/better_table.tres`
- Create: `data/buttons/house/better_bed.tres`

**Interfaces:**
- Consumes: `effect_id`s from Task 4, `max_purchases`/`cooldown_gate_condition` fields from Task 2.

- [ ] **Step 1: Add `cooldown_gate_condition` to `eat_bread.tres`**

Add this line to the existing `[resource]` block (anywhere among the other field assignments — exact position doesn't matter):
```
cooldown_gate_condition = "familiars >= 1"
```

- [ ] **Step 2: Create `data/buttons/house/better_chair.tres`**

```
[gd_resource type="Resource" load_steps=2 format=3]

[ext_resource type="Script" path="res://data/button_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "better_chair"
labels = Array[String](["A Better Chair"])
cost_type = "familiars"
base_cost = 2.0
cost_scaling = "double"
cost_step = 0.0
cooldown_sec = 0.0
unlock_condition = "has_upgrade(\"chair\")"
effect_id = "better_chair"
flavor_lines = Array[String]([])
one_shot = false
button_column = 2
sort_order = 5
tier_source = ""
cost_count_source = ""
room_description_fragment = ""
max_purchases = 4
cooldown_gate_condition = ""
```

- [ ] **Step 3: Create `data/buttons/house/better_table.tres`**

```
[gd_resource type="Resource" load_steps=2 format=3]

[ext_resource type="Script" path="res://data/button_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "better_table"
labels = Array[String](["A Better Table"])
cost_type = "familiars"
base_cost = 4.0
cost_scaling = "double"
cost_step = 0.0
cooldown_sec = 0.0
unlock_condition = "has_upgrade(\"table\")"
effect_id = "better_table"
flavor_lines = Array[String]([])
one_shot = false
button_column = 2
sort_order = 6
tier_source = ""
cost_count_source = ""
room_description_fragment = ""
max_purchases = 4
cooldown_gate_condition = ""
```

- [ ] **Step 4: Create `data/buttons/house/better_bed.tres`**

```
[gd_resource type="Resource" load_steps=2 format=3]

[ext_resource type="Script" path="res://data/button_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "better_bed"
labels = Array[String](["A Better Bed"])
cost_type = "familiars"
base_cost = 8.0
cost_scaling = "double"
cost_step = 0.0
cooldown_sec = 0.0
unlock_condition = "has_upgrade(\"bed\")"
effect_id = "better_bed"
flavor_lines = Array[String]([])
one_shot = false
button_column = 2
sort_order = 7
tier_source = ""
cost_count_source = ""
room_description_fragment = ""
max_purchases = 4
cooldown_gate_condition = ""
```

- [ ] **Step 5: Verify all files**

Run: `grep -L 'type="Resource"' data/buttons/house/better_chair.tres data/buttons/house/better_table.tres data/buttons/house/better_bed.tres`
Expected: no output (all three use the correct generic header — the same `type="Resource"` + `script = ExtResource(...)` pattern established for every other `ButtonData` `.tres` in this project, per the header-mismatch bug found and fixed in Ticket 9).

Run: `grep 'cooldown_gate_condition' data/buttons/house/eat_bread.tres`
Expected: `cooldown_gate_condition = "familiars >= 1"`

- [ ] **Step 6: Cross-check against architecture.md §6**

Read `docs/architecture.md` §6's Better Chair/Better Table/Better Bed rows and confirm `base_cost` (2.0/4.0/8.0), `cost_scaling="double"`, and the per-level effect numbers match exactly what Task 4's effect functions apply. State explicitly that the check was performed and what it found (matches, or any drift), rather than leaving it unperformed.

- [ ] **Step 7: Final real headless check**

Run: `cd /home/brian/Public/Programming/Godot/a-blue-orb && /home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64 --headless --quit 2>&1`
Expected: no errors — confirms all three new `.tres` files load correctly alongside everything from Tasks 1-5.

- [ ] **Step 8: Commit and push, closing the issue**

```bash
git add data/buttons/house/eat_bread.tres data/buttons/house/better_chair.tres data/buttons/house/better_table.tres data/buttons/house/better_bed.tres
git commit -m "$(cat <<'EOF'
Add Better Chair/Table/Bed .tres files, gate Eat Bread's cooldown

Closes #13
EOF
)"
git push
```

- [ ] **Step 9: Verify the issue closed**

Run: `gh issue view 13 --json state --jq .state`
Expected: `CLOSED`

- [ ] **Step 10: Report to the user**

State: three repeatable upgrades are built and load-verified, Eat Bread's cooldown now genuinely pauses at 0 familiars (verified via real code trace, not just visual), and one-shot furniture won't reappear on a future reload (though full save/reload behavior still needs Ticket 11 to exist before it can be truly exercised end-to-end). As always, the project loading cleanly under real headless execution confirms structure, not gameplay feel — recommend the user actually buy Better Chair four times in the editor and confirm the button vanishes after the 4th purchase, and test Eat Bread's cooldown stall by spending all familiars on furniture and watching the button stay disabled until a new familiar is summoned. Issue #14 (Orb Channeling + Better Meal) is the natural next stop for the House tab's remaining stretch content, or Ticket 11 (Save System) is next in strict ticket order.

---

## Self-Review Notes

- **Spec coverage:** every acceptance criterion in the narrowed issue #13 is traced explicitly — cumulative bonus totals (Task 4 Step 3), gating on base furniture ownership (the `.tres` `unlock_condition` fields in Task 6, using the pre-existing `has_upgrade` shape), Eat Bread's cooldown stall (Task 3 Step 3), and the save-reload skip (Task 5 Step 2).
- **No placeholders:** every function and `.tres` field is complete. Orb Channeling and Better Meal are formally split into issue #14, not silently dropped or half-built here.
- **Type/name consistency:** `better_chair_level`/`better_table_level`/`better_bed_level` (Task 1) are read/written with identical names in Task 4's effect functions. `max_purchases`/`cooldown_gate_condition` (Task 2) are consumed with identical names in Task 3's `button_action.gd` logic and set with identical names in Task 6's `.tres` files. `effect_id` values (`better_chair`/`better_table`/`better_bed`, Task 6) match exactly the three new `match` cases added in Task 4 Step 2.

## Execution Handoff

Two execution options:

1. **Subagent-Driven (recommended)** - dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** - execute tasks in this session using `executing-plans`, batch execution with checkpoints.
