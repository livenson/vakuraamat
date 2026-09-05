# Shows this node only when a TimelineState flag matches. Attach to props whose presence
# is a consequence (the well ring, the boundary stone, the orchard, the young forest).
class_name Conditional
extends Node3D

@export var flag := ""
@export var visible_when := true       # true: show when flag set; false: show when unset
@export var min_chapter := 0           # also hidden before this chapter (content gating)


func _ready() -> void:
	EventBus.flag_changed.connect(func(f, _v):
		if f == flag:
			refresh())
	EventBus.chapter_changed.connect(func(_c): refresh())
	refresh()


func refresh() -> void:
	var on := TimelineState.has_flag(flag) == visible_when if flag != "" else true
	on = on and GameState.chapter >= min_chapter
	visible = on
	for c in find_children("*", "CollisionShape3D", true, false):
		c.disabled = not on
