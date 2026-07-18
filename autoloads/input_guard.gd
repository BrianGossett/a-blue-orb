extends Node

const MAX_CLICKS_PER_SECOND: int = 100
const WINDOW_MSEC: int = 1000

var _click_timestamps_msec: Array[int] = []


func try_register_click() -> bool:
	var now := Time.get_ticks_msec()
	_prune_old_clicks(now)
	if _click_timestamps_msec.size() >= MAX_CLICKS_PER_SECOND:
		return false
	_click_timestamps_msec.append(now)
	return true


func _prune_old_clicks(now: int) -> void:
	while _click_timestamps_msec.size() > 0 and now - _click_timestamps_msec[0] > WINDOW_MSEC:
		_click_timestamps_msec.pop_front()
