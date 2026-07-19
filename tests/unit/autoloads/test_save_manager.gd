extends GutTest

# SaveManager reads/writes the REAL user://save.json path — the same file
# an actual played build uses on this machine, not a test-isolated
# location. before_all()/after_all() back the raw file text up once before
# any test in this script runs and restore it byte-exact once after all of
# them finish (or delete the file if nothing existed before), so this
# script can never leave real save data corrupted. This was verified
# working by diffing user://save.json's contents before and after a full
# suite run — see task-6b-report.md.
#
# NOTE (see report): SaveManager is a live project autoload, so its
# EventBus-driven autosave-on-purchase listener can also be triggered by
# *other*, pre-existing test files elsewhere in the suite (any test that
# emits EventBus.upgrade_purchased/familiar_gained on the real singleton),
# outside of this file's before_all/after_all window. That is a
# suite-wide risk this single file's hooks cannot fully close on their
# own; it is reported to the controller, not fixed here.

const SAVE_PATH := "user://save.json"

var _had_save_before: bool = false
var _save_backup_text: String = ""


func before_all() -> void:
	_had_save_before = FileAccess.file_exists(SAVE_PATH)
	if _had_save_before:
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		_save_backup_text = f.get_as_text()
		f.close()


func after_all() -> void:
	if _had_save_before:
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		f.store_string(_save_backup_text)
		f.close()
	elif FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func before_each() -> void:
	GameState.from_dict({})


func test_real_round_trip_through_actual_file_io() -> void:
	# Not just the in-memory to_dict()/from_dict() Task 3 already covered —
	# this goes through SaveManager's real file write and re-read.
	GameState.add_mana(12.0)
	GameState.add_familiars(3)
	GameState.mark_upgrade_purchased("chair")
	GameState.advance_confidence_tier()
	GameState.advance_confidence_tier()

	SaveManager.save_game()
	GameState.from_dict({})  # simulate a fresh session

	var result: bool = SaveManager.load_game()

	assert_true(result, "load_game() should succeed once a real save file exists")
	assert_eq(GameState.mana, 12.0)
	assert_eq(GameState.familiars, 3)
	assert_true(GameState.has_upgrade("chair"))
	assert_eq(GameState.confidence_tier, 2)


func test_save_version_present_in_written_file() -> void:
	SaveManager.save_game()

	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)

	assert_true(parsed is Dictionary)
	assert_eq((parsed as Dictionary).get("save_version"), Constants.SAVE_VERSION)


func test_version_mismatch_is_rejected_without_mutating_state() -> void:
	# Ticket 11's own explicit acceptance criterion: "hand-edit a save's
	# version field and attempt import."
	GameState.add_mana(42.0)
	var before: Dictionary = GameState.to_dict()

	var bad_json := JSON.stringify({
		"save_version": Constants.SAVE_VERSION + 999,
		"game_state": {"mana": 999.0, "health": 1.0},
	})

	var result: bool = SaveManager.import_save(bad_json)

	assert_false(result, "a version mismatch must be rejected")
	assert_eq(GameState.to_dict(), before, "GameState must be completely unchanged — no partial mutation")


func test_is_blacked_out_never_restored_through_save_manager() -> void:
	# Ticket 11's own flagged soft-lock risk, already fixed at the
	# GameState.from_dict() level (Task 3) — re-confirmed here transitively
	# through the real SaveManager path, since that's what an actual
	# save/load in play uses.
	GameState.enter_blackout()
	SaveManager.save_game()
	GameState.from_dict({})

	SaveManager.load_game()

	assert_false(GameState.is_blacked_out)


func test_better_x_reload_seeding_wired_end_to_end_after_real_load() -> void:
	# Ticket 11's own flagged "second reload gap." First confirm the raw
	# field round-trips through real file I/O...
	GameState.better_chair_level = 3
	SaveManager.save_game()
	GameState.from_dict({})

	SaveManager.load_game()

	assert_eq(GameState.better_chair_level, 3, "raw field should round-trip through real file I/O")

	# ...then verify the UI-layer half. _purchase_count is private, so
	# verify via an externally observable effect: the rendered label text,
	# which should reflect labels[3] (seeded from level 3) rather than
	# labels[0].
	var button = add_child_autofree(load("res://scenes/ui/button_action.tscn").instantiate())
	var data := ButtonData.new()
	data.count_seed_source = "better_chair_level"
	data.cost_type = "none"
	data.labels = ["L0", "L1", "L2", "L3", "L4"]
	button.set_data(data)

	assert_eq(button.text, data.labels[3],
		"seeded purchase count from a real load should be reflected in the rendered label")
