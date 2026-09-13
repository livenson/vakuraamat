# The sound of riding an old bicycle, made as it plays, from no recording: the tyres hissing on the
# road louder and brighter with the speed; while you pedal, the chain rattling over the ring and a pedal
# creaking on some turns of the crank; while you coast, the freewheel's pawls ticking over the ratchet,
# faster the faster you go; now and then a loose mudguard's tink. FirstPersonController makes one on
# mount, feeds it the speed and whether the pedals turn, and frees it on dismount (playtest 2026-09-13:
# "when riding on a bicycle, can you add a sound too ... older one").
class_name BikeSound
extends AudioStreamPlayer

const RATE := 22050.0
const WHEEL_M := 2.1          # a 28-inch wheel's circumference
const RATCHET := 18           # an old freewheel's teeth: clicks per wheel turn while coasting
const GEAR := 2.6             # wheel turns per turn of the crank
const CHAINRING := 44         # links over the ring per turn of the crank

var speed := 0.0              # metres per second
var pedalling := false
var _pb: AudioStreamGeneratorPlayback = null
var _rng := RandomNumberGenerator.new()
var _level := 0.0             # the tyres' loudness, following the speed smoothly
var _hiss := 0.0              # low-passed noise
var _ratchet := 0.0           # phases, in events
var _link := 0.0
var _crank := 0.0
var _click := 0.0             # envelopes of the short sounds, 1 at their start
var _click_phase := 0.0
var _rattle := 0.0
var _creak := 0.0
var _creak_phase := 0.0
var _tink := 0.0
var _tink_phase := 0.0


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.12
	stream = gen
	volume_db = -4.0
	_rng.seed = 1953
	play()
	_pb = get_stream_playback() as AudioStreamGeneratorPlayback


func _process(_delta: float) -> void:
	if _pb == null:
		return
	var dt := 1.0 / RATE
	var wheel_hz := speed / WHEEL_M
	var crank_hz := wheel_hz / GEAR
	var target := clampf(speed / 3.0, 0.0, 1.0)
	var bright := 0.02 + 0.06 * clampf(speed / 10.0, 0.0, 1.0)
	for i in _pb.get_frames_available():
		_level += (target - _level) * 0.0005
		# the tyres: noise, low-passed, opening up with the speed
		_hiss += (_rng.randf() * 2.0 - 1.0 - _hiss) * bright
		var s := _hiss * 0.9 * _level
		if pedalling and speed > 0.2:
			# the chain: a soft knock per link over the ring
			_link += crank_hz * CHAINRING * dt
			if _link >= 1.0:
				_link -= 1.0
				_rattle = _rng.randf_range(0.2, 0.5)
			# the crank: an old pedal creaks on the down stroke, not every time
			_crank += crank_hz * dt
			if _crank >= 1.0:
				_crank -= 1.0
				if _rng.randf() < 0.55:
					_creak = 1.0
		elif speed > 0.3:
			# coasting: the pawls click over the ratchet
			_ratchet += wheel_hz * RATCHET * dt
			if _ratchet >= 1.0:
				_ratchet -= 1.0
				_click = 1.0
		if speed > 3.0 and _rng.randf() < 0.25 * dt:
			_tink = 1.0   # a loose mudguard on a bump
		if _rattle > 0.001:
			s += (_rng.randf() * 2.0 - 1.0) * _rattle * 0.25
			_rattle *= 0.985
		if _click > 0.001:
			_click_phase += TAU * 3100.0 * dt
			s += sin(_click_phase) * _click * 0.45 + (_rng.randf() - 0.5) * _click * 0.25
			_click *= 0.985   # about 3 ms
		if _creak > 0.001:
			_creak_phase += TAU * (780.0 - 180.0 * (1.0 - _creak)) * dt
			s += sin(_creak_phase) * sin(_creak_phase * 0.5) * _creak * 0.12
			_creak *= 0.9996   # about a tenth of a second, falling in pitch
		if _tink > 0.001:
			_tink_phase += TAU * 2400.0 * dt
			s += sin(_tink_phase) * _tink * 0.15
			_tink *= 0.9993
		s = clampf(s, -1.0, 1.0)
		_pb.push_frame(Vector2(s, s))
