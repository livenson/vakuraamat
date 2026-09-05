# Wraps the inkgd runtime. One compiled ink story per era; each is kept alive so its
# variables and visit counts persist, and their state is saved with the game.
#
# Conventions in the .ink files:
#   - Lines are Estonian; an English version rides in a tag:  Tere! # en: Hello!
#   - Choice text carries both, split by %%:  * [Tere. %% Hello.]
#   - EXTERNAL functions available to ink:
#       flag(name)          -> bool   TimelineState flag
#       has_item(id)        -> bool   in inventory (artifact or era-local)
#       give_item(id, target) -> bool deliver an artifact (consumes it, fires its consequence)
#       take_item(id)                 give the player an item
#       set_flag(name)                set a plain (non-consequence) flag
#       end_chapter()
#       chapter()           -> int
#       trigger(cp_id)      -> bool   fire a consequence point that is a choice, not a delivery
#       visiting()          -> bool   the player is a guest in a friend's world (co-op blocks)
#   Tags: '# me' marks a line spoken by the player; '# speaker: KEY' overrides the speaker.
extends Node

signal line(text: String, speaker: String, tags: Array)
signal choices(options: Array)           # Array of {index, text}
signal ended()

const STORY_RESOURCE := preload("res://scripts/narrative/ink_story_resource.gd")

var _players: Dictionary = {}     # era_id -> InkPlayer
var _active: Node = null
var _active_era: String = ""
var _pending_states: Dictionary = {}   # era_id -> json state loaded from a save
var _factory = preload("res://addons/inkgd/ink_player_factory.gd")
var _externals := Externals.new()
var default_speaker := ""         # translation key of who is talking unless a line says otherwise
var force_visiting := false       # tests: pretend to be a visitor in a friend's world


## Functions callable from ink via EXTERNAL declarations.
class Externals:
	extends RefCounted
	func flag(name) -> bool:
		return TimelineState.has_flag(str(name))
	func has_item(id) -> bool:
		return Inventory.has(str(id))
	func give_item(id, target) -> bool:
		return GameState.deliver_artifact(str(id), str(target))
	func take_item(id) -> void:
		Inventory.add(str(id))
	func set_flag(name) -> void:
		TimelineState.set_flag(str(name), true)
	func end_chapter() -> void:
		GameState.end_chapter()
	func chapter() -> int:
		return GameState.chapter
	func trigger(cp_id) -> bool:
		return GameState.trigger_consequence(str(cp_id))
	func visiting() -> bool:
		return Friends.visiting_code != "" or Narrative.force_visiting


func _ready() -> void:
	EventBus.dialogue_ended.connect(func(_id): _active = null)
	# Create the shared ink runtime node once the tree has finished adding autoloads.
	await get_tree().process_frame
	load("res://addons/inkgd/ink_runtime_manager.gd").init(get_tree().root)


func _player_for(era_id: String) -> Node:
	if _players.has(era_id):
		return _players[era_id]
	var era: EraDefinition = GameState.era(era_id)
	if era == null or era.narrative_story == "":
		return null
	var player = _factory.create()
	player.name = "InkPlayer_" + era_id
	player.loads_in_background = false
	add_child(player)
	var res = STORY_RESOURCE.new()
	res.json = FileAccess.get_file_as_string(era.narrative_story)
	player.ink_file = res
	player.create_story()
	var ok: bool = await player.loaded
	if not ok:
		push_error("could not load ink story for %s" % era_id)
		return null
	_bind_externals(player)
	if _pending_states.has(era_id):
		player.set_state(_pending_states[era_id])
		_pending_states.erase(era_id)
	_players[era_id] = player
	return player


func _bind_externals(player: Node) -> void:
	for fn in ["flag", "has_item", "give_item", "take_item", "set_flag", "end_chapter", "chapter", "trigger", "visiting"]:
		player.bind_external_function(fn, _externals, fn, fn in ["flag", "has_item", "chapter", "visiting"])


## Start a conversation at a knot in the current era's story.
func start(knot: String, npc_id: String = "") -> bool:
	var player: Node = await _player_for(GameState.current_era)
	if player == null:
		push_error("no story for era %s" % GameState.current_era)
		return false
	_active = player
	_active_era = GameState.current_era
	EventBus.dialogue_started.emit(npc_id)
	player.choose_path(knot)
	_advance()
	return true


func choose(index: int) -> void:
	if _active == null:
		return
	_active.choose_choice_index(index)
	_advance()


## Emits lines until a choice or the end of the flow.
func _advance() -> void:
	while _active and _active.can_continue:
		var raw: String = _active.continue_story()
		var tags: Array = _active.current_tags
		var text := _localise(raw.strip_edges(), tags)
		if text.is_empty():
			continue
		line.emit(text, _speaker_from(tags), tags)
	if _active == null:
		return
	if _active.has_choices:
		var opts := []
		for c in _active.current_choices:
			opts.append({"index": c.index, "text": _localise_choice(c.text)})
		choices.emit(opts)
	else:
		ended.emit()
		EventBus.dialogue_ended.emit("")


func _localise(text: String, tags: Array) -> String:
	var locale := TranslationServer.get_locale().substr(0, 2)
	if locale == "et":
		return text
	for t in tags:
		var s := str(t).strip_edges()
		if s.begins_with(locale + ":"):
			return s.substr(locale.length() + 1).strip_edges()
	return text


## Choice text carries both languages: "Eesti tekst %% English text".
func _localise_choice(text: String) -> String:
	var parts := text.split("%%")
	if parts.size() < 2:
		return text
	return parts[0].strip_edges() if TranslationServer.get_locale().begins_with("et") else parts[1].strip_edges()


func _speaker_from(tags: Array) -> String:
	for t in tags:
		var s := str(t).strip_edges()
		if s == "me":
			return ""
		if s.begins_with("speaker:"):
			return s.substr(8).strip_edges()
	return default_speaker


func to_dict() -> Dictionary:
	var d := {}
	for era_id in _players:
		d[era_id] = _players[era_id].get_state()
	return d


func from_dict(d: Dictionary) -> void:
	for era_id in d:
		if _players.has(era_id):
			_players[era_id].set_state(d[era_id])
		else:
			_pending_states[era_id] = d[era_id]
