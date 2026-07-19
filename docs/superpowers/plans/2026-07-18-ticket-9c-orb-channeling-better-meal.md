# Ticket 9c: Orb Channeling + Better Meal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Orb Channeling allocator (assign/unassign familiars to passive per-second mana income, with assigned familiars reserved out of the spendable pool) and Better Meal (a repeatable upgrade gated on never outpacing Better Table's level) — the two pieces split off from Ticket 9b because both needed real design decisions, both now resolved directly with the project owner.

**Architecture:** `GameState` gains a reserved-familiars concept (`familiars_assigned_to_orb`, `idle_familiars()`) — `spend_familiars()` and `button_action.gd::_can_afford()` both switch from checking raw `familiars` to checking the idle pool, so assigned familiars are genuinely unspendable until unassigned. A new `OrbChannelManager` autoload ticks `orb_mana_per_second` into `mana` once a second, following `RegenManager`'s established pattern. A new `orb_channeling.tscn` component (not a `ButtonData`/`button_action.tscn` instance — it doesn't fit that shape) provides the up/down allocator UI, instanced as a static child of `area_tab.tscn`'s upgrades column. Better Meal reuses the entire "Better X" machinery Ticket 9b/11 already built (`max_purchases`, `count_seed_source`, tier-field-reading effect functions) — the only genuinely new piece is extending `ButtonData.is_unlock_condition_met()` to compare two live stats to each other (not just a stat to a literal number), which `better_meal.tres`'s "never exceed Better Table's level" gate needs.

**Tech Stack:** GDScript, Godot 4.7. A working Godot 4.7.1 binary exists at `/home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64` (not on PATH) — this ticket's GameState logic (reservation arithmetic, stat-vs-stat comparison) is exactly the kind of thing worth a real executed test, following Ticket 11's precedent.

## Global Constraints

- **Familiar reservation, confirmed with the project owner:** assigning a familiar to the orb removes it from the spendable pool until explicitly unassigned. `GameState.idle_familiars() -> int` (`familiars - familiars_assigned_to_orb`) becomes the actual "can I spend this many familiars" quantity — both `spend_familiars()` (the authoritative check) and `button_action.gd::_can_afford()` (the UI-layer check that must stay consistent with it, or a button could show as affordable when spending would actually fail) switch to it. `familiars` itself keeps meaning "total owned," unchanged.
- **Better Meal gating, confirmed with the project owner:** extend `is_unlock_condition_met()`'s existing `>=` parsing so its operands (both sides) can be either a literal number OR another stat name — plus add a `<` operator alongside the existing `>=`, using the same operand resolution. `better_meal.tres` uses `unlock_condition = "better_meal_level < better_table_level"` — true only when Better Meal hasn't yet caught up to Better Table's level, matching the design doc's "matching table tier" gate (verified algebraically: at `better_meal_level=0, better_table_level=0`, `0 < 0` is `false`, correctly locked until Table is upgraded at least once; after each Meal purchase the gate re-locks until Table is upgraged further). This is a backward-compatible refactor of `is_unlock_condition_met`'s existing operand handling, not a new condition shape — every existing `.tres` file's `unlock_condition` (all currently `stat >= number`) continues to work identically, since a literal number is still a valid operand.
- **New `GameState` fields/methods for Orb Channeling:**
  - `familiars_assigned_to_orb: int = 0`.
  - `idle_familiars() -> int`: `familiars - familiars_assigned_to_orb`.
  - `assign_familiar_to_orb() -> bool`: fails (returns `false`, no mutation) if `idle_familiars() <= 0`; otherwise increments `familiars_assigned_to_orb` and calls the already-existing (and until now unused) `add_orb_mana_per_second(1.0)`.
  - `unassign_familiar_from_orb() -> bool`: fails if `familiars_assigned_to_orb <= 0`; otherwise decrements it and calls `add_orb_mana_per_second(-1.0)`.
  - `spend_familiars(n)` changes its affordability check from `familiars < n` to `idle_familiars() < n` — the only change to this existing method; the mutation itself (`familiars -= n`) and signal emission are unchanged.
  - All fields added to `to_dict()`/`from_dict()`.
- **New `GameState` fields/methods for Better Meal:** `better_meal_level: int = 0`, `advance_better_meal_level()` (same `min(x+1, 4)` clamp pattern as the other three Better X tiers), added to `to_dict()`/`from_dict()`.
- **New `OrbChannelManager` autoload** (`autoloads/orb_channel_manager.gd`): a `Timer` ticking every `1.0`s, applying `GameState.orb_mana_per_second` to `mana` via `GameState.add_mana(...)` if the rate is above zero — structurally identical to `RegenManager` (Ticket 9). Deliberately NOT gated on blackout: blackout blocks HP-spending actions specifically (design doc's stated scope for that mechanic), and passive mana income isn't an HP-spending action — this is a judgment call, documented here rather than silently decided, since `RegenManager` (health regen) WAS gated on blackout for a reason specific to health mechanics that doesn't transfer to mana income.
- **`_effect_better_meal()`'s defensive guard checks the REAL constraint, not a flat cap:** `if GameState.better_meal_level >= GameState.better_table_level: push_error(...); return false` — unlike the other three Better X effect functions' flat `>= 4` guards, this one guards against the actual "never exceed table tier" rule (which the `unlock_condition` already enforces at the UI layer; this is defense-in-depth against a click somehow bypassing that, not the primary enforcement).
- **Better Meal's effect is HP restoration only, no orb mana gain** — verified against both the design doc and architecture.md §6: unlike Chair/Table/Bed/their Better-X counterparts (all of which state both an HP-related effect AND "+X orb mana gain"), Better Meal's entry states only "+5 HP restore per level." Do not invent an orb-mana component that isn't in the source.
- **`better_meal.tres` reuses the full Ticket 9b/11 Better-X pattern:** `max_purchases=4` (defense-in-depth alongside the unlock condition, which already prevents a 5th purchase once `better_table_level` itself caps at 4), `count_seed_source="better_meal_level"` (seeds `_purchase_count` on creation, same mechanism the other three already use), `cost_scaling="double"`, `base_cost=10.0`, `cost_type="mana"`.
- **`better_meal.tres`'s `sort_order` is `8`** (appended after `better_bed`'s `7`, not inserted before Chair/Table/Bed to match the design doc's literal column listing order) — a deliberate, low-risk display-order deviation from the doc, flagged for Ticket 12's cross-check rather than churning three already-shipped `.tres` files' `sort_order` values to renumber them.
- **The "Plinth for the Orb" purchase step from the source docs is deliberately not built.** `architecture.md` §6 lists "A Plinth for the Orb" as a Column 1 button-table row, but its own Notes column says "Not a button — up/down arrow allocator," and its Cost column is empty — the source material contradicts itself about whether a separate purchase/unlock step exists. Resolution (a judgment call, not re-confirmed with the project owner given the low risk and easy reversibility): skip the contradictory "Plinth" purchase concept entirely. `orb_channeling.tscn` is a static, always-present child of `area_tab.tscn`'s upgrades column, gated only by simple visibility: hidden until `GameState.familiars >= 1` (matching the precedent Eat Bread already established — nothing about the orb-assignment concept is meaningful before the player has any familiars), shown from then on. Flagged in the final report so the project owner can override this reading if the "Plinth" purchase step was actually intended.
- **`orb_channeling.tscn` is NOT a `ButtonData` resource or a `button_action.tscn` instance** — it doesn't fit that shape (continuous state, two buttons, no single click-cost-effect flow) and the issue's own body already concluded this. It's a small, self-contained `Control` scene with its own script, calling `GameState.assign_familiar_to_orb()`/`unassign_familiar_from_orb()` directly and refreshing its own display — no `EffectHandler` involvement.
- **`orb_channeling.tscn` respects `InputGuard`** (both buttons check `try_register_click()` first, matching every other clickable element in the game) but does NOT respect blackout (assigning/unassigning familiars doesn't spend HP or otherwise interact with what blackout blocks — consistent with `OrbChannelManager` also not being blackout-gated, for the same reason).
- **Known, explicitly out-of-scope staleness gap, not fixed here:** existing familiar-costing buttons (Chair, Table, Bed, Better X) do not reactively refresh their own disabled/affordability state when `familiars`/`idle_familiars()` changes due to a DIFFERENT button's action or the new Orb Channeling allocator — `button_action.gd` only recomputes `_is_disabled()` reactively on its own click or the small set of signals it already listens to (`tier_source`, blackout). This gap already existed before this ticket (e.g. Summon Familiar's `familiar_gained` signal doesn't make Chair re-check its own affordability either) — this ticket doesn't make it meaningfully worse, and fixing it project-wide (every button listening to every resource-change signal) is out of scope here. Flagged for Ticket 12's cross-check pass.
- `sort_order` conventions, `.tres` header conventions (`type="Resource"` + `script = ExtResource(...)`, never the custom class name directly — the real bug found and fixed in Ticket 9), and direct-to-master workflow all carry over unchanged from every prior ticket.
- Direct-to-master. Final commit closes issue #14 (`Closes #14`).

---

### Task 1: Extend `GameState` for Orb Channeling and Better Meal

**Files:**
- Modify: `autoloads/game_state.gd`

**Interfaces:**
- Produces: `familiars_assigned_to_orb`, `idle_familiars()`, `assign_familiar_to_orb()`, `unassign_familiar_from_orb()`, `better_meal_level`, `advance_better_meal_level()` — Task 2 (`button_action.gd`), Task 4 (`EffectHandler`), and Task 7 (`orb_channeling.gd`) all consume these.

- [ ] **Step 1: Add the two new fields**

Add after the existing `var better_bed_level: int = 0` line:

```gdscript
var familiars_assigned_to_orb: int = 0
var better_meal_level: int = 0
```

- [ ] **Step 2: Change `spend_familiars()`'s affordability check to the idle pool**

Change:
```gdscript
func spend_familiars(n: int) -> bool:
	if familiars < n:
		return false
	familiars -= n
	EventBus.familiar_gained.emit(familiars)
	return true
```
to:
```gdscript
func spend_familiars(n: int) -> bool:
	if idle_familiars() < n:
		return false
	familiars -= n
	EventBus.familiar_gained.emit(familiars)
	return true
```

- [ ] **Step 3: Add the four new methods**

Add near the other `add_*`/`advance_*` methods, before `to_dict()`:

```gdscript
func idle_familiars() -> int:
	return familiars - familiars_assigned_to_orb


func assign_familiar_to_orb() -> bool:
	if idle_familiars() <= 0:
		return false
	familiars_assigned_to_orb += 1
	add_orb_mana_per_second(1.0)
	return true


func unassign_familiar_from_orb() -> bool:
	if familiars_assigned_to_orb <= 0:
		return false
	familiars_assigned_to_orb -= 1
	add_orb_mana_per_second(-1.0)
	return true


func advance_better_meal_level() -> void:
	better_meal_level = min(better_meal_level + 1, 4)
```

- [ ] **Step 4: Update `to_dict()` and `from_dict()`**

In `to_dict()`, add two entries:
```gdscript
		"familiars_assigned_to_orb": familiars_assigned_to_orb,
		"better_meal_level": better_meal_level,
```

In `from_dict()`, add two matching lines:
```gdscript
	familiars_assigned_to_orb = data.get("familiars_assigned_to_orb", 0)
	better_meal_level = data.get("better_meal_level", 0)
```

- [ ] **Step 5: Manually trace**

1. *Reservation correctly blocks spending beyond the idle pool* — trace: `familiars=5`, assign 3 to orb (`familiars_assigned_to_orb=3`, `orb_mana_per_second` +3.0). `idle_familiars() = 5-3 = 2`. `spend_familiars(3)` (e.g. Bed's cost): `idle_familiars() < 3` → `2 < 3` → `true` → returns `false`, no mutation — correctly blocked even though raw `familiars=5 >= 3`. `spend_familiars(2)`: `2 < 2` → `false` → proceeds, `familiars` drops to `3`, `familiars_assigned_to_orb` stays `3` (unchanged — the spend came from the idle pool only), `idle_familiars()` is now `0`. ✓
2. *Backward compatibility for a player who never touches Orb Channeling* — trace: `familiars_assigned_to_orb` stays `0` forever unless `assign_familiar_to_orb()` is called. `idle_familiars() = familiars - 0 = familiars` — identical to the pre-this-ticket behavior in every respect. ✓
3. *Assign/unassign fail safely at the boundaries* — trace: `idle_familiars()=0`, `assign_familiar_to_orb()` → `0 <= 0` → `true` → returns `false`, no mutation. `familiars_assigned_to_orb=0`, `unassign_familiar_from_orb()` → `0 <= 0` → `true` → returns `false`, no mutation. Neither can go negative. ✓

- [ ] **Step 6: Verify with the real Godot binary**

Run: `cd /home/brian/Public/Programming/Godot/a-blue-orb && /home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64 --headless --quit 2>&1`
Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add autoloads/game_state.gd
git commit -m "Add familiar reservation and Better Meal tier to GameState (Ticket 9c)

spend_familiars() now checks the idle pool (familiars minus those
assigned to the orb), not raw familiars — an assigned familiar is
genuinely unspendable until unassigned, per the project owner's
explicit reservation-model decision."
```

---

### Task 2: Fix `button_action.gd::_can_afford()` for the reservation model

**Files:**
- Modify: `scenes/ui/button_action.gd`

**Interfaces:**
- Consumes: `GameState.idle_familiars()` (Task 1).

- [ ] **Step 1: Change the familiars affordability check**

Change:
```gdscript
func _can_afford() -> bool:
	var cost := ButtonData.calculate_cost(data.base_cost, data.cost_scaling, data.cost_step, _cost_count())
	match data.cost_type:
		"mana":
			return GameState.mana >= cost
		"familiars":
			return float(GameState.familiars) >= cost
		_:
			return true
```
to:
```gdscript
func _can_afford() -> bool:
	var cost := ButtonData.calculate_cost(data.base_cost, data.cost_scaling, data.cost_step, _cost_count())
	match data.cost_type:
		"mana":
			return GameState.mana >= cost
		"familiars":
			return float(GameState.idle_familiars()) >= cost
		_:
			return true
```

- [ ] **Step 2: Manually trace**

*A familiars-costing button correctly shows disabled when familiars are all assigned to the orb, matching what `spend_familiars()` would actually allow* — trace: `familiars=5`, all 5 assigned to orb (`idle_familiars()=0`). Chair's `_can_afford()`: `cost_type="familiars"`, `cost=1.0` → `float(GameState.idle_familiars()) >= 1.0` → `0.0 >= 1.0` → `false` → button shows disabled — CORRECTLY matching that `spend_familiars(1)` would also fail (Task 1's fix). Before this fix, `_can_afford()` would have checked raw `familiars=5 >= 1` → `true` (button shows enabled), but the actual purchase would then silently fail at the deduction step — this fix closes that UI/state inconsistency. ✓

- [ ] **Step 3: Verify with the real Godot binary**

Run: `cd /home/brian/Public/Programming/Godot/a-blue-orb && /home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64 --headless --quit 2>&1`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add scenes/ui/button_action.gd
git commit -m "Make _can_afford() respect familiar reservation (Ticket 9c)

Without this, a familiars-costing button could show as affordable
based on raw familiars while an actual click would fail silently at
the deduction step, since spend_familiars() now checks the idle pool."
```

---

### Task 3: Extend `ButtonData.is_unlock_condition_met` for stat-vs-stat comparison

**Files:**
- Modify: `data/button_data.gd`

**Interfaces:**
- Produces: `is_unlock_condition_met` supporting a stat name (not just a literal number) on either side of `>=`, plus a new `<` operator — Task 5's `better_meal.tres` uses this.

- [ ] **Step 1: Refactor `is_unlock_condition_met` to resolve either side as number-or-stat, add `<`**

Change:
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
		var inner := condition.trim_prefix("has_upgrade(").trim_suffix(")")
		var upgrade_id := inner.trim_prefix("\"").trim_suffix("\"")
		return GameState.has_upgrade(upgrade_id)
	if ">=" in condition:
		var parts := condition.split(">=")
		if parts.size() == 2:
			var stat_name := parts[0].strip_edges()
			var threshold := parts[1].strip_edges().to_float()
			return _get_stat_value(stat_name) >= threshold
	push_error("ButtonData: unrecognized unlock_condition shape \"%s\"" % condition)
	return false
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
		var inner := condition.trim_prefix("has_upgrade(").trim_suffix(")")
		var upgrade_id := inner.trim_prefix("\"").trim_suffix("\"")
		return GameState.has_upgrade(upgrade_id)
	if ">=" in condition:
		var parts := condition.split(">=")
		if parts.size() == 2:
			return _resolve_operand(parts[0].strip_edges()) >= _resolve_operand(parts[1].strip_edges())
	if "<" in condition:
		var parts := condition.split("<")
		if parts.size() == 2:
			return _resolve_operand(parts[0].strip_edges()) < _resolve_operand(parts[1].strip_edges())
	push_error("ButtonData: unrecognized unlock_condition shape \"%s\"" % condition)
	return false


static func _resolve_operand(token: String) -> float:
	if token.is_valid_float():
		return token.to_float()
	return _get_stat_value(token)
```

- [ ] **Step 2: Manually trace**

1. *Every existing `.tres` file's condition still works identically* — trace: `"food_eaten_count >= 5"` splits into `["food_eaten_count", "5"]`; `_resolve_operand("food_eaten_count")` → `"food_eaten_count".is_valid_float()` is `false` → `_get_stat_value("food_eaten_count")` (unchanged behavior). `_resolve_operand("5")` → `"5".is_valid_float()` is `true` → `5.0`. Result: `_get_stat_value("food_eaten_count") >= 5.0` — byte-for-byte the same comparison the old code performed. Same reasoning applies to every other existing `stat >= number` condition in the project (`familiars >= 1`, `confidence_tier >= N`, `has_upgrade(...)` compounds). ✓
2. *Better Meal's stat-vs-stat gate resolves correctly* — trace: `"better_meal_level < better_table_level"` splits into `["better_meal_level", "better_table_level"]` on `<`. Neither `is_valid_float()` (both are identifiers, not numeric strings) → both resolve via `_get_stat_value(...)`. At `better_meal_level=0, better_table_level=0`: `0.0 < 0.0` → `false` → locked. After Better Table reaches level 1 (`better_table_level=1`, `better_meal_level` still `0`): `0.0 < 1.0` → `true` → unlocked. After buying Better Meal once (`better_meal_level=1`): `1.0 < 1.0` → `false` → locked again until Better Table advances further. ✓ Matches "never exceed table tier."
3. *`_get_stat_value`'s new stat needed for this trace (`better_table_level`) resolves correctly* — this requires `_get_stat_value` to have a `"better_table_level"` case; check the current file — Ticket 9b added `better_chair_level`/`better_table_level`/`better_bed_level` fields to `GameState` but did NOT add corresponding cases to `_get_stat_value` (nothing needed them as unlock-condition operands until now). This is a real gap this task must also close — see Step 3.

- [ ] **Step 3: Add `better_table_level` (and, for completeness/consistency, the other three Better-X tiers) to `_get_stat_value`**

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
		"food_eaten_count":
			return float(GameState.food_eaten_count)
		_:
			push_error("ButtonData: unknown stat \"%s\" in unlock_condition" % stat_name)
			return -INF
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
		"better_chair_level":
			return float(GameState.better_chair_level)
		"better_table_level":
			return float(GameState.better_table_level)
		"better_bed_level":
			return float(GameState.better_bed_level)
		"better_meal_level":
			return float(GameState.better_meal_level)
		_:
			push_error("ButtonData: unknown stat \"%s\" in unlock_condition" % stat_name)
			return -INF
```

(`better_meal_level` is included here even though nothing currently writes a condition comparing it as a bare `>=`/`<` right-hand operand beyond Task 5's own `better_meal.tres` — it's needed as the LEFT-hand operand for that exact condition, and adding all four tiers together, not just the one Better Meal strictly needs, keeps `_get_stat_value` a complete, consistent reference for every tier field `GameState` exposes, rather than adding them piecemeal as each becomes strictly necessary.)

- [ ] **Step 4: Re-trace Step 2's point 3 now that the gap is closed**

*`_get_stat_value("better_table_level")` now resolves* — trace: `match "better_table_level"` → `return float(GameState.better_table_level)` — no longer falls through to the `-INF` fail-closed default. Combined with Step 2's trace, `better_meal.tres`'s unlock condition now evaluates correctly end-to-end. ✓

- [ ] **Step 5: Verify with the real Godot binary**

Run: `cd /home/brian/Public/Programming/Godot/a-blue-orb && /home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64 --headless --quit 2>&1`
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add data/button_data.gd
git commit -m "Extend is_unlock_condition_met for stat-vs-stat comparison, add < operator (Ticket 9c)

Backward-compatible: every existing stat >= number condition resolves
identically through the new shared _resolve_operand() path. Needed
for Better Meal's 'never exceed table tier' gate. Also fills a real
gap found while tracing this: _get_stat_value never gained cases for
the four Better-X tier fields Ticket 9b added."
```

---

### Task 4: Add `_effect_better_meal()` to `EffectHandler`

**Files:**
- Modify: `autoloads/effect_handler.gd`

**Interfaces:**
- Produces: `better_meal` effect_id — Task 5's `better_meal.tres` references this.

- [ ] **Step 1: Add the new effect function**

Add after `_effect_better_bed()`:

```gdscript
func _effect_better_meal() -> bool:
	if GameState.better_meal_level >= GameState.better_table_level:
		push_error("EffectHandler: better_meal_level cannot exceed better_table_level")
		return false
	GameState.add_food_heal_bonus(5.0)
	GameState.advance_better_meal_level()
	LogManager.push("the meal tastes a little better.")
	return true
```

- [ ] **Step 2: Add the effect_id to `run_effect()`'s dispatch**

Change:
```gdscript
		"better_bed":
			return _effect_better_bed()
		_:
```
to:
```gdscript
		"better_bed":
			return _effect_better_bed()
		"better_meal":
			return _effect_better_meal()
		_:
```

- [ ] **Step 3: Manually trace**

1. *No self-deduction (the established, twice-fixed bug class doesn't recur a third time)* — trace: `_effect_better_meal()` calls only `add_food_heal_bonus`, `advance_better_meal_level`, `LogManager.push` — no `spend_*` call. Cost is already deducted generically by `button_action.gd` before this function runs. ✓
2. *The real-constraint guard is reachable and correct, distinct from the flat-4 pattern* — trace: unlike `_effect_better_chair/table/bed`'s `>= 4` guards, this one checks `better_meal_level >= better_table_level` directly. If somehow called with `better_meal_level=2, better_table_level=2` (Meal caught up to Table, shouldn't be purchasable per the `.tres`'s own `unlock_condition`, but this guard defends the effect layer independently): `2 >= 2` → `true` → `push_error`, `return false`, no mutation. ✓
3. *Cumulative bonus matches the doc's "+5 HP restore per level"* — trace: each successful call adds `5.0` to `food_heal_bonus` (shared with Table's own contributions — additive, no conflict) and advances the level by exactly `1`. ✓

- [ ] **Step 4: Verify with the real Godot binary**

Run: `cd /home/brian/Public/Programming/Godot/a-blue-orb && /home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64 --headless --quit 2>&1`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add autoloads/effect_handler.gd
git commit -m "Add _effect_better_meal (Ticket 9c)

Guards the real 'never exceed table tier' constraint directly,
unlike the other three Better-X effects' flat >=4 guards — defense
in depth alongside better_meal.tres's own unlock_condition."
```

---

### Task 5: Create `better_meal.tres`

**Files:**
- Create: `data/buttons/house/better_meal.tres`

**Interfaces:**
- Consumes: `effect_id="better_meal"` (Task 4), `count_seed_source`/`max_purchases` (Ticket 9b/11), the new `<` operator (Task 3).

- [ ] **Step 1: Create the file**

```
[gd_resource type="Resource" load_steps=2 format=3]

[ext_resource type="Script" path="res://data/button_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "better_meal"
labels = Array[String](["A Better Meal"])
cost_type = "mana"
base_cost = 10.0
cost_scaling = "double"
cost_step = 0.0
cooldown_sec = 0.0
unlock_condition = "better_meal_level < better_table_level"
effect_id = "better_meal"
flavor_lines = Array[String]([])
one_shot = false
button_column = 2
sort_order = 8
tier_source = ""
cost_count_source = ""
room_description_fragment = ""
max_purchases = 4
cooldown_gate_condition = ""
count_seed_source = "better_meal_level"
```

- [ ] **Step 2: Verify**

Run: `grep -E 'type="Resource"|type="ButtonData"' data/buttons/house/better_meal.tres`
Expected: only the `type="Resource"` header line matches — no `type="ButtonData"` anywhere (the established, previously-fixed header bug).

- [ ] **Step 3: Verify with the real Godot binary**

Run: `cd /home/brian/Public/Programming/Godot/a-blue-orb && /home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64 --headless --quit 2>&1`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add data/buttons/house/better_meal.tres
git commit -m "Add better_meal.tres (Ticket 9c)"
```

---

### Task 6: Create `OrbChannelManager` autoload, register

**Files:**
- Create: `autoloads/orb_channel_manager.gd`
- Modify: `project.godot`

**Interfaces:**
- Consumes: `GameState.orb_mana_per_second`, `GameState.add_mana()`.

- [ ] **Step 1: Write `autoloads/orb_channel_manager.gd`**

```gdscript
extends Node

const TICK_INTERVAL_SEC: float = 1.0

var _timer: Timer


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = TICK_INTERVAL_SEC
	_timer.timeout.connect(_on_tick)
	add_child(_timer)
	_timer.start()


func _on_tick() -> void:
	if GameState.orb_mana_per_second > 0.0:
		GameState.add_mana(GameState.orb_mana_per_second)
```

- [ ] **Step 2: Register it in `project.godot`**

Current `[autoload]` section (after Ticket 11, seven entries: EventBus, GameState, LogManager, EffectHandler, InputGuard, RegenManager, SaveManager). Append an eighth line:

```
OrbChannelManager="*res://autoloads/orb_channel_manager.gd"
```

- [ ] **Step 3: Verify**

Run: `tail -11 project.godot`
Expected: the eight autoload lines, `OrbChannelManager` last.

- [ ] **Step 4: Manually trace**

*No income before any familiar is assigned* — trace: fresh state, `orb_mana_per_second=0.0` (unchanged default). `_on_tick()`'s guard `0.0 > 0.0` is `false` → `add_mana` never called. Once `assign_familiar_to_orb()` (Task 1) raises it to `1.0`, subsequent ticks add `1.0` mana per second, clamped by nothing (mana has no cap, unlike health). ✓

- [ ] **Step 5: Verify with the real Godot binary**

Run: `cd /home/brian/Public/Programming/Godot/a-blue-orb && /home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64 --headless --quit 2>&1`
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add autoloads/orb_channel_manager.gd project.godot
git commit -m "Add OrbChannelManager autoload (Ticket 9c)

Ticks orb_mana_per_second into mana once a second, following
RegenManager's established pattern. Not gated on blackout — mana
income isn't an HP-spending action, unlike RegenManager's health
regen, which blackout specifically exists to gate."
```

---

### Task 7: Create `orb_channeling.tscn`

**Files:**
- Create: `scenes/ui/orb_channeling.gd`
- Create: `scenes/ui/orb_channeling.tscn`

**Interfaces:**
- Consumes: `GameState.assign_familiar_to_orb()`/`unassign_familiar_from_orb()`/`idle_familiars()`/`familiars_assigned_to_orb` (Task 1), `EventBus.familiar_gained` (Ticket 3), `InputGuard.try_register_click()` (Ticket 7).

- [ ] **Step 1: Write `scenes/ui/orb_channeling.gd`**

```gdscript
extends Control

@onready var _count_label: Label = $Root/CountLabel
@onready var _info_label: Label = $Root/InfoLabel
@onready var _up_button: Button = $Root/UpButton
@onready var _down_button: Button = $Root/DownButton


func _ready() -> void:
	_up_button.pressed.connect(_on_up_pressed)
	_down_button.pressed.connect(_on_down_pressed)
	EventBus.familiar_gained.connect(_on_familiar_gained)
	_refresh()


func _on_familiar_gained(_new_total: int) -> void:
	_refresh()


func _on_up_pressed() -> void:
	if not InputGuard.try_register_click():
		return
	GameState.assign_familiar_to_orb()
	_refresh()


func _on_down_pressed() -> void:
	if not InputGuard.try_register_click():
		return
	GameState.unassign_familiar_from_orb()
	_refresh()


func _refresh() -> void:
	visible = GameState.familiars >= 1
	_count_label.text = str(GameState.familiars_assigned_to_orb)
	_info_label.text = "(%d idle)" % GameState.idle_familiars()
	_up_button.disabled = GameState.idle_familiars() <= 0
	_down_button.disabled = GameState.familiars_assigned_to_orb <= 0
```

- [ ] **Step 2: Write `scenes/ui/orb_channeling.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scenes/ui/orb_channeling.gd" id="1"]

[node name="OrbChanneling" type="Control"]
script = ExtResource("1")

[node name="Root" type="HBoxContainer" parent="."]

[node name="NameLabel" type="Label" parent="Root"]
text = "Orb Channeling"

[node name="DownButton" type="Button" parent="Root"]
text = "-"

[node name="CountLabel" type="Label" parent="Root"]
text = "0"

[node name="UpButton" type="Button" parent="Root"]
text = "+"

[node name="InfoLabel" type="Label" parent="Root"]
text = "(0 idle)"
```

- [ ] **Step 3: Manually trace against the acceptance criteria**

1. *Assign/unassign correctly move familiars between pools, bounds prevent over-assignment* — trace: `familiars=3`, all idle. Click Up 3 times: each click passes `InputGuard`, calls `assign_familiar_to_orb()` (succeeds each time since `idle_familiars()` is `3,2,1` respectively, all `>0`), `_refresh()` updates `_count_label` to `"1"`,`"2"`,`"3"` and `_info_label` to `"(2 idle)"`,`"(1 idle)"`,`"(0 idle)"`. After the 3rd click, `_up_button.disabled` becomes `true` (`idle_familiars() <= 0`) — a 4th click's `assign_familiar_to_orb()` would fail cleanly (Task 1's own guard) even if somehow triggered, but the disabled button prevents it from firing at all. ✓
2. *Income accumulates* — covered by Task 6's trace (`OrbChannelManager` reads the same `orb_mana_per_second` this component's assign/unassign calls mutate via `add_orb_mana_per_second`).
3. *Hidden until the player has a familiar* — trace: fresh save, `familiars=0` → `_refresh()`'s `visible = GameState.familiars >= 1` → `false` → component hidden. After `Summon Familiar` fires `EventBus.familiar_gained(1)` → `_on_familiar_gained` → `_refresh()` → `visible = true`. ✓

- [ ] **Step 4: Verify with the real Godot binary**

Run: `cd /home/brian/Public/Programming/Godot/a-blue-orb && /home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64 --headless --quit 2>&1`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add scenes/ui/orb_channeling.gd scenes/ui/orb_channeling.tscn
git commit -m "Add orb_channeling.tscn (Ticket 9c)

Not a ButtonData/button_action.tscn instance — a continuous
assign/unassign allocator doesn't fit that single-click-effect shape.
Hidden until the player has at least one familiar, matching the
precedent Eat Bread already established for familiar-gated content."
```

---

### Task 8: Wire `orb_channeling.tscn` into `area_tab.tscn`, cross-check, commit closing the issue

**Files:**
- Modify: `scenes/ui/area_tab.tscn`

**Interfaces:**
- Consumes: `orb_channeling.tscn` (Task 7).

- [ ] **Step 1: Add the ext_resource and node**

Change the `[gd_scene ...]` header from `load_steps=5` to `load_steps=6`.

Add a third `[ext_resource]` line after the existing two:
```
[ext_resource type="PackedScene" path="res://scenes/ui/orb_channeling.tscn" id="3"]
```

Add a new node immediately after the `[node name="ColumnUpgrades" ...]` declaration (making it `ColumnUpgrades`'s first child, appearing above the dynamically-loaded upgrade buttons):
```
[node name="OrbChanneling" parent="Root/Content/ButtonGrid/ColumnUpgrades" instance=ExtResource("3")]
```

- [ ] **Step 2: Verify**

Run: `cat scenes/ui/area_tab.tscn`
Expected: `load_steps=6`, three `[ext_resource]` lines (`area_tab.gd`, `stat_bar.tscn`, `orb_channeling.tscn`), and the new `OrbChanneling` node positioned right after `ColumnUpgrades`, before `RoomInfo`.

- [ ] **Step 3: Doc cross-check**

Read `docs/architecture.md` §6 and confirm: Orb Channeling's `+1 mana/sec per familiar assigned` rate matches `assign_familiar_to_orb()`'s `add_orb_mana_per_second(1.0)` exactly; Better Meal's `10 mana base, ×2/upgrade, +5 HP restore per level` matches `better_meal.tres`'s `base_cost`/`cost_scaling` and `_effect_better_meal()`'s `add_food_heal_bonus(5.0)` exactly. State explicitly what was checked and found.

- [ ] **Step 4: Final full-project headless check**

Run: `cd /home/brian/Public/Programming/Godot/a-blue-orb && /home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64 --headless --quit 2>&1`
Expected: no errors — confirms `area_tab.tscn`'s new node reference and `orb_channeling.tscn`'s `$Root/...` paths all resolve.

- [ ] **Step 5: Real executed integration test — following Ticket 11's precedent, not manual trace, for the GameState reservation and stat-vs-stat logic**

Write a throwaway headless script to a scratchpad location (never the project repo), exercising the real autoloads (reference them via `root.get_node("Name")`, not bare identifiers, if the script itself is the `--script`/`SceneTree` target — a Godot quirk confirmed during Ticket 11's equivalent step: bare autoload identifiers don't compile-time-resolve inside a script that IS the main-loop target, even though the autoloads are genuinely present at runtime). Example:

```gdscript
extends SceneTree

func _initialize():
	var GameState = root.get_node("GameState")
	var ButtonData = load("res://data/button_data.gd")

	# Reservation model
	GameState.add_familiars(3)
	assert(GameState.idle_familiars() == 3)
	assert(GameState.assign_familiar_to_orb())
	assert(GameState.assign_familiar_to_orb())
	assert(GameState.idle_familiars() == 1)
	assert(GameState.orb_mana_per_second == 2.0)
	assert(not GameState.spend_familiars(2))  # only 1 idle, can't spend 2
	assert(GameState.spend_familiars(1))      # exactly 1 idle, succeeds
	assert(GameState.familiars == 2)
	assert(GameState.familiars_assigned_to_orb == 2)  # unaffected by the spend
	assert(GameState.unassign_familiar_from_orb())
	assert(GameState.orb_mana_per_second == 1.0)

	# Better Meal gating
	GameState.better_table_level = 0
	GameState.better_meal_level = 0
	assert(not ButtonData.is_unlock_condition_met("better_meal_level < better_table_level"))
	GameState.advance_better_table_level()
	assert(ButtonData.is_unlock_condition_met("better_meal_level < better_table_level"))
	GameState.advance_better_meal_level()
	assert(not ButtonData.is_unlock_condition_met("better_meal_level < better_table_level"))

	print("ALL ORB CHANNELING / BETTER MEAL ASSERTIONS PASSED")
	quit()
```

Run it, confirm the pass message with no `Assertion failed` lines, and delete the script afterward. Record the actual output in the report.

- [ ] **Step 6: Commit and push, closing the issue**

```bash
git add scenes/ui/area_tab.tscn
git commit -m "$(cat <<'EOF'
Wire orb_channeling.tscn into area_tab.tscn

Closes #14
EOF
)"
git push
```

- [ ] **Step 7: Verify the issue closed**

Run: `gh issue view 14 --json state --jq .state`
Expected: `CLOSED`

- [ ] **Step 8: Report to the user**

State: both pieces are built and verified with real executed tests (the reservation model and the stat-vs-stat unlock condition), not just manual trace. Flag clearly: (1) the "Plinth" purchase-step ambiguity was resolved by skipping it entirely (Orb Channeling just appears once you have a familiar) — this is a judgment call the user should override if a real purchase/unlock step was intended. (2) A pre-existing staleness gap (buttons don't reactively refresh affordability when familiars change from something else, like assigning to the orb) was found and flagged for Ticket 12, not fixed here. (3) As always, visual layout and the actual click-and-watch-mana-tick-up experience need the user to open the editor. Ticket 12 (Polish / Cross-Check Pass) is next — the last of the original 12 tickets, and a natural place to also address the two flagged gaps (sort_order display ordering, button staleness).

---

## Self-Review Notes

- **Spec coverage:** both of issue #14's acceptance criteria are traced — Orb Channeling's assign/unassign/income/bounds in Task 7 Step 3 and Task 6 Step 4, Better Meal's gating/effect/documentation in Task 5 and Task 4 Step 3. Both open design questions (reservation model, unlock-condition mechanism) were resolved with the project owner directly, not invented.
- **No placeholders:** every function and file is complete. The "Plinth" ambiguity and the button-staleness gap are explicitly flagged as judgment calls / follow-up work, not silently dropped.
- **Type/name consistency:** `GameState.idle_familiars()`/`assign_familiar_to_orb()`/`unassign_familiar_from_orb()` (Task 1) are used identically in Task 2 (`button_action.gd`) and Task 7 (`orb_channeling.gd`). `better_meal_level` (Task 1) is used identically in Task 3's `_get_stat_value`, Task 4's `EffectHandler`, and Task 5's `.tres`. The new `_resolve_operand` helper (Task 3) is used consistently by both the `>=` and `<` branches.

## Execution Handoff

Two execution options:

1. **Subagent-Driven (recommended)** - dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** - execute tasks in this session using `executing-plans`, batch execution with checkpoints.
