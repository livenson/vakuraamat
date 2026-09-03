# Global signal hub. Autoload "EventBus". Systems talk through here, never directly.
extends Node

signal flag_changed(flag_name: String, value: Variant)
signal era_change_started(from_era: String, to_era: String)
signal era_changed(era_id: String)
signal item_added(item_id: String, era_id: String)      # era_id == "" for artifacts
signal item_removed(item_id: String, era_id: String)
signal consequence_triggered(cp_id: String)
signal journal_entry_added(entry: Dictionary)
signal chapter_changed(chapter: int)
signal chapter_committed(chapter: int)
signal location_visited(location_id: String)
signal dialogue_started(npc_id: String)
signal dialogue_ended(npc_id: String)
signal notice(text: String)                              # short toast for the player
signal register_opened()
