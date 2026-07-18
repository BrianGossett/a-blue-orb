# Ticket 2 + 3: GameState + EventBus Autoloads Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `GameState` and `EventBus` autoload singletons — the single source of truth for player stats and the global signal hub every later ticket's UI and gameplay code depends on.

**Architecture:** Two small autoload scripts. `EventBus` is signal declarations only (Ticket 3, GitHub issue #3). `GameState` holds every player-facing stat behind typed setter methods that mutate state then emit the matching `EventBus` signal (Ticket 2, GitHub issue #2). Built together in one run because `GameState`'s methods reference `EventBus` directly — `GameState` cannot compile correctly against Ticket 2's own acceptance criteria until `EventBus` exists (confirmed with the project owner before starting: build both, close both issues).

**Tech Stack:** GDScript, Godot 4.7.

## Global Constraints

- Godot 4.7 project, GL Compatibility renderer. GDScript files use tab indentation (Godot's standard style, matching the project's default editor settings — no `.editorconfig` override exists).
- No `godot`/`godot4` CLI binary exists on this machine (confirmed in the prior ticket). No automated execution of GDScript is possible here — verification is by manual code trace against each acceptance criterion, not by running tests. State this limitation plainly when reporting; the user must open the Godot editor to confirm these autoloads actually load and behave correctly.
- Autoloads are registered in `project.godot`'s `[autoload]` section as `Name="*res://path/to/script.gd"`. `EventBus` must be registered before `GameState` in file order, since `GameState`'s methods reference the `EventBus` global by name.
- `EventBus`'s signal signatures (exact names, exact parameters) are fixed by Ticket 3's issue body — copy them verbatim, no additions, no renames:
  ```gdscript
  signal mana_changed(new_value: float)
  signal health_changed(new_value: float, max_value: float)
  signal familiar_gained(new_total: int)
  signal upgrade_purchased(upgrade_id: String)
  signal health_depleted
  signal blackout_ended
  signal house_tier_changed(new_tier: int)
  ```
- `GameState`'s fields and method signatures are fixed by Ticket 2's issue body (see Task 2 below for the exact list) — every setter must fire its matching signal *after* mutating state, and never before a failed/no-op mutation (e.g. `spend_mana` returning `false` on insufficient funds must NOT emit `mana_changed`, since no mutation happened).
- `house_tier_changed` and `blackout_ended` are NOT emitted by anything built in this plan — `house_tier` has no setter method in Ticket 2's spec (that's Ticket 9's job), and blackout recovery is Ticket 10's job. This is expected; Ticket 3's acceptance criterion that every signal eventually fires is scoped to "by the end of this ticket batch" (Ticket 12), not by the end of this plan.
- Commit convention: this plan closes two issues in one run (per the project owner's explicit choice) — the final commit message must contain both `Closes #2` and `Closes #3`.
- Direct-to-master: no branches, no PRs.

---

### Task 1: Create the `EventBus` autoload (Ticket 3 / issue #3)

**Files:**
- Create: `autoloads/event_bus.gd`

**Interfaces:**
- Produces: a global singleton named `EventBus` (once registered in Task 3) exposing exactly the 7 signals listed in Global Constraints, for Task 2's `GameState` to call.

- [ ] **Step 1: Write the file**

```gdscript
extends Node

signal mana_changed(new_value: float)
signal health_changed(new_value: float, max_value: float)
signal familiar_gained(new_total: int)
signal upgrade_purchased(upgrade_id: String)
signal health_depleted
signal blackout_ended
signal house_tier_changed(new_tier: int)
```

Write this exactly to `autoloads/event_bus.gd`.

- [ ] **Step 2: Verify no gameplay logic crept in**

Run: `cat autoloads/event_bus.gd`
Expected: exactly the 9 lines above (1 `extends` line, 7 `signal` lines, no blank-line-separated logic, no `func` declarations) — this satisfies Ticket 3's acceptance criterion "No gameplay logic lives here."

- [ ] **Step 3: Commit**

```bash
git add autoloads/event_bus.gd
git commit -m "Add EventBus autoload script (Ticket 3)

Signal declarations only, per Ticket 3. Not yet registered as an
autoload singleton or wired to any emitter — that happens in the
next two tasks of this plan."
```

(This commit does NOT close issue #3 yet — closing happens once both scripts are registered and working, in Task 3.)

---

### Task 2: Create the `GameState` autoload (Ticket 2 / issue #2)

**Files:**
- Create: `autoloads/game_state.gd`

**Interfaces:**
- Consumes: `EventBus` global singleton from Task 1 (not yet registered — this task only writes the script; registration is Task 3).
- Produces: `GameState.add_mana`, `GameState.spend_mana`, `GameState.add_health`, `GameState.spend_health`, `GameState.add_familiars`, `GameState.spend_familiars`, `GameState.has_upgrade`, `GameState.mark_upgrade_purchased`, `GameState.to_dict`, `GameState.from_dict` — these exact names/signatures are what Ticket 5 (`EffectHandler`), Ticket 9 (button content), Ticket 10 (blackout), and Ticket 11 (`SaveManager`) will call in later tickets.

- [ ] **Step 1: Write the file**

```gdscript
extends Node

var mana: float = 0.0
var health: float = 50.0
var max_health: float = 50.0
var familiars: int = 0
var resources: Dictionary = {
	"stone": 0,
	"wood": 0,
	"water": 0,
	"crystals": 0,
}
var confidence_tier: int = 0
var house_tier: int = 0
var purchased_upgrades: Array[String] = []
var orb_mana_per_click: float = 0.0
var orb_mana_per_second: float = 0.0
var is_blacked_out: bool = false


func add_mana(amount: float) -> void:
	mana += amount
	EventBus.mana_changed.emit(mana)


func spend_mana(amount: float) -> bool:
	if mana < amount:
		return false
	mana -= amount
	EventBus.mana_changed.emit(mana)
	return true


func add_health(amount: float) -> void:
	health = min(health + amount, max_health)
	EventBus.health_changed.emit(health, max_health)


func spend_health(amount: float) -> void:
	health = max(health - amount, 0.0)
	EventBus.health_changed.emit(health, max_health)
	if health <= 0.0:
		EventBus.health_depleted.emit()


func add_familiars(n: int) -> void:
	familiars += n
	EventBus.familiar_gained.emit(familiars)


func spend_familiars(n: int) -> bool:
	if familiars < n:
		return false
	familiars -= n
	EventBus.familiar_gained.emit(familiars)
	return true


func has_upgrade(id: String) -> bool:
	return purchased_upgrades.has(id)


func mark_upgrade_purchased(id: String) -> void:
	if purchased_upgrades.has(id):
		return
	purchased_upgrades.append(id)
	EventBus.upgrade_purchased.emit(id)


func to_dict() -> Dictionary:
	return {
		"mana": mana,
		"health": health,
		"max_health": max_health,
		"familiars": familiars,
		"resources": resources.duplicate(),
		"confidence_tier": confidence_tier,
		"house_tier": house_tier,
		"purchased_upgrades": purchased_upgrades.duplicate(),
		"orb_mana_per_click": orb_mana_per_click,
		"orb_mana_per_second": orb_mana_per_second,
		"is_blacked_out": is_blacked_out,
	}


func from_dict(data: Dictionary) -> void:
	mana = data.get("mana", 0.0)
	health = data.get("health", 50.0)
	max_health = data.get("max_health", 50.0)
	familiars = data.get("familiars", 0)
	resources = data.get("resources", {"stone": 0, "wood": 0, "water": 0, "crystals": 0})
	confidence_tier = data.get("confidence_tier", 0)
	house_tier = data.get("house_tier", 0)
	purchased_upgrades.assign(data.get("purchased_upgrades", []))
	orb_mana_per_click = data.get("orb_mana_per_click", 0.0)
	orb_mana_per_second = data.get("orb_mana_per_second", 0.0)
	is_blacked_out = data.get("is_blacked_out", false)
```

Write this exactly to `autoloads/game_state.gd`.

Note on `orb_mana_per_click`/`orb_mana_per_second` starting at `0.0`: Ticket 2's issue body doesn't give these two an explicit starting number (unlike `mana`, `health`, `familiars`, etc., which are explicit). `0.0` is the ordinary default for an additive-bonus accumulator field with no stated starting value — Ticket 9's button content is what actually populates the base/bonus amounts later. This is a routine implementation default, not a flagged ambiguity.

- [ ] **Step 2: Manually trace each acceptance criterion against the code**

Since no Godot binary exists to execute this, verify by reading the code:

1. *"Every setter fires the matching EventBus signal after mutating state"* — trace: `add_mana`→`mana_changed` ✓, `spend_mana` (success path only)→`mana_changed` ✓, `add_health`→`health_changed` ✓, `spend_health`→`health_changed` (+ `health_depleted` if it hits 0) ✓, `add_familiars`→`familiar_gained` ✓, `spend_familiars` (success path only)→`familiar_gained` ✓, `mark_upgrade_purchased` (only if newly added)→`upgrade_purchased` ✓. `has_upgrade`, `to_dict`, `from_dict` are not setters (read/serialize only) — correctly fire nothing.
2. *"No public field is ever set directly from outside this script"* — confirm every `var` above has no corresponding direct-write path other than through the listed methods; this can't be fully verified until later tickets actually call `GameState` (nothing to check yet in this diff beyond "the methods exist and are the only mutation surface"). Flag as verified-so-far, re-check when Ticket 5's `EffectHandler` is built.
3. *"`spend_mana(1000)` on a fresh state returns `false` and mana stays at `0`"* — trace: fresh `GameState.mana == 0.0`; `spend_mana(1000)` evaluates `0.0 < 1000` → `true` → returns `false` immediately, `mana` untouched. ✓ This also confirms the class is instantiable and callable without the `EventBus` autoload being registered yet, since the failure path never reaches the `EventBus.mana_changed.emit(...)` line — satisfying "unit-testable in isolation" without needing a live scene tree.

Record this trace in the commit message or report — don't just assert "looks right."

- [ ] **Step 3: Commit**

```bash
git add autoloads/game_state.gd
git commit -m "Add GameState autoload script (Ticket 2)

Single source of truth for player stats, per Ticket 2. References
the EventBus singleton by name but isn't registered as an autoload
yet (Task 3 of this plan handles registration for both scripts
together, since GameState won't resolve the EventBus reference
until it is)."
```

(This commit does NOT close issue #2 yet — same reason as Task 1.)

---

### Task 3: Register both autoloads and close both issues

**Files:**
- Modify: `project.godot`

**Interfaces:**
- Consumes: `autoloads/event_bus.gd` (Task 1), `autoloads/game_state.gd` (Task 2).
- Produces: the registered `EventBus` and `GameState` singletons every later ticket (5, 6, 8, 9, 10, 11) assumes exist and are accessible by name from any script.

- [ ] **Step 1: Add the `[autoload]` section to `project.godot`**

Current file ends with the `[rendering]` section. Append a new `[autoload]` section, with `EventBus` listed before `GameState`:

```
[autoload]

EventBus="*res://autoloads/event_bus.gd"
GameState="*res://autoloads/game_state.gd"
```

- [ ] **Step 2: Verify the section was added correctly**

Run: `tail -5 project.godot`
Expected:
```

[autoload]

EventBus="*res://autoloads/event_bus.gd"
GameState="*res://autoloads/game_state.gd"
```

- [ ] **Step 3: Commit and push, closing both issues**

```bash
git add project.godot
git commit -m "$(cat <<'EOF'
Register EventBus and GameState as autoload singletons

Closes #2
Closes #3
EOF
)"
git push
```

- [ ] **Step 4: Verify both issues closed**

Run: `gh issue view 2 --json state --jq .state && gh issue view 3 --json state --jq .state`
Expected: `CLOSED` printed twice.

- [ ] **Step 5: Report to the user**

State: both autoloads are built and registered; nothing in this diff can be executed/verified here (no Godot binary). What to check in the editor: open the project, confirm it loads with no autoload-related errors in the Output panel (a broken singleton reference shows up immediately on project load), and optionally open the Script editor on `autoloads/game_state.gd` to spot-check there are no red squiggles (parse errors) on the `EventBus.___.emit(...)` lines. Ticket 4 (`LogManager` Autoload) is next.

---

## Self-Review Notes

- **Spec coverage:** every field and method Ticket 2 lists is present with the exact signature given; every signal Ticket 3 lists is present verbatim. Both tickets' acceptance criteria are each addressed by name in Task 2 Step 2 (GameState) and Task 1 Step 2 / Task 3 Step 4 (EventBus's "every signal eventually emitted" criterion is explicitly scoped to the full ticket batch in Global Constraints, not this plan, so it's not a gap).
- **No placeholders:** both scripts are complete, exact GDScript — nothing deferred to "later" within their own scope.
- **Type/name consistency:** `EventBus` and `GameState` autoload names match exactly between the scripts (Task 1/2), the registration (Task 3), and the plan's own Interfaces sections. Signal names/params match Ticket 3's issue body verbatim; method names/params match Ticket 2's issue body verbatim.

## Execution Handoff

Two execution options:

1. **Subagent-Driven (recommended)** - dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** - execute tasks in this session using `executing-plans`, batch execution with checkpoints.
