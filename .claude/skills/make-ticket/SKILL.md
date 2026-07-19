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
