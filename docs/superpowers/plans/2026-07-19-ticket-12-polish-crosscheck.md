# Ticket 12 — Polish / Cross-Check Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close out GitHub issue #12 — a verification pass over Tickets 1–11 (plus everything since, including 9b/9c and this session's follow-up work), not new functionality. Confirm docs match the build, confirm no dead-end/soft-lock exists in a full playthrough, and flag (not necessarily fix) anything found that's genuinely out of this ticket's own "not new functionality" scope.

**Architecture:** No new subsystems. Task 1 is a real, executed GUT integration test that plays through a full session (empty save → every House button purchased/maxed) using the actual `EffectHandler`/`GameState`/`ButtonData` machinery, replacing what would otherwise be another prose "I traced through the code and it should work" — this project has the tooling to actually run it now. Task 2 fixes two confirmed documentation drifts in `docs/architecture.md` §6 (Confidence's table went from 4 separate rows to one consolidated button; "A Plinth for the Orb" was renamed to "Orb Channeling" when it shipped) and formally documents a real, already-known gap this ticket's own checklist asks to catch (`EventBus.house_tier_changed` has zero emitters — `house_tier` is read, serialized, and wired to the tab title, but nothing anywhere advances it), then closes the issue. The `house_tier` gap itself is **not fixed here** — nothing in the design doc specifies what should trigger house-tier advancement, so building that mechanism would be new functionality, which this ticket's own Goal line explicitly excludes. It gets flagged in the doc and filed as its own follow-up ticket after this plan closes, the same way this project has handled every other "found a real gap, decide fix-now vs. flag-and-file" moment.

**Tech Stack:** Godot 4.7 / GDScript, GUT (vendored at `addons/gut/`).

## Global Constraints

- Direct-to-master: no branches, no PRs.
- GDScript: never `var x := min(...)` / `max(...)` — Variant-inference parse error in this engine build.
- Standard test-run command (mandatory flags, not optional):
  ```
  <godot_bin> --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -ginclude_subdirs -gpre_run_script=res://tests/hooks/pre_run_save_guard.gd -gpost_run_script=res://tests/hooks/post_run_save_guard.gd -gexit
  ```
  Godot binary path: `$(cat .claude/godot-binary-path.txt)`.
- **Already independently verified by the controller before this plan was written — do not re-derive, just build on it:** every button's cost/effect numbers in `data/buttons/house/*.tres` and `autoloads/effect_handler.gd` match `docs/architecture.md` §6 exactly (all 11 shipped buttons cross-checked field-by-field: `touch_orb`, `summon_familiar`, `eat_bread`, `chair`, `table`, `bed`, `confidence` [consolidated], `better_chair`, `better_table`, `better_bed`, `better_meal`). No pricing/effect-number fixes are in scope for this plan.
- **Already independently confirmed:** `EventBus`'s 10 signals — `mana_changed`(2 emitters), `health_changed`(3), `familiar_gained`(2), `upgrade_purchased`(1), `health_depleted`(1), `blackout_ended`(1), `confidence_tier_changed`(1), `state_changed`(25), `game_reset`(2) all have at least one real emitter. `house_tier_changed` has **zero** — this is the one real finding from this checklist item, handled per the Architecture section above (documented + flagged + filed as a follow-up ticket, not fixed in this plan).
- **Already independently confirmed:** the log line format (`tests/unit/autoloads/test_log_manager.gd`, from an earlier plan) already asserts the exact mockup format (`[HH:MM:SS] you gingerly touch the orb.`, lowercase after the timestamp) and passes. No work needed for this checklist item — Task 2's report just states this explicitly rather than silently skipping it.

---

### Task 1: Real executed full-playthrough GUT test

**Files:**
- Create: `tests/unit/integration/test_full_playthrough.gd`

**Interfaces:**
- Consumes: the full, current shipped House content — every `.tres` in `data/buttons/house/`, `autoloads/effect_handler.gd`, `autoloads/game_state.gd`, `scenes/ui/area_tab.tscn` (real scene instantiation, since the acceptance criterion is "play through a session," not just "call effect functions in isolation").

- [ ] **Step 1: Write the test**

  Instantiate the real `area_tab.tscn` with the real `data/areas/house.tres`, and drive an actual playthrough by calling `_handle_click()` on the real button instances found in the columns (not by calling `EffectHandler.run_effect()` directly — the point is proving the *UI-reachable* path has no dead end, matching what a real player clicking through the tab would experience). `before_each()`: `GameState.from_dict({})`.

  Suggested sequence (work out the exact numbers by actually running it — GUT will tell you immediately if a step is unaffordable or a button isn't found; don't hand-trace this speculatively, execute and adjust):

  1. Find and click Touch the Orb once (confirms the always-available baseline action works).
  2. Find and click Summon Familiar enough times to reach at least 5 familiars (needed for Bed's unlock) — its cost grows each time (`1 + 1×count` mana), so click Touch the Orb between summons as needed to afford it, or summon early while mana is cheap and bank familiars before spending any.
  3. Once `familiars >= 1`, find and click Eat Bread (note its 5-second cooldown — call `_process(5.0)` directly on that button instance to fast-forward past it in the test rather than waiting) enough times to reach `food_eaten_count >= 5` (needed for Table).
  4. Buy Chair (`food_eaten_count >= 2`, costs 1 familiar) once eligible.
  5. Buy Table (`food_eaten_count >= 5 && familiars >= 3`, costs 2 familiars) once eligible.
  6. Buy Bed (`familiars >= 5`, costs 4 familiars) once eligible.
  7. Buy Confidence up through all 4 levels (10/20/50/100 mana each — bank mana via Touch the Orb clicks between purchases).
  8. Buy Better Chair, Better Table, Better Bed each up through all 4 levels (familiar-costed, doubling each level).
  9. Buy Better Meal up through all 4 levels (mana-costed, doubling; gated on `better_meal_level < better_table_level`, so this needs Table already bought first, which step 5 already ensures).

  After each purchase, assert the button becomes correctly disabled/hidden as expected (one-shot buttons vanish; `max_purchases`-capped buttons vanish at level 4) — this is what "no dead end" actually means operationally: every button that's supposed to become reachable does, and every button that's supposed to retire does.

  End-state assertions: `GameState.confidence_tier == 4`, `GameState.better_chair_level == 4`, `GameState.better_table_level == 4`, `GameState.better_bed_level == 4`, `GameState.better_meal_level == 4`, `GameState.has_upgrade("chair")`, `GameState.has_upgrade("table")`, `GameState.has_upgrade("bed")` all true, `GameState.health > 0.0` (the playthrough shouldn't have accidentally blacked out and gotten stuck — if it does, that's a genuine finding, not a test bug to paper over).

- [ ] **Step 2: Run it for real, iterate on the exact sequence until it passes**

  ```bash
  BIN=$(cat .claude/godot-binary-path.txt)
  "$BIN" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -ginclude_subdirs -gpre_run_script=res://tests/hooks/pre_run_save_guard.gd -gpost_run_script=res://tests/hooks/post_run_save_guard.gd -gexit
  ```

  If a step fails because a button isn't affordable yet or hasn't unlocked, that's expected mid-development — adjust the *sequence* (bank more mana/familiars first), not the game's numbers. If a step reveals a genuine dead end that no reordering can solve, that's a real finding — stop and report it to the controller rather than working around it.

- [ ] **Step 3: Full-project headless sanity check, watching for any warnings/errors during a real playthrough**

  ```bash
  "$BIN" --headless --quit
  ```

  Also capture and review the full stderr/stdout of the GUT run itself from Step 2 for any unexpected `push_error`/`push_warning`/engine error lines beyond the ones already known-and-expected from other tests' intentional-failure assertions (e.g. `test_refund_on_effect_failure`'s deliberate `better_chair_level already at max` error). List anything new found.

- [ ] **Step 4: Commit**

  ```bash
  git add tests/unit/integration/test_full_playthrough.gd
  git commit -m "Add a real executed full-playthrough test (Ticket 12 checklist item)"
  ```

---

### Task 2: Fix confirmed doc drift, document the house_tier gap, close #12

**Files:**
- Modify: `docs/architecture.md`

- [ ] **Step 1: Fix the Confidence table row**

  In `docs/architecture.md` §6 "House — Column 2 (Upgrades)", the table currently lists Gain Confidence as 4 separate rows (matching how it originally shipped in Ticket 9). It was consolidated into one repeatable button since (this session, `confidence.tres`). Replace the 4 rows:

  ```
  | Gain Confidence 1 | 10 mana | +3 orb mana gain, +5 HP cost on touch |
  | Gain Confidence 2 | 20 mana | +5 orb mana gain, +5 HP cost |
  | Gain Confidence 3 | 50 mana | +7 orb mana gain, +5 HP cost |
  | Gain Confidence 4 | 100 mana | +10 orb mana gain, +5 HP cost |
  ```

  With one row reflecting the shipped shape (same numbers, one button, matching how Better Chair/Table/Bed/Meal are already documented as single repeatable rows with a "×N max" style note):

  ```
  | Gain Confidence | 10/20/50/100 mana per level (×4 max) | +3/+5/+7/+10 orb mana gain per level, +5 HP cost on touch per level |
  ```

- [ ] **Step 2: Fix the "A Plinth for the Orb" naming**

  Same section, Column 1 table. The row currently reads:

  ```
  | A Plinth for the Orb | — | Unlocks Orb Channeling assignment (+1 mana/sec per familiar assigned) | Not a button — up/down arrow allocator |
  ```

  It shipped as "Orb Channeling" (the component's actual name in `scenes/ui/orb_channeling.tscn`/`.gd`), not gated behind a separate "Plinth" purchase/unlock step — it simply appears once the player has at least one familiar (this was a deliberate scope decision made and explicitly communicated to the project owner during that ticket, not an oversight). Update the row to reflect what actually shipped:

  ```
  | Orb Channeling | — | +1 mana/sec per familiar assigned to it | Not a button — up/down arrow allocator; appears once the player has ≥1 familiar (no separate "Plinth" purchase step, unlike the original design doc concept) |
  ```

- [ ] **Step 3: Document the `house_tier_changed` gap**

  Add a short note in §6, right after the Column 2 table (or wherever reads most naturally alongside the other numbers) — this is documentation of a known gap, not a design decision, so keep it factual:

  ```markdown
  **Known gap, flagged by Ticket 12's cross-check, not yet built:** `house_tier` (and `EventBus.house_tier_changed`, which drives the House tab's title progression through `AreaData.name_progression`) is never advanced by anything currently shipped — `GameState` has no `advance_house_tier()`-style method, and no ticket's content triggers one. The field/signal/tab-title-wiring all exist and work correctly once something calls them; nothing does yet. Needs a follow-up ticket to decide what should trigger house-tier progression (a milestone doesn't exist in the design doc yet) — not built here, since that's new functionality, not a cross-check fix.
  ```

- [ ] **Step 4: Verify — read the full updated §6 back and confirm no other row still describes something no longer matching the shipped `.tres` files**

  Cross-check one more time against the actual current `data/buttons/house/*.tres` field dump (already done once by the controller before this plan was written — repeat it yourself to catch anything the controller's pass might have missed):
  ```bash
  for f in data/buttons/house/*.tres; do echo "=== $f ==="; grep -E "^id =|^base_cost|^cost_scaling|^cost_table" "$f"; done
  ```

- [ ] **Step 5: Full-project headless sanity check**

  ```bash
  BIN=$(cat .claude/godot-binary-path.txt)
  "$BIN" --headless --quit
  ```

  (Doc-only change; this just confirms nothing else in the repo is broken at the point of closing out the ticket.)

- [ ] **Step 6: Commit and push, closing the issue**

  ```bash
  git add docs/architecture.md
  git commit -m "$(cat <<'EOF'
  Fix architecture.md drift found in Ticket 12's cross-check

  Confidence consolidated to one row (matches the shipped single-button
  design); "A Plinth for the Orb" renamed to "Orb Channeling" (matches
  the shipped component, no separate purchase step); documented the
  house_tier_changed dead-signal gap as a known, unbuilt gap rather than
  silently leaving the doc to imply it works.

  Closes #12
  EOF
  )"
  git push
  ```

- [ ] **Step 7: Verify the issue closed**

  ```bash
  gh issue view 12 --json state --jq .state
  ```

  Expected: `CLOSED`.

- [ ] **Step 8: Report to the user**

  State what was verified clean (button costs/effects match the docs exactly, log format matches, no other unused signals besides the one flagged), what the real executed playthrough test confirmed (list any milestones it exercised), and the one real gap found and intentionally NOT fixed here (`house_tier_changed`/`house_tier` progression has no trigger anywhere) — recommend filing it as a follow-up ticket via `make-ticket` rather than deciding a trigger mechanism unilaterally, since nothing in the design doc specifies one. Note that this was the last of the original 12 tickets.
