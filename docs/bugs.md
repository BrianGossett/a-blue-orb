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

---

## Bug 13 — Buttons don't refresh when an unrelated action makes their unlock_condition true
**Found:** 2026-07-19
**Status:** Fixed
**Description:** Buttons whose `unlock_condition` depends on a stat another button/action changes stay visually disabled even after the condition is satisfied — they only refresh if something unrelated (like a blackout) coincidentally triggers that button's own `_refresh()`.
**Root cause (hypothesis):** `button_action.gd`'s `_ready()` only connects to `EventBus.health_depleted`/`blackout_ended` and, for `tier_source` buttons, `confidence_tier_changed`/`house_tier_changed` — there's no general mechanism re-evaluating `unlock_condition` when the specific stats it references change elsewhere.
**Root cause (confirmed):** `scenes/ui/button_action.gd`'s `_ready()` only connected to `EventBus.health_depleted`/`blackout_ended` and, for `tier_source` buttons, `confidence_tier_changed`/`house_tier_changed` — there was no general mechanism re-evaluating `unlock_condition` when the specific stats it references changed via a *different* button's action. Matches the original hypothesis exactly; no surprises found during the fix.
**Fix summary:** Added a generic, argument-less `EventBus.state_changed` signal, emitted from every public `GameState` mutator (`autoloads/event_bus.gd`, `autoloads/game_state.gd`). Every `button_action.gd` instance now connects to it unconditionally in `_ready()` and calls `_refresh()` on it (`scenes/ui/button_action.gd`), so any state change re-evaluates every live button's `unlock_condition`/afford/cooldown state, not just the ones already covered by blackout or `tier_source` signals.
**Ticket:** Bug 13 in docs/tickets.md · GitHub issue: #17
