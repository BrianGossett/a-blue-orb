---
name: work-ticket
description: Use when the next open GitHub issue labeled 'ticket' needs to be implemented, committed, and closed.
---

# Work Ticket

Implements the next open `ticket`-labeled GitHub issue, commits, and pushes so GitHub closes it automatically. One ticket per invocation — this skill does not chain to the next ticket automatically, because verifying gameplay/visual behavior requires opening the Godot editor between tickets, which only the user can do.

## Procedure

1. **Find the next ticket:**

   ```bash
   gh issue list --label ticket --state open --json number,title,body --jq 'sort_by(.number) | .[0]'
   ```

   Issue numbers ascend in the order `sync-tickets` created them, which follows the tickets file's own suggested build order — the lowest-numbered open issue is always the correct next one to work. If no open issues remain, report that all tickets are done and stop.

2. **Cross-check the ticket against the living docs.** The issue body is a snapshot of the tickets file at sync time. Before implementing, read `docs/design_doc.md` and `docs/architecture.md` and confirm any numbers/behavior the ticket references (costs, effects, unlock conditions) match what's currently in those docs — they're the balancing source of truth, not the issue body, in case of drift between when the ticket was written and now.

3. **Check for genuine ambiguity before implementing.** If the ticket (or the docs it points to) leaves something undecided rather than merely unspecified-but-inferable — e.g. an effect explicitly marked TBD, a UI element flagged as "check in before building" — stop and ask the user rather than inventing an answer. Don't treat ordinary implementation judgment calls (e.g. exact pixel spacing) as blockers; only stop for things the ticket itself flags as open.

4. **Implement using the issue body as the spec.** Go straight to `writing-plans` to produce an implementation plan, then `executing-plans` (or `subagent-driven-development`) to execute it. Do not run a separate `brainstorming` pass first — these tickets are already detailed specs (files to touch, exact numbers, acceptance criteria); re-brainstorming them is redundant. If `writing-plans` or `executing-plans` surface a genuine ambiguity per step 3 mid-implementation, stop and ask then too.

5. **Run whatever headless verification is possible.** Check for a Godot CLI binary first:

   ```bash
   command -v godot4 2>/dev/null || command -v godot 2>/dev/null
   ```

   If one exists, use it to catch script parse/compile errors (e.g. opening the project headlessly and checking stderr for GDScript errors). If no binary is found, skip this step entirely — don't fail the ticket over a missing binary, and don't guess at a binary name. Either way, **state plainly in your final report that visual and gameplay behavior has not been verified** — that requires the user opening the project in the Godot editor.

6. **Commit and push:**

   ```bash
   git add <files touched by this ticket>
   git commit -m "$(cat <<'EOF'
   <one-line summary of what this ticket built>

   Closes #N
   EOF
   )"
   git push
   ```

   `Closes #N` (matching the actual issue number from step 1) is required in the commit message body — GitHub auto-closes the issue when this lands on the default branch. Push straight to master; no branch, no PR.

7. **Report to the user:** what was built, what to check in the Godot editor to confirm it actually works, and which ticket is next (or that all tickets are done).

## If the user reopens an issue

If a ticket's issue gets reopened after the user finds a problem in-editor, treat it the same as step 1 finding it as the next open issue — implement the fix as a follow-up commit on the same ticket, closing it again the same way.
