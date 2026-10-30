class_name FSAHistory
extends RefCounted
## Undo / redo by snapshots of the whole document (a clip is a few dozen KB, so this stays simple and can never drift).
## Every change, from a slider, a drag, a menu or an agent, goes through commit(); `who` says whether you or an agent made it.

const LIMIT := 300

var undo_stack: Array = []   # [{label, who, before, after, time}]
var redo_stack: Array = []
var saved_at := 0            # undo_stack size when the clip was last saved (dirty = size differs)


## record a change: `before` is doc.to_dict() taken before it
func commit(label: String, before: Dictionary, after: Dictionary, who: String = "you") -> void:
	# a run of the same edit (a slider being dragged with auto-key on) is one step
	if not undo_stack.is_empty() and redo_stack.is_empty():
		var last: Dictionary = undo_stack[undo_stack.size() - 1]
		if str(last["label"]) == label and str(last["who"]) == who and Time.get_ticks_msec() - int(last["time"]) < 900 and saved_at != undo_stack.size():
			last["after"] = after
			last["time"] = Time.get_ticks_msec()
			return
	undo_stack.append({"label": label, "who": who, "before": before, "after": after, "time": Time.get_ticks_msec()})
	if undo_stack.size() > LIMIT:
		undo_stack.pop_front()
		saved_at -= 1
	redo_stack.clear()


func can_undo() -> bool:
	return not undo_stack.is_empty()


func can_redo() -> bool:
	return not redo_stack.is_empty()


## the document to load after an undo (or {} when there is nothing)
func undo() -> Dictionary:
	if undo_stack.is_empty():
		return {}
	var e: Dictionary = undo_stack.pop_back()
	redo_stack.append(e)
	return e


func redo() -> Dictionary:
	if redo_stack.is_empty():
		return {}
	var e: Dictionary = redo_stack.pop_back()
	undo_stack.append(e)
	return e


func clear() -> void:
	undo_stack.clear()
	redo_stack.clear()
	saved_at = 0


func mark_saved() -> void:
	saved_at = undo_stack.size()


func dirty() -> bool:
	return saved_at != undo_stack.size()


func labels(n: int = 40) -> Array:
	var out: Array = []
	for i in range(undo_stack.size() - 1, maxi(-1, undo_stack.size() - 1 - n), -1):
		var e: Dictionary = undo_stack[i]
		out.append("%s%s" % ["[agent] " if str(e["who"]) != "you" else "", e["label"]])
	return out
