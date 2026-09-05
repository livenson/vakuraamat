# A person: one of the MakeHuman figures in assets/models/humans (tools/blender/make_humans.py,
# game_engine rig) with a procedural gait and a few standing poses driven on the Skeleton3D, so no
# animation clips are needed. Used by ambient walkers (TrafficAgent), cyclists and NPCs.
# Clothes are tinted per era so the same eight figures read as different people.
class_name HumanFigure
extends Node3D

const DIR := "res://assets/models/humans/"
const MEN := ["man_casual", "man_work", "man_old", "man_young"]
const WOMEN := ["woman_casual", "woman_elegant", "woman_old", "woman_sport"]
const HEIGHT := 1.70                       # exported figure height, metres
const STRIDE := 1.35                       # metres per full gait cycle at walking speed
const ARM_DOWN := 0.7                      # radians that bring the A-pose arms down to the sides
# clothes tints per era: pre-1900 undyed wool and linen, 1938 dark suits, 2026 anything
const TINTS := {
	1798: [Color(0.55, 0.48, 0.38), Color(0.4, 0.36, 0.3), Color(0.6, 0.58, 0.5), Color(0.35, 0.3, 0.28), Color(0.5, 0.42, 0.3)],
	1938: [Color(0.3, 0.3, 0.33), Color(0.42, 0.38, 0.32), Color(0.5, 0.5, 0.55), Color(0.25, 0.25, 0.28), Color(0.55, 0.5, 0.42)],
	2026: [Color(1, 1, 1), Color(0.7, 0.75, 0.9), Color(0.9, 0.6, 0.55), Color(0.6, 0.65, 0.7), Color(0.85, 0.85, 0.7), Color(0.5, 0.7, 0.6)],
}

var skeleton: Skeleton3D
var walking := false
var speed_ratio := 1.0                     # 1 = walking pace
var pose := "stand"                        # stand | arms_folded | holding | sit
var _phase := 0.0
var _bones: Dictionary = {}                # name -> index
var _rest: Dictionary = {}                 # name -> rest rotation (Quaternion)
var _axes: Dictionary = {}                 # name -> {x, y, z}: the figure's axes expressed in the bone's rest frame


static func available() -> bool:
	return ResourceLoader.exists(DIR + MEN[0] + ".glb")


## A figure picked with `rng`: a man or a woman, tinted for `year`.
static func make(rng: RandomNumberGenerator, year: int = 2026, variant: String = "") -> HumanFigure:
	var f := HumanFigure.new()
	if variant == "":
		var list: Array = MEN if rng.randf() < 0.5 else WOMEN
		variant = list[rng.randi() % list.size()]
	f.setup(variant, rng, year)
	return f


func setup(variant: String, rng: RandomNumberGenerator, year: int) -> void:
	var scene: PackedScene = load(DIR + variant + ".glb")
	if scene == null:
		return
	var model: Node3D = scene.instantiate()
	model.rotation.y = PI   # the export faces +Z; agents and NPCs face -Z
	add_child(model)
	skeleton = model.find_child("*", true, false) as Skeleton3D if model is Skeleton3D else null
	for n in model.find_children("*", "Skeleton3D", true, false):
		skeleton = n
		break
	if skeleton:
		for i in skeleton.get_bone_count():
			var bn := skeleton.get_bone_name(i)
			_bones[bn] = i
			_rest[bn] = skeleton.get_bone_rest(i).basis.get_rotation_quaternion()
			var inv := skeleton.get_bone_global_rest(i).basis.inverse()
			_axes[bn] = {"x": (inv * Vector3.RIGHT).normalized(), "y": (inv * Vector3.UP).normalized(), "z": (inv * Vector3.BACK).normalized()}
	_tint(model, rng, year)
	var k := rng.randf_range(0.95, 1.04)
	scale = Vector3(k, k, k)


## Suits, dresses and hats get an era tint; skin, hair and eyes keep their textures.
func _tint(model: Node3D, rng: RandomNumberGenerator, year: int) -> void:
	var palette: Array = TINTS[1798] if year < 1900 else (TINTS[1938] if year < 1990 else TINTS[2026])
	var tint: Color = palette[rng.randi() % palette.size()]
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var lname := mi.name.to_lower()
		if not ("suit" in lname or "dress" in lname or "fedora" in lname or "shirt" in lname or "trouser" in lname):
			continue
		for si in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(si)
			if m is BaseMaterial3D:
				var c: BaseMaterial3D = m.duplicate()
				c.albedo_color = c.albedo_color * tint
				mi.set_surface_override_material(si, c)


func set_walking(on: bool, ratio: float = 1.0) -> void:
	walking = on
	speed_ratio = ratio


func _process(delta: float) -> void:
	if skeleton == null:
		return
	if walking:
		_phase += delta * speed_ratio * 1.3 * TAU / STRIDE
		_gait(_phase, clampf(speed_ratio, 0.3, 1.6))
	else:
		_hold(pose)


## Rotate a bone from its rest pose about the figure's axes: `pitch` about the lateral axis (swing
## forward/back), `roll` about the forward axis (out to the side), `yaw` about the vertical axis.
## Bone rolls differ per bone in the exported rig, so the axes come from each bone's rest frame.
func _rot(bone: String, pitch: float, roll: float = 0.0, yaw: float = 0.0) -> void:
	if not _bones.has(bone):
		return
	var ax: Dictionary = _axes[bone]
	var q := Quaternion(ax.x, pitch) * Quaternion(ax.z, roll) * Quaternion(ax.y, yaw)
	skeleton.set_bone_pose_rotation(_bones[bone], _rest[bone] * q)


## Legs swing about the hip, knees bend on the back swing, arms swing opposite, torso sways a little.
## Positive pitch moves the limb's far end forward for legs and arms hanging down.
func _gait(t: float, amp: float) -> void:
	var swing := sin(t) * 0.42 * amp
	var knee_l := maxf(0.0, -sin(t - 0.5)) * 0.9 * amp
	var knee_r := maxf(0.0, sin(t - 0.5)) * 0.9 * amp
	_rot("thigh_l", swing)
	_rot("thigh_r", -swing)
	_rot("calf_l", -knee_l)
	_rot("calf_r", -knee_r)
	_rot("foot_l", knee_l * 0.4)
	_rot("foot_r", knee_r * 0.4)
	_rot("upperarm_l", -swing * 0.6, -ARM_DOWN)
	_rot("upperarm_r", swing * 0.6, ARM_DOWN)
	_rot("lowerarm_l", 0.25 + maxf(0.0, -swing) * 0.4)
	_rot("lowerarm_r", 0.25 + maxf(0.0, swing) * 0.4)
	_rot("spine_01", sin(t * 2.0) * 0.02, 0.0, sin(t) * 0.05)
	_rot("head", 0.0, 0.0, -sin(t) * 0.04)
	position.y = absf(sin(t)) * 0.03 * amp


## Standing poses for NPCs. The exported rest pose is an A-pose; ARM_DOWN brings the arms to the sides.
func _hold(p: String) -> void:
	match p:
		"arms_folded":
			_rot("upperarm_l", 0.5, -ARM_DOWN * 0.8)
			_rot("upperarm_r", 0.5, ARM_DOWN * 0.8)
			_rot("lowerarm_l", 1.7, 0.0, 0.8)
			_rot("lowerarm_r", 1.7, 0.0, -0.8)
		"holding":
			_rot("upperarm_l", 0.4, -ARM_DOWN)
			_rot("upperarm_r", 0.4, ARM_DOWN)
			_rot("lowerarm_l", 1.5)
			_rot("lowerarm_r", 1.5)
		"sit":
			_rot("thigh_l", 1.4)
			_rot("thigh_r", 1.4)
			_rot("calf_l", -1.3)
			_rot("calf_r", -1.3)
			_rot("upperarm_l", 0.8, -ARM_DOWN)
			_rot("upperarm_r", 0.8, ARM_DOWN)
			_rot("lowerarm_l", 0.6)
			_rot("lowerarm_r", 0.6)
		_:
			_rot("upperarm_l", 0.05, -ARM_DOWN)
			_rot("upperarm_r", 0.05, ARM_DOWN)
			_rot("lowerarm_l", 0.2)
			_rot("lowerarm_r", 0.2)
