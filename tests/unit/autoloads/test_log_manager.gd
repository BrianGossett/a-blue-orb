extends GutTest

var lm


func before_each() -> void:
	lm = load("res://autoloads/log_manager.gd").new()
	watch_signals(lm)


func after_each() -> void:
	lm.free()


func test_push_formats_timestamp_and_lowercases_text() -> void:
	lm.push("You gingerly touch the orb.")
	var lines: Array[String] = lm.get_lines()
	var last_line: String = lines[lines.size() - 1]
	var re := RegEx.new()
	re.compile("^\\[\\d{2}:\\d{2}:\\d{2}\\] you gingerly touch the orb\\.$")
	assert_not_null(re.search(last_line), "Expected '%s' to match the timestamped, lowercased format." % last_line)
	assert_signal_emitted_with_parameters(lm, "line_added", [last_line])


func test_rolling_buffer_caps_at_200_and_evicts_oldest_first() -> void:
	for i in range(205):
		lm.push("line %d" % i)
	var lines: Array[String] = lm.get_lines()
	assert_eq(lines.size(), 200)
	assert_true(lines[0].ends_with("line 5"), "Expected oldest-first eviction to leave 'line 5' at the front, got '%s'." % lines[0])
