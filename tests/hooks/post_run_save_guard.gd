extends GutHookScript

const SAVE_PATH := "user://save.json"
const BACKUP_PATH := "user://save.json.gut_backup"
const ABSENT_MARKER_PATH := "user://save.json.gut_backup_absent"


func run() -> void:
	if FileAccess.file_exists(ABSENT_MARKER_PATH):
		if FileAccess.file_exists(SAVE_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ABSENT_MARKER_PATH))
		return

	if not FileAccess.file_exists(BACKUP_PATH):
		gut.logger.error("post_run_save_guard: no backup found — pre_run_save_guard may not have run. Real save.json (if any) was left untouched by this guard, but was NOT protected during this suite run.")
		return

	var backup := FileAccess.open(BACKUP_PATH, FileAccess.READ)
	var content := backup.get_as_text()
	backup.close()

	var dest := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	dest.store_string(content)
	dest.close()

	DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKUP_PATH))
