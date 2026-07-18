# Ticket 8: UI Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the scene structure from the mockup — tabs, a data-driven area tab, a persistent log panel, and a stat readout — with House as the only functional tab.

**Architecture:** `main.tscn` holds a `TabContainer` (House tab + a disabled Ritual Site placeholder) and a sibling `log_panel.tscn` so the log survives tab switches. `area_tab.tscn` is generic — it binds to an `AreaData` resource (a new resource class this ticket introduces, resolving a gap flagged back in Ticket 1's plan) rather than hardcoding "House," and dynamically loads whatever `ButtonData` `.tres` files exist under `data/buttons/<area_data.id>/` — currently none, since Ticket 9 hasn't populated House content yet, which is expected and fine for this ticket.

**Tech Stack:** GDScript, Godot 4.7, hand-written `.tscn`/`.tres` scene/resource files (no Godot editor available to generate them).

## Global Constraints

- No `godot`/`godot4` CLI binary — verification is manual trace of code and hand-checked `.tscn`/`.tres` syntax against Godot 4's documented scene-file format, not an executed test. Visual layout, actual tab-switching, and actual button rendering can only be confirmed by the user opening the project in the editor — flag this plainly in the final report, more so than prior tickets, since this is the first ticket with real scene files and layout.
- **New resource class, `AreaData`** (`data/area_data.gd`, sibling to `data/button_data.gd`): `id: String`, `name_progression: Array[String]`, `base_description: String`. This resolves the gap flagged in Ticket 1's plan ("no Area resource class exists yet — that shape gets decided when Ticket 8/9 build area_tab.tscn's data binding"). Named `AreaData` (not bare `Area`) to match `ButtonData`'s naming convention and avoid confusion with Godot's built-in `Area2D`/`Area3D` node types.
- `data/areas/house.tres` (a real `AreaData` instance, not a stub) gets created in this ticket: `id="house"`, `name_progression=["A Small Shelter", "A Lonely Hut", "A Sturdy Cottage", "A Comfortable House", "A Fine Residence"]` (design doc §6's first five house names — the batch's explicit stop point), `base_description="You are in a small room."` (matching the mockup's example text).
- **Documented deviation from architecture doc §5's literal diagram:** the doc's diagram labels the 2-column button area a single `GridContainer (2 columns)`. A literal Godot `GridContainer` fills cells row-major left-to-right — correct for a grid of same-length rows, wrong for two independently-lengthed vertical lists (actions: 7 items eventually, upgrades: 5 items eventually, per Ticket 9). This plan uses `HBoxContainer > two VBoxContainer children` instead, which is what actually produces "two independent columns stacking down." Functionally equivalent to what the mockup shows; only the literal Godot node class differs from the doc's diagram. Flag for Ticket 12's doc cross-check, not a blocker now.
- **`LogManager` gets one small addition in this ticket:** a public `get_lines() -> Array[String]` getter (returns a duplicate, matching the alias-safety pattern already used in `GameState.to_dict()`). Ticket 4's plan explicitly deferred this exact decision to "whichever ticket builds the log panel UI" — that's this ticket. Without it, `log_panel.tscn` could only show lines pushed *after* it starts listening, losing any backlog from systems that logged before the UI existed (which Ticket 4's own acceptance criteria explicitly anticipated as a real scenario).
- **Button loading is dynamic, not hardcoded:** `area_tab.gd` scans `res://data/buttons/<area_data.id>/` at runtime via `DirAccess`, loading every `.tres` file found and routing it into the actions or upgrades column based on `ButtonData.button_column` (1 or 2). Since `data/buttons/house/` currently only contains `.gitkeep` (Ticket 9 hasn't run), this loop finds zero real buttons right now — expected, not a bug. The loop explicitly skips any filename not ending in `.tres`.
- **Tab title is dynamic, not hardcoded "House":** `area_tab.gd` sets its own tab's title (via `TabContainer.set_tab_title()`, since `AreaTab` is a direct child of the `TabContainer`) from `area_data.name_progression[GameState.house_tier]` (clamped to array bounds), on `_ready()` and again whenever `EventBus.house_tier_changed` fires. Nothing in `Tickets 1-8` actually emits `house_tier_changed` yet (that's Ticket 9's job when it wires house-tier progression) — connecting now is harmless and means the title will already update correctly once Ticket 9 starts firing it, no rework needed later.
- **Ritual Site tab:** a plain `Control` node named `"Ritual Site"` (the literal node name becomes its `TabContainer` tab label — no script needed for the label itself), disabled via `set_tab_disabled(1, true)` in a small script (`scenes/main.gd`) attached to the `TabContainer` node. No content behind it, per the ticket's explicit "don't build out any Ritual Site content" note.
- **Room art placeholder:** a `TextureRect` with an embedded `GradientTexture2D` sub-resource (`fill = 1`, i.e. `FILL_RADIAL`), matching the mockup's "circle vignette" note and the ticket's explicit guidance that a flat/gradient placeholder is correct — not blocked on real art.
- **`project.godot` gets `run/main_scene="res://scenes/main.tscn"` added** under `[application]`. Not explicitly required by Ticket 8's acceptance criteria, but it's the natural, low-risk connection that lets the user actually press Play in the editor and see this ticket's work — worth doing now rather than leaving the project with no runnable entry point.
- **Stat bar placement:** top of the House tab, above the button grid (per the ticket's own note: "use your judgment... flag it for a design pass later"). Explicitly flagged as such in the final report, not treated as a settled design decision.
- Godot 4 `.tscn`/`.tres` syntax conventions used throughout, consistent with prior tickets' files: `[gd_scene load_steps=N format=3]` header where `N` = (ext_resources + sub_resources + 1); `[ext_resource type="..." path="res://..." id="N"]`; `[sub_resource type="..." id="Name_N"]` declared before any `[node]` that references it; instanced child scenes via `[node name="..." parent="..." instance=ExtResource("N")]` with property overrides as plain `key = value` lines beneath; full-rect `Control` nodes get `anchor_right = 1.0` and `anchor_bottom = 1.0` (the actual runtime-effective anchor properties — `anchors_preset` alone is an editor-only hint and is omitted here since it has no runtime effect by itself).
- Direct-to-master. Final commit closes issue #8 (`Closes #8`).

---

### Task 1: Create the `AreaData` resource class and `house.tres`

**Files:**
- Create: `data/area_data.gd`
- Create: `data/areas/house.tres`

**Interfaces:**
- Produces: `AreaData` resource shape (`id`, `name_progression`, `base_description`) and a real `house` instance — Task 5 (`area_tab.tscn`) binds to this; Task 6 (`main.tscn`) references it as an `ext_resource`.

- [ ] **Step 1: Write `data/area_data.gd`**

```gdscript
class_name AreaData
extends Resource

@export var id: String
@export var name_progression: Array[String]
@export var base_description: String
```

- [ ] **Step 2: Write `data/areas/house.tres`**

```
[gd_resource type="AreaData" load_steps=2 format=3]

[ext_resource type="Script" path="res://data/area_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = "house"
name_progression = Array[String](["A Small Shelter", "A Lonely Hut", "A Sturdy Cottage", "A Comfortable House", "A Fine Residence"])
base_description = "You are in a small room."
```

- [ ] **Step 3: Verify by hand-checking the file structure**

Run: `cat data/areas/house.tres`
Expected: exactly the content above. Confirm the `[gd_resource type="AreaData" ...]` header names the class registered by `data/area_data.gd`'s `class_name AreaData` line — a mismatch here would fail to load in the editor. Confirm `load_steps=2` matches the actual resource count (1 `ext_resource` + 1 for the resource itself).

- [ ] **Step 4: Commit**

```bash
git add data/area_data.gd data/areas/house.tres
git commit -m "Add AreaData resource class and house.tres (Ticket 8)

Resolves the Area-resource gap flagged in Ticket 1's plan. house.tres
uses the first five house names from design doc §6 — the batch's
explicit stop point."
```

---

### Task 2: Add `get_lines()` to `LogManager`

**Files:**
- Modify: `autoloads/log_manager.gd`

**Interfaces:**
- Produces: `LogManager.get_lines() -> Array[String]` — Task 3's `log_panel.gd` calls this once on `_ready()` to backfill any lines logged before the panel existed.

- [ ] **Step 1: Add the method**

Add after `push()` in `autoloads/log_manager.gd`:

```gdscript
func get_lines() -> Array[String]:
	return _lines.duplicate()
```

- [ ] **Step 2: Manually trace**

*Backfill correctness* — trace: any system that called `LogManager.push(...)` before `log_panel.tscn` exists (per Ticket 4's own acceptance criterion — "should work even before the log panel scene is built") has its lines sitting in `_lines`. `get_lines()` returns a duplicate of the current buffer at call time, so a caller reading it once at startup gets every line pushed so far, in order, without risking later mutation of `LogManager`'s internal array through the returned reference (matches the `.duplicate()` alias-safety pattern already used in `GameState.to_dict()`). ✓

- [ ] **Step 3: Commit**

```bash
git add autoloads/log_manager.gd
git commit -m "Add LogManager.get_lines() for UI backfill (Ticket 8)

Ticket 4's plan deferred this exact decision to whichever ticket
builds the log panel UI. Without it, log_panel.tscn could only show
lines pushed after it starts listening, losing any backlog from
systems that logged before the UI existed."
```

---

### Task 3: Create `log_panel.tscn` + `log_panel.gd`

**Files:**
- Create: `scenes/ui/log_panel.gd`
- Create: `scenes/ui/log_panel.tscn`

**Interfaces:**
- Consumes: `LogManager.get_lines()` (Task 2), `LogManager.line_added` signal (Ticket 4).
- Produces: a self-contained, drop-in log display — Task 6's `main.tscn` instances this as a `TabContainer` sibling.

- [ ] **Step 1: Write `scenes/ui/log_panel.gd`**

```gdscript
extends Control

@onready var _lines_label: RichTextLabel = $Lines


func _ready() -> void:
	for line in LogManager.get_lines():
		_append_line(line)
	LogManager.line_added.connect(_append_line)


func _append_line(timestamped_text: String) -> void:
	_lines_label.text += timestamped_text + "\n"
```

- [ ] **Step 2: Write `scenes/ui/log_panel.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scenes/ui/log_panel.gd" id="1"]

[node name="LogPanel" type="Control"]
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")

[node name="Lines" type="RichTextLabel" parent="."]
anchor_right = 1.0
anchor_bottom = 1.0
scroll_following = true
```

- [ ] **Step 3: Manually trace against Ticket 8's log-related acceptance criterion**

*"Switching to the (disabled) Ritual Site tab and back doesn't clear or duplicate the log"* — this scene has no code path that clears `_lines_label.text` except appending (`+=`, never `=` alone or `clear()`), and (per Task 6's structure) `LogPanel` is a sibling of `TabContainer`, never a child of any tab — so tab switching never removes, hides-and-reinstantiates, or otherwise touches this node's tree position or lifecycle. No duplicate-append path exists either: `_ready()` runs exactly once per instance, and `main.tscn` instances exactly one `LogPanel`. ✓

- [ ] **Step 4: Commit**

```bash
git add scenes/ui/log_panel.gd scenes/ui/log_panel.tscn
git commit -m "Add log_panel.tscn (Ticket 8)

Backfills existing LogManager lines on startup, then listens for new
ones. Never clears — safe to leave outside the TabContainer so it
persists across tab switches."
```

---

### Task 4: Create `stat_bar.tscn` + `stat_bar.gd`

**Files:**
- Create: `scenes/ui/stat_bar.gd`
- Create: `scenes/ui/stat_bar.tscn`

**Interfaces:**
- Consumes: `EventBus.mana_changed`, `EventBus.health_changed`, `GameState.mana`/`health`/`max_health` (for initial values).
- Produces: a self-contained readout — Task 5's `area_tab.tscn` instances this at the top of the House tab.

- [ ] **Step 1: Write `scenes/ui/stat_bar.gd`**

```gdscript
extends HBoxContainer

@onready var _mana_label: Label = $ManaLabel
@onready var _health_label: Label = $HealthLabel


func _ready() -> void:
	EventBus.mana_changed.connect(_on_mana_changed)
	EventBus.health_changed.connect(_on_health_changed)
	_on_mana_changed(GameState.mana)
	_on_health_changed(GameState.health, GameState.max_health)


func _on_mana_changed(new_value: float) -> void:
	_mana_label.text = "Mana: %s" % _format_number(new_value)


func _on_health_changed(new_value: float, max_value: float) -> void:
	_health_label.text = "Health: %s / %s" % [_format_number(new_value), _format_number(max_value)]


func _format_number(value: float) -> String:
	if value == floor(value):
		return str(int(value))
	return str(value)
```

- [ ] **Step 2: Write `scenes/ui/stat_bar.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scenes/ui/stat_bar.gd" id="1"]

[node name="StatBar" type="HBoxContainer"]
script = ExtResource("1")

[node name="ManaLabel" type="Label" parent="."]
text = "Mana: 0"

[node name="HealthLabel" type="Label" parent="."]
text = "Health: 50 / 50"
```

- [ ] **Step 3: Manually trace**

*Initial display matches a fresh save* — trace: on `_ready()`, `_on_mana_changed(GameState.mana)` is called directly (not just relying on a future signal) with the fresh-save value `0.0` → `_format_number(0.0)` → `0.0 == floor(0.0)` true → `"0"` → label reads `"Mana: 0"`. Same for health: `_on_health_changed(50.0, 50.0)` → `"Health: 50 / 50"`. Matches the `.tscn`'s own static placeholder text, and matches `GameState`'s documented fresh-save defaults. ✓

- [ ] **Step 4: Commit**

```bash
git add scenes/ui/stat_bar.gd scenes/ui/stat_bar.tscn
git commit -m "Add stat_bar.tscn (Ticket 8)

Placement (top of House tab, above the button grid) is a judgment
call per the ticket's own note that the mockup doesn't show exact
placement — flagged for a design pass later, not a settled decision."
```

---

### Task 5: Create `area_tab.tscn` + `area_tab.gd`

**Files:**
- Create: `scenes/ui/area_tab.gd`
- Create: `scenes/ui/area_tab.tscn`

**Interfaces:**
- Consumes: `AreaData` (Task 1), `stat_bar.tscn` (Task 4), `ButtonData`/`button_action.tscn` (Ticket 5/6), `EventBus.house_tier_changed` (Ticket 3), `GameState.house_tier` (Ticket 2).
- Produces: `set_area_data(data: AreaData)` and the `area_data` exported property — Task 6's `main.tscn` binds `house.tres` to this via a scene-file property override, no glue script needed in `main.tscn` itself for this part.

- [ ] **Step 1: Write `scenes/ui/area_tab.gd`**

```gdscript
extends Control

@export var area_data: AreaData

const BUTTON_ACTION_SCENE := preload("res://scenes/ui/button_action.tscn")

@onready var _column_actions: VBoxContainer = $Root/Content/ButtonGrid/ColumnActions
@onready var _column_upgrades: VBoxContainer = $Root/Content/ButtonGrid/ColumnUpgrades
@onready var _description_label: RichTextLabel = $Root/Content/RoomInfo/Description


func _ready() -> void:
	EventBus.house_tier_changed.connect(_on_house_tier_changed)
	if area_data:
		_apply_area_data()


func set_area_data(new_data: AreaData) -> void:
	area_data = new_data
	if is_inside_tree():
		_apply_area_data()


func _apply_area_data() -> void:
	_description_label.text = area_data.base_description
	_update_tab_title()
	_load_buttons()


func _update_tab_title() -> void:
	var tab_container := get_parent() as TabContainer
	if tab_container == null:
		return
	var tier := clampi(GameState.house_tier, 0, area_data.name_progression.size() - 1)
	tab_container.set_tab_title(get_index(), area_data.name_progression[tier])


func _on_house_tier_changed(_new_tier: int) -> void:
	_update_tab_title()


func _load_buttons() -> void:
	var dir_path := "res://data/buttons/%s/" % area_data.id
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for file_name in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var button_data: ButtonData = load(dir_path + file_name)
		var instance: Button = BUTTON_ACTION_SCENE.instantiate()
		instance.set_data(button_data)
		if button_data.button_column == 1:
			_column_actions.add_child(instance)
		else:
			_column_upgrades.add_child(instance)
```

- [ ] **Step 2: Write `scenes/ui/area_tab.tscn`**

```
[gd_scene load_steps=5 format=3]

[ext_resource type="Script" path="res://scenes/ui/area_tab.gd" id="1"]
[ext_resource type="PackedScene" path="res://scenes/ui/stat_bar.tscn" id="2"]

[sub_resource type="Gradient" id="Gradient_1"]
colors = PackedColorArray(0.85, 0.88, 0.95, 1, 0.6, 0.68, 0.88, 1)

[sub_resource type="GradientTexture2D" id="GradientTexture2D_1"]
gradient = SubResource("Gradient_1")
fill = 1
fill_from = Vector2(0.5, 0.5)
fill_to = Vector2(1, 0.5)

[node name="AreaTab" type="Control"]
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")

[node name="Root" type="VBoxContainer" parent="."]
anchor_right = 1.0
anchor_bottom = 1.0

[node name="StatBar" parent="Root" instance=ExtResource("2")]

[node name="Content" type="HBoxContainer" parent="Root"]

[node name="ButtonGrid" type="HBoxContainer" parent="Root/Content"]

[node name="ColumnActions" type="VBoxContainer" parent="Root/Content/ButtonGrid"]

[node name="ColumnUpgrades" type="VBoxContainer" parent="Root/Content/ButtonGrid"]

[node name="RoomInfo" type="VBoxContainer" parent="Root/Content"]

[node name="RoomArt" type="TextureRect" parent="Root/Content/RoomInfo"]
custom_minimum_size = Vector2(150, 150)
texture = SubResource("GradientTexture2D_1")

[node name="Description" type="RichTextLabel" parent="Root/Content/RoomInfo"]
custom_minimum_size = Vector2(200, 100)
```

- [ ] **Step 3: Manually trace each relevant acceptance criterion**

1. *"Visually matches the mockup layout: 2-column button grid on the left, room art + description on the right"* — structural trace, not pixel-verified (no editor): `Root/Content` is an `HBoxContainer` with two children — `ButtonGrid` (an `HBoxContainer` of `ColumnActions`/`ColumnUpgrades`, the "2-column button grid") and `RoomInfo` (a `VBoxContainer` of `RoomArt`/`Description`) — side by side, left-to-right, matching the mockup's left/right split. `StatBar` sits above `Content` inside `Root`, per the placement judgment call. Full visual confirmation needs the editor.
2. *"`area_tab.tscn` reads from a bound `area.tres` resource rather than hardcoding 'House' anywhere in this scene's script"* — grepped: the literal string `"House"` does not appear anywhere in `area_tab.gd`. Title comes from `area_data.name_progression[tier]`, description from `area_data.base_description`, buttons from `area_data.id`-derived folder path. Confirmed data-driven, no hardcoding. ✓
3. *Button loading with zero real buttons present (current state — Ticket 9 hasn't run)* — trace: `DirAccess.open("res://data/buttons/house/")` succeeds (directory exists, has `.gitkeep`); `dir.get_files()` returns `[".gitkeep"]`; the loop's `not file_name.ends_with(".tres")` guard skips it; loop body never executes; both column containers stay empty. No error, no crash — matches the expected pre-Ticket-9 state. ✓

- [ ] **Step 4: Commit**

```bash
git add scenes/ui/area_tab.gd scenes/ui/area_tab.tscn
git commit -m "Add area_tab.tscn (Ticket 8)

Data-driven: binds to an AreaData resource rather than hardcoding
House, and loads whatever ButtonData .tres files exist under
data/buttons/<area_data.id>/ at runtime — currently none, since
Ticket 9 hasn't populated House content yet."
```

---

### Task 6: Create `main.tscn` + `main.gd`, wire the project's main scene, close the issue

**Files:**
- Create: `scenes/main.gd`
- Create: `scenes/main.tscn`
- Modify: `project.godot`

**Interfaces:**
- Consumes: `area_tab.tscn` (Task 5), `house.tres` (Task 1), `log_panel.tscn` (Task 3).

- [ ] **Step 1: Write `scenes/main.gd`**

```gdscript
extends TabContainer


func _ready() -> void:
	set_tab_disabled(1, true)
```

- [ ] **Step 2: Write `scenes/main.tscn`**

```
[gd_scene load_steps=5 format=3]

[ext_resource type="Script" path="res://scenes/main.gd" id="1"]
[ext_resource type="PackedScene" path="res://scenes/ui/area_tab.tscn" id="2"]
[ext_resource type="Resource" path="res://data/areas/house.tres" id="3"]
[ext_resource type="PackedScene" path="res://scenes/ui/log_panel.tscn" id="4"]

[node name="Main" type="Control"]
anchor_right = 1.0
anchor_bottom = 1.0

[node name="Root" type="VBoxContainer" parent="."]
anchor_right = 1.0
anchor_bottom = 1.0

[node name="Tabs" type="TabContainer" parent="Root"]
size_flags_vertical = 3
script = ExtResource("1")

[node name="AreaTab" parent="Root/Tabs" instance=ExtResource("2")]
area_data = ExtResource("3")

[node name="Ritual Site" type="Control" parent="Root/Tabs"]

[node name="LogPanel" parent="Root" instance=ExtResource("4")]
custom_minimum_size = Vector2(0, 150)
```

- [ ] **Step 3: Set the project's main scene**

In `project.godot`, under `[application]`, add a line after `config/icon="res://icon.svg"`:

```
run/main_scene="res://scenes/main.tscn"
```

- [ ] **Step 4: Verify**

Run: `grep -A5 '\[application\]' project.godot`
Expected: `config/name`, `config/features`, `config/icon`, and the new `run/main_scene` line, in that order.

Run: `cat scenes/main.tscn`
Expected: exactly the content from Step 2. Confirm the `Ritual Site` node's literal name (with the space) — that's what becomes its tab label, no script needed for it.

- [ ] **Step 5: Manually trace the remaining acceptance criteria**

1. *"'Ritual Site' tab exists, visible, disabled/greyed, clicking does nothing"* — trace: `Tabs` (the `TabContainer`, script `main.gd`) has two children: `AreaTab` (tab 0) and `Ritual Site` (tab 1). `main.gd`'s `_ready()` calls `set_tab_disabled(1, true)` — this is Godot's documented mechanism for a visible-but-unclickable tab; no further code needed since `Ritual Site`'s `Control` has no children and no script, so there's nothing to accidentally build out behind it. ✓
2. *"Log panel is a sibling of TabContainer, not inside it"* — trace: `scenes/main.tscn`'s tree: `Main > Root > [Tabs, LogPanel]` — `Tabs` and `LogPanel` are both direct children of `Root`, i.e. siblings. `LogPanel` is never a descendant of `Tabs`. ✓ (this is also what Task 3's trace relies on)

- [ ] **Step 6: Commit and push, closing the issue**

```bash
git add scenes/main.gd scenes/main.tscn project.godot
git commit -m "$(cat <<'EOF'
Add main.tscn UI shell, wire as project main scene

Closes #8
EOF
)"
git push
```

- [ ] **Step 7: Verify the issue closed**

Run: `gh issue view 8 --json state --jq .state`
Expected: `CLOSED`

- [ ] **Step 8: Report to the user**

State plainly: this ticket has real scene/layout files that were hand-written without any way to validate them in the actual Godot editor — structural correctness (node tree, script attachments, signal wiring, resource bindings) was traced carefully, but visual layout, actual tab-clicking, and actual rendering need the user to open the project and look. Specifically ask the user to check: the project opens without console errors (a malformed `.tscn`/`.tres` would show up immediately here — this is the single most important check), pressing Play shows the House tab with an empty button grid (expected — no buttons until Ticket 9) plus the room art placeholder and description, the log panel shows below and persists when clicking the greyed-out Ritual Site tab, and the stat bar reads "Mana: 0" / "Health: 50 / 50". Also flag: stat bar placement and the GridContainer→HBox/VBox substitution are both documented judgment calls, not settled design. Ticket 9 (House Button Content) is next — and per Ticket 9's already-amended issue body (from Ticket 5's review), it now also needs to touch `EffectHandler`/`GameState`, not just `.tres` files.

---

## Self-Review Notes

- **Spec coverage:** all three of Ticket 8's acceptance criteria are traced across Tasks 3, 5, and 6. The `AreaData` gap from Ticket 1 is resolved in Task 1. `LogManager`'s missing backfill capability (deferred explicitly in Ticket 4's plan) is resolved in Task 2.
- **No placeholders:** every file is complete. The two explicitly deferred/judgment-call items (stat bar placement, GridContainer substitution) are documented with reasoning, not silent guesses.
- **Type/name consistency:** `AreaData`'s field names (`id`, `name_progression`, `base_description`) are used identically in `data/areas/house.tres`, `area_tab.gd`, and this plan's own descriptions. Node paths in `area_tab.gd`'s `@onready` vars match the exact tree structure written in `area_tab.tscn` Task 5 Step 2 — double-checked path-by-path in the plan itself, not just asserted.

## Execution Handoff

Two execution options:

1. **Subagent-Driven (recommended)** - dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** - execute tasks in this session using `executing-plans`, batch execution with checkpoints.
