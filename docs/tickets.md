## Ticket 1 — Project Scaffolding
**Status:** Closed
**GitHub issue:** #1


**Goal:** Create the folder structure and empty Godot project so every later ticket has somewhere to put files.

**Files to create:**
```
a-blue-orb/
├── project.godot
├── autoloads/
├── data/buttons/house/
├── data/areas/
├── data/balancing/
├── scenes/ui/
├── scenes/areas/house/
├── scenes/areas/ritual_site/   (empty, stub only — see architecture doc §7.2)
├── assets/fonts/
├── assets/art/rooms/
├── assets/icons/
└── docs/  (already has design_doc.md, architecture.md, mockups/)
```

**Acceptance criteria:**
- [ ] Project opens cleanly in Godot 4.x with no default nodes left in place.
- [ ] Folder structure matches `docs/architecture.md` §2 exactly (this is the reference — if anything here conflicts with that doc, the doc wins and should be updated to match whatever's decided).
- [ ] `.gitignore` set up for Godot (ignore `.godot/`, `*.tmp`, export artifacts).
- [ ] Empty `ritual_site.tres` and `ritual_site.tscn` exist as placeholders per architecture doc §7.2 — don't build them out, just make sure nothing else assumes they're missing.

---

## Ticket 2 — GameState Autoload
**Status:** Closed
**GitHub issue:** #2


**Goal:** Single source of truth for every player-facing number. No scene should ever hold its own copy of a stat — this is the architecture doc's core non-negotiable (§1).

**File:** `autoloads/game_state.gd`

**State to hold:**
- `mana: float` (starts at 0)
- `health: float`, `max_health: float` (starts at 50/50)
- `familiars: int` (starts at 0)
- `resources: Dictionary` — stub only for now (`{stone: 0, wood: 0, water: 0, crystals: 0}`), not wired to anything yet since Ritual Site is out of scope. Include the field so `SaveManager`'s schema doesn't need to change later.
- `confidence_tier: int` (starts at 0, max 4 — see Ticket 9 for what this drives)
- `house_tier: int` (starts at 0 — drives house name progression, see Ticket 9)
- `purchased_upgrades: Array[String]` — set of one-shot upgrade IDs already bought (chair, table, bed, etc.)
- `orb_mana_per_click: float` and `orb_mana_per_second: float` — base + all the additive bonuses from furniture/confidence tiers land here
- `is_blacked_out: bool` (see Ticket 10)

**Required methods (don't let scenes mutate fields directly):**
- `add_mana(amount: float) -> void`
- `spend_mana(amount: float) -> bool` — returns false and does nothing if insufficient; never goes negative
- `add_health(amount: float) -> void` — clamps to `max_health`
- `spend_health(amount: float) -> void` — clamps to 0, fires `EventBus.health_depleted` if it hits 0 (don't gate this on `is_blacked_out` here — that flag is Ticket 10's job to set from the signal)
- `add_familiars(n: int) -> void`
- `spend_familiars(n: int) -> bool` — returns false if insufficient
- `has_upgrade(id: String) -> bool`
- `mark_upgrade_purchased(id: String) -> void`
- `to_dict() -> Dictionary` and `from_dict(data: Dictionary) -> void` — for `SaveManager` (Ticket 11)

**Acceptance criteria:**
- [ ] Every setter fires the matching `EventBus` signal (see Ticket 3) after mutating state — this is what UI listens to instead of polling.
- [ ] No public field is ever set directly from outside this script in code review — everything goes through a method.
- [ ] Unit-testable in isolation: `spend_mana(1000)` on a fresh state returns `false` and mana stays at 0.

---

## Ticket 3 — EventBus Autoload
**Status:** Closed
**GitHub issue:** #3


**Goal:** Global signal hub so UI never polls `GameState` every frame.

**File:** `autoloads/event_bus.gd`

**Signals to define:**
```gdscript
signal mana_changed(new_value: float)
signal health_changed(new_value: float, max_value: float)
signal familiar_gained(new_total: int)
signal upgrade_purchased(upgrade_id: String)
signal health_depleted
signal blackout_ended
signal house_tier_changed(new_tier: int)
```

**Acceptance criteria:**
- [ ] No gameplay logic lives here — this file is signal declarations only.
- [ ] Every signal listed is actually emitted somewhere by the end of this ticket batch (cross-check against Tickets 2, 9, 10 when those are done — don't leave a signal declared but never fired).

---

## Ticket 4 — LogManager Autoload
**Status:** Closed
**GitHub issue:** #4


**Goal:** Central place anything can push a flavor/mechanical log line to, decoupled from the log UI itself.

**File:** `autoloads/log_manager.gd`

**Interface:**
- `push(text: String) -> void` — timestamps the line (`[HH:MM:SS]`) and appends to an internal array, then emits a signal the log UI listens to.
- `signal line_added(timestamped_text: String)`
- Keep a rolling buffer (last ~200 lines) so the log doesn't grow unbounded over a multi-hour session — per the design doc, sessions can run 3–6 hours.

**Acceptance criteria:**
- [ ] Calling `LogManager.push("You gingerly touch the orb.")` results in a line appearing with a timestamp, matching the mockup's log format exactly: `[12:00:12] you gingerly touch the orb.`
- [ ] Does not depend on any UI node existing — should work (and not error) even before the log panel scene is built, since other systems will start calling this before Ticket 8 is done.

---

## Ticket 5 — ButtonData Resource + EffectHandler
**Status:** Closed
**GitHub issue:** #5


**Goal:** The data-driven button system that's the backbone of the whole UI (architecture doc §4). Get this right before building any actual House buttons — everything in Ticket 9 depends on this shape being correct.

**File:** `data/button_data.gd`

```gdscript
class_name ButtonData
extends Resource

@export var id: String
@export var labels: Array[String]        # progression of labels
@export var cost_type: String            # "mana" | "familiars" | "none"
@export var base_cost: float
@export var cost_scaling: String         # "linear" | "double" | "fixed"
@export var cost_step: float
@export var cooldown_sec: float
@export var unlock_condition: String     # e.g. "familiars >= 1"
@export var effect_id: String
@export var flavor_lines: Array[String]
@export var one_shot: bool               # true for Chair/Table/Bed — button vanishes after purchase
@export var button_column: int           # 1 or 2, matches the mockup's two-column layout
```

**File:** `autoloads/effect_handler.gd` (or a static class, your call — document which in a code comment)

- Maps `effect_id` strings to functions: `_effect_touch_orb()`, `_effect_summon_familiar()`, `_effect_eat_food()`, `_effect_gain_confidence()`, `_effect_add_chair()`, etc.
- Each function reads/writes `GameState`, calls `LogManager.push()` with a flavor line, and returns whether the effect succeeded (for cost deduction / UI feedback).

**Cost formula logic (needs its own small pure function, testable independent of any button):**
- `linear`: `base_cost + (cost_step * count_owned)` — e.g. Summon Familiar costs `1 + (1 * familiars_owned)`.
- `double`: `base_cost * pow(2, upgrade_level)` — e.g. A Better Meal, A Better Chair.
- `fixed`: always `base_cost`, no scaling — e.g. Touch the Orb has no mana cost at all, cost_type "none".

**Acceptance criteria:**
- [ ] A `.tres` file can be created in the editor for "Summon Familiar" with the fields above, and the cost formula produces the design doc's numbers exactly at familiars = 0, 1, 5 (costs: 1, 2, 6 mana).
- [ ] `unlock_condition` string parsing supports at minimum: `stat >= number` and `has_upgrade("id")` — enough to cover every condition in the design doc's House table (architecture doc §6). Don't over-engineer a full expression parser; a small switch/match on a handful of known condition shapes is fine.
- [ ] Effect functions never mutate `GameState` fields directly — they call `GameState`'s public methods from Ticket 2.

---

## Ticket 6 — button_action.tscn Generic Button Component
**Status:** Closed
**GitHub issue:** #6


**Goal:** One reusable scene that renders any `ButtonData`, used for every button in the House tab (and later Ritual Site, when that's picked back up).

**File:** `scenes/ui/button_action.tscn` + `button_action.gd`

**Behavior:**
- Takes a `ButtonData` resource (exported var or `set_data()` call).
- Renders current label — indexed by the button's current tier/level (e.g. Touch the Orb shows `labels[0]` until Confidence 1 is bought, then `labels[1]`).
- Displays cost next to/on the button if `cost_type != "none"` (e.g. "Summon Familiar (2 mana)").
- Greys out (`disabled = true`) when `unlock_condition` isn't met, or when on cooldown, or when the player can't afford the cost — three different disabled states, but visually the mockup only shows one greyed style, so a single `disabled` bool covering all three is fine.
- On click: checks cooldown → checks cost → deducts cost via `GameState` → calls `EffectHandler` for `effect_id` → starts cooldown timer → if `one_shot`, hides itself and fires a signal so the area description (Ticket 9) can update.
- Respects the global click-rate limiter from Ticket 7 — every click event should pass through that check before anything else happens.

**Acceptance criteria:**
- [ ] Matches the mockup visually: buttons "hug their text, fixed width per column" — don't let button width vary wildly based on label length within a column; use a consistent min-width per column instead.
- [ ] A `one_shot` button (Chair) disappears after purchase and its cost is deducted exactly once — no double-fire on rapid clicks.
- [ ] Cooldown visually communicates it's on cooldown (disabled state is enough for v1 — a progress-fill or countdown text is a nice-to-have, not required).

---

## Ticket 7 — Global Click-Rate Limiter
**Status:** Closed
**GitHub issue:** #7


**Goal:** Hard cap of no more than 100 clicks/second, globally, independent of per-button cooldowns. Resolved decision — see architecture doc §7.3.

**File:** `autoloads/input_guard.gd` (or fold into an existing autoload if that's cleaner — your call, just don't duplicate the counter logic in multiple places)

**Behavior:**
- Rolling counter of click events within any 1-second window.
- Exposes something like `InputGuard.try_register_click() -> bool` — every button's click handler (Ticket 6) calls this first and bails out silently if it returns `false`.
- This is a safety net against autoclicker macros, not a gameplay pacing mechanic — it should never be reachable by normal human clicking, so don't build any UI feedback for hitting it (no "you're clicking too fast!" message needed).

**Acceptance criteria:**
- [ ] A scripted test that fires 200 simulated clicks in under a second results in no more than 100 actually registering as click events downstream.
- [ ] Per-button cooldowns (e.g. Touch the Orb's 1 click/sec) still work independently — this ticket doesn't replace those, it sits underneath them.

---

## Ticket 8 — UI Shell (main.tscn, tabs, log panel)
**Status:** Closed
**GitHub issue:** #8


**Goal:** The scene structure from the mockup, wired up but with House as the only functional tab.

**Files:** `scenes/main.tscn`, `scenes/ui/area_tab.tscn`, `scenes/ui/log_panel.tscn`, `scenes/ui/stat_bar.tscn`

**Structure (matches architecture doc §5):**
```
main.tscn
└── TabContainer            ("The House" tab active, "Ritual Site" tab visible-but-disabled)
    └── area_tab.tscn (House instance)
        ├── HBoxContainer
        │   ├── GridContainer (2 columns: col 1 actions, col 2 upgrades)
        │   └── VBoxContainer (right side)
        │       ├── TextureRect (circle vignette room art — placeholder gradient is fine, see notes)
        │       └── RichTextLabel (room description)
└── log_panel.tscn (sibling of TabContainer, NOT inside it — must persist across tab switches)
```

**Notes:**
- Log panel being a sibling, not a child of the tab content, is load-bearing — the mockup shows it persisting under both tabs. Don't let it live inside `area_tab.tscn` or it'll duplicate/reset on tab switch.
- Ritual Site tab should exist and be visible in the `TabContainer` (matches mockup) but disabled/greyed — clicking it does nothing yet. Don't build out any Ritual Site content behind it.
- Room art: since real art may never get made (design doc §"Minimalist Visual Design"), a simple `TextureRect` with a flat color or CSS-gradient-style `Gradient` resource is the correct placeholder — don't block this ticket on needing actual artwork.
- `stat_bar.tscn` shows mana/health readouts — mockup doesn't show exact placement, use your judgment (top of the House tab, above the button grid, is reasonable) and flag it for a design pass later.

**Acceptance criteria:**
- [ ] Visually matches the "2a" mockup layout: 2-column button grid on the left, room art + description on the right, log panel full-width at the bottom, tabs at the top.
- [ ] Switching to the (disabled) Ritual Site tab and back doesn't clear or duplicate the log.
- [ ] `area_tab.tscn` reads from a bound `area.tres` resource rather than hardcoding "House" anywhere in this scene's script — this is what lets Ritual Site slot in later without rebuilding this scene.

---

## Ticket 9 — House Button Content
**Status:** Closed
**GitHub issue:** #9

**Goal:** Populate `data/buttons/house/` with every button from the design doc's House tables (architecture doc §6), fully playable start-to-finish.

**Files:** One `.tres` per button in `data/buttons/house/`, following the `ButtonData` shape from Ticket 5 — **plus code changes to `autoloads/effect_handler.gd` and `autoloads/game_state.gd`.** This is not data-only. `ButtonData`'s current shape (Ticket 5) has no field for effect magnitudes — every effect's numbers live in `effect_handler.gd` as hardcoded values inside named functions, one per `effect_id`. Ticket 5 only built 5 of them (`touch_orb`, `summon_familiar`, `eat_food`, `gain_confidence`, `add_chair`). This ticket needs to add the rest as new `effect_id` cases in `EffectHandler.run_effect()`'s match statement — at minimum `add_table`, `add_bed`, `better_meal`, `better_chair`, `better_table`, `better_bed`, and whatever the Orb Channeling allocator (item 7 below) needs — following the same pattern as Ticket 5's existing five (read/write `GameState` only through its public methods, call `LogManager.push()`, return success bool).

**Button ordering (flagged by Ticket 8's final review):** `area_tab.gd`'s `_load_buttons()` loads every `.tres` in `data/buttons/house/` and sorts them by `ButtonData.sort_order` (an int field added for exactly this) before adding them to their column — it does NOT preserve filename/alphabetical order. Every `.tres` this ticket creates must set `sort_order` to match its position in the "Column 1" / "Column 2" lists below (e.g. `touch_orb.tres` = 1, `summon_familiar.tres` = 2, ... `confidence_1.tres` = 1, `better_meal.tres` = 5, etc. — sort_order only needs to order buttons within their own column, not across columns). Skipping this means buttons render in whatever order the filesystem happens to return them, not the mockup's intended order.

**Tab title note:** `area_tab.gd` already sets the House tab's title from `AreaData.name_progression[GameState.house_tier]` (Ticket 8) — at `house_tier = 0` it reads "A Small Shelter", not "The House" (the mockup's placeholder label). This is intended, working behavior, not something to fix — just don't be surprised by it when verifying in the editor.

**Two specific gaps flagged by Ticket 5's final review — resolve as part of this ticket, don't silently drop:**
- **Confidence's HP-cost growth is not implemented.** Design doc/architecture §6: each Confidence tier adds both `+N orb mana gain` (already implemented, Ticket 5) *and* `+5 HP cost on touch` (not implemented — `_effect_touch_orb()` currently spends a fixed `5.0` HP regardless of confidence tier). As shipped, confidence is strictly stronger than designed (more mana per touch, same HP cost forever). Fixing this needs a new accumulating field on `GameState` (e.g. `orb_health_cost_per_click`, mirroring `orb_mana_per_click`'s pattern — starts at `5.0`, a new `add_orb_health_cost_per_click(amount)` method, no matching `EventBus` signal needed just like the mana one) plus updating `_effect_touch_orb()` to spend that field's value instead of a hardcoded `5.0`, and `_effect_gain_confidence()` to also call the new method.
- **Chair's (and Better Chair's) "+1 HP regen/min" passive effect has no mechanism anywhere in the codebase.** No ticket in this batch builds a ticking/regen system. `_effect_add_chair()` currently only applies the instant parts (familiar cost, upgrade flag, `orb_mana_per_click` bonus). This needs an actual per-minute regen tick somewhere — a `Timer` in `GameState` (or a new small autoload if that reads cleaner) that periodically calls `add_health()` by whatever the current accumulated regen rate is. If this feels like its own sub-task, that's fine — just make sure it's built before this ticket is called done, since "+1 HP regen/min" is explicitly one of Chair's two effects in the design doc, not a stretch item.

**Column 1 (Actions) — build in this order, each depends on the last being testable:**
1. `touch_orb.tres` — no cost, +1 mana / −5 HP, 1 click/sec cooldown. Labels progress through 5 tiers as Confidence upgrades are bought (Ticket 9, Column 2): "Gingerly touch the orb" → "Carefully touch the orb" → "Place your hand on the orb" → "Place both hands on the orb" → "Hold the orb for a moment".
2. `summon_familiar.tres` — cost: 1 mana + 1 per familiar owned (linear scaling). Label starts as "Make Something", renames to "Summon Familiar" after first use (this is a one-time label change on first purchase, not tier-based — may need a small special case since it's not driven by the same tier system as Touch the Orb).
3. `eat_bread.tres` — appears after 1st familiar summoned, +10 HP, 1 click/5 sec, cooldown only recharges while `familiars >= 1`. Label changes to match table tier later (Ticket 9 food progression, below).
4. `chair.tres` (one_shot) — "Stop Sitting on the Floor" → appears after eating food 2x, costs 1 familiar, +1 HP regen/min +1 orb mana gain, vanishes after purchase and updates room description.
5. `table.tres` (one_shot) — "Something to Eat On" → appears after eating food 5x + 3 familiars, costs 2 familiars, +2 HP from food +2 orb mana gain.
6. `bed.tres` (one_shot) — "Somewhere to Rest" → appears at 5 familiars, costs 4 familiars, +20 max HP +3 orb mana gain.
7. `orb_plinth.tres` — not a standard button; unlocks the "Orb Channeling" allocator (up/down arrow UI, +1 mana/sec per familiar assigned). This one probably needs its own small custom UI component rather than fitting `button_action.tscn` — flag this and check in before building if the shape doesn't fit.

**Column 2 (Upgrades):**
8. `confidence_1.tres` through `confidence_4.tres` — 10/20/50/100 mana, each granting +3/+5/+7/+10 orb mana gain and +5 HP cost on touch, each unlocking the next tier's label on `touch_orb.tres`.
9. `better_meal.tres` — 10 mana base, ×2 per upgrade, +5 HP restore per level, gated on owning the matching table tier.
10. `better_chair.tres` — 2 familiars base, ×2 per upgrade, max 4 levels, +1 HP regen/min +1 orb mana gain per level.
11. `better_table.tres` — 4 familiars base, ×2 per upgrade, +2 HP from food +2 orb mana gain per level.
12. `better_bed.tres` — 8 familiars base, ×2 per upgrade. **Effect is TBD in the source design doc** — don't invent a number here, stub it with a `TODO` comment and flag it back for a design decision before shipping.

**Food/table name progression** (drives `eat_bread.tres`'s label and `better_meal.tres`'s tier): Rickety Table/Bread → Plain Table/Soup → Sturdy Table/Stew → Fine Table/Roast → Handsome Table/Shepherd's Pie.

**House name progression** (drives `area_tab.tscn`'s title/description per architecture doc — house_tier on `GameState`): A Small Shelter → A Lonely Hut → A Sturdy Cottage → A Comfortable House → A Fine Residence (further tiers exist in the design doc but are explicitly stretch-goal content — stop at "A Fine Residence" for this ticket batch unless told otherwise).

**Acceptance criteria:**
- [ ] A player can go from a fresh save (0 mana, 0 familiars, 50 HP) all the way through summoning familiars, eating, buying chair/table/bed, and maxing all 4 Confidence tiers, using only this ticket's content — no dead ends, no button that never becomes clickable.
- [ ] Every `unlock_condition` in this list is verified against the actual gate described in the design doc table (architecture doc §6 has these transcribed already — cross-check against it, not just this ticket, in case of transcription drift).
- [ ] One-shot buttons update the room description text (the `RichTextLabel` from Ticket 8) when purchased — "The room has a chair" gets appended/rebuilt, matching the mockup's "description updates as furniture is bought" note.
- [ ] Confidence's HP-cost-on-touch actually grows by +5 per tier (verify: at Confidence 4, touching the orb costs 25 HP, not 5).
- [ ] Chair and Better Chair's "+1 HP regen/min" (cumulative) is actually ticking during play, not just applying the one-shot `orb_mana_per_click` bonus.

---

## Ticket 9b — Better Chair/Table/Bed, Eat Bread cooldown, save-reload defensive fix
**Status:** Closed
**GitHub issue:** #13

Follow-up to Ticket 9 (House Button Content — core loop). Narrowed scope, decided directly with the project owner: this issue now covers only Better Chair, Better Table, Better Bed, and two small isolated fixes. Orb Channeling and Better Meal were split into a separate follow-up issue (both need their own design/architecture decisions before implementation — see that issue).

## 1. Better Chair, Better Table, Better Bed (repeatable, tiered upgrades)

`better_chair.tres`, `better_table.tres`, `better_bed.tres` (architecture.md §6, Column 2) are repeatable upgrades layered on top of the one-shot furniture Ticket 9 already built — `×2 cost per level`, gated on owning the matching base furniture (`has_upgrade("chair")` etc. — the existing condition shape covers this, no new grammar needed), each disappearing after a maximum number of purchases.

Per-level effects, each derived directly from the matching one-shot furniture's own established bonus (not invented fresh — Better Chair/Table already show a "per-level bonus = the one-shot's own bonus" pattern in the design doc, applied here to Bed too):
- **Better Chair** (2 familiars base, ×2/level, max 4 levels): +1 HP regen/min, +1 orb mana gain per level.
- **Better Table** (4 familiars base, ×2/level, max 4 levels): +2 HP from food, +2 orb mana gain per level.
- **Better Bed** (8 familiars base, ×2/level, max 4 levels): +20 max HP, +3 orb mana gain per level — this effect was undecided in the source design doc; the project owner confirmed mirroring the established per-level-equals-one-shot pattern rather than inventing something new.

New `GameState` fields needed: `better_chair_level`, `better_table_level`, `better_bed_level` (each 0-4), separate from the one-shot `purchased_upgrades` set (which tracks "do I own it," not "what level is the upgrade at").

New `ButtonData` field needed: `max_purchases: int` (0 = unlimited) — a button hides itself once its own purchase count reaches this, distinct from `one_shot` (which hides after exactly 1 purchase). `cost_count_source` does NOT need a new option for these — each upgrade's own self-referential click count (the existing default `_purchase_count` behavior) is already correct here, unlike Summon Familiar's need to track a live external stat.

## 2. Eat Bread cooldown nuance: only recharges while `familiars >= 1`

Deferred from Ticket 9. The cooldown mechanism needs to switch from a fire-and-forget `SceneTreeTimer` to a per-frame countdown that can pause, gated by a new optional `ButtonData.cooldown_gate_condition: String` field reusing the exact same condition grammar `is_unlock_condition_met` already parses (e.g. `"familiars >= 1"`) — no new parser needed, just a new field consumed by the same existing function.

## 3. Save/reload defensive fix for one-shot furniture (partial — full fix still needs Ticket 11)

Ticket 11 (Save System) still doesn't exist, so this can't be fully tested yet, but the defensive half that doesn't require a save system is being added now: `area_tab.gd::_load_buttons()` will skip re-showing a one-shot button whose `id` is already in `GameState.purchased_upgrades`, and will seed `_furniture_fragments` (and rebuild the description) from those already-purchased buttons' `room_description_fragment` values at load time, not only reactively via the purchase signal. This does NOT fix `_load_buttons()` being called a second time on the same node (duplicate button instances) — that's a distinct idempotency concern, not exercised by anything today, and is Ticket 11's problem if its reload flow ever calls `set_area_data()` on a live node rather than reloading the whole scene.

**Acceptance criteria:**
- [ ] Owning Chair, buying Better Chair four times reaches `better_chair_level=4`, the button disappears after the 4th purchase, and total bonus is +4 HP regen/min +4 orb mana gain (cumulative across all 4 levels).
- [ ] Same shape verified for Better Table (+8 total HP-from-food bonus, +8 orb mana gain) and Better Bed (+80 total max HP, +12 orb mana gain) at 4 levels each.
- [ ] None of the three upgrade buttons are clickable/visible before their matching base furniture is owned.
- [ ] Eat Bread's cooldown does not tick down while `familiars == 0` (verify: spend all familiars on furniture, confirm Eat Bread's cooldown timer visibly stalls until a familiar is summoned again), and does tick normally whenever `familiars >= 1`.
- [ ] A `ButtonData` instance representing an already-purchased one-shot furniture item is skipped by `_load_buttons()` (verify by manually calling `GameState.mark_upgrade_purchased("chair")` before `_load_buttons()` runs, then confirming no Chair button gets instantiated and the room description already reads "...has a chair.").

---

## Ticket 9c — Orb Channeling + Better Meal
**Status:** Closed
**GitHub issue:** #14

Split off from Ticket 9b (issue #13) — both items here need a real design/architecture decision before implementation, unlike the rest of 9b which was directly actionable.

## 1. Orb Channeling (`orb_plinth.tres` + custom allocator UI)

"A Plinth for the Orb" (architecture.md §6, Column 1) is not a normal button — it's an up/down arrow allocator that assigns familiars to passive mana generation (`+1 mana/sec per familiar assigned`). It doesn't fit the generic `button_action.tscn` component (label + cost + single click effect) at all: it needs a stepper control bound to a live count, a running total of "assigned" vs. "idle" familiars, and continuous per-second income rather than a discrete click effect. This needs its own scene/component, not a `ButtonData` resource. `GameState` will also need a field for familiars-assigned-to-orb (distinct from total `familiars`), since `orb_mana_per_second` already exists on `GameState` as a placeholder but nothing currently writes to it. Continuous income likely wants its own ticking autoload, following the `RegenManager` (Ticket 9) pattern — a `Timer` applying `orb_mana_per_second` to mana once per second.

**Open design question, needs the project owner's input before planning:** what happens to a familiar assigned to the orb if it's later "spent" elsewhere (Chair/Table/Bed cost familiars)? Does assignment reserve/lock familiars out of the general pool, or can an assigned familiar still be spent (silently reducing the assigned count too)? This affects the UI's up/down arrow bounds and whether `GameState` needs its own validation beyond `spend_familiars`.

## 2. Better Meal — blocked on a new unlock-condition shape

`better_meal.tres` (architecture.md §6, Column 2): 10 mana base, ×2 per upgrade, +5 HP restore per level — gated on "owning the matching table tier" per the design doc. That gating condition doesn't have an equivalent in the current `unlock_condition` grammar (`is_unlock_condition_met` supports `stat >= threshold`, `&&`-joined compounds, and `has_upgrade(id)` — none of which express "my current Better Meal level must not exceed my current Better Table level").

**Open design question:** since Better Table doesn't yet have a "tier" concept surfaced anywhere except its own `better_table_level` (Ticket 9b), does "matching table tier" mean Better Meal's level N purchase requires `better_table_level >= N`? If so, the unlock condition needs either (a) a new condition shape that compares two stats to each other (not just a stat to a literal number), or (b) computing the allowed max level in code before offering the button, outside the declarative `unlock_condition` string entirely. Worth deciding which approach fits the project's "small switch/match on a handful of known condition shapes, don't over-engineer a full expression parser" philosophy (established in Ticket 5) before writing `better_meal.tres`.

**Precedent now available, from Ticket 9b:** Better Meal is the same *shape* as Better Chair/Table/Bed (a capped, repeatable, `GameState`-tier-tracked upgrade with doubling cost) — don't reinvent that part. `ButtonData` already has `max_purchases: int` (hides a button after N purchases, used for all three Better X upgrades at `max_purchases=4`) and `cooldown_gate_condition: String` (reuses `is_unlock_condition_met`'s existing grammar to pause a cooldown on a live condition — not directly relevant to Better Meal's gating, but worth knowing it exists as the established pattern for "reuse the condition parser rather than add a new mechanism"). Better Meal's own tier field (`GameState.better_meal_level` or similar) and its `_effect_better_meal()` function should follow the exact same pattern as `_effect_better_chair()` etc. — read/increment the tier field directly, never self-deduct cost (that bug class has been found and fixed twice already in this project). What's genuinely new for Better Meal, not covered by the precedent, is only the *unlock condition* comparing two stats to each other, described above.

**Acceptance criteria:**
- [ ] Orb Channeling: player can assign/unassign familiars via the allocator, `orb_mana_per_second` accumulates correctly, income actually ticks into `mana` over time, and the allocator's bounds correctly prevent assigning more familiars than are available.
- [ ] Better Meal: purchasable up to (and gated correctly by) whatever "matching table tier" resolves to, `food_heal_bonus` grows per level as specified in architecture.md §6, and the unlock-condition mechanism chosen is documented clearly enough that a future ticket extending it understands the pattern.

---

## Ticket 10 — Health Depletion / Blackout Recovery
**Status:** Closed
**GitHub issue:** #10


**Goal:** Resolved decision from architecture doc §7.1 — fade to black, all buttons on cooldown, +1 HP when cooldown ends.

**Files:** touches `autoloads/game_state.gd` (already has the `health_depleted` signal firing from Ticket 2), a new `blackout_overlay.tscn` UI piece, and `data/balancing/constants.gd` for the tunable.

**Behavior:**
- `EventBus.health_depleted` fires when health hits 0 (already wired in Ticket 2).
- On that signal: full-screen fade-to-black overlay appears, every `button_action.tscn` instance goes disabled (regardless of its own cooldown state).
- A single `Timer` starts, duration = `Constants.BLACKOUT_RECOVERY_SEC` (put a placeholder value like `5.0` in `constants.gd` with a comment that it's a balancing placeholder, not a locked number).
- On timer timeout: `GameState.add_health(1)`, overlay fades out, buttons re-enable, `EventBus.blackout_ended` fires.
- **Edge case to handle:** if the player's actions would still leave them unable to recover (e.g. every action costs more HP than they have and nothing regenerates), this +1 HP grant is the only way out of a blackout — make sure `is_blacked_out` on `GameState` genuinely blocks all HP-spending actions until recovery completes, or the "no unrecoverable state" pillar (design doc §2) breaks.

**Note from Ticket 9's final review:** `autoloads/regen_manager.gd` (added in Ticket 9 for Chair's "+1 HP regen/min") ticks unconditionally whenever `GameState.health_regen_per_minute > 0` — it has no `is_blacked_out` check. Decide here whether passive regen should pause during blackout (a Chair owner could otherwise passively self-revive without the blackout mechanism ever mattering) or whether that's acceptable/intended. If it should pause, gate `RegenManager._on_tick()`'s `add_health` call on `not GameState.is_blacked_out`.

**Acceptance criteria:**
- [ ] Spending health down to exactly 0 (not below — `GameState.spend_health` should clamp) triggers the full sequence with no way to click through it early.
- [ ] After recovery, the player has exactly 1 HP and normal play resumes — verify this doesn't chain into an immediate second blackout if the player's next action costs more than 1 HP (that's expected/fine — just confirm it's not a soft-lock, since they can wait and let natural regen or another Eat Bread click bring them back up).

---

## Ticket 11 — Save System (autosave + manual export/import)
**Status:** Closed
**GitHub issue:** #11


**Goal:** `SaveManager` autoload per architecture doc §3, including the export/import fallback decided for third-party web hosting risk.

**File:** `autoloads/save_manager.gd`

**Behavior:**
- `save_game() -> void` — serializes `GameState.to_dict()` plus a `save_version` field into a JSON blob, writes to `user://save.json`.
- `load_game() -> bool` — reads `user://save.json` if it exists, checks `save_version` against the current expected constant; on mismatch, log a warning and treat as no save found for now (a real migration path isn't needed yet — see architecture doc §7.4, just don't crash or silently corrupt state).
- Autosave: a `Timer` firing every 15–30 sec (put the interval in `constants.gd`), plus an explicit `save_game()` call on every purchase (hook into `EventBus.upgrade_purchased` and `EventBus.familiar_gained` at minimum).
- `export_save() -> void` — same JSON blob, offered as a browser download (HTML5 export) or a file-save dialog (standalone). Check Godot's `FileAccess`/`OS` APIs for the correct approach per platform — this may need an `if OS.has_feature("web")` branch.
- `import_save(file_data: String) -> bool` — parses JSON, version-checks, and calls `GameState.from_dict()` if valid; returns false with no state change if the file is malformed or version-mismatched.

**Soft-lock risk flagged by Ticket 10's final review — handle explicitly, don't just carry it forward silently:** `GameState.is_blacked_out` is already serialized in `to_dict()`/`from_dict()` (from Ticket 2, before blackout actually did anything). Now that Ticket 10 makes that flag authoritatively block all HP spending (`spend_health()` no-ops while it's true), a naive save/load creates a genuine unrecoverable state: if autosave fires during the ~5s blackout window and the player later reloads that save, `from_dict()` restores `is_blacked_out=true`, but nothing re-arms the recovery — the blackout overlay isn't shown, no recovery `Timer` is running (it lives on `blackout_overlay.tscn`'s instance, not in saved state), and every `button_action.gd` instance's local blackout flag defaults to `false` on a fresh scene load (it's only set by the live `health_depleted` signal, which won't fire just from loading a save). Net effect: buttons render enabled, but `spend_health()` silently blocks forever with no visible indication why and no path back — exactly the "no unrecoverable state" pillar this whole mechanic exists to protect. Resolve one of: (a) exclude `is_blacked_out` from persistence entirely and always load as `false`, (b) force it to `false` in `load_game()`/`import_save()` regardless of what the file says, or (c) if loading into `is_blacked_out=true` is ever intentional, have `load_game()` explicitly re-trigger the full blackout sequence (show overlay, start timer) rather than leaving it inert. (a) or (b) are simplest and likely correct, since a blackout is meant to be a short transient state, not something worth persisting across a session boundary at all.

**Second reload gap, flagged by Ticket 9b's final review — the Better X upgrades (Chair/Table/Bed) need reconstruction on load, not just deserialization:** `better_chair_level`/`better_table_level`/`better_bed_level` are persisted in `to_dict()`/`from_dict()`, but nothing reconstructs the matching UI-layer state on load. Each Better X button's `_purchase_count` (in `button_action.gd`, drives its cost formula and its `max_purchases`-based hide check) resets to `0` in `set_data()` and has no `tier_source` wiring back to its `GameState` level field (unlike Touch the Orb, which uses `tier_source` for exactly this kind of external-state sync). Concretely: loading a save with `better_chair_level=4` would re-show the Better Chair button at its base cost (2 familiars) instead of hiding it; clicking it would deduct familiars, then `_effect_better_chair()`'s `>= 4` guard would fire, `push_error`, and `run_effect` returns `false` — which `button_action.gd::_handle_click()` currently ignores (cost was already deducted before the effect ran), so the player would silently lose familiars for nothing, repeatedly, until enough wasted clicks happened to trip `max_purchases` and hide the button. Not reachable today (nothing calls `from_dict()` yet), but real once this ticket ships. Fix needs either: seeding each Better X button's `_purchase_count` from its `GameState` level field on load (e.g. via `set_purchase_count()`, the same mechanism `tier_source` already uses), or making `_handle_click()` respect `run_effect()`'s return value and refund/skip on `false` (a more general fix worth considering regardless, since it's the root cause of the wasted-currency failure mode).

**Acceptance criteria:**
- [ ] Closing and reopening the game (or reloading the page on web) restores exact state — mana, health, familiars, all purchased upgrades, house tier.
- [ ] `save_version` is present in every save file from day one, even though there's nothing to migrate yet.
- [ ] Export produces a file a player can actually download in an HTML5 export (test this in an actual browser export, not just the editor — `user://` behavior can differ).
- [ ] Import correctly rejects a save file from a different `save_version` without corrupting current state — verify by hand-editing a save's version field and attempting import.

---

## Ticket 12 — Polish / Cross-Check Pass
**Status:** Open
**GitHub issue:** #12


**Goal:** Not new functionality — a verification pass once Tickets 1–11 are done, to catch drift between the docs and the build.

**Checklist:**
- Every button's cost/effect numbers match architecture doc §6 exactly — diff them by hand, table by table.
- Every `EventBus` signal declared in Ticket 3 is actually emitted somewhere (grep for unused signals).
- Play through a full session start-to-finish (empty save → all House content purchased) and confirm no dead-end, no soft-lock, no console errors.
- Confirm the log panel format exactly matches the mockup: `[HH:MM:SS] you gingerly touch the orb.` (lowercase after the timestamp, matching the mock's tone — flag if this was built differently and needs a fix).
- Flag anything discovered during build that should update `docs/architecture.md` (per that doc's own workflow note in §8) — don't let the doc silently go stale.


---

## Bug 13 — Buttons don't refresh when an unrelated action makes their unlock_condition true
**Status:** Not yet synced

**Description:** Buttons whose `unlock_condition` depends on a stat another button/action changes (food_eaten_count, familiars, mana, has_upgrade, etc.) stay visually disabled even after the condition is actually satisfied. They only "un-stick" if something happens to independently trigger that specific button's own `_refresh()` — e.g. surviving a blackout, since `EventBus.health_depleted`/`blackout_ended` are the only global signals every `button_action.gd` instance listens to regardless of its own data.

**Repro steps:**
1. Start a fresh session (or one with House content loaded).
2. Eat bread twice (`food_eaten_count` reaches 2, satisfying `chair.tres`'s `unlock_condition = "food_eaten_count >= 2"`).
3. Observe the Chair button: it stays greyed out/disabled instead of becoming clickable, even though the condition is now true.
4. Same pattern applies to Table (`food_eaten_count >= 5 && familiars >= 3`), Bed (`familiars >= 5`), Confidence 2–4 (`confidence_tier >= N`), and Better Chair/Table/Bed (`has_upgrade(...)`) — any button without a `tier_source` set, whose unlock condition depends on state that changes via a *different* button's click.

**Expected vs. Actual:** Expected: a button whose `unlock_condition` becomes true re-evaluates and enables itself promptly (on the very next relevant state change, not just eventually). Actual: it only re-evaluates if something coincidentally calls that specific button instance's own `_refresh()` — its own click (can't happen, it's disabled), `tier_source` signal (only 2 buttons use this), or a blackout/recovery cycle (unrelated to the unlock condition at all).

**Root cause hypothesis:** `scenes/ui/button_action.gd`'s `_ready()` only connects `EventBus.health_depleted`/`EventBus.blackout_ended` (both call `_refresh()`) and, for buttons with `tier_source` set, `EventBus.confidence_tier_changed`/`house_tier_changed` (via `_connect_tier_source()`). There is no general mechanism that re-evaluates `_is_disabled()` (which checks `ButtonData.is_unlock_condition_met()`) when the specific stats a button's own `unlock_condition` references change from elsewhere — e.g. `food_eaten_count`, `familiars`, `mana`, or `has_upgrade(...)` results. This gap was flagged during Ticket 9c's final review as a known, deferred issue intended for Ticket 12 (Polish/Cross-Check Pass), but Ticket 12 hasn't addressed it yet.

**Affected files/scenes:** `scenes/ui/button_action.gd` (the missing reactive-refresh mechanism), `autoloads/event_bus.gd` (may need broader signals or a different refresh trigger), every `.tres` in `data/buttons/house/` with a non-empty `unlock_condition` and no `tier_source`.

**Acceptance criteria:**
- [ ] After eating bread twice, the Chair button becomes clickable without requiring any unrelated action (like a blackout) to refresh it.
- [ ] The same holds for Table, Bed, Confidence 2–4, Better Chair/Table/Bed, and any other button whose `unlock_condition` depends on a stat that changes via a different button's action.
- [ ] The fix generalizes — it shouldn't require hardcoding a signal connection per stat per button; a new stat added later with an `unlock_condition` referencing it should work without touching `button_action.gd` again.
- [ ] A GUT test locks this down: mutate the relevant `GameState` stat directly (not through the gated button itself), and confirm an already-instantiated `button_action.tscn` with a matching `unlock_condition` becomes enabled without any other trigger.
