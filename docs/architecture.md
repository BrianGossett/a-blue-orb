# "A Blue Orb" — Game Architecture Document

*Companion to the Design Doc. This is the technical reference: file layout, engine structure, data flow, and the numbers we're actually shipping with. Update this as systems get built — the Design Doc stays the "why," this stays the "how."*

**Engine:** Godot 4.x (GDScript)
**Repo:** `a-blue-orb`
**Status:** Draft v0.1 — scaffolding proposal, not yet matched against committed code. Update once the repo has real scenes/scripts in it.

---

## 1. Design Principles → Architecture Decisions

A few things from the Design Doc drive real technical decisions, worth stating up front so future-us doesn't relitigate them:

| Design Doc says... | Architecture response |
|---|---|
| "Numbers can always go up," no unrecoverable state | Game state is a single source of truth (autoload), never derived/duplicated across scenes. No scene should hold its own copy of a stat. |
| Mostly text and buttons, minimal visuals | UI-heavy, art-light. Scenes are mostly `Control` nodes. Room art is a swappable texture, not a scene per room. |
| Button labels/effects change as you upgrade ("gingerly touch" → "carefully touch") | Buttons are **data-driven**, not hardcoded. A button's label, cost, and effect live in a Resource file, not in scene tree text. |
| Long tail of costs that double/scale (x2 per tier, +1 per familiar, etc.) | Costs are formulas tied to a level/count, not fixed per-purchase numbers baked into scenes. |
| Auto-save often, session length shouldn't matter | Central `SaveManager` autoload, timer-based autosave, single JSON blob. |
| Eventually a whole separate mini-game (spider boss fight) inside an Area | Areas are decoupled scenes loaded/unloaded by a manager — a boss fight can be a totally different scene type without breaking the incremental core. |

---

## 2. Top-Level Project Structure

```
a-blue-orb/
├── docs/
│   ├── design_doc.md              (exported copy of the Google Doc, kept in sync)
│   ├── architecture.md            (this file)
│   └── mockups/                   (exported PNGs from Claude Design, numbered per iteration, e.g. 2a_house_tab.png)
├── project.godot
├── autoloads/
│   ├── game_state.gd              (Singleton: all player stats — mana, health, familiars, resources)
│   ├── event_bus.gd               (Singleton: global signals, e.g. "familiar_gained", "area_unlocked")
│   ├── save_manager.gd            (Singleton: load/save to file, autosave timer)
│   └── log_manager.gd             (Singleton: pushes flavor/log lines to the log UI)
├── data/
│   ├── buttons/                   (Resource files, one per button — see §4)
│   │   ├── house/
│   │   │   ├── touch_orb.tres
│   │   │   ├── summon_familiar.tres
│   │   │   ├── eat_bread.tres
│   │   │   ├── gain_confidence_1.tres
│   │   │   ├── ...
│   │   └── ritual_site/
│   │       ├── build_workbench.tres
│   │       ├── ...
│   ├── areas/
│   │   ├── house.tres              (Area resource: name-progression list, unlock conditions)
│   │   └── ritual_site.tres
│   └── balancing/
│       └── constants.gd            (single file of tunable base numbers — see §6)
├── scenes/
│   ├── main.tscn                   (root: tab container + log panel, persistent across areas)
│   ├── ui/
│   │   ├── area_tab.tscn           (reusable: 2-col button grid + room art + description panel)
│   │   ├── button_action.tscn      (reusable button component bound to a ButtonData resource)
│   │   ├── log_panel.tscn
│   │   └── stat_bar.tscn           (mana/health readouts)
│   └── areas/
│       ├── house/
│       │   └── house.tscn
│       └── ritual_site/
│           └── ritual_site.tscn
└── assets/
    ├── fonts/
    ├── art/
    │   └── rooms/                  (circle-vignette room art per house tier)
    └── icons/
```

**Why `data/buttons/` as individual `.tres` Resources, not one big JSON or hardcoded scene logic:** every button in the design doc's tables has the same shape — a label (sometimes several, changing as it upgrades), a cost, a cooldown, and an effect. Godot custom Resources let each button be a small inspectable file you (or Falkner) can tweak without touching code, and they show up as their own inspector UI in the editor. This is the cleanest way to keep design and code in sync as the button tables grow.

---

## 3. Core Autoload Singletons

Godot's autoload system is the backbone here — these four singletons are loaded once and accessible from anywhere, which matches the "single source of truth" principle above.

### `GameState`
Holds every player-facing number: `mana`, `health`, `max_health`, `familiars`, `resources` (dict: stone/wood/water/crystals/etc.), `confidence_tier`, `house_tier`, unlocked areas, purchased upgrades (as a set of IDs). Exposes typed getter/setter methods (`add_mana(amount)`, `spend_familiars(n) -> bool`) rather than letting scenes mutate fields directly, so every change can validate (never below zero, never past caps) and fire signals.

### `EventBus`
Global signal hub: `mana_changed`, `health_changed`, `familiar_gained`, `upgrade_purchased`, `area_unlocked`, `health_depleted`. UI listens to this instead of polling `GameState` every frame — keeps UI decoupled from game logic.

### `SaveManager`
Serializes `GameState` to a single JSON dict, writes to `user://save.json` for the standalone build. For the **web export**, Godot's `user://` maps to IndexedDB automatically in HTML5 exports (not cookies — the design doc's "browser cookies" note is slightly off for Godot specifically; IndexedDB is the actual mechanism and holds far more than a cookie would, which works in our favor for autosave frequency). Runs on a `Timer` (every ~15–30s, tunable) plus on every purchase, per the "auto save often" pillar.

Every save includes a **`save_version` field** written alongside the `GameState` data (from day one, not retrofitted later). On load, `SaveManager` compares it to the current expected version; a mismatch is the hook point for a migration step or a graceful fallback, rather than a renamed button/resource silently corrupting or crashing an old save.

**Export/import fallback (web hosting risk):** IndexedDB persistence is solid on a domain we control, but if the game ends up embedded in an iframe on a third-party site (itch.io serves web games this way), some browsers — Safari in particular, and privacy-hardened Chrome/Firefox — restrict or clear storage for third-party iframe content. A player's save could vanish with no warning. `SaveManager` should expose an **export save** (dump the current JSON blob as a downloadable `.json` file) and **import save** (read a `.json` file back in, version-checked like any other load) as a manual safety net. Cheap to build now, and it turns "my save got wiped" into "just re-upload the file" instead of a lost playthrough.

### `LogManager`
Queue that the log panel reads from. Anything that wants to print a line (`"You gingerly touch the orb."` / `"The orb is cool to the touch."`) calls `LogManager.push(text)`. Keeps flavor text generation out of gameplay code — a button's *effect* script just calls `LogManager.push(data.flavor_text)`, where flavor lines live in the button's Resource, not hardcoded in logic.

---

## 4. Data-Driven Buttons

This is the piece that keeps the whole "areas full of buttons that rename themselves and change costs" system maintainable instead of a wall of `if` statements.

**`ButtonData` (custom Resource, `button_data.gd`):**

```gdscript
class_name ButtonData
extends Resource

@export var id: String
@export var labels: Array[String]        # progression of labels, e.g. ["Gingerly touch the orb", "Carefully touch the orb", ...]
@export var cost_type: String            # "mana" | "familiars" | "stone" | etc.
@export var base_cost: float
@export var cost_scaling: String         # "linear" | "double" | "fixed"
@export var cost_step: float             # +1 per familiar, x2 per tier, etc.
@export var cooldown_sec: float
@export var unlock_condition: String     # reference to a condition check, e.g. "familiars >= 1"
@export var effect_id: String            # which EffectHandler function runs on click
@export var flavor_lines: Array[String]
```

An `EffectHandler` (autoload or static class) maps `effect_id` strings to actual gameplay functions (`_effect_touch_orb()`, `_effect_gain_confidence()`, etc.), so the *data* says "which effect" and the *code* says "what the effect does." Balancing a number (mana gain, HP loss, cost) never requires touching a script — only the `.tres` file.

The generic `button_action.tscn` scene reads a `ButtonData`, renders the current label (indexed by the player's tier for that button), greys itself out if `unlock_condition` isn't met, and shows/hides itself per the design doc's "button appears/disappears and gets replaced by description text" pattern (e.g. Chair, Table, Bed — one-shot purchases that vanish and become area-description text).

---

## 5. UI Architecture (from the mockup)

Matching the "2a" mockup you shared:

```
main.tscn
└── TabContainer                  ("The House" / "Ritual Site" tabs)
    └── area_tab.tscn (x1 per area, instanced from area .tres data)
        ├── HBoxContainer
        │   ├── GridContainer (2 columns)   ← actions (col 1) / upgrades (col 2)
        │   │   └── button_action.tscn instances, populated from data/buttons/<area>/
        │   └── VBoxContainer (right side)
        │       ├── TextureRect (circle vignette, room art — swaps per house tier)
        │       └── RichTextLabel (room description, rebuilt from a template string as furniture is bought)
└── log_panel.tscn (bottom, full width, outside the TabContainer so it persists across tab switches)
```

Key decisions matching the mock:
- **Log panel is a sibling of the TabContainer, not inside it** — the mockup shows the log persisting under both tabs, so it can't live inside a per-area scene or it'd reset/duplicate on tab switch.
- **Room art + description swap together per tab**, driven by whichever `area.tres` is active — same panel, different bound data, not a separate scene per area.
- **Circle vignette is a `TextureRect` with a `CanvasItem` clip/shader**, not a separate art asset per room — keeps the "I might not do pixel art" flexibility from the design doc; a simple color/gradient placeholder can stand in until/unless real room art gets made.
- **Greyed-out locked buttons** (like "a better chair" in the mock) are the same `button_action.tscn`, just with `disabled = true` when `unlock_condition` fails — not a separate visual state to maintain.

---

## 6. Balancing Reference (numbers currently locked in from the Design Doc)

Pulled directly from the design doc's tables so this doc doubles as the live balancing reference. **All marked WIP in the source — update both docs together when these change.**

### House — Column 1 (Actions)

| Button | Cost | Effect | Notes |
|---|---|---|---|
| Gingerly Touch the Orb | — | +1 mana, −5 HP | 1 click/sec cooldown |
| Summon Familiar | 1 mana, +1 per familiar owned | +1 familiar | Renames to "Summon Familiar" after first use |
| Eat Bread | — | +10 HP | Appears after 1st familiar; 1 click/5 sec; cooldown only recharges with ≥1 familiar |
| Stop Sitting on the Floor (→ Chair) | 1 familiar | +1 HP regen/min, +1 orb mana gain | Appears after eating food 2x; one-shot, removes button |
| Something to Eat On (→ Table) | 2 familiars | +2 HP from food, +2 orb mana gain | Appears after 5 food + 3 familiars; one-shot |
| Somewhere to Rest (→ Bed) | 4 familiars | +20 max HP, +3 orb mana gain | Appears at 5 familiars; one-shot |
| A Plinth for the Orb | — | Unlocks Orb Channeling assignment (+1 mana/sec per familiar assigned) | Not a button — up/down arrow allocator |

### House — Column 2 (Upgrades)

| Button | Cost | Effect |
|---|---|---|
| Gain Confidence 1 | 10 mana | +3 orb mana gain, +5 HP cost on touch |
| Gain Confidence 2 | 20 mana | +5 orb mana gain, +5 HP cost |
| Gain Confidence 3 | 50 mana | +7 orb mana gain, +5 HP cost |
| Gain Confidence 4 | 100 mana | +10 orb mana gain, +5 HP cost |
| A Better Meal | 10 mana, ×2/upgrade | +5 HP restore per level; gated on matching table tier |
| A Better Chair | 2 familiars, ×2/upgrade (×4 max) | +1 HP regen/min, +1 orb mana gain per level |
| A Better Table | 4 familiars, ×2/upgrade | +2 HP from food, +2 orb mana gain per level |
| A Better Bed | 8 familiars, ×2/upgrade | (effect TBD in source doc) |

### Table → Food progression
Rickety Table/Bread → Plain Table/Soup → Sturdy Table/Stew → Fine Table/Roast → Handsome Table/Shepherd's Pie.

### Starting state
`mana = 0`, `health = 50`. On `health <= 0`: fade to black, all buttons disabled/on cooldown; when the cooldown ends, player regains +1 HP (see §7.1 for implementation notes).

### Click-rate cap
Global hard limit: **no more than 100 clicks/second**, enforced independently of any per-button cooldown (see §7.3).

### Ritual Site — NOT IN SCOPE YET
Deferred. Structure is documented here for reference only, not for building against right now: primary resources (Stone/Wood/Water/Crystals, familiar-gathered) → created resources (Arcane Dust, Arcane Ink, Charcoal, Chiseled Stone, Sigil Inscribed Stone) via stations → Sigil Inscribed Stone repairs the 4 magic circles → all 4 charged unlocks placing the orb → **MVP: placing the orb ends the game immediately**. No numbers to track here until this area is picked back up — see §7.2.

---

## 7. Open Questions — Resolved

1. **Health-depleted recovery** — RESOLVED. On `health <= 0`: fade to black, all buttons disabled/on cooldown. When the cooldown ends, player gets +1 HP. Implementation: `GameState.health_depleted` signal triggers a UI fade + a single `Timer`; on timeout, `GameState.add_health(1)` fires and buttons re-enable. The cooldown duration itself isn't specified yet — treat as a `balancing/constants.gd` value (e.g. `BLACKOUT_RECOVERY_SEC`) so it's tunable without touching logic.
2. **Ritual Site** — OUT OF SCOPE for now. Not building it yet. `data/areas/ritual_site.tres` and `scenes/areas/ritual_site/` stay as empty placeholders/stubs in the file structure (§2) so the House area and core systems (GameState, SaveManager, EventBus, LogManager, ButtonData) aren't built assuming a second area that doesn't exist yet. Whether the "Ritual Site" tab is hidden entirely or shown-but-disabled in the meantime is a small open call, not urgent.
3. **Click-rate limiter** — RESOLVED. Hard cap of no more than 100 clicks/second, global. This reads as a spam/autoclicker-macro guard rather than a gameplay pacing mechanic — 100/sec is far above human click speed. Implementation: a rolling counter in an input-handling layer (or a small `InputGuard` autoload) that drops clicks past the threshold within any 1-second window. This sits *underneath* the existing per-button cooldowns already in the tables (e.g. "1 click/sec" on Touch the Orb) as a global safety net, not a replacement for them.
4. **Save format versioning** — RESOLVED. Save files will include a version field. Implementation: `SaveManager` writes a `save_version` (or similar) string/int alongside the `GameState` dict on every save. On load, `SaveManager` checks it against the current expected version — if it doesn't match, that's the hook point for either a migration step (rename/remap old fields to new ones) or a graceful "this save is from an older version" fallback, rather than a silent crash or corrupted state when a button or resource gets renamed later. Exact migration strategy (auto-migrate vs. warn-and-reset) is a call for whenever the first breaking change actually happens — not needed yet, just the field itself, from day one.

---

## 8. Workflow Notes

- **Design Doc** (Google Doc, linked from repo README) stays the narrative/intent source of truth — themes, story, pillars, stretch ideas.
- **This doc** stays the technical/numbers source of truth — gets updated whenever a system is actually built, so it reflects real code, not just plans.
- **Mockups** from Claude Design get exported into `docs/mockups/` with the same numbering scheme shown in the tool (2a, etc.) so a scene can be traced back to the mock it was built from.
- Recommend a lightweight rule: **any change to a number in the Design Doc's tables gets mirrored into §6 here in the same sitting** — otherwise the two docs drift and balancing changes get lost.
- **Export/import save** (see §3, `SaveManager`) is a to-build item, not yet implemented — flagging it here so it doesn't get lost before the game actually gets embedded/hosted anywhere third-party.
