---
name: sync-tickets
description: Use when a markdown tickets/backlog file needs to become GitHub issues, or when re-running after that file changed to pick up new or edited tickets without duplicating existing issues.
---

# Sync Tickets

Turns a tickets markdown file into GitHub issues, one per ticket, safe to re-run.

## Input

A path to a tickets markdown file. If not given, ask for one.

## Ticket file format

Each ticket is a level-2 heading `## Ticket N — <Title>`. Tickets are separated by a `---` horizontal rule. Each ticket's body may contain a `**Acceptance criteria:**` line followed by a bullet list (`- ...`) running until the next `---` or end of file.

## Procedure

1. **Ensure the `ticket` label exists:**

   ```bash
   gh label create ticket --color "0E8A16" --description "Tracked build ticket" 2>/dev/null || true
   ```

   (The `|| true` handles the label already existing — `gh label create` exits non-zero in that case, which is expected on re-runs.)

2. **Parse the file.** Split on `\n## Ticket ` to get one chunk per ticket. For each chunk, extract:
   - `N` and `Title` from the heading line (`Ticket N — Title`)
   - The full ticket body up to (not including) the next `---` line or end of file

3. **For each ticket, check for an existing issue before creating one:**

   ```bash
   gh issue list --label ticket --state all --search "in:title \"Ticket N —\"" --json number,title
   ```

   If any result's title starts with `Ticket N —`, skip this ticket (already synced) and count it as skipped.

4. **Convert the body's acceptance criteria to a task list.** Within the ticket body, find the line `**Acceptance criteria:**` and every following `- ` bullet up to the next blank-line-terminated section or `---`. Rewrite each of those bullets from `- <text>` to `- [ ] <text>`. Leave every other line of the body untouched — this only touches the acceptance-criteria bullets, not code blocks or other bullet lists (e.g. file-tree listings) elsewhere in the ticket.

5. **Create the issue:**

   ```bash
   gh issue create \
     --title "Ticket N — Title" \
     --body-file <path to a temp file containing the converted body> \
     --label ticket
   ```

   Use a temp file for `--body-file` rather than `--body` — ticket bodies contain backticks, code fences, and quotes that are unsafe to inline into a shell argument.

6. **Report a summary** at the end: `"X created, Y skipped (already existed)."` List the skipped ticket numbers/titles so it's clear a re-run didn't silently do nothing.

## Notes

- Re-running after editing the tickets file is safe: unchanged tickets are skipped by title match, new tickets get created. This does NOT detect edits to an already-synced ticket's body — if a ticket's content changed after its issue was created, the issue won't be updated automatically. Flag this to the user if you notice a mismatch between the file and an existing issue's body.
- This skill only creates issues. It never closes, edits, or comments on existing ones — that's `work-ticket`'s job.
