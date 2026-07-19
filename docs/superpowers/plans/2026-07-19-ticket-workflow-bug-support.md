# Bug-Ticket Support + GUT Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a third ticket-workflow skill (`make-ticket`) that authors feature *and* bug tickets into a standing `docs/tickets.md`, extend `sync-tickets`/`work-ticket` so bug tickets flow through the same GitHub pipeline plus a permanent `docs/bugs.md` history log, and replace `work-ticket`'s prose-tracing verification with real GUT (Godot Unit Test) runs.

**Architecture:** `docs/tickets.md` becomes the single source-of-truth backlog (feature + bug tickets, one shared numbering sequence); `sync-tickets` turns entries into dual-labeled (`ticket`+`bug`) GitHub issues; `work-ticket` implements the next open issue, verifying logic via a real headless GUT suite under `tests/unit/` instead of manual trace, and on a reported problem authors a bug ticket + `docs/bugs.md` stub instead of pushing broken work. `docs/bugs.md` is a permanent, append-only resolution log, separate from the backlog, updated in place when a bug closes.

**Tech Stack:** Godot 4.7 / GDScript, GUT v9.7.1 (vendored addon), `gh` CLI, existing `.claude/skills/{work-ticket,sync-tickets}` conventions.

**Source spec:** `/home/brian/Downloads/claude-code-prompt.md` (seven "pieces" — this plan's tasks map onto them; a few pieces are split into multiple tasks for review granularity, and Piece 4/Piece 5's order is swapped from the source doc for a cleaner dependency order — see Task 8's note).

## Global Constraints

- Direct-to-master: no branches, no PRs — matches `work-ticket`/`sync-tickets`'s existing convention. Every task in this plan is its own commit.
- `.tres` files defining custom `Resource` subclasses must use `type="Resource"` header + `script = ExtResource(...)`, never `type="ClassName"` directly (known load bug in this engine build). Not directly touched by this plan, but any new `.tres` must follow it.
- GDScript: never `var x := min(...)` / `max(...)` — Variant-inference parse error in this engine build. Always `var x: float = min(...)`.
- **Godot binary resolution order** (used by Task 2's setup and Task 11's `work-ticket` edit — both must state this order so each skill file is self-contained): (a) `command -v godot4` / `command -v godot` on PATH, (b) `$GODOT_BIN` env var, (c) a path saved in `.claude/godot-binary-path.txt` (gitignored — machine-specific, never commit it), (d) ask the user once for the path and save it to that file. On this machine today, (a) and (b) both miss; the real binary is at `/home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64` — Task 2 writes this path directly to the cache file rather than asking, since the controller already knows it from this session.
- GUT version: pin to tag `v9.7.1` when vendoring `addons/gut/` (latest stable GUT release, supports Godot 4.x).
- Standard test-run command once GUT is installed: `<godot_bin> --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit`.
- `docs/tickets.md` ticket/bug numbering is **one shared, interleaved sequence** (`## Ticket N —` and `## Bug N —` both count) — never two separate counters. Parse `N` as a leading integer plus an optional letter suffix (e.g. `9`, `9b`, `9c`) and sort/max by `(integer, suffix)` — plain string sort puts `"10"` before `"9b"`, which is wrong.
- `docs/design_doc.md` is a manually-synced Google Doc export — never edit it directly; flag proposed changes to the user as "update the Google Doc: ...".
- GUT tests cover **logic only** (state mutation, signal emission, calculation, unlock conditions) — never visual/layout/feel. `work-ticket`'s editor-check pause still exists for that; GUT shrinks what's left in that pause, it doesn't replace it.
- **Autoload-singleton test isolation:** `EffectHandler`, `scenes/ui/button_action.gd`, and `scenes/ui/area_tab.gd` all reference the live `GameState`/`EventBus`/`LogManager`/`InputGuard` autoload singletons directly by name (not injected dependencies) — any test that exercises them runs against the *live* singleton, not a fresh instance. Reset relevant `GameState` fields at the start of every such test via `GameState.from_dict({})` (every field falls back to its documented default because `from_dict` reads each key with `.get(key, default)`) — do this in GUT's `before_each()`. `autoloads/game_state.gd`'s own methods don't reference the singleton by name internally (only `EventBus.*.emit`), so **pure `GameState` logic tests** (Task 3) may instead instantiate a fresh, non-singleton copy via `load("res://autoloads/game_state.gd").new()` for full isolation — prefer that where possible, fall back to the live-singleton-plus-reset pattern only where the code under test (EffectHandler, button_action.gd, area_tab.gd) hardcodes the singleton name.
- A criterion that is a static/code-review invariant rather than an observable runtime behavior (e.g. "no gameplay logic lives in this file", "no public field is ever set directly from outside this script") is **not** GUT-testable — note it explicitly as skipped-and-why in the task report rather than forcing a test or silently dropping it.

---

### Task 1: Backfill existing tickets into `docs/tickets.md` (Piece 1)

**Files:**
- Create: `docs/tickets.md`

**Interfaces:**
- Produces: `docs/tickets.md` in the exact format `sync-tickets` already parses (`## Ticket N — Title` / separated by `---` / `**Acceptance criteria:**` bullets), consumed by every later task in this plan.

- [ ] **Step 1: Fetch every ticket-labeled issue, all states**

  ```bash
  gh issue list --label ticket --state all --json number,title,body,state,labels --limit 200
  ```

- [ ] **Step 2: Sort by parsed ticket number, not GitHub issue number**

  Parse `N` (and optional letter suffix) out of each title (`Ticket N —` or `Bug N —`). Sort by `(int(N), suffix)`. As of this plan, the 14 existing issues are (issue# → parsed order): `1,2,3,4,5,6,7,8,9,9b(#13),9c(#14),10,11,12` — confirm this matches what step 1 returns; if it doesn't, trust the parse, not issue-number order.

- [ ] **Step 3: Reconstruct one entry per issue**

  For each issue, in parsed order:
  - Heading: `## Ticket N — Title` normally, or `## Bug N — Title` if the issue carries the `bug` label (none currently do — all 14 existing issues are `Ticket` entries, this branch just needs to exist for correctness).
  - Directly under the heading: `**Status:** Open` or `**Status:** Closed` (from the issue's `state`), then `**GitHub issue:** #<n>`.
  - Body: the issue body **verbatim**, including checkbox state exactly as-is (`- [x]` / `- [ ]`) — do not flatten checked boxes back to plain bullets; the checked state is real completion history.

- [ ] **Step 4: Assemble the file**

  Concatenate all 14 reconstructed entries in ticket-number order, each separated by a `---` line (matching `sync-tickets`'s split-on-`---` parsing). No file header needed beyond the entries themselves — this mirrors what `sync-tickets` already expects to read back.

- [ ] **Step 5: Verify**

  - `grep -c '^## Ticket' docs/tickets.md` → `14`.
  - Spot-check: `Ticket 12` (the one open issue, #12) shows `**Status:** Open`; every other entry shows `**Status:** Closed`.
  - Confirm `sync-tickets`'s existing skip-logic would treat all 14 as already-synced (title-prefix match `Ticket N —` against the existing `gh issue list` output) — no code change needed for this, just confirm by inspection that every heading's `N —` prefix exactly matches an existing issue title's prefix.

- [ ] **Step 6: Commit**

  ```bash
  git add docs/tickets.md
  git commit -m "Backfill docs/tickets.md from existing GitHub issues (Piece 1)"
  ```

---

### Task 2: Install GUT, create `tests/unit/`, resolve the Godot binary path (Piece 2 setup)

**Files:**
- Create: `addons/gut/` (vendored from GUT v9.7.1)
- Create: `tests/unit/test_smoke.gd`
- Create: `.claude/godot-binary-path.txt` (gitignored — created on disk but never committed)
- Modify: `project.godot`
- Modify: `.gitignore`

**Interfaces:**
- Produces: a working `<godot_bin> --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit` command and a `tests/unit/` root, consumed by Tasks 3–6 and by Task 11's `work-ticket` edit.

- [ ] **Step 1: Vendor GUT v9.7.1**

  ```bash
  git clone --depth 1 --branch v9.7.1 https://github.com/bitwes/Gut.git /tmp/gut-vendor
  mkdir -p addons
  cp -r /tmp/gut-vendor/addons/gut addons/gut
  rm -rf /tmp/gut-vendor
  ```

  Confirm `addons/gut/plugin.cfg` and `addons/gut/gut_cmdln.gd` both exist after copying.

- [ ] **Step 2: Enable the plugin in `project.godot`**

  Append a new section at the end of the file:

  ```
  [editor_plugins]

  enabled=PackedStringArray("res://addons/gut/plugin.cfg")
  ```

- [ ] **Step 3: Resolve the Godot binary path — do not ask, the value is already known**

  `command -v godot4` and `command -v godot` both miss on this machine, and `$GODOT_BIN` is unset. Write the known-good path directly:

  ```bash
  mkdir -p .claude
  echo "/home/brian/Public/Programming/Godot_v4.7.1-stable_linux.x86_64" > .claude/godot-binary-path.txt
  ```

- [ ] **Step 4: Add the cache file to `.gitignore`**

  Append to `.gitignore`:

  ```
  # Machine-specific Godot binary path cache (Piece 2)
  .claude/godot-binary-path.txt
  ```

  Confirm with `git status` that the file shows as untracked/ignored, not staged.

- [ ] **Step 5: Create the `tests/unit/` root with one smoke test**

  `tests/unit/test_smoke.gd`:

  ```gdscript
  extends GutTest

  func test_smoke() -> void:
      assert_true(true, "GUT runner is wired up correctly.")
  ```

- [ ] **Step 6: Run the suite for real**

  ```bash
  cd /home/brian/Public/Programming/Godot/a-blue-orb
  BIN=$(cat .claude/godot-binary-path.txt)
  "$BIN" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
  ```

  Expected: exit code `0`, summary reports 1 test run, 0 failures.

- [ ] **Step 7: Full-project headless sanity check**

  ```bash
  "$BIN" --headless --quit
  ```

  Expected: no errors — confirms the new `[editor_plugins]` section and vendored addon don't break project load.

- [ ] **Step 8: Commit**

  ```bash
  git add addons/gut project.godot tests/unit/test_smoke.gd .gitignore
  git commit -m "Vendor GUT v9.7.1, enable plugin, add tests/unit/ (Piece 2 setup)"
  ```

  Do **not** `git add .claude/godot-binary-path.txt` — it must stay untracked per Step 4.

---

### Task 3: GUT tests for Tickets 2, 3, 4 (GameState, EventBus, LogManager) (Piece 2 backfill A)

**Files:**
- Create: `tests/unit/autoloads/test_game_state.gd`
- Create: `tests/unit/autoloads/test_event_bus.gd`
- Create: `tests/unit/autoloads/test_log_manager.gd`

**Interfaces:**
- Consumes: `autoloads/game_state.gd` (current field/method list — see Global Constraints for the isolation pattern), `autoloads/event_bus.gd`'s 8 declared signals, `autoloads/log_manager.gd`'s `push()`/`get_lines()`.

- [ ] **Step 1: `test_game_state.gd` — instantiate a fresh, non-singleton copy per test** (per Global Constraints, `GameState`'s own code never references the singleton by name)

  ```gdscript
  extends GutTest

  var gs

  func before_each() -> void:
      gs = load("res://autoloads/game_state.gd").new()

  func after_each() -> void:
      gs.free()
  ```

  Write one `test_*` method per assertion below (GUT's `watch_signals(gs)` / `assert_signal_emitted(gs, "signal_name", [args])` / `assert_signal_not_emitted`):

  - `add_mana(5.0)` → `gs.mana == 5.0`; `mana_changed` emitted with `[5.0]`.
  - `spend_mana(1000.0)` on a fresh instance → returns `false`, `gs.mana` still `0.0`, `mana_changed` **not** emitted (this is Ticket 2's own explicitly-listed acceptance criterion — test it exactly as stated).
  - `add_mana(5.0)` then `spend_mana(3.0)` → returns `true`, `gs.mana == 2.0`, `mana_changed` emitted with `[2.0]`.
  - `add_health(100.0)` on fresh instance (`max_health` 50) → `gs.health == 50.0` (clamped), `health_changed` emitted with `[50.0, 50.0]`.
  - `gs.enter_blackout()` then `spend_health(10.0)` → `gs.health` unchanged (still `50.0`), no `health_changed` emitted (guarded by `is_blacked_out`).
  - `spend_health(60.0)` on fresh instance → `gs.health == 0.0` (clamped), `health_changed` emitted with `[0.0, 50.0]`, **and** `health_depleted` emitted.
  - `add_familiars(3)` → `gs.familiars == 3`; `familiar_gained` emitted with `[3]`.
  - Reservation model: `add_familiars(3)`, `gs.familiars_assigned_to_orb = 2` (direct field set is fine inside the test, it's exercising `idle_familiars()` not going through effect code), `spend_familiars(2)` → returns `false` (only 1 idle), `gs.familiars` unchanged; `spend_familiars(1)` → returns `true`, `gs.familiars == 2`.
  - `mark_upgrade_purchased("chair")` → `gs.has_upgrade("chair") == true`; `upgrade_purchased` emitted with `["chair"]`. Call `mark_upgrade_purchased("chair")` again → `upgrade_purchased` emitted exactly once total across both calls (idempotent early-return).
  - `advance_confidence_tier()` called 5 times from fresh (`confidence_tier` starts 0) → final `gs.confidence_tier == 4` (clamped by `min(x+1,4)`); `confidence_tier_changed` emitted 5 times, the last one with `[4]` (the code has no change-guard, so the 5th call still emits — assert this is what happens, it's current correct behavior, not a bug to "fix").
  - `to_dict()`/`from_dict()` round-trip: on a fresh instance call `add_mana(7.0)`, `add_familiars(2)`, `mark_upgrade_purchased("bed")`, `gs.enter_blackout()`; call `to_dict()`; create a second fresh instance, call `from_dict()` with that dict; assert every field matches the first instance **except** `is_blacked_out`, which must be `false` on the second instance regardless (the dict's `is_blacked_out` value is `true`, but `from_dict` deliberately ignores it and hardcodes `false` — this is the Ticket 11 "never restore blackout from a save" rule; assert it explicitly).
  - `resources` dict aliasing fix: build `var input := {"stone": 1, "wood": 0, "water": 0, "crystals": 0}`, call `from_dict({"resources": input})` on a fresh instance, then mutate `input["stone"] = 999`; assert `gs.resources["stone"] == 1` (proves `.duplicate()` is used, not aliasing).

  Skip (note in report as a static/code-review criterion, not runtime-testable): "no public field is ever set directly from outside this script in code review."

- [ ] **Step 2: `test_event_bus.gd`**

  Skip "no gameplay logic lives here" (static/code-review criterion, note why).

  For "every signal listed is actually emitted somewhere by the end of this ticket batch": this isn't a single function's behavior, so don't force it into a GUT test — instead run a repo-wide check and report findings:

  ```bash
  for sig in mana_changed health_changed familiar_gained upgrade_purchased health_depleted blackout_ended house_tier_changed confidence_tier_changed; do
    echo "=== $sig ==="
    grep -rn "EventBus\.$sig\.emit" --include="*.gd" .
  done
  ```

  Report which of the 8 signals have zero emitters found — this is exactly the kind of drift Ticket 3's own acceptance criterion warned about ("don't leave a signal declared but never fired"). If any are unemitted, state it plainly in the task report; do not silently fix it (out of scope for this task — it's a backfill-testing task, not a bug-fix task) unless it's trivial to confirm as intentional (e.g. `blackout_ended` might only fire from a scene/UI script rather than an autoload — check `scenes/ui/blackout_overlay.gd` too, not just autoloads, before concluding it's missing).

- [ ] **Step 3: `test_log_manager.gd`** (LogManager is itself an autoload but has zero external dependencies — safe to test against the live singleton directly, or instantiate fresh via `load("res://autoloads/log_manager.gd").new()`; prefer fresh-instance for isolation from other tests' log lines)

  - `push("You gingerly touch the orb.")` → `get_lines()[-1]` matches exactly `"[%s] you gingerly touch the orb." % <the actual HH:MM:SS format Time.get_time_string_from_system() produces>` — assert via regex `^\[\d{2}:\d{2}:\d{2}\] you gingerly touch the orb\.$` rather than a literal timestamp (can't control wall-clock time in the test). Also assert `line_added` signal emitted with that same string.
  - Rolling buffer cap: push 205 distinct lines (e.g. `"line %d" % i` for `i` in `0..204`); assert `get_lines().size() == 200`; assert `get_lines()[0]` corresponds to the 6th pushed line (`"line 5"`), proving oldest-first eviction (`pop_front`), not newest-first.

- [ ] **Step 4: Confirm Tickets 1 and 8 have no missed logic criteria**

  Read `gh issue view 1 --json body --jq .body` and `gh issue view 8 --json body --jq .body`. Ticket 1 (scaffolding) has none — confirm and move on. Ticket 8 (UI shell) is almost entirely visual **except** one criterion — "`area_tab.tscn` reads from a bound `area.tres` resource rather than hardcoding House anywhere in this scene's script" — which is deferred to Task 6, since that task already builds `area_tab.tscn` scene-instantiation test infrastructure for Ticket 9's room-description/sort_order criteria and it's cheaper to share that setup than duplicate it here. Note this deferral explicitly in the report; do not write an `area_tab` test in this task.

- [ ] **Step 5: Run the full suite, confirm green**

  ```bash
  BIN=$(cat .claude/godot-binary-path.txt)
  "$BIN" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
  ```

  Expected: exit 0, all tests (smoke + this task's new ones) pass. If anything fails, it's either a real bug in already-shipped code (flag it — don't silently "fix" GameState/EventBus/LogManager in this backfill task, report it to the controller) or a mistaken test (fix the test).

- [ ] **Step 6: Commit**

  ```bash
  git add tests/unit/autoloads/test_game_state.gd tests/unit/autoloads/test_event_bus.gd tests/unit/autoloads/test_log_manager.gd
  git commit -m "Backfill GUT tests for Tickets 2/3/4 — GameState, EventBus, LogManager (Piece 2 backfill)"
  ```

---

### Task 4: GUT tests for Ticket 5 (ButtonData + EffectHandler) (Piece 2 backfill B)

**Files:**
- Create: `tests/unit/data/test_button_data.gd`
- Create: `tests/unit/autoloads/test_effect_handler.gd`

**Interfaces:**
- Consumes: `data/button_data.gd`'s `calculate_cost()` (static, pure — no isolation concerns) and `is_unlock_condition_met()` (static, but reads the live `GameState` singleton via `_get_stat_value`/`has_upgrade` — needs the reset pattern), `autoloads/effect_handler.gd`'s five Ticket-5-era effects (`touch_orb`, `summon_familiar`, `eat_food`, `gain_confidence`, `add_chair` — live-singleton, needs reset pattern).

- [ ] **Step 1: `test_button_data.gd` — `calculate_cost` (pure static function, no GameState involvement, no reset needed)**

  - `calculate_cost(1.0, "linear", 1.0, 0)` → `1.0`; `calculate_cost(1.0, "linear", 1.0, 1)` → `2.0`; `calculate_cost(1.0, "linear", 1.0, 5)` → `6.0` — this is Ticket 5's own explicit acceptance criterion ("Summon Familiar costs 1, 2, 6 mana at familiars = 0, 1, 5"), test it verbatim.
  - `calculate_cost(10.0, "double", 0.0, 0)` → `10.0`; `..., 2)` → `40.0` (`10 * 2^2`).
  - `calculate_cost(5.0, "fixed", 999.0, 7)` → `5.0` regardless of `count`.

  `is_unlock_condition_met` (needs `GameState.from_dict({})` reset in `before_each()` since it reads the live singleton):

  - `""` → `true` (empty condition always met).
  - `"familiars >= 1"` with `GameState.familiars == 0` → `false`; after `GameState.add_familiars(1)` → `true`.
  - `"has_upgrade(\"chair\")"` → `false` before, `true` after `GameState.mark_upgrade_purchased("chair")`.
  - Compound: `"familiars >= 1 && has_upgrade(\"chair\")"` → `false` if only one half is true, `true` once both are.
  - Stat-vs-stat (the grammar extension from Ticket 9c, still exercised here since it's part of the current shipped grammar): `"better_meal_level < better_table_level"` — `false` at `0 < 0`; `true` after `GameState.advance_better_table_level()` (`0 < 1`).
  - Unknown stat name fails closed: a condition referencing a made-up stat via `>=` (e.g. `"nonexistent_stat >= 0"`) → `false` (per `_get_stat_value`'s documented `-INF` fail-closed default — `-INF >= 0` is false).

- [ ] **Step 2: `test_effect_handler.gd`** (`before_each()`: `GameState.from_dict({})`)

  - `_effect_touch_orb()` (via `EffectHandler.run_effect("touch_orb")`) on fresh state: `GameState.mana` increases by `orb_mana_per_click` (`1.0`), `GameState.health` decreases by `orb_health_cost_per_click` (`5.0`, i.e. `45.0`), returns `true`.
  - `_effect_summon_familiar()`: `GameState.familiars` goes `0 → 1`, returns `true`.
  - `_effect_eat_food()`: `GameState.health` (start below max, e.g. after touching the orb once) increases by `10.0 + food_heal_bonus` (`10.0` at baseline), `food_eaten_count` increments, returns `true`.
  - `_effect_gain_confidence()` called once: `orb_mana_per_click` goes `1.0 → 4.0` (+3.0), `orb_health_cost_per_click` goes `5.0 → 10.0` (+5.0), `confidence_tier` goes `0 → 1`, returns `true`. Called a 5th time (already at tier 4): returns `false` (guard `tier_index >= CONFIDENCE_MANA_BONUS.size()`).
  - `_effect_add_chair()`: requires `GameState.familiars >= 1` set up first (`add_familiars(1)`) since real play would have `button_action.gd` deduct the familiar cost before calling this — but `_effect_add_chair()` itself does **not** deduct familiars (regression test for the double-deduction bug fixed in Ticket 9: assert `GameState.familiars` is **unchanged** by calling `run_effect("add_chair")` directly — cost deduction is `button_action.gd`'s job, never the effect's). Assert `has_upgrade("chair") == true`, `orb_mana_per_click` +1.0, `health_regen_per_minute` +1.0, returns `true`.

  This double-deduction regression check is the single most important assertion in this task — it's a bug class that has been found and fixed twice in this project's history; a GUT test locking it down is exactly the kind of coverage this backfill exists to add.

- [ ] **Step 3: Run the full suite, confirm green** (same command as Task 3 Step 5). Report and do not silently fix any failure that reveals a real bug in shipped code — flag it to the controller instead.

- [ ] **Step 4: Commit**

  ```bash
  git add tests/unit/data/test_button_data.gd tests/unit/autoloads/test_effect_handler.gd
  git commit -m "Backfill GUT tests for Ticket 5 — ButtonData cost/unlock logic, EffectHandler (Piece 2 backfill)"
  ```

---

### Task 5: GUT tests for Tickets 6, 7 (button_action.gd logic + InputGuard) (Piece 2 backfill C)

**Files:**
- Create: `tests/unit/ui/test_button_action.gd`
- Create: `tests/unit/autoloads/test_input_guard.gd`

**Interfaces:**
- Consumes: `scenes/ui/button_action.gd` (needs live-singleton reset + real scene instantiation, since it `extends Button` and is meant to be added to the tree), `autoloads/input_guard.gd`'s `try_register_click()`.

- [ ] **Step 1: `test_button_action.gd`** — instantiate the real `button_action.tscn` via `add_child_autofree(load("res://scenes/ui/button_action.tscn").instantiate())`, build a `ButtonData` in-code with `ButtonData.new()` and explicit field assignment (do not load a `.tres` from disk for these — keeping the fixture inline makes each test's exact cost/cooldown/effect values self-evident). `before_each()`: `GameState.from_dict({})`.

  - **One-shot purchase, no double-fire:** build a `ButtonData` with `cost_type="mana"`, `base_cost=0.0` (free, to isolate from cost-deduction logic), `effect_id="summon_familiar"`, `one_shot=true`, `labels=["Test"]`. Call `set_data()`, then call `_handle_click()` twice in direct succession (simulating the `_is_processing_click` re-entrancy guard doesn't matter here since we're calling the private method directly, not `.pressed.emit()` — the deliberate test is that after the first click the button is `hidden` and its purchase already fired `run_effect` once; call `_handle_click()` a second time and assert `GameState.familiars` did **not** increase again, i.e. the button's own hidden/one-shot state is exactly why a real double-click can't re-fire, even though this direct-call test bypasses the actual re-entrancy guard). Assert `GameState.familiars == 1` after both calls (not `2`), and the button `visible == false`.
  - **Afford gating, `"mana"` cost:** `ButtonData` with `cost_type="mana"`, `base_cost=5.0`, `cost_scaling="fixed"`, `effect_id="touch_orb"`. With `GameState.mana == 0.0`: `_is_disabled() == true` (can't afford). After `GameState.add_mana(5.0)`: `_is_disabled() == false` (ignoring unlock_condition/cooldown, both empty/zero here).
  - **Afford gating, `"familiars"` cost respects the reservation model:** `ButtonData` with `cost_type="familiars"`, `base_cost=2.0`, `cost_scaling="fixed"`, `effect_id="summon_familiar"`. `GameState.add_familiars(2)` then `GameState.familiars_assigned_to_orb = 2` (all reserved, 0 idle) → `_is_disabled() == true` (can't afford — this exercises the Ticket 9c fix where `_can_afford()` checks `idle_familiars()`, not raw `familiars`).
  - **Cooldown blocks a second click; refund on effect failure:** `ButtonData` with `cost_type="mana"`, `base_cost=1.0`, `cost_scaling="fixed"`, `cooldown_sec=5.0`, `effect_id="touch_orb"`. `GameState.add_mana(1.0)`, call `_handle_click()` once → cost deducted, `_is_on_cooldown == true`, `_is_disabled() == true`. Separately (fresh state), set `effect_id` to something that returns `false` (e.g. `"better_chair"` with `GameState.better_chair_level` pre-set to `4`, the max — `_effect_better_chair()` returns `false` at the guard), `GameState.add_mana(1.0)`, call `_handle_click()` → assert `GameState.mana` is back to `1.0` (refunded, not lost) and `_purchase_count`/cooldown were **not** advanced (the whole point of the refund-on-failure path added in Ticket 11).
  - **`max_purchases` hides the button:** `ButtonData` with `max_purchases=1`, `cost_type="none"`, `effect_id="summon_familiar"`, `one_shot=false`. Call `_handle_click()` once → `visible == false` (hidden at the cap, same as `one_shot` but via the separate `max_purchases` mechanism — Ticket 9c's `better_meal` pattern).

- [ ] **Step 2: `test_input_guard.gd`** — instantiate fresh via `load("res://autoloads/input_guard.gd").new()` (no external dependencies, safe to isolate).

  - Ticket 7's own explicit acceptance criterion: fire `try_register_click()` 200 times in a tight loop (no real time passing between calls — they'll all land in the same `Time.get_ticks_msec()` millisecond or close to it, which is fine, that's the point of the 1-second rolling window) and assert **no more than 100** of the 200 calls return `true`. Count the `true` results, assert `count <= 100` — assert it's *exactly* `100` given all 200 calls happen well within one second (the 101st call onward should all see `_click_timestamps_msec.size() >= 100` and return `false`).
  - Confirm this doesn't interfere with per-button cooldowns: this is really just confirming `InputGuard` and `button_action.gd`'s own `_is_on_cooldown` are two independent mechanisms — no new test needed beyond what Step 1 already covers for cooldown and what this step covers for the rate limiter; note in the report that both mechanisms were verified independently and neither depends on the other's internal state.

- [ ] **Step 3: Run the full suite, confirm green.**

- [ ] **Step 4: Commit**

  ```bash
  git add tests/unit/ui/test_button_action.gd tests/unit/autoloads/test_input_guard.gd
  git commit -m "Backfill GUT tests for Tickets 6/7 — button_action.gd logic, InputGuard (Piece 2 backfill)"
  ```

---

### Task 6: GUT tests for Ticket 9 (House button content) + deferred Ticket 8 criterion (Piece 2 backfill D)

**Files:**
- Create: `tests/unit/autoloads/test_effect_handler_ticket9.gd`
- Create: `tests/unit/ui/test_area_tab.gd`
- Create: `tests/unit/autoloads/test_regen_manager.gd`

**Interfaces:**
- Consumes: the rest of `autoloads/effect_handler.gd` (`add_table`, `add_bed`, `better_chair`, `better_table`, `better_bed` — `better_meal` was already covered incidentally by Task 4's unlock-condition tests but not its effect directly, add it here too), `scenes/ui/area_tab.gd`, `autoloads/regen_manager.gd`.

- [ ] **Step 1: `test_effect_handler_ticket9.gd`** (`before_each()`: `GameState.from_dict({})`)

  - `_effect_add_table()`: `food_heal_bonus` +2.0, `orb_mana_per_click` +2.0, `has_upgrade("table") == true`. No self-deduction (same double-deduction regression pattern as Task 4's chair test — assert `GameState.familiars` unchanged).
  - `_effect_add_bed()`: `max_health` +20.0 (assert `GameState.max_health == 70.0` from the default 50), `orb_mana_per_click` +3.0, `has_upgrade("bed") == true`. No self-deduction.
  - `_effect_better_chair()` / `_effect_better_table()` / `_effect_better_bed()`: each callable exactly 4 times before the guard kicks in (`>= 4`); the 5th call returns `false` and does not mutate state further. Assert the per-call deltas match Task 4/Step 2's already-tested `_effect_add_chair` shape (`+1.0` regen/mana for chair, `+2.0`/`+2.0` for table, `+20.0` max_health/`+3.0` mana for bed) accumulate correctly across all 4 calls (e.g. chair: `health_regen_per_minute == 4.0` after 4 calls).
  - `_effect_better_meal()`: requires `better_table_level > better_meal_level` per its own guard — `GameState.advance_better_table_level()` once, then `run_effect("better_meal")` → `food_heal_bonus` +5.0, `better_meal_level` `0 → 1`, returns `true`. Calling it again immediately (still only `better_table_level == 1`) → `false` (guard: `better_meal_level >= better_table_level`).
  - Confidence's HP-cost growth at max tier (Ticket 9's own explicit acceptance criterion: "at Confidence 4, touching the orb costs 25 HP, not 5"): call `run_effect("gain_confidence")` 4 times, then `run_effect("touch_orb")` — assert `GameState.health` dropped by exactly `25.0` from whatever it was before that final call.

- [ ] **Step 2: `test_regen_manager.gd`** — instantiate fresh via `load("res://autoloads/regen_manager.gd").new()`, call `_on_tick()` directly rather than waiting on the real 60-second `Timer` (this is Ticket 9's flagged gap: "Chair's +1 HP regen/min passive effect" needed *some* ticking mechanism — `RegenManager` is that mechanism, added after Ticket 9 shipped; test its tick logic directly, not the timer plumbing, which Task 2's smoke test / full-project headless check already proves doesn't error).

  - `before_each()`: `GameState.from_dict({})`.
  - With `GameState.health_regen_per_minute == 0.0` (default): call `_on_tick()` → `GameState.health` unchanged (guard: `> 0.0`).
  - `GameState.add_health_regen_per_minute(1.0)`, drop `GameState.health` below max first (e.g. via `spend_health(10.0)`), call `_on_tick()` → `GameState.health` increased by `1.0`.
  - `GameState.enter_blackout()` with `health_regen_per_minute > 0.0` → `_on_tick()` → `GameState.health` unchanged (guard: `not GameState.is_blacked_out`) — this is the ticking-during-blackout edge case, worth locking down since it's easy to regress.

- [ ] **Step 3: `test_area_tab.gd`** — instantiate the real `area_tab.tscn` via `add_child_autofree(load("res://scenes/ui/area_tab.tscn").instantiate())`. `before_each()`: `GameState.from_dict({})`.

  - **Deferred Ticket 8 criterion — no hardcoded "House":** build two distinct `AreaData` resources in-code (`AreaData.new()` with different `id`/`name_progression`/`base_description`), call `set_area_data()` with the first, assert the tab title / description reflect that data; call `set_area_data()` again with the second, assert they change to match the second — proving nothing about "House" is hardcoded in the script (it's entirely driven by the bound resource).
  - **`sort_order` ordering (Ticket 9's flagged gap from Ticket 8's review):** use the real `AreaData` at `data/areas/house.tres` and the real `data/buttons/house/*.tres` files (already shipped — 14 of them: `bed`, `better_bed`, `better_chair`, `better_meal`, `better_table`, `chair`, `confidence_1..4`, `eat_bread`, `summon_familiar`, `table`, `touch_orb`). Call `set_area_data()` with it, then read `_column_actions.get_children()` and `_column_upgrades.get_children()` (both `@onready` vars are private but reachable from a test in the same class via GUT's normal node access — if genuinely inaccessible, use `.get_node("Root/Content/ButtonGrid/ColumnActions")` etc.) and assert each column's children are in strictly ascending `data.sort_order` — this proves the `sort_custom` comparator in `_load_buttons()` is doing its job, independent of filesystem enumeration order.
  - **Room description rebuild (Ticket 9's own explicit acceptance criterion):** with a fresh `AreaData`/no purchases, `_description_label.text == area_data.base_description`. Simulate one one-shot purchase by calling `_on_one_shot_purchased()` directly with a `ButtonData` stub (`room_description_fragment = "a chair"`) → description becomes `"<base>. The room has a chair."`. Add a second fragment (`"a table"`) → `"...has a chair and a table."` (two-item join). Add a third (`"a bed"`) → `"...has a chair, a table, and a bed."` (Oxford-comma three-item join) — exercise all three branches of `_join_with_commas_and`.

- [ ] **Step 4: Run the full suite, confirm green.**

- [ ] **Step 5: Commit**

  ```bash
  git add tests/unit/autoloads/test_effect_handler_ticket9.gd tests/unit/ui/test_area_tab.gd tests/unit/autoloads/test_regen_manager.gd
  git commit -m "Backfill GUT tests for Ticket 9 — House button content, RegenManager, deferred Ticket 8 area_tab check (Piece 2 backfill)"
  ```

---

### Task 6b: GUT tests for Tickets 10, 11 (user-requested extension beyond the original Piece 2 scope)

The source spec's Piece 2 backfill only covered Tickets 1–9. The user asked, mid-execution, to extend GUT coverage to Ticket 10 (blackout/recovery) and Ticket 11 (save system) too. This task follows the same conventions as Tasks 3–6.

**Files:**
- Create: `tests/unit/ui/test_blackout_overlay.gd`
- Create: `tests/unit/autoloads/test_save_manager.gd`

**Interfaces:**
- Consumes: `scenes/ui/blackout_overlay.gd`/`.tscn` (Ticket 10), `autoloads/save_manager.gd` (Ticket 11), `data/balancing/constants.gd`'s `BLACKOUT_RECOVERY_SEC` (5.0) / `SAVE_VERSION` (1) / `AUTOSAVE_INTERVAL_SEC` (20.0).

**Task-specific constraint — real file I/O safety:** `SaveManager.save_game()`/`load_game()`/`import_save()` read and write the actual `user://save.json` path, which is the **same path a real played build uses on this machine**, not a test-isolated location. Any test that calls these methods must back up whatever's at `user://save.json` before running (if anything) and restore it exactly afterward (`before_each`/`after_each`, or `before_all`/`after_all` if GUT supports file-level setup — check `addons/gut/test.gd` for the exact hook names available), so running this test suite can never destroy real save data on this machine. Read the existing file's raw bytes/text (not just parsed JSON) so restoration is byte-exact.

- [ ] **Step 1: `test_blackout_overlay.gd`** — instantiate the real scene via `add_child_autofree(load("res://scenes/ui/blackout_overlay.tscn").instantiate())`. `before_each()`: `GameState.from_dict({})`.

  - Trigger via the real production path: fresh state (`health` 50), call `GameState.spend_health(50.0)` directly (this is what actually emits `EventBus.health_depleted` at exactly 0, which `blackout_overlay.gd`'s `_on_health_depleted()` listens for) → assert the overlay's `visible == true` and `GameState.is_blacked_out == true`.
  - Re-entrancy guard: with the overlay already blacked out (from the step above), call `_on_health_depleted()` again directly → assert no error and no duplicate/restarted timer (the guard is `if GameState.is_blacked_out: return` at the top of the method — the second call should be a complete no-op; a reasonable proxy assertion is that `GameState.is_blacked_out` is still simply `true`, not toggled or re-entered).
  - Recovery: with the overlay blacked out, call `_on_recovery_timeout()` directly (bypassing the real `Timer`'s wait) → assert `GameState.health` increased by exactly `1.0`, `GameState.is_blacked_out == false`, and `EventBus.blackout_ended` was emitted (`watch_signals(EventBus)` before the call).
  - Full-blockage acceptance criterion (Ticket 10's own — re-asserted here in integration context, not just at the `GameState`-unit level Task 3 already covered): once blacked out (via `_on_health_depleted()`), call `GameState.spend_health(10.0)` → assert `GameState.health` unchanged at `0.0` (the guard genuinely blocks HP-spending, not just in isolation but through the same object graph the real game uses).
  - `Constants.BLACKOUT_RECOVERY_SEC` is actually wired to the overlay's `Timer`: after instantiating the scene (which runs `_ready()`), assert the internal `Timer`'s `wait_time == Constants.BLACKOUT_RECOVERY_SEC` — reach it via `.get_node()`-style access if the `_timer` var isn't directly visible from the test script, or via a debugger-style property read if GUT exposes it; if truly unreachable without modifying `blackout_overlay.gd`, assert `Constants.BLACKOUT_RECOVERY_SEC == 5.0` alone and note in the report that the wiring itself wasn't independently re-verified beyond reading the source.

- [ ] **Step 2: `test_save_manager.gd`**

  `before_each()`: back up `user://save.json` (read its text if `FileAccess.file_exists("user://save.json")`, else note it didn't exist) and call `GameState.from_dict({})`. `after_each()`: restore the backed-up text (`FileAccess.open("user://save.json", FileAccess.WRITE)` + `store_string`), or delete the file via `DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.json"))` if it didn't exist before this test.

  - **Real round trip through actual file I/O** (not just the in-memory `to_dict()`/`from_dict()` Task 3 already covered): on a reset `GameState`, call `add_mana(12.0)`, `add_familiars(3)`, `mark_upgrade_purchased("chair")`, `advance_confidence_tier()` twice. Call `SaveManager.save_game()`. Reset `GameState` again (`from_dict({})`, simulating a fresh session). Call `SaveManager.load_game()` → assert returns `true`, and assert `GameState.mana == 12.0`, `familiars == 3`, `has_upgrade("chair") == true`, `confidence_tier == 2` — the real file was written and re-read, not just the in-memory dict.
  - **`save_version` present:** after `save_game()`, read `user://save.json` directly, `JSON.parse_string()` it, assert the top-level `"save_version"` key equals `Constants.SAVE_VERSION`.
  - **Version-mismatch rejection (Ticket 11's own explicit acceptance criterion — "hand-edit a save's version field and attempt import"):** build a JSON string by hand with `"save_version": Constants.SAVE_VERSION + 999` and a plausible `"game_state"` payload; call `SaveManager.import_save(that_string)` → assert returns `false`; assert `GameState` is completely unchanged from whatever it was immediately before the call (no partial/corrupting mutation).
  - **`is_blacked_out` never restored, through the real `SaveManager` path** (Ticket 11's own flagged soft-lock risk, already fixed at the `GameState.from_dict()` level per Task 3 — re-confirm the guarantee holds transitively through `SaveManager` too, since that's the actual call path a save/load in real play uses): `GameState.enter_blackout()`, `SaveManager.save_game()`, `GameState.from_dict({})` (reset), `SaveManager.load_game()` → assert `GameState.is_blacked_out == false`.
  - **Better-X reload-seeding gap (Ticket 11's own flagged "second reload gap" — confirm it's actually fixed, not just that the raw field round-trips):** reset `GameState`, set `GameState.better_chair_level = 3` directly, `SaveManager.save_game()`, reset again, `SaveManager.load_game()` → assert the raw field round-trips (`GameState.better_chair_level == 3`). Then verify the UI-layer half: instantiate a real `button_action.tscn` (`add_child_autofree(...)`), build a `ButtonData` in-code with `count_seed_source = "better_chair_level"` (mirroring the three shipped `.tres` files that already use this field), call `set_data()` on the button → assert the button's seeded purchase count reflects level `3` (check via whatever's externally observable — e.g. the rendered label text matching `data.labels[3]` rather than `data.labels[0]`, since `_purchase_count` itself is private). This proves the reload-seeding path Ticket 11 flagged is wired end-to-end after a real load, not just that the `GameState` field persists.

- [ ] **Step 3: Run the full suite, confirm green** (same command as prior tasks, with `-ginclude_subdirs`).

- [ ] **Step 4: Report any real pre-existing bugs found, do not fix them** — same pattern as Tasks 3–6: flag clearly, let the controller decide whether to fix out-of-band.

- [ ] **Step 5: Commit**

  ```bash
  git add tests/unit/ui/test_blackout_overlay.gd tests/unit/autoloads/test_save_manager.gd
  git commit -m "Backfill GUT tests for Tickets 10/11 — blackout/recovery, SaveManager (user-requested scope extension)"
  ```

---

### Task 7: Default `sync-tickets` input to `docs/tickets.md` (Piece 3)

**Files:**
- Modify: `.claude/skills/sync-tickets/SKILL.md`

- [ ] **Step 1: Edit the `## Input` section**

  Replace:
  ```markdown
  ## Input

  A path to a tickets markdown file. If not given, ask for one.
  ```
  With:
  ```markdown
  ## Input

  A path to a tickets markdown file. If not given, default to `docs/tickets.md`. Only ask for a path if `docs/tickets.md` does not exist yet.
  ```

- [ ] **Step 2: Verify** — `docs/tickets.md` exists as of Task 1, so re-reading the skill file and confirming the new default text is the only change (`git diff` should show exactly this one-paragraph swap).

- [ ] **Step 3: Commit**

  ```bash
  git add .claude/skills/sync-tickets/SKILL.md
  git commit -m "Default sync-tickets input to docs/tickets.md (Piece 3)"
  ```

---

### Task 8: Create `docs/bugs.md` — permanent bug history log (Piece 5, moved ahead of Piece 4)

**Files:**
- Create: `docs/bugs.md`

**Note on ordering:** the source spec lists this as Piece 5, after Piece 4 (`make-ticket`). This plan builds it first because `make-ticket`'s bug path (Task 9) and `work-ticket`'s bug-handling path (Task 11) both append to/update this file — writing the file's format once, here, means later tasks reference an existing file instead of each re-describing the template inline.

- [ ] **Step 1: Write `docs/bugs.md`**

  ```markdown
  # Bug History

  A permanent, append-only record of every bug found in this project and why it happened. Entries are never deleted — only updated with resolution info once a bug is fixed.

  `make-ticket`'s bug path appends a new entry here (status `Open`) when it authors a bug ticket. `work-ticket` updates that same entry in place — filling in **Root cause (confirmed)**, **Fix summary**, and flipping **Status** to `Fixed` — in the same commit that closes the bug's ticket.

  New entries are appended at the end of this file, each preceded by a `---` horizontal rule. Entry format:

  ```
  ## Bug N — <Title>
  **Found:** <date>
  **Status:** Open | Fixed
  **Description:** <what was observed>
  **Root cause (hypothesis):** <filled in when the bug ticket is authored>
  **Root cause (confirmed):** <filled in when work-ticket closes it — may differ from the hypothesis>
  **Fix summary:** <filled in on close — what changed and where>
  **Ticket:** Bug N in docs/tickets.md · GitHub issue: pending sync
  ```

  `sync-tickets` replaces "GitHub issue: pending sync" with the real issue number the moment it creates that bug's issue.

  No bugs have been logged yet.
  ```

- [ ] **Step 2: Commit**

  ```bash
  git add docs/bugs.md
  git commit -m "Add docs/bugs.md — permanent bug history log (Piece 5)"
  ```

---

### Task 9: New skill `make-ticket` (Piece 4)

**Files:**
- Create: `.claude/skills/make-ticket/SKILL.md`

**Interfaces:**
- Consumes: `docs/tickets.md`'s format (Task 1), `docs/bugs.md`'s entry format (Task 8), `.claude/skills/sync-tickets/SKILL.md`'s parse logic (must stay compatible — read it, don't guess).
- Produces: the bug-ticket field list (`Description` / `Repro steps` / `Expected vs. Actual` / `Root cause hypothesis` / `Affected files/scenes` / `Acceptance criteria`) that Task 11's `work-ticket` edit reuses verbatim when authoring a bug ticket from a failed run.

- [ ] **Step 1: Write `.claude/skills/make-ticket/SKILL.md`**

  ```markdown
  ---
  name: make-ticket
  description: Use when authoring a new feature or bug ticket into docs/tickets.md — writes the ticket entry only, does not talk to GitHub. Run sync-tickets afterward to turn it into a GitHub issue.
  ---

  # Make Ticket

  Authors a new `## Ticket N —` or `## Bug N —` entry into `docs/tickets.md`. This skill never touches GitHub — that's `sync-tickets`'s job, run afterward.

  ## Trigger phrases

  - Feature path: "make a ticket", "let's make a ticket", "new ticket", "ticket making".
  - Bug path: "bug ticket", "file a bug", "found a bug", "log a bug", "there's a bug in Godot".
  - If the phrasing doesn't clearly indicate which, ask which path before doing anything else.

  ## Shared behavior (both paths)

  1. **Determine the next number `N`.** Scan `docs/tickets.md` for every `## Ticket N —` and `## Bug N —` heading — both count against one shared, interleaved sequence, not separate counters. Parse `N` as a leading integer plus an optional letter suffix (e.g. `9`, `9b`, `9c`) and sort by `(integer, suffix)` to find the true max — plain string sort puts `"10"` before `"9b"`, which is wrong. New tickets always get a plain integer `N` (`max(N) + 1`); letter suffixes only exist from historical ticket splits, don't generate new ones here.
  2. **Write the entry**, ending with a `**Acceptance criteria:**` line followed by `- ` bullets — this exact marker text is what `sync-tickets` converts to GitHub task-list checkboxes; don't deviate from it.
  3. **Append to the end of `docs/tickets.md`**, separated from the previous entry by a `---` line on its own — matches the format `sync-tickets` parses (splits on `\n## Ticket ` / `\n## Bug `, reads the body up to the next `---` or end of file; read `.claude/skills/sync-tickets/SKILL.md` if unsure of the exact logic this must stay compatible with).
  4. **Never invent a number, cost, or effect** that isn't already in `docs/design_doc.md` or `docs/architecture.md` and isn't something the user just told you directly in this conversation — ask instead of guessing.
  5. **After writing**, tell the user the ticket number and that `sync-tickets` still needs to run to turn it into a GitHub issue.

  ## Feature ticket path (`## Ticket N — <Title>`)

  1. Accept either an uploaded design image or a text description of the feature.
  2. **Always ask at least one clarifying question before writing anything**, unless the request already fully specifies exact numbers, exact scene, and exact acceptance criteria. At minimum, cover: which area/scene this belongs to, whether it's a new system or an extension of an existing one, and whether any number/cost/effect it implies is already decided in the design doc vs. still open.
  3. Cross-check against `docs/design_doc.md` and `docs/architecture.md`. If the ticket introduces a new number, system, or file that belongs in `docs/architecture.md` (per that doc's own §1 "Design Principles → Architecture Decisions" and §6 balancing reference), draft the addition and propose it to the user in the same sitting — per architecture.md's own stated rule, it drifts from reality if changes aren't mirrored immediately.
  4. `docs/design_doc.md` is a synced export of a Google Doc the user edits directly — never edit it. If the ticket implies a design doc change, flag it clearly as `"update the Google Doc: ..."` instead of silently editing the local copy (editing the local copy without the source Google Doc changing would make them drift, which is worse than leaving both alone).
  5. Write the ticket body: description, relevant context/constraints, files/scenes likely touched, then `**Acceptance criteria:**`.

  ## Bug ticket path (`## Bug N — <Title>`)

  1. Accept a description of what broke — prose, a pasted error/stack trace, or a screenshot.
  2. **Ask clarifying questions**: repro steps if not given, expected vs. actual behavior, which scene/script/autoload seems involved, whether it blocks other work.
  3. Write the ticket body with these sections, in this order, before `**Acceptance criteria:**`:
     - **Description**
     - **Repro steps**
     - **Expected vs. Actual**
     - **Root cause hypothesis** — best guess only, explicitly labeled as a hypothesis, not a confirmed diagnosis
     - **Affected files/scenes**
     - `**Acceptance criteria:**` — bullets describing what "fixed" looks like (e.g. "X no longer happens when Y", "Z behaves as described in repro steps")
  4. Append a matching stub entry to `docs/bugs.md` (format documented at the top of that file — create the file if it somehow doesn't exist yet, using that same format) with `**Status:** Open` and `**Ticket:** Bug N in docs/tickets.md · GitHub issue: pending sync`. This is the permanent log entry; `work-ticket` updates it (confirmed root cause, fix summary, status) when the bug is actually fixed, and `sync-tickets` fills in the real issue number the moment it syncs.
  ```

- [ ] **Step 2: Verify format compatibility with `sync-tickets`**

  Read `.claude/skills/sync-tickets/SKILL.md` (as it stands after Task 7, before Task 10's edits) and confirm every format claim above (heading shape, `---` separators, `**Acceptance criteria:**` marker) matches what it currently parses. Note in the report if Task 10's planned changes (bug-heading parsing) will be needed for this skill to actually work end-to-end — they will; that's expected, this task only authors ticket text, `sync-tickets` isn't bug-aware until Task 10 lands.

- [ ] **Step 3: Commit**

  ```bash
  git add .claude/skills/make-ticket/SKILL.md
  git commit -m "Add make-ticket skill — authors feature and bug tickets into docs/tickets.md (Piece 4)"
  ```

---

### Task 10: Extend `sync-tickets` for bug tickets (Piece 6)

**Files:**
- Modify: `.claude/skills/sync-tickets/SKILL.md`

**Interfaces:**
- Consumes: `docs/bugs.md`'s entry format (Task 8), the "GitHub issue: pending sync" placeholder text `make-ticket` writes (Task 9).

- [ ] **Step 1: Label creation (Procedure step 1)** — add `bug` alongside the existing `ticket` label:

  ```bash
  gh label create ticket --color "0E8A16" --description "Tracked build ticket" 2>/dev/null || true
  gh label create bug --color "D93F0B" --description "Bug ticket" 2>/dev/null || true
  ```

- [ ] **Step 2: Parser (Procedure step 2)** — generalize the split. Currently: "Split on `\n## Ticket ` to get one chunk per ticket." Change to: split on both `\n## Ticket ` and `\n## Bug `, preserving which keyword each chunk used (needed for title/labels below) — e.g. conceptually, split on the regex `\n## (Ticket|Bug) ` and capture group 1 as the entry's `Kind` alongside `N`/`Title`/body exactly as today.

- [ ] **Step 3: Existing-issue matching (Procedure step 3)** — currently hardcodes `Ticket N —`. Change the skip-check to match on `"<Kind> N —"` using each entry's own parsed `Kind` (`Ticket` or `Bug`), not a hardcoded string.

- [ ] **Step 4: Issue creation (Procedure step 5)** — title becomes `"%s %d — %s" % [Kind, N, Title]` (unchanged for `Ticket` entries, e.g. still `Ticket 12 — ...`; new for `Bug` entries, e.g. `Bug 15 — ...` — keep "Bug" in the title, don't normalize it to "Ticket"). Labels: `Ticket` entries get `--label ticket` (unchanged); `Bug` entries get **both** `--label ticket --label bug` (keeps bug issues in the same unified queue `work-ticket` already reads via `--label ticket`, while still allowing `--label bug` filtering).

- [ ] **Step 5: Backfill the bugs.md issue number** — immediately after creating a `Bug N —` issue, check `docs/bugs.md` for a `## Bug N —` entry whose `**Ticket:**` line still reads `GitHub issue: pending sync`; if found, replace that phrase with `#<the new issue number>` in place. If no matching entry exists (shouldn't happen if `make-ticket` was used, but don't hard-fail if it does), skip silently — creating `docs/bugs.md` entries isn't this skill's job.

- [ ] **Step 6: Summary report cross-check (Procedure step 6)** — after the existing "`X created, Y skipped`" summary, add: list any GitHub issue labeled `bug` that is **closed** but whose corresponding `docs/bugs.md` entry (matched by parsed `N`) still says `**Status:** Open`, or is missing a filled-in `**Root cause (confirmed):**` / `**Fix summary:**` (i.e. those fields are still the literal placeholder text or blank). Flag each such mismatch explicitly by bug number and issue number — this is the "did the resolution actually get logged" check, since `work-ticket` updates `bugs.md` on close but nothing else double-checks it landed.

- [ ] **Step 7: Notes section wording** — the existing note "`work-ticket` picks the next ticket by lowest open issue number..." and the re-run-safety note should read "ticket or bug" wherever they currently say "ticket" and mean either — a light wording pass, not a logic change.

- [ ] **Step 8: Verify against Task 1's real data** — run the parser logic (by hand or a scratch script) against the current `docs/tickets.md` (14 `Ticket` entries, 0 `Bug` entries as of Task 1) and confirm it still recognizes and correctly skips all 14 (they're already synced) with no behavior change for pure-`Ticket` files — this task must not break the existing, already-verified sync behavior.

- [ ] **Step 9: Commit**

  ```bash
  git add .claude/skills/sync-tickets/SKILL.md
  git commit -m "Extend sync-tickets for bug tickets — dual labels, bugs.md issue-number backfill, resolution cross-check (Piece 6)"
  ```

---

### Task 11: Extend `work-ticket` for GUT verification and bug handling (Piece 7)

**Files:**
- Modify: `.claude/skills/work-ticket/SKILL.md`

**Interfaces:**
- Consumes: Task 2's resolved-binary-path convention and standard test-run command, Task 9's bug-ticket field list (reused verbatim when authoring a bug from a failed run), Task 8's `docs/bugs.md` format.

- [ ] **Step 1: Step 1 (find the next ticket) — fetch labels too, report ticket vs. bug**

  Change the `--json` fields to include `labels`:
  ```bash
  gh issue list --label ticket --state open --json number,title,body,labels --jq 'sort_by(.number) | .[0]'
  ```
  When reporting which issue was picked, state whether it's a **feature ticket** or a **bug ticket** by checking whether its `labels` include `bug`.

- [ ] **Step 2: Steps 2–4 (doc cross-check, ambiguity check, plan) — unchanged.**

- [ ] **Step 3: Replace the old Step 5 ("run whatever headless verification is possible") with real GUT verification**

  New procedure text:

  > **Verify with GUT, not prose-tracing.** For each of the ticket's acceptance criteria that's testable as logic (state mutation, signal emission, calculation, unlock condition — not layout/visual/feel), write or extend a GUT test under `tests/unit/`, mirroring the source tree (e.g. `autoloads/game_state.gd` → `tests/unit/autoloads/test_game_state.gd`; if a test file for that source file already exists from an earlier ticket, extend it rather than creating a second one).
  >
  > Resolve the Godot binary path, in this order, stopping at the first hit: (a) `command -v godot4` / `command -v godot` on PATH, (b) `$GODOT_BIN` env var, (c) `.claude/godot-binary-path.txt` (gitignored — if it doesn't exist yet, ask the user once for the path and save it there so no future run has to ask again), (d) if none of the above resolve, ask.
  >
  > Run the full suite:
  > ```bash
  > BIN=$(cat .claude/godot-binary-path.txt)   # or whichever of (a)/(b) resolved
  > "$BIN" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
  > ```
  >
  > **If any test fails: fix and rerun.** This is not a stop-and-ask situation — a failing test against the ticket's own acceptance criteria is a bug in the current diff, not an ambiguity. Only stop and ask if a reasonable attempt to fix it fails, or the failure reveals the acceptance criteria themselves are contradictory or wrong.
  >
  > **Only once the full suite is green**, stop for editor verification. Report what was built, which acceptance criteria GUT already confirmed (list them), and a checklist of what's left for the user to verify visually/by feel in the editor — GUT shrinks this list, it doesn't replace it. End the turn and wait for the reply.

- [ ] **Step 4: Replace Step 6 (commit) to include test files**

  ```bash
  git add <files touched by this ticket> tests/unit/<any new or extended test files>
  git commit -m "$(cat <<'EOF'
  <one-line summary of what this ticket built>

  Closes #N
  EOF
  )"
  git push
  ```

- [ ] **Step 5: Replace the old implicit "if the user reports a problem" handling with the full bug-authoring flow**

  New procedure text:

  > **If the user confirms it works in the editor:** commit (Step 4) and push exactly as before — direct to master, no branch/PR.
  >
  > **If the user reports a problem:** do not commit or push anything for this ticket. Instead:
  > 1. Author a bug entry using the same fields `make-ticket`'s bug path uses (Description, Repro steps, Expected vs. Actual, Root cause hypothesis, Affected files/scenes, Acceptance criteria — see `.claude/skills/make-ticket/SKILL.md`), and append it to `docs/tickets.md` as the next `## Bug N —` in the shared numbering sequence (same numbering rule as `make-ticket`: scan for the max of both `Ticket`/`Bug` headings, parsed as `(integer, suffix)`).
  > 2. Append the matching stub to `docs/bugs.md` (status `Open`), same format `make-ticket` writes.
  > 3. If the problem found is the kind GUT *could* have caught (state/logic, not visual), say so explicitly in the new bug's acceptance criteria — the eventual fix should close the coverage gap with a real test, not just patch the symptom.
  > 4. Report to the user that the current ticket's GitHub issue stays open (nothing was pushed, nothing closed) pending the new bug ticket, and ask whether they want the fix attempted now in this same session or left for a later `work-ticket`/bug run once it's synced. Don't decide this yourself — ask.

- [ ] **Step 6: Add a new final item — regression-test-first for bug tickets**

  New procedure text:

  > **When the ticket being worked is itself a `## Bug N —` / `Bug N —` issue:** write the regression test first when possible — confirm it fails against the current (buggy) code (i.e. it actually reproduces the bug), then write the fix, then confirm the same test now passes. Once the user confirms in the editor that the fix works, update that bug's original entry in `docs/bugs.md` before committing: fill in **Root cause (confirmed)** (use what was actually found while fixing it — this may differ from the ticket's original hypothesis) and **Fix summary**, flip **Status** to `Fixed`, and include `docs/bugs.md` in the same commit as the code fix and the new regression test.

- [ ] **Step 7: Confirm everything else is unchanged**

  Re-read the resulting file end to end and confirm: cross-checking design/architecture docs, stopping on genuine ambiguity mid-implementation, one-ticket-per-invocation (no auto-chaining to the next ticket), and the existing "If the user reopens an issue" section are all still present and untouched in spirit — only Steps 5–7 (verification, commit, problem-handling) and the bug-specific addition actually change.

- [ ] **Step 8: Commit**

  ```bash
  git add .claude/skills/work-ticket/SKILL.md
  git commit -m "Extend work-ticket for GUT verification and bug-ticket handling (Piece 7)"
  ```

---

### Task 12: Final consistency check + interactive dry-run walkthrough (controller-led, not a subagent dispatch)

This task is performed directly by the orchestrating session after Task 11's review passes — it requires live interaction with the real user (placeholder content, watching for reactions, answering questions), which a subagent cannot do. Do not dispatch this as an implementer task.

- [ ] **Step 1: Cross-file consistency check**

  Confirm all four SKILL.md-affecting pieces (`make-ticket` new, `sync-tickets` and `work-ticket` edited, GUT setup) agree on: the shared `Ticket`/`Bug` numbering rule (identical wording/parse rule in `make-ticket` and `work-ticket`'s bug-authoring step), the `docs/tickets.md` default path (`sync-tickets`), the `ticket`+`bug` dual-labeling (`sync-tickets` creates both, `work-ticket`'s `--label ticket` query still catches bug issues), and the resolved Godot binary path convention (identical resolution order in Task 2's setup and `work-ticket`'s Step 3).

- [ ] **Step 2: Confirm backfill results**

  `grep -c '^## Ticket' docs/tickets.md` → `14`, `grep -c '^## Bug' docs/tickets.md` → `0`. Run the full GUT suite one more time (`tests/unit/`) and confirm it's green end-to-end, covering Tickets 1–9's logic per this plan's Tasks 3–6.

- [ ] **Step 3: Dry-run walkthrough with the user, using placeholder content**

  In order, using clearly-labeled placeholder/example content (not real tickets):
  1. Invoke `make-ticket`'s feature path — author a throwaway example ticket, show the resulting `docs/tickets.md` entry.
  2. Invoke `make-ticket`'s bug path — author a throwaway example bug, show the resulting `docs/tickets.md` entry and the new `docs/bugs.md` stub.
  3. Invoke `sync-tickets` — sync both placeholder entries, show the created GitHub issues (titles, labels) and the `docs/bugs.md` issue-number backfill.
  4. Invoke `work-ticket` on the placeholder feature ticket — actually write and run one real GUT test as part of it, show the suite passing, then **stop at the editor-verification pause** rather than pushing straight through, to demonstrate the new pause-before-push behavior.
  5. Afterward, delete/close out the placeholder GitHub issues and remove the placeholder `docs/tickets.md`/`docs/bugs.md` entries and any placeholder test file — this walkthrough must not leave fake tickets or tests in the permanent record.

  Wait for the user to sanity-check the format and pause behavior before considering this plan complete.
