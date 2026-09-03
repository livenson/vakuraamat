# A plantable plot. Interact: plant a seed from the era-local bag, or harvest when ready.
# State machine: EMPTY -> GROWING -> READY -> (harvest) EMPTY. Visuals: a grid of stalks
# scaled by growth progress, recoloured when ripe.
class_name FarmPlot
extends Interactable

@export var plot_id := ""
@export var era_id := ""
@export var size := Vector2(4, 3)

var _stalks: Array[MeshInstance3D] = []
var _mat := StandardMaterial3D.new()
var _crop: CropDefinition = null


func _key() -> String:
	return "%s:%s" % [era_id, plot_id]


func _ready() -> void:
	label_key = "FARM_PLOT"
	_mat.roughness = 0.9
	var cols := int(size.x / 0.5)
	var rows := int(size.y / 0.5)
	var stalk := CylinderMesh.new()
	stalk.top_radius = 0.02
	stalk.bottom_radius = 0.05
	stalk.height = 1.0
	stalk.radial_segments = 5
	for r in rows:
		for c in cols:
			var mi := MeshInstance3D.new()
			mi.mesh = stalk
			mi.material_override = _mat
			mi.position = Vector3(-size.x / 2 + 0.25 + c * 0.5, 0, -size.y / 2 + 0.25 + r * 0.5)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_stalks.append(mi)
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func state() -> String:
	var st := Farming.plot_state(_key())
	if st.is_empty():
		return "EMPTY"
	return "READY" if Farming.progress(_key()) >= 1.0 else "GROWING"


func _current_crop() -> CropDefinition:
	return Farming.crops.get(Farming.plot_state(_key()).get("crop", ""))


func _refresh() -> void:
	var st := state()
	_crop = _current_crop() if st != "EMPTY" else null
	var p := Farming.progress(_key())
	for mi in _stalks:
		mi.visible = st != "EMPTY"
		if _crop:
			var h: float = _crop.stalk_height * maxf(0.05, p)
			mi.scale = Vector3(1, h, 1)
			mi.position.y = h / 2
	if _crop:
		_mat.albedo_color = _crop.ripe_color if st == "READY" else _crop.stalk_color


func prompt() -> String:
	match state():
		"EMPTY": return tr("FARM_PLANT")
		"READY": return tr("FARM_HARVEST")
		_: return tr("FARM_WAIT")


func hover_text() -> String:
	match state():
		"EMPTY":
			var seeds := _seeds_in_bag()
			return tr("FARM_EMPTY_HINT") if seeds.is_empty() else tr("FARM_EMPTY_READY") % tr(seeds[0].display_name_key)
		"READY": return tr("FARM_READY_TEXT") % tr(_current_crop().display_name_key)
		_: return tr("FARM_GROWING_TEXT") % [tr(_current_crop().display_name_key), int(Farming.progress(_key()) * 100)]
	return ""


func _seeds_in_bag() -> Array:
	var out := []
	for id in Inventory.local_items(era_id):
		var c := Farming.crop_for_seed(id)
		if c and era_id in c.eras and not out.has(c):
			out.append(c)
	return out


func interact(_player: Node3D) -> void:
	match state():
		"EMPTY":
			var seeds := _seeds_in_bag()
			if seeds.is_empty():
				EventBus.notice.emit(tr("FARM_EMPTY_HINT"))
				return
			var crop: CropDefinition = seeds[0]
			Inventory.remove(crop.seed_item_id)
			Farming.plant(_key(), crop.id)
			_refresh()
			EventBus.notice.emit(tr("FARM_PLANTED") % tr(crop.display_name_key))
		"READY":
			var crop := _current_crop()
			for i in crop.yield_quantity:
				Inventory.add(crop.yield_item_id)
			EventBus.notice.emit(tr("FARM_HARVESTED") % [crop.yield_quantity, tr(GameState.item(crop.yield_item_id).display_name_key)])
			Farming.clear(_key())
			_refresh()
		_:
			EventBus.notice.emit(hover_text())
