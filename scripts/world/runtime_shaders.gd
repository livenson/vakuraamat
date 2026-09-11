# The shaders of the materials the game builds in code (buildings, roads, parcels, the terrain's
# generated shader, the sky), written by tools/godot/shader_manifest.gd. Nothing loads this at
# runtime: it exists for the export's shader baker, which bakes only the shaders it finds in
# resources. A shader missing from the bake is compiled on the first frame that uses it, on the
# thread that draws the loading screen - on a first launch on macOS that was 10 s of frozen window.
class_name RuntimeShaders
extends Resource

@export var materials: Array[Material] = []   # a copy of each distinct one: the baker regenerates its shader
@export var sources: PackedStringArray = []   # where each came from, for the reader of a diff
