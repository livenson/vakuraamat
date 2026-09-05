# Global signal hub. Autoload "EventBus". Systems talk through here, never directly.
extends Node

signal era_change_started(from_era: String, to_era: String)
signal era_changed(era_id: String)
signal location_visited(location_id: String)
signal notice(text: String)                              # short toast for the player
