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

No bugs have been logged yet.

---

## Bug 14 — [DEMO — placeholder, will be removed after the walkthrough] Log panel scrollbar doesn't stick to bottom
**Found:** 2026-07-19
**Status:** Open
**Description:** DEMO CONTENT for Task 12's dry-run walkthrough only.
**Root cause (hypothesis):** `scenes/ui/log_panel.gd` likely doesn't call `scroll_to_line()` (or equivalent) on `line_added`.
**Root cause (confirmed):**
**Fix summary:**
**Ticket:** Bug 14 in docs/tickets.md · GitHub issue: #16
