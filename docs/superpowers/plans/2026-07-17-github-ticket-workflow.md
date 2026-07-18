# GitHub Ticket Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build two project-scoped Claude Code skills — `sync-tickets` and `work-ticket` — that turn `Blue_Orb_Tickets_House_Tab.md` into GitHub issues and then implement them one at a time, closing each issue on push.

**Architecture:** Two independent skill documents under `.claude/skills/`. `sync-tickets` is a one-way markdown-to-GitHub-issues importer with idempotent re-runs. `work-ticket` finds the next open `ticket`-labeled issue and drives it through the existing `writing-plans` → `executing-plans` skills, treating the issue body as the spec, then commits with a closing keyword and pushes directly to master.

**Tech Stack:** `gh` CLI (already authenticated as BrianGossett, scopes include `repo`), git, GDScript/Godot 4.7 (no local `godot` CLI binary currently installed — see Global Constraints).

## Global Constraints

- Repo is `BrianGossett/a-blue-orb` on GitHub, remote already configured. `gh auth status` confirms an authenticated session — do not re-auth.
- Skills are project-scoped: `.claude/skills/<skill-name>/SKILL.md`. Frontmatter has exactly two fields, `name` and `description`, combined under 1024 characters. `description` starts with "Use when…", third person, states triggering conditions only — never a workflow summary (this is a hard rule from `superpowers:writing-skills`: a description that summarizes the process causes agents to skip reading the actual skill body).
- Direct-to-master workflow: no feature branches, no PRs. Every ticket's implementation is one or more commits pushed straight to `master`.
- `docs/design_doc.md`, `docs/architecture.md`, `docs/mockups/2a_house_tab.png` already exist in the repo (bootstrapped prior to this plan) — both skills can assume they're present.
- No `godot`/`godot4` binary is on PATH on this machine (verified via `which` and a filesystem search). `work-ticket` must probe for one at runtime (`command -v godot4 || command -v godot`) and skip headless verification gracefully if absent — never hard-fail a ticket because the binary is missing, and never assume a specific binary name exists.
- The tickets source file for this batch is `/home/brian/Documents/Blue_Orb_Tickets_House_Tab.md` (outside the repo). `sync-tickets` takes a file path as input rather than hardcoding this — it's meant to be reusable for a future Ritual Site batch.
- Ticket file format `sync-tickets` must parse: each ticket is a `## Ticket N — <Title>` heading; tickets are separated by a `---` horizontal rule; each ticket body contains a `**Acceptance criteria:**` line followed by a bullet list (`- ...`) that runs to the next `---` or end of file.

---

### Task 1: Write the `sync-tickets` skill

**Files:**
- Create: `.claude/skills/sync-tickets/SKILL.md`

**Interfaces:**
- Produces: a repeatable procedure that, given a tickets markdown file path, ends with one open GitHub issue per ticket, each labeled `ticket`, titled `Ticket N — <Title>`.
- Consumes: nothing from other tasks (no code dependencies — this is a standalone instruction document).

- [ ] **Step 1: Write the skill file**

```markdown
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
```

- [ ] **Step 2: Sanity-check the frontmatter**

Run: `head -4 .claude/skills/sync-tickets/SKILL.md | wc -c`
Expected: under 1024 (combined `name`+`description` frontmatter well within the limit — this file's frontmatter block is ~230 characters).

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/sync-tickets/SKILL.md
git commit -m "Add sync-tickets skill

Turns a tickets markdown file into GitHub issues, one per ticket,
idempotent on re-run."
```

---

### Task 2: Run `sync-tickets` for real against the House Tab tickets file

This is both the test of Task 1's skill and real, needed work — it produces the 12 GitHub issues the rest of this project's tickets will be tracked against.

**Files:** none (this task only runs commands against GitHub, no repo files change).

**Interfaces:**
- Consumes: the `sync-tickets` skill from Task 1, and `/home/brian/Documents/Blue_Orb_Tickets_House_Tab.md`.
- Produces: 12 open GitHub issues labeled `ticket`, titled `Ticket 1 — Project Scaffolding` through `Ticket 12 — Polish / Cross-Check Pass`, which Task 4 (and every future `work-ticket` run) depends on existing.

- [ ] **Step 1: Follow the `sync-tickets` skill's procedure** using `/home/brian/Documents/Blue_Orb_Tickets_House_Tab.md` as the input file. This means actually executing the label-creation command, parsing the 12 tickets out of the file, and running a `gh issue create` per ticket per the skill's Step 5.

- [ ] **Step 2: Verify all 12 issues were created**

Run: `gh issue list --label ticket --state open --json number,title --jq '.[] | "\(.number): \(.title)"'`

Expected: 12 lines, numbered 1–12 (assuming no other issues exist in the repo yet), titles matching the 12 ticket names from the file (`Project Scaffolding`, `GameState Autoload`, `EventBus Autoload`, `LogManager Autoload`, `ButtonData Resource + EffectHandler`, `button_action.tscn Generic Button Component`, `Global Click-Rate Limiter`, `UI Shell (main.tscn, tabs, log panel)`, `House Button Content`, `Health Depletion / Blackout Recovery`, `Save System (autosave + manual export/import)`, `Polish / Cross-Check Pass`).

- [ ] **Step 3: Spot-check one issue body has converted checkboxes**

Run: `gh issue view 1 --json body --jq .body | grep -A5 "Acceptance criteria"`
Expected: the acceptance criteria bullets show as `- [ ]` not `- `.

- [ ] **Step 4: Verify idempotency by re-running the sync procedure**

Follow the skill's procedure again from Step 1 (label creation, parse, per-ticket existence check, create-if-missing) against the same file.

Run: `gh issue list --label ticket --state all --json number --jq 'length'`
Expected: still `12` — no duplicates created. The skill's summary report from this second run should read `0 created, 12 skipped`.

---

### Task 3: Write the `work-ticket` skill

**Files:**
- Create: `.claude/skills/work-ticket/SKILL.md`

**Interfaces:**
- Consumes: open issues labeled `ticket` (produced by `sync-tickets`), `docs/design_doc.md`, `docs/architecture.md`.
- Produces: a repeatable procedure that implements the next open ticket, commits with a closing keyword, and pushes to master.

- [ ] **Step 1: Write the skill file**

```markdown
---
name: work-ticket
description: Use when the next open GitHub issue labeled 'ticket' needs to be implemented, committed, and closed. Picks the next ticket in build order and pushes a commit that closes its issue.
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
```

- [ ] **Step 2: Sanity-check the frontmatter**

Run: `head -4 .claude/skills/work-ticket/SKILL.md | wc -c`
Expected: under 1024.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/work-ticket/SKILL.md
git commit -m "Add work-ticket skill

Implements the next open ticket-labeled issue, commits with a
closing keyword, and pushes to master."
```

---

### Task 4: Run `work-ticket` for real — implement Ticket 1 (Project Scaffolding)

This is both the test of Task 3's skill and the actual start of the game build.

**Files:**
- Create: `autoloads/.gitkeep`
- Create: `data/buttons/house/.gitkeep`
- Create: `data/areas/ritual_site.tres`
- Create: `data/balancing/.gitkeep`
- Create: `scenes/ui/.gitkeep`
- Create: `scenes/areas/house/.gitkeep`
- Create: `scenes/areas/ritual_site/ritual_site.tscn`
- Create: `assets/fonts/.gitkeep`
- Create: `assets/art/rooms/.gitkeep`
- Create: `assets/icons/.gitkeep`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: the `work-ticket` skill from Task 3, issue #1 (`Ticket 1 — Project Scaffolding`, created in Task 2).
- Produces: the folder structure every later ticket (2–12) writes files into.

- [ ] **Step 1: Follow the `work-ticket` skill's procedure.** Step 1 of that procedure will resolve to issue #1 (`Ticket 1 — Project Scaffolding`) since it's the lowest-numbered open `ticket` issue. Its acceptance criteria (verify via `gh issue view 1 --json body --jq .body`):
  - Project opens cleanly in Godot 4.x with no default nodes left in place.
  - Folder structure matches `docs/architecture.md` §2 exactly.
  - `.gitignore` set up for Godot (ignore `.godot/`, `*.tmp`, export artifacts).
  - Empty `ritual_site.tres` and `ritual_site.tscn` exist as placeholders.

- [ ] **Step 2: Create the folder structure.** Git doesn't track empty directories, so folders with no ticket-1 content get a `.gitkeep`:

```bash
mkdir -p autoloads data/buttons/house data/areas data/balancing \
  scenes/ui scenes/areas/house scenes/areas/ritual_site \
  assets/fonts assets/art/rooms assets/icons

touch autoloads/.gitkeep data/buttons/house/.gitkeep data/balancing/.gitkeep \
  scenes/ui/.gitkeep scenes/areas/house/.gitkeep \
  assets/fonts/.gitkeep assets/art/rooms/.gitkeep assets/icons/.gitkeep
```

(`data/areas/` and `scenes/areas/ritual_site/` are not empty — they get the placeholder files below, so no `.gitkeep` needed there.)

- [ ] **Step 3: Create the `ritual_site.tres` placeholder**

Write `data/areas/ritual_site.tres`:

```
[gd_resource type="Resource" format=3]

[resource]
```

This is a minimal valid Godot 4 Resource file. No custom `Area` resource class exists yet (that shape gets decided when Ticket 8/9 build `area_tab.tscn`'s data binding) — this stub only needs to exist and be loadable, per the ticket's acceptance criteria.

- [ ] **Step 4: Create the `ritual_site.tscn` placeholder**

Write `scenes/areas/ritual_site/ritual_site.tscn`:

```
[gd_scene format=3]

[node name="RitualSite" type="Node"]
```

- [ ] **Step 5: Update `.gitignore`**

Current content:
```
# Godot 4+ specific ignores
.godot/
/android/
```

Add `*.tmp` and an export-artifacts entry:

```
# Godot 4+ specific ignores
.godot/
/android/

# Export artifacts
*.tmp
/export/
```

- [ ] **Step 6: Verify the structure matches `docs/architecture.md` §2**

Run: `find autoloads data scenes assets -type f -o -type d | sort`
Expected: every directory listed in architecture.md §2 is present (`autoloads/`, `data/buttons/house/`, `data/areas/`, `data/balancing/`, `scenes/ui/`, `scenes/areas/house/`, `scenes/areas/ritual_site/`, `assets/fonts/`, `assets/art/rooms/`, `assets/icons/`), plus the two ritual-site placeholder files.

- [ ] **Step 7: Check for a Godot CLI binary (work-ticket skill step 5)**

Run: `command -v godot4 2>/dev/null || command -v godot 2>/dev/null; echo "exit: $?"`
Expected on this machine: no output before `exit: 1` (no binary installed) — confirm the skill's procedure treats this as "skip headless verification," not a failure.

- [ ] **Step 8: Commit and push (work-ticket skill step 6)**

```bash
git add autoloads data scenes assets .gitignore
git commit -m "$(cat <<'EOF'
Scaffold project folder structure per architecture doc §2

Closes #1
EOF
)"
git push
```

- [ ] **Step 9: Verify the issue closed**

Run: `gh issue view 1 --json state --jq .state`
Expected: `CLOSED`

- [ ] **Step 10: Report to the user (work-ticket skill step 7)**

State: the folder structure is in place, there's nothing visual to check in the Godot editor for this particular ticket (it's pure scaffolding — worth opening the project once to confirm it still loads cleanly with no default nodes), and Ticket 2 (`GameState` Autoload) is next.

---

## Self-Review Notes

- **Spec coverage:** every element of the design doc's two skill sections (parsing, idempotency, labeling, task-list conversion, next-issue selection, doc cross-check, ambiguity stop, headless-verification-with-fallback, commit/push/close, one-ticket-per-run) has a corresponding step above. The prerequisite docs bootstrap was completed before this plan (not a task here) since it's a one-time step, not part of either skill.
- **No placeholders:** Task 4 embeds Ticket 1's actual acceptance criteria and real file contents (the `.tres`/`.tscn` stubs, the `.gitignore` diff) rather than deferring to "follow the ticket" alone — this doubles as the first real proof the `work-ticket` skill's instructions are followable.
- **Type/name consistency:** `ticket` label name, `Ticket N — Title` title format, and `Closes #N` commit convention are used identically across Task 1, Task 2, Task 3, and Task 4.

## Execution Handoff

Two execution options:

1. **Subagent-Driven (recommended)** - dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** - execute tasks in this session using `executing-plans`, batch execution with checkpoints.
