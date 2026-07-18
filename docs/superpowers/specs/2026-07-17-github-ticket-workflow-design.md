# GitHub Ticket Workflow — Design

**Date:** 2026-07-17
**Status:** Approved

## Problem

Brian has a build-tickets file (`Blue_Orb_Tickets_House_Tab.md`, 12 tickets covering the House tab end-to-end) that he wants to work through with GitHub as the tracker: each ticket becomes a GitHub issue, gets implemented, and the issue closes when the commit lands.

## Prerequisite bootstrap (one-time, done manually before either skill runs)

The tickets file assumes `docs/design_doc.md`, `docs/architecture.md`, and `docs/mockups/2a_house_tab.png` already exist in the repo (per Ticket 1). They didn't — they were found elsewhere on disk:

- `docs/design_doc.md` ← converted from `~/Downloads/A Blue Orb.docx`
- `docs/architecture.md` ← from `~/Downloads/Game_Architecture_Document (2).md` (the current version — it includes the export/import-save section that `(1)` and the unsuffixed copy lack)
- `docs/mockups/2a_house_tab.png` ← from `~/Documents/2a.png`

This is a one-time step, not repeated by either skill below.

## Two composable skills

### `sync-tickets`

**Input:** path to a tickets markdown file.

**Behavior:**
1. Parse the file by splitting on `## Ticket N — <title>` headers.
2. For each ticket, check for an existing GitHub issue via `gh issue list --label ticket --state all` whose title starts with `Ticket N —`. Skip if found — this makes re-runs safe after editing the tickets file (e.g. adding a Ritual Site batch later).
3. Otherwise create the issue via `gh issue create`:
   - **Title:** `Ticket N — <name>`
   - **Body:** the ticket's full markdown content, with its `**Acceptance criteria:**` bullets rewritten as `- [ ]` GitHub task-list checkboxes
   - **Label:** `ticket` (create the label first if it doesn't exist)
4. Report a summary: N created, M skipped as already existing.

### `work-ticket`

**Behavior:**
1. Find the lowest-numbered open issue labeled `ticket` via `gh issue list --label ticket --state open`. Issue numbers ascend in the order `sync-tickets` created them, which follows the tickets file's own suggested build order — so "lowest number" is "next in dependency order."
2. Read the issue body as the spec. Cross-check any numbers/behavior against `docs/design_doc.md` and `docs/architecture.md` rather than trusting the issue body blindly, since those docs are the living balancing reference.
3. Go straight to the `writing-plans` → `executing-plans` skills using the issue body as the spec. No separate brainstorming pass — these tickets are already detailed enough to act as specs.
4. If something in the ticket is genuinely undecided (e.g. Ticket 9's flagged "A Better Bed's effect is TBD"), stop and ask rather than inventing a number.
5. Run whatever headless verification is possible (GDScript logic checks, `godot --headless --check-only` for parse errors). State plainly that visual/gameplay behavior still needs a check in the Godot editor — that can't be verified headlessly.
6. Commit with a message ending in `Closes #N`, push to master directly (no branch/PR — solo project, no CI yet). GitHub auto-closes the issue on push.
7. Stop. Report what to check in the editor and which ticket is next. (One ticket per invocation — chaining through multiple automatically was explicitly rejected, since editor verification only happens between runs.)

## Out of scope

- Any handling for Ritual Site tickets (explicitly stubbed in this batch).
- Branch/PR workflow — revisit if this becomes a multi-contributor project.
- Auto-reopening logic beyond what GitHub does natively if Brian manually reopens an issue after finding a problem in-editor.
