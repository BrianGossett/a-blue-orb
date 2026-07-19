extends GutHookScript
# Paired with post_run_save_guard.gd. This guarantee holds on a graceful
# suite exit only — if the process is killed between this hook writing the
# backup and the post-run hook restoring it, the real save.json is left
# test-mutated and a stray .gut_backup file remains until the next run.

const SAVE_PATH := "user://save.json"
const BACKUP_PATH := "user://save.json.gut_backup"
const ABSENT_MARKER_PATH := "user://save.json.gut_backup_absent"


func run() -> void:
	if FileAccess.file_exists(BACKUP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKUP_PATH))
	if FileAccess.file_exists(ABSENT_MARKER_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ABSENT_MARKER_PATH))

	if not FileAccess.file_exists(SAVE_PATH):
		var marker := FileAccess.open(ABSENT_MARKER_PATH, FileAccess.WRITE)
		marker.close()
		return

	var source := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var content := source.get_as_text()
	source.close()

	var backup := FileAccess.open(BACKUP_PATH, FileAccess.WRITE)
	backup.store_string(content)
	backup.close()
