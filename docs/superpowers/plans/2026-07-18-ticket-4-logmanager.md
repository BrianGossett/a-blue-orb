# Ticket 4: LogManager Autoload Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `LogManager` autoload — the central place any system pushes a flavor/mechanical log line to, decoupled from the log UI (which doesn't exist until Ticket 8).

**Architecture:** One small autoload script, `autoloads/log_manager.gd`, exposing `push(text)` and a `line_added` signal. No dependency on `GameState` or `EventBus` — this is a standalone queue.

**Tech Stack:** GDScript, Godot 4.7, `Time` singleton for the system clock.

## Global Constraints

- Godot 4.7 project. GDScript files use tab indentation (matches `autoloads/event_bus.gd` and `autoloads/game_state.gd`, already in the repo).
- No `godot`/`godot4` CLI binary exists on this machine — no automated execution is possible. Verification is a manual code trace against each acceptance criterion, documented in the commit/report, not an executed test.
- Autoloads are registered in `project.godot`'s `[autoload]` section as `Name="*res://path/to/script.gd"`. The existing section (added for Tickets 2/3) is:
  ```
  [autoload]

  EventBus="*res://autoloads/event_bus.gd"
  GameState="*res://autoloads/game_state.gd"
  ```
  `LogManager` gets appended as a third line — it has no load-order dependency on the other two (it doesn't reference them, and they don't reference it).
- Ticket 4's exact interface requirement: `push(text: String) -> void` and `signal line_added(timestamped_text: String)`. Log format must match the mockup exactly: `[HH:MM:SS] <lowercase text>` — e.g. `[12:00:12] you gingerly touch the orb.`. `Time.get_time_string_from_system()` returns Godot's system clock already formatted as `HH:MM:SS` (24-hour, zero-padded) — no manual formatting needed for the timestamp portion.
- **Judgment call (not a flagged ambiguity, so not stopping to ask):** the ticket's own acceptance-criteria example passes `push("You gingerly touch the orb.")` (capital "You") but shows the expected logged line as `[12:00:12] you gingerly touch the orb.` (lowercase "you"). The only way both halves of that example are consistent is if `push()` lowercases the message text itself. This also matches Ticket 12's later cross-check ("lowercase after the timestamp, matching the mock's tone"). Implementation: `push()` calls `.to_lower()` on the incoming text before formatting/storing/emitting it.
- Rolling buffer: keep the last ~200 lines (per the ticket, sessions run 3-6 hours and the buffer must not grow unbounded). Evict the oldest line once the buffer exceeds 200.
- Do not add a public getter for the buffered lines (e.g. `get_lines()`) — not requested by this ticket's interface, and not needed yet. Ticket 8 (log panel UI) can add its own way to read backlog when it's actually built, following whatever pattern fits the UI at that point. Adding it now would be speculative.
- This ticket is self-contained: no other ticket's issue needs to be open/closed alongside it (unlike Tickets 2+3).

---

### Task 1: Create and register the `LogManager` autoload

**Files:**
- Create: `autoloads/log_manager.gd`
- Modify: `project.godot`

**Interfaces:**
- Produces: `LogManager.push(text: String) -> void` and `LogManager.line_added(timestamped_text: String)` signal — Ticket 8's log panel will connect to `line_added` to append lines to its display, and every effect-handling ticket (5, 9, 10) will call `LogManager.push(...)` for flavor text.

- [ ] **Step 1: Write `autoloads/log_manager.gd`**

```gdscript
extends Node

signal line_added(timestamped_text: String)

const MAX_LINES: int = 200

var _lines: Array[String] = []


func push(text: String) -> void:
	var line := "[%s] %s" % [Time.get_time_string_from_system(), text.to_lower()]
	_lines.append(line)
	if _lines.size() > MAX_LINES:
		_lines.pop_front()
	line_added.emit(line)
```

- [ ] **Step 2: Manually trace each acceptance criterion against the code**

Since no Godot binary exists to execute this, verify by reading the code:

1. *"Calling `LogManager.push(\"You gingerly touch the orb.\")` results in a line appearing with a timestamp, matching the mockup's log format exactly: `[12:00:12] you gingerly touch the orb.`"* — trace: `text.to_lower()` turns `"You gingerly touch the orb."` into `"you gingerly touch the orb."`; `Time.get_time_string_from_system()` returns e.g. `"12:00:12"`; the format string produces `"[12:00:12] you gingerly touch the orb."` — matches exactly. ✓
2. *"Does not depend on any UI node existing — should work (and not error) even before the log panel scene is built"* — trace: `push()` only touches `_lines` (a local array field) and emits `line_added`. Emitting a signal with zero connected listeners is a normal no-op in Godot — it does not error. Nothing in this file references any UI node, `get_node()`, or the scene tree. ✓
3. *Rolling buffer stays bounded* — trace: after `_lines.append(line)`, `if _lines.size() > MAX_LINES: _lines.pop_front()` removes the oldest entry whenever the buffer exceeds 200, so it never grows past 200 regardless of session length. ✓

Record this trace in the commit message or report.

- [ ] **Step 3: Add `LogManager` to the `[autoload]` section in `project.godot`**

Current section (added for Tickets 2/3):
```
[autoload]

EventBus="*res://autoloads/event_bus.gd"
GameState="*res://autoloads/game_state.gd"
```

Append a third line:
```
[autoload]

EventBus="*res://autoloads/event_bus.gd"
GameState="*res://autoloads/game_state.gd"
LogManager="*res://autoloads/log_manager.gd"
```

- [ ] **Step 4: Verify the section**

Run: `tail -6 project.godot`
Expected:
```

[autoload]

EventBus="*res://autoloads/event_bus.gd"
GameState="*res://autoloads/game_state.gd"
LogManager="*res://autoloads/log_manager.gd"
```

- [ ] **Step 5: Commit and push, closing the issue**

```bash
git add autoloads/log_manager.gd project.godot
git commit -m "$(cat <<'EOF'
Add LogManager autoload

Closes #4
EOF
)"
git push
```

- [ ] **Step 6: Verify the issue closed**

Run: `gh issue view 4 --json state --jq .state`
Expected: `CLOSED`

- [ ] **Step 7: Report to the user**

State: `LogManager` is built and registered; nothing in this diff was executed (no Godot binary). What to check in the editor: open the project, confirm no autoload errors in the Output panel, and optionally test manually by calling `LogManager.push("test")` from the Remote/Debugger console or a temporary `_ready()` print in any script to eyeball the format. Ticket 5 (`ButtonData` Resource + `EffectHandler`) is next.

---

## Self-Review Notes

- **Spec coverage:** `push()` and `line_added` match Ticket 4's interface exactly; the rolling-buffer requirement, the mockup log format, and the "works before any UI exists" criterion are each traced individually in Step 2.
- **No placeholders:** the script is complete; nothing deferred.
- **Type/name consistency:** `LogManager` as the autoload name matches the class's usage pattern from the ticket text (`LogManager.push(...)`) and the existing `EventBus`/`GameState` registration style in `project.godot`.

## Execution Handoff

Two execution options:

1. **Subagent-Driven (recommended)** - dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** - execute tasks in this session using `executing-plans`, batch execution with checkpoints.
