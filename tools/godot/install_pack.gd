# Installs a tile-service zip as a user pack without the menu (for scripted checks):
#   godot --headless --path . res://tools/godot/install_pack.tscn -- --zip=/abs/site.zip --id=aakre
extends Node


func _ready() -> void:
	await get_tree().process_frame
	var zip := ""
	var id := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--zip="):
			zip = a.trim_prefix("--zip=")
		elif a.begins_with("--id="):
			id = a.trim_prefix("--id=")
	if zip == "" or id == "":
		print("[install_pack] usage: -- --zip=<file> --id=<site id>")
		get_tree().quit(1)
		return
	var ok := Locator.install_zip(zip, id)
	Sites.scan()
	print("[install_pack] %s -> %s (available: %s)" % [zip, "installed" if ok else "FAILED", Sites.available])
	get_tree().quit(0 if ok else 1)
