# The ride's sound, as if the bicycle were a motorbike (playtest 2026-09-13: "sound is not great. Can
# you rather find a cool sounds as if this were a motorbike?"): two CC0 recordings from Freesound, cut
# into seamless loops (assets/audio, THIRD_PARTY.md) - a motorbike idling (lmbubec, 119455) and one on
# the throttle (overmedium, 651750) - pitched up with the speed and crossfaded from the one to the
# other, revving a little higher and louder while the throttle (forward) is held. FirstPersonController
# makes one on mount, feeds it the speed and whether forward is held, and frees it on dismount.
class_name BikeSound
extends Node

const IDLE := "res://assets/audio/moto_idle.wav"
const THROTTLE := "res://assets/audio/moto_throttle.wav"
const TOP := 14.0             # m/s, the ride's fastest (FirstPersonController.current_speed, dash)

var speed := 0.0              # metres per second
var pedalling := false        # the throttle: forward held
var _idle: AudioStreamPlayer
var _throttle: AudioStreamPlayer
var _rev := 0.0               # 0 idle .. 1 flat out, following the speed smoothly
var _mix := 0.0               # how much of the throttle recording is heard


func _ready() -> void:
	_idle = _loop(IDLE)
	_throttle = _loop(THROTTLE)
	_apply()


func _process(delta: float) -> void:
	var t := clampf(speed / TOP, 0.0, 1.0)
	_rev = lerpf(_rev, t + (0.18 if pedalling else 0.0), minf(1.0, delta * 3.0))   # the revs lead on the gas
	_mix = lerpf(_mix, clampf(t * 1.4 + (0.3 if pedalling else 0.0), 0.0, 1.0), minf(1.0, delta * 2.5))
	_apply()


func _apply() -> void:
	_idle.pitch_scale = 1.0 + 0.6 * _rev
	_throttle.pitch_scale = 0.8 + 0.7 * _rev
	_idle.volume_db = linear_to_db(maxf(1.0 - 0.8 * _mix, 0.001)) - 4.0
	_throttle.volume_db = linear_to_db(maxf(_mix, 0.001)) - 6.0


## A player looping one of the recordings, started silent; the mix fades it in.
func _loop(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	if ResourceLoader.exists(path):
		var s: AudioStream = load(path)
		if s is AudioStreamWAV:
			# the whole file is the loop: its end was crossfaded into its start when it was cut
			var w := s as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
		p.stream = s
	add_child(p)
	if p.stream:
		p.play()
	return p
