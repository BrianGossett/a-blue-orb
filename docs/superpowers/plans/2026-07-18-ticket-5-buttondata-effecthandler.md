# Ticket 5: ButtonData Resource + EffectHandler Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the data-driven button system's backbone: the `ButtonData` resource shape (with its cost formula and unlock-condition parser as pure/testable functions) and the `EffectHandler` autoload that dispatches `effect_id` strings to gameplay functions.

**Architecture:** `data/button_data.gd` defines the `ButtonData` Resource shape plus two static functions (`calculate_cost`, `is_unlock_condition_met`) that are testable independent of any button instance. `autoloads/effect_handler.gd` is a new autoload with a `run_effect(effect_id)` dispatcher and five effect functions, each calling only `GameState`'s public methods. Extends `autoloads/game_state.gd` (Ticket 2, already closed) with three methods that were missing but are required for the confidence/furniture effects to work without violating "never mutate GameState fields directly."

**Tech Stack:** GDScript, Godot 4.7.

## Global Constraints

- GDScript files use tab indentation (matches the three existing autoloads).
- No `godot`/`godot4` CLI binary exists on this machine — verification is a manual code trace against each acceptance criterion, not an executed test.
- `ButtonData`'s exact field shape (copied verbatim from the issue body — note this is a superset of `docs/architecture.md` §4, which is missing `one_shot` and `button_column`; the issue body is the current source of truth here, and this drift is worth a note in Ticket 12's doc cross-check pass, not a blocker now):
  ```gdscript
  class_name ButtonData
  extends Resource

  @export var id: String
  @export var labels: Array[String]
  @export var cost_type: String
  @export var base_cost: float
  @export var cost_scaling: String
  @export var cost_step: float
  @export var cooldown_sec: float
  @export var unlock_condition: String
  @export var effect_id: String
  @export var flavor_lines: Array[String]
  @export var one_shot: bool
  @export var button_column: int
  ```
- Cost formula (must be its own pure function, no `self`/instance state — takes explicit params, testable without constructing a `ButtonData`):
  - `linear`: `base_cost + (cost_step * count)`
  - `double`: `base_cost * pow(2, count)`
  - `fixed`: `base_cost` (ignores `count` and `cost_step`)
  - Verified numbers (Summon Familiar: `base_cost=1.0, cost_scaling="linear", cost_step=1.0`): count=0 → 1, count=1 → 2, count=5 → 6. These three values are the acceptance criterion's exact check.
- Unlock-condition parser supports exactly two shapes, matched via `match`/string checks, not a general expression parser: `has_upgrade("id")` and `<stat> >= <number>`, where `<stat>` is one of `mana`, `familiars`, `confidence_tier`, `house_tier` (the numeric `GameState` fields referenced by the House table's conditions, e.g. `"familiars >= 1"`). An empty `unlock_condition` string means "always unlocked" (no gate).
- **GameState extension (approved by the project owner as part of this ticket, not a separate one):** `GameState` (Ticket 2) has no mutator for `orb_mana_per_click`, `orb_mana_per_second`, or a way to advance `confidence_tier` — yet the confidence and chair effects both need to increase `orb_mana_per_click`. Add three methods to `autoloads/game_state.gd`:
  - `add_orb_mana_per_click(amount: float) -> void`
  - `add_orb_mana_per_second(amount: float) -> void`
  - `advance_confidence_tier() -> void` (clamped to max 4, per Ticket 2's own field comment)
  None of these fire an `EventBus` signal — Ticket 3's fixed signal list has nothing for these fields, matching the precedent that not every field has a signal (only the ones Ticket 2 originally specified do).
- **Default value correction:** `orb_mana_per_click` currently defaults to `0.0` in `game_state.gd`. This was an ungiven-default judgment call made while building Ticket 2, before any code actually consumed the field. Now that `_effect_touch_orb()` needs to read it (base mana-per-click, which the design doc fixes at `+1 mana`), the default must be `1.0` — 0.0 would mean touching the orb does nothing on a fresh save, which contradicts the design doc. Change both the field's default declaration and its `from_dict()` fallback default to `1.0`. `orb_mana_per_second` stays `0.0` (no passive gain until the Orb Plinth/channeling allocator is built, later in Ticket 9) — do not touch that one.
- **Explicitly deferred, not built here (documented via a short code comment where it matters, not silently dropped):**
  - Confidence's "+5 HP cost on touch" growth per tier — `_effect_touch_orb()` keeps a fixed 5.0 HP cost. Scaling this needs a new GameState field (an accumulating per-click health cost) that isn't part of this ticket's approved GameState extension. Ticket 9 owns wiring up `confidence_N.tres` and `touch_orb.tres` for real and should add it then.
  - Chair's "+1 HP regen/min" passive effect — no ticking/regen system exists anywhere in the codebase yet (not in any of the 12 tickets as its own build item). `_effect_add_chair()` applies only its instant/one-shot components (cost, upgrade flag, `orb_mana_per_click` bonus); the passive regen part is left for whichever ticket ends up building a regen mechanism.
- Effect functions must never write `GameState` fields directly — every mutation goes through a `GameState` method call (existing or newly added in this plan).
- `EffectHandler` is a new autoload (`autoloads/effect_handler.gd`, `extends Node`), registered in `project.godot`'s `[autoload]` section as a fourth entry (order doesn't matter relative to the other three — it doesn't get referenced by them, only calls into them).
- Direct-to-master, commit message must contain `Closes #5`.

---

### Task 1: Extend `GameState` with the three missing methods and fix the `orb_mana_per_click` default

**Files:**
- Modify: `autoloads/game_state.gd`

**Interfaces:**
- Produces: `GameState.add_orb_mana_per_click(amount: float) -> void`, `GameState.add_orb_mana_per_second(amount: float) -> void`, `GameState.advance_confidence_tier() -> void` — Task 3's `EffectHandler` calls all three.

- [ ] **Step 1: Change the field default**

In `autoloads/game_state.gd:16`, change:
```gdscript
var orb_mana_per_click: float = 0.0
```
to:
```gdscript
var orb_mana_per_click: float = 1.0
```

- [ ] **Step 2: Change the `from_dict` fallback default to match**

In `autoloads/game_state.gd:95`, change:
```gdscript
	orb_mana_per_click = data.get("orb_mana_per_click", 0.0)
```
to:
```gdscript
	orb_mana_per_click = data.get("orb_mana_per_click", 1.0)
```

- [ ] **Step 3: Add the three new methods**

Add after the existing `mark_upgrade_purchased` function (`autoloads/game_state.gd:63-67`), before `to_dict()`:

```gdscript
func add_orb_mana_per_click(amount: float) -> void:
	orb_mana_per_click += amount


func add_orb_mana_per_second(amount: float) -> void:
	orb_mana_per_second += amount


func advance_confidence_tier() -> void:
	confidence_tier = min(confidence_tier + 1, 4)
```

- [ ] **Step 4: Manually trace the new methods and the default change**

1. *`add_orb_mana_per_click(3.0)` on a fresh state* — trace: `orb_mana_per_click` starts at `1.0` (new default), becomes `1.0 + 3.0 = 4.0`. No `EventBus` signal fires (none exists for this field — confirmed against Ticket 3's fixed 7-signal list). ✓
2. *`advance_confidence_tier()` called 5 times on a fresh state* — trace: `confidence_tier` goes `0→1→2→3→4→4` (the 5th call: `min(4+1, 4) = 4`, clamped, matching Ticket 2's own "max 4" comment on the field). ✓
3. *Fresh `GameState.orb_mana_per_click == 1.0`* — confirms the corrected default matches the design doc's base "+1 mana" per orb touch, so `_effect_touch_orb()` (Task 3) reading this field on a brand-new save produces the right number without any confidence upgrades yet. ✓

- [ ] **Step 5: Commit**

```bash
git add autoloads/game_state.gd
git commit -m "Extend GameState for Ticket 5's effect functions

Adds add_orb_mana_per_click, add_orb_mana_per_second, and
advance_confidence_tier — Ticket 2 didn't include mutators for these
fields, but the confidence/chair effect functions built in this same
ticket batch need them to avoid mutating GameState fields directly.

Also corrects orb_mana_per_click's default from 0.0 to 1.0: nothing
consumed this field until now, and 0.0 would mean touching the orb
does nothing on a fresh save, contradicting the design doc's base
+1 mana per touch."
```

(Does not close issue #5 yet — that happens once `ButtonData` and `EffectHandler` are also built, in Task 3.)

---

### Task 2: Create the `ButtonData` resource with its cost formula and unlock-condition parser

**Files:**
- Create: `data/button_data.gd`

**Interfaces:**
- Produces: the `ButtonData` resource class (12 exported fields per Global Constraints), `ButtonData.calculate_cost(base_cost, cost_scaling, cost_step, count) -> float`, `ButtonData.is_unlock_condition_met(condition: String) -> bool` — Ticket 6's `button_action.tscn` will call both static functions on whatever `ButtonData` resource it's bound to.
- Consumes: `GameState` (for `is_unlock_condition_met`'s stat lookups — `mana`, `familiars`, `confidence_tier`, `house_tier`).

- [ ] **Step 1: Write the file**

```gdscript
class_name ButtonData
extends Resource

@export var id: String
@export var labels: Array[String]
@export var cost_type: String
@export var base_cost: float
@export var cost_scaling: String
@export var cost_step: float
@export var cooldown_sec: float
@export var unlock_condition: String
@export var effect_id: String
@export var flavor_lines: Array[String]
@export var one_shot: bool
@export var button_column: int


static func calculate_cost(base_cost: float, cost_scaling: String, cost_step: float, count: int) -> float:
	match cost_scaling:
		"linear":
			return base_cost + (cost_step * count)
		"double":
			return base_cost * pow(2, count)
		"fixed":
			return base_cost
		_:
			push_error("ButtonData: unknown cost_scaling \"%s\"" % cost_scaling)
			return base_cost


static func is_unlock_condition_met(condition: String) -> bool:
	if condition.is_empty():
		return true
	if condition.begins_with("has_upgrade("):
		var inner := condition.trim_prefix("has_upgrade(").trim_suffix(")")
		var id := inner.trim_prefix("\"").trim_suffix("\"")
		return GameState.has_upgrade(id)
	if ">=" in condition:
		var parts := condition.split(">=")
		if parts.size() == 2:
			var stat_name := parts[0].strip_edges()
			var threshold := parts[1].strip_edges().to_float()
			return _get_stat_value(stat_name) >= threshold
	push_error("ButtonData: unrecognized unlock_condition shape \"%s\"" % condition)
	return false


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
			push_error("ButtonData: unknown stat \"%s\" in unlock_condition" % stat_name)
			return 0.0
```

- [ ] **Step 2: Manually trace each acceptance criterion**

1. *Cost formula produces the design doc's numbers for Summon Familiar (`base_cost=1.0, cost_scaling="linear", cost_step=1.0`) at familiars = 0, 1, 5* — trace: `calculate_cost(1.0, "linear", 1.0, 0)` = `1.0 + (1.0*0)` = `1.0` ✓; `calculate_cost(1.0, "linear", 1.0, 1)` = `1.0 + (1.0*1)` = `2.0` ✓; `calculate_cost(1.0, "linear", 1.0, 5)` = `1.0 + (1.0*5)` = `6.0` ✓. Matches the required 1/2/6 mana exactly.
2. *`unlock_condition` parsing supports `stat >= number` and `has_upgrade("id")`* — trace: `is_unlock_condition_met("familiars >= 1")` splits on `">="` into `["familiars ", " 1"]`, strips edges to `"familiars"` and `"1"`, `_get_stat_value("familiars")` returns `float(GameState.familiars)`, compared `>= 1.0`. ✓. `is_unlock_condition_met("has_upgrade(\"chair\")")`: `trim_prefix("has_upgrade(")` on `has_upgrade("chair")` leaves `"chair")`, `trim_suffix(")")` leaves `"chair"`, `trim_prefix("\"")`/`trim_suffix("\"")` leave `chair`, calls `GameState.has_upgrade("chair")`. ✓
3. *Effect functions never mutate GameState fields directly* — not applicable to this file (no `GameState` field writes appear anywhere in `button_data.gd`; it only reads `GameState.mana`/`familiars`/`confidence_tier`/`house_tier` and calls `GameState.has_upgrade()`, a read-only method). This criterion is really about Task 3's `EffectHandler` — re-verified there.

- [ ] **Step 3: Commit**

```bash
git add data/button_data.gd
git commit -m "Add ButtonData resource with cost formula and unlock parser (Ticket 5)

calculate_cost and is_unlock_condition_met are static functions,
testable independent of any button instance or .tres file."
```

(Does not close issue #5 yet — happens in Task 3.)

---

### Task 3: Create the `EffectHandler` autoload, register it, and close the issue

**Files:**
- Create: `autoloads/effect_handler.gd`
- Modify: `project.godot`

**Interfaces:**
- Consumes: `GameState`'s methods (original 8 from Ticket 2 plus the 3 added in Task 1), `LogManager.push()`.
- Produces: `EffectHandler.run_effect(effect_id: String) -> bool` — Ticket 6's `button_action.tscn` calls this after deducting cost, passing the clicked button's `effect_id`.

- [ ] **Step 1: Write `autoloads/effect_handler.gd`**

```gdscript
extends Node
# Autoload (not a static class): effect functions call other autoloads
# (GameState, LogManager) by singleton name, which reads most naturally
# from a Node in the same autoload family.


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
			push_error("EffectHandler: unknown effect_id \"%s\"" % effect_id)
			return false


func _effect_touch_orb() -> bool:
	GameState.add_mana(GameState.orb_mana_per_click)
	# Fixed 5 HP cost — confidence's "+5 HP cost" growth per tier isn't
	# wired up yet; needs a new GameState field Ticket 9 should add
	# when it builds confidence_N.tres and touch_orb.tres for real.
	GameState.spend_health(5.0)
	LogManager.push("you gingerly touch the orb.")
	return true


func _effect_summon_familiar() -> bool:
	GameState.add_familiars(1)
	LogManager.push("you summon a familiar.")
	return true


func _effect_eat_food() -> bool:
	GameState.add_health(10.0)
	LogManager.push("you eat the bread. it is simple, but satisfying.")
	return true


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

- [ ] **Step 2: Manually trace each acceptance criterion**

1. *`.tres` creation + cost formula* — already traced in Task 2; not re-verified here.
2. *`unlock_condition` parsing* — already traced in Task 2; not re-verified here.
3. *"Effect functions never mutate GameState fields directly — they call GameState's public methods"* — trace every function: `_effect_touch_orb` calls `GameState.add_mana(...)`, `GameState.spend_health(...)` (both methods, no field writes). `_effect_summon_familiar` calls `GameState.add_familiars(...)`. `_effect_eat_food` calls `GameState.add_health(...)`. `_effect_gain_confidence` calls `GameState.add_orb_mana_per_click(...)` and `GameState.advance_confidence_tier()`. `_effect_add_chair` calls `GameState.spend_familiars(...)`, `GameState.mark_upgrade_purchased(...)`, `GameState.add_orb_mana_per_click(...)`. Every single `GameState` interaction across all five functions is a method call — grep confirms no `GameState.<field> =` assignment appears anywhere in this file. ✓

- [ ] **Step 3: Register `EffectHandler` in `project.godot`**

Current `[autoload]` section (after Ticket 4):
```
[autoload]

EventBus="*res://autoloads/event_bus.gd"
GameState="*res://autoloads/game_state.gd"
LogManager="*res://autoloads/log_manager.gd"
```

Append a fourth line:
```
[autoload]

EventBus="*res://autoloads/event_bus.gd"
GameState="*res://autoloads/game_state.gd"
LogManager="*res://autoloads/log_manager.gd"
EffectHandler="*res://autoloads/effect_handler.gd"
```

- [ ] **Step 4: Verify the section**

Run: `tail -7 project.godot`
Expected:
```

[autoload]

EventBus="*res://autoloads/event_bus.gd"
GameState="*res://autoloads/game_state.gd"
LogManager="*res://autoloads/log_manager.gd"
EffectHandler="*res://autoloads/effect_handler.gd"
```

- [ ] **Step 5: Commit and push, closing the issue**

```bash
git add autoloads/effect_handler.gd project.godot
git commit -m "$(cat <<'EOF'
Add EffectHandler autoload with 5 effect functions

Closes #5
EOF
)"
git push
```

- [ ] **Step 6: Verify the issue closed**

Run: `gh issue view 5 --json state --jq .state`
Expected: `CLOSED`

- [ ] **Step 7: Report to the user**

State: `ButtonData` (cost formula + unlock parser) and `EffectHandler` (5 effect functions covering touch_orb, summon_familiar, eat_food, gain_confidence, add_chair) are built and registered; `GameState` gained 3 new methods and a corrected default. Nothing executed (no Godot binary) — all verification is manual trace. Two things explicitly deferred and worth knowing about: confidence's growing HP-cost-per-touch and chair's passive HP-regen-per-minute have no mechanism yet and will need new work when Ticket 9 builds the real House content. What to check in the editor: project loads with no autoload/parse errors; optionally create a scratch `.tres` for `touch_orb` or `summon_familiar` in the inspector to confirm `ButtonData` shows up as an assignable resource type. Ticket 6 (`button_action.tscn` Generic Button Component) is next.

---

## Self-Review Notes

- **Spec coverage:** all three of Ticket 5's acceptance criteria are traced explicitly (cost formula numbers in Task 2 Step 2.1, unlock parsing in Task 2 Step 2.2, no-direct-mutation in Task 3 Step 2.3). The `ButtonData` field list matches the issue body verbatim, including the two fields (`one_shot`, `button_column`) that `architecture.md` §4 is currently missing — flagged as a doc-drift note for Ticket 12, not treated as a conflict to resolve now.
- **No placeholders:** every function is a complete, real implementation. The two explicitly deferred behaviors (confidence HP-cost growth, chair regen) are not silently dropped — they're named, explained, and pointed at Ticket 9 via both the plan's Global Constraints and short in-code comments, which is different from a bare `TODO`.
- **Type/name consistency:** `GameState.add_orb_mana_per_click`/`add_orb_mana_per_second`/`advance_confidence_tier` are defined in Task 1 with the exact names Task 3's `EffectHandler` calls. `ButtonData.calculate_cost`/`is_unlock_condition_met` names match what Task 3's self-review references back to Task 2.

## Execution Handoff

Two execution options:

1. **Subagent-Driven (recommended)** - dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** - execute tasks in this session using `executing-plans`, batch execution with checkpoints.
