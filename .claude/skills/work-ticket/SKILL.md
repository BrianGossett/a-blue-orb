---
name: work-ticket
description: Use when the next open GitHub issue labeled 'ticket' needs to be implemented, committed, and closed.
---

# Work Ticket

Implements the next open `ticket`-labeled GitHub issue, commits, and pushes so GitHub closes it automatically. One ticket per invocation — this skill does not chain to the next ticket automatically, because verifying gameplay/visual behavior requires opening the Godot editor between tickets, which only the user can do.

## Procedure

1. **Find the next ticket:**

   ```bash
   gh issue list --label ticket --state open --json number,title,body,labels --jq 'sort_by(.number) | .[0]'
   ```

   Issue numbers ascend in the order `sync-tickets` created them, which follows the tickets file's own suggested build order — the lowest-numbered open issue is always the correct next one to work. If no open issues remain, report that all tickets are done and stop.

   When reporting which issue was picked, state whether it's a **feature ticket** or a **bug ticket** by checking whether its `labels` include `bug`.

2. **Cross-check the ticket against the living docs.** The issue body is a snapshot of the tickets file at sync time. Before implementing, read `docs/design_doc.md` and `docs/architecture.md` and confirm any numbers/behavior the ticket references (costs, effects, unlock conditions) match what's currently in those docs — they're the balancing source of truth, not the issue body, in case of drift between when the ticket was written and now.

3. **Check for genuine ambiguity before implementing.** If the ticket (or the docs it points to) leaves something undecided rather than merely unspecified-but-inferable — e.g. an effect explicitly marked TBD, a UI element flagged as "check in before building" — stop and ask the user rather than inventing an answer. Don't treat ordinary implementation judgment calls (e.g. exact pixel spacing) as blockers; only stop for things the ticket itself flags as open.

4. **Implement using the issue body as the spec.** Go straight to `writing-plans` to produce an implementation plan, then `executing-plans` (or `subagent-driven-development`) to execute it. Do not run a separate `brainstorming` pass first — these tickets are already detailed specs (files to touch, exact numbers, acceptance criteria); re-brainstorming them is redundant. If `writing-plans` or `executing-plans` surface a genuine ambiguity per step 3 mid-implementation, stop and ask then too.

5. **Verify with GUT, not prose-tracing.** For each of the ticket's acceptance criteria that's testable as logic (state mutation, signal emission, calculation, unlock condition — not layout/visual/feel), write or extend a GUT test under `tests/unit/`, mirroring the source tree (e.g. `autoloads/game_state.gd` → `tests/unit/autoloads/test_game_state.gd`; if a test file for that source file already exists from an earlier ticket, extend it rather than creating a second one).

   Resolve the Godot binary path, in this order, stopping at the first hit: (a) `command -v godot4` / `command -v godot` on PATH, (b) `$GODOT_BIN` env var, (c) `.claude/godot-binary-path.txt` (gitignored — if it doesn't exist yet, ask the user once for the path and save it there so no future run has to ask again), (d) if none of the above resolve, ask.

   Run the full suite, using the exact standard command below (the `-gpre_run_script`/`-gpost_run_script` flags are mandatory, not optional — they protect the real `user://save.json` from being silently overwritten by any test that mutates the live `GameState`/`EventBus` singletons, per Task 6b's finding):
   ```bash
   BIN=$(cat .claude/godot-binary-path.txt)   # or whichever of (a)/(b) resolved
   "$BIN" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -ginclude_subdirs -gpre_run_script=res://tests/hooks/pre_run_save_guard.gd -gpost_run_script=res://tests/hooks/post_run_save_guard.gd -gexit
   ```

   **If any test fails: fix and rerun.** This is not a stop-and-ask situation — a failing test against the ticket's own acceptance criteria is a bug in the current diff, not an ambiguity. Only stop and ask if a reasonable attempt to fix it fails, or the failure reveals the acceptance criteria themselves are contradictory or wrong.

   **Only once the full suite is green**, stop for editor verification. Report what was built, which acceptance criteria GUT already confirmed (list them), and a checklist of what's left for the user to verify visually/by feel in the editor — GUT shrinks this list, it doesn't replace it. End the turn and wait for the reply.

6. **If the user confirms it works in the editor:** commit and push exactly as before — direct to master, no branch/PR.

   ```bash
   git add <files touched by this ticket> tests/unit/<any new or extended test files>
   git commit -m "$(cat <<'EOF'
   <one-line summary of what this ticket built>

   Closes #N
   EOF
   )"
   git push
   ```

   `Closes #N` (matching the actual issue number from step 1) is required in the commit message body — GitHub auto-closes the issue when this lands on the default branch. Push straight to master; no branch, no PR.

   **If the user reports a problem:** do not commit or push anything for this ticket. Instead:
   1. Author a bug entry using the same fields `make-ticket`'s bug path uses (Description, Repro steps, Expected vs. Actual, Root cause hypothesis, Affected files/scenes, Acceptance criteria — see `.claude/skills/make-ticket/SKILL.md`), and append it to `docs/tickets.md` as the next `## Bug N —` in the shared numbering sequence (same numbering rule as `make-ticket`: scan for the max of both `Ticket`/`Bug` headings, parsed as `(integer, suffix)`).
   2. Append the matching stub to `docs/bugs.md` (status `Open`), same format `make-ticket` writes.
   3. If the problem found is the kind GUT *could* have caught (state/logic, not visual), say so explicitly in the new bug's acceptance criteria — the eventual fix should close the coverage gap with a real test, not just patch the symptom.
   4. Report to the user that the current ticket's GitHub issue stays open (nothing was pushed, nothing closed) pending the new bug ticket, and ask whether they want the fix attempted now in this same session or left for a later `work-ticket`/bug run once it's synced. Don't decide this yourself — ask.

7. **Report to the user:** what was built, what to check in the Godot editor to confirm it actually works, and which ticket is next (or that all tickets are done).

## If the user reopens an issue

If a ticket's issue gets reopened after the user finds a problem in-editor, treat it the same as step 1 finding it as the next open issue — implement the fix as a follow-up commit on the same ticket, closing it again the same way.

## When the ticket being worked is itself a bug

When the ticket being worked is itself a `## Bug N —` / `Bug N —` issue: write the regression test first when possible — confirm it fails against the current (buggy) code (i.e. it actually reproduces the bug), then write the fix, then confirm the same test now passes. Once the user confirms in the editor that the fix works, update that bug's original entry in `docs/bugs.md` before committing: fill in **Root cause (confirmed)** (use what was actually found while fixing it — this may differ from the ticket's original hypothesis) and **Fix summary**, flip **Status** to `Fixed`, and include `docs/bugs.md` in the same commit as the code fix and the new regression test.
