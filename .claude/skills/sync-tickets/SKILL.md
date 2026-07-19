---
name: sync-tickets
description: Use when a markdown tickets/backlog file needs to become GitHub issues, or when re-running after that file changed to pick up new or edited tickets without duplicating existing issues.
---

# Sync Tickets

Turns a tickets markdown file into GitHub issues, one per ticket, safe to re-run.

## Input

A path to a tickets markdown file. If not given, default to `docs/tickets.md`. Only ask for a path if `docs/tickets.md` does not exist yet.

## Ticket file format

Each ticket is a level-2 heading `## Ticket N — <Title>`. Tickets are separated by a `---` horizontal rule. Each ticket's body may contain a `**Acceptance criteria:**` line followed by a bullet list (`- ...`) running until the next `---` or end of file.

## Procedure

1. **Ensure the `ticket` and `bug` labels exist:**

   ```bash
   gh label create ticket --color "0E8A16" --description "Tracked build ticket" 2>/dev/null || true
   gh label create bug --color "D93F0B" --description "Bug ticket" 2>/dev/null || true
   ```

   (The `|| true` handles the label already existing — `gh label create` exits non-zero in that case, which is expected on re-runs.)

2. **Parse the file.** Split on `\n## Ticket ` and `\n## Bug ` — conceptually, the regex `\n## (Ticket|Bug) ` — to get one chunk per ticket or bug. For each chunk, extract:
   - `Kind` — which keyword (`Ticket` or `Bug`) the heading used. Needed below to reconstruct the right issue title and labels.
   - `N` and `Title` from the heading line (`<Kind> N — Title`). Strip markdown formatting (backtick code spans, `*`/`_` emphasis) from `Title` before using it anywhere an issue title is needed — GitHub issue titles render as plain text, and the heading may contain inline code spans (e.g. `` `GameState` Autoload ``) that should read as plain words in the title. Leave the entry body's own markdown untouched.
   - The full body up to (not including) the next `---` line or end of file

3. **List existing issues once, then match locally.** Don't use `gh issue list --search`, which is served by GitHub's search index and can lag seconds-to-minutes behind issue creation — a re-run shortly after a previous sync (or a retry after a partial failure) can miss just-created issues and create duplicates. Instead:

   ```bash
   gh issue list --label ticket --state all --json number,title --limit 200
   ```

   Run this once before the per-ticket loop. For each entry, skip creating it if any result's title starts with `<Kind> N —` — using that entry's own parsed `Kind` (`Ticket` or `Bug`), not a hardcoded string, and exact `N`, not a prefix match against other numbers — count it as skipped.

4. **Convert the body's acceptance criteria to a task list.** Within the ticket body, find the line `**Acceptance criteria:**` and every following `- ` bullet up to the next blank-line-terminated section or `---`. Rewrite each of those bullets from `- <text>` to `- [ ] <text>`. Leave every other line of the body untouched — this only touches the acceptance-criteria bullets, not code blocks or other bullet lists (e.g. file-tree listings) elsewhere in the ticket.

5. **Create the issue:**

   ```bash
   gh issue create \
     --title "Kind N — Title" \
     --body-file <path to a temp file containing the converted body> \
     --label ticket
   ```

   Title is `"%s %d — %s" % [Kind, N, Title]` using each entry's own parsed `Kind` — unchanged for `Ticket` entries (e.g. still `Ticket 12 — ...`), and `Bug N — ...` for `Bug` entries (keep "Bug" in the title, don't normalize it to "Ticket"). Labels: `Ticket` entries get `--label ticket` (unchanged); `Bug` entries get **both** `--label ticket --label bug` — this keeps bug issues in the same unified queue `work-ticket` already reads via `--label ticket`, while still allowing `--label bug` filtering.

   Use a temp file for `--body-file` rather than `--body` — ticket bodies contain backticks, code fences, and quotes that are unsafe to inline into a shell argument.

6. **Backfill the bugs.md issue number.** Immediately after creating a `Bug N —` issue, check `docs/bugs.md` for a `## Bug N —` entry whose `**Ticket:**` line still reads `GitHub issue: pending sync`; if found, replace that phrase with `#<the new issue number>` in place. If no matching entry exists — shouldn't happen if `make-ticket` was used to author the bug, but don't hard-fail if it does — skip silently; creating `docs/bugs.md` entries isn't this skill's job.

7. **Report a summary** at the end: `"X created, Y skipped (already existed)."` List the skipped ticket/bug numbers and titles so it's clear a re-run didn't silently do nothing.

   Then cross-check bug resolutions: for every GitHub issue labeled `bug` that is **closed**, look up its corresponding `docs/bugs.md` entry by the parsed `N` and flag it explicitly — by bug number and issue number — if:
   - its `**Status:**` line still reads `Open`, or
   - its `**Root cause (confirmed):**` or `**Fix summary:**` line is still the literal placeholder text (or blank).

   This is the "did the resolution actually get logged" check — `work-ticket` updates `bugs.md` on close, but nothing else double-checks it landed.

## Notes

- Re-running after editing the tickets file is safe: unchanged tickets or bugs are skipped by title match, new ones get created. This does NOT detect edits to an already-synced entry's body — if a ticket or bug's content changed after its issue was created, the issue won't be updated automatically. Flag this to the user if you notice a mismatch between the file and an existing issue's body.
- This skill only creates issues. It never closes, edits, or comments on existing ones — that's `work-ticket`'s job.
- `work-ticket` picks the next ticket or bug by lowest open issue *number*, which only matches the tickets file's intended build order if entries are appended to the file, never inserted in the middle. Inserting an entry between existing ones (e.g. a new "Ticket 4.5") and syncing it later gives it a higher issue number than entries that come after it in the file, so it would be worked out of order.
