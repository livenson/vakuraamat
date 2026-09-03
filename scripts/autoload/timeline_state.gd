# The single source of truth for everything that has ever changed across eras.
# Flat dictionary. Never nested. Never simulated. Era scenes read it on activation;
# only consequence points (via GameState.trigger_consequence) write it.
#
# Chapters: flags set during a chapter are "pending" until the chapter commits
# (design doc 2.6). revert_uncommitted() restores the last committed snapshot.
extends Node

var flags: Dictionary = {}            # String -> Variant (bool/int/String), pending + committed
var _committed: Dictionary = {}       # snapshot at the last commit point


func get_flag(flag_name: String, default: Variant = false) -> Variant:
	return flags.get(flag_name, default)


func has_flag(flag_name: String) -> bool:
	return flags.has(flag_name) and bool(flags[flag_name])


func set_flag(flag_name: String, value: Variant = true) -> void:
	if flags.get(flag_name) == value:
		return
	flags[flag_name] = value
	SaveManager.mark_dirty()
	EventBus.flag_changed.emit(flag_name, value)


func is_committed(flag_name: String) -> bool:
	return _committed.has(flag_name) and bool(_committed[flag_name])


func commit() -> void:
	_committed = flags.duplicate()


func revert_uncommitted() -> void:
	var changed := []
	for k in flags.keys():
		if not _committed.has(k) or _committed[k] != flags[k]:
			changed.append(k)
	flags = _committed.duplicate()
	for k in changed:
		EventBus.flag_changed.emit(k, flags.get(k, false))


func to_dict() -> Dictionary:
	return {"flags": flags.duplicate(), "committed": _committed.duplicate()}


func from_dict(d: Dictionary) -> void:
	flags = d.get("flags", {}).duplicate()
	_committed = d.get("committed", {}).duplicate()
	for k in flags:
		EventBus.flag_changed.emit(k, flags[k])
