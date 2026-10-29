extends Node
## Procedurally generated sound effects (no audio files needed).
## One-shots are baked into AudioStreamWAVs at startup; the engine hum is
## synthesized live through an AudioStreamGenerator.

const RATE := 22050
const VOICES := 10

var _streams := {}
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0

var _engine_player: AudioStreamPlayer
var _engine_playback: AudioStreamGeneratorPlayback
var _engine_freq := 45.0
var _engine_target_freq := 45.0
var _engine_vol := 0.0
var _engine_target_vol := 0.0
var _engine_phase := 0.0

var _screech_player: AudioStreamPlayer
var _screech_target := 0.0
var _rng := RandomNumberGenerator.new()
var _noise_lp := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 1337
	_bake_sounds()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_voices.append(p)

	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.1
	_engine_player = AudioStreamPlayer.new()
	_engine_player.stream = gen
	_engine_player.volume_db = -14.0
	add_child(_engine_player)
	_engine_player.play()
	_engine_playback = _engine_player.get_stream_playback() as AudioStreamGeneratorPlayback

	_screech_player = AudioStreamPlayer.new()
	_screech_player.stream = _streams["screech"]
	_screech_player.volume_db = -80.0
	add_child(_screech_player)
	_screech_player.play()


func play(sound: String, pitch := 1.0, volume_db := 0.0) -> void:
	if not _streams.has(sound):
		return
	var p := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	p.stream = _streams[sound]
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.play()


## rpm: 0..1 (roughly speed ratio), throttle: 0..1, on: whether the engine should be audible.
func set_engine(rpm: float, throttle: float, on := true) -> void:
	_engine_target_freq = 42.0 + 110.0 * clampf(rpm, 0.0, 1.4)
	_engine_target_vol = (0.35 + 0.65 * clampf(throttle, 0.0, 1.0)) if on else 0.0


## intensity: 0..1 tire squeal loudness.
func set_screech(intensity: float) -> void:
	_screech_target = clampf(intensity, 0.0, 1.0)


func _process(delta: float) -> void:
	var cur := db_to_linear(_screech_player.volume_db)
	cur = lerpf(cur, _screech_target * 0.55, 1.0 - exp(-12.0 * delta))
	_screech_player.volume_db = linear_to_db(maxf(cur, 0.0001))
	_screech_player.pitch_scale = 0.9 + 0.2 * _screech_target
	_fill_engine(delta)


func _fill_engine(delta: float) -> void:
	if _engine_playback == null:
		return
	var frames := _engine_playback.get_frames_available()
	var k := 1.0 - exp(-8.0 * delta)
	_engine_freq = lerpf(_engine_freq, _engine_target_freq, k)
	_engine_vol = lerpf(_engine_vol, _engine_target_vol, k)
	for i in frames:
		_engine_phase = fmod(_engine_phase + _engine_freq / RATE, 1.0)
		var ph := _engine_phase * TAU
		# A few harmonics plus a rough pulse give a buzzy little arcade engine.
		var s := sin(ph) * 0.5 + sin(ph * 2.0) * 0.25 + sin(ph * 3.0 + 0.5) * 0.12
		s += (0.18 if _engine_phase < 0.18 else -0.04)
		s *= _engine_vol * 0.6
		_engine_playback.push_frame(Vector2(s, s))


# --- Sound baking ------------------------------------------------------------------

func _bake_sounds() -> void:
	_streams["coin"] = _build(0.14, func(t: float, p: float) -> float:
		var f := 988.0 if t < 0.05 else 1319.0
		return _square(f * t) * 0.35 * (1.0 - p))

	_streams["pickup"] = _build(0.35, func(t: float, p: float) -> float:
		var step := floorf(p * 4.0)
		var f := 523.0 * pow(1.26, step)
		return (sin(TAU * f * t) * 0.6 + _square(f * t) * 0.15) * (1.0 - p * 0.8))

	_streams["combo"] = _build(0.3, func(t: float, p: float) -> float:
		return (sin(TAU * 880.0 * t) * 0.4 + sin(TAU * 1320.0 * t) * 0.3) * pow(1.0 - p, 2.0))

	_streams["bank"] = _build(0.45, func(t: float, p: float) -> float:
		var notes := [523.0, 659.0, 784.0, 1047.0]
		var f: float = notes[mini(int(p * 4.0), 3)]
		return (_square(f * t) * 0.25 + sin(TAU * f * t) * 0.35) * (1.0 - p * 0.7))

	_streams["boost"] = _build(0.5, func(t: float, p: float) -> float:
		var f := 120.0 + 500.0 * p
		return (_rng.randf_range(-1.0, 1.0) * 0.35 + sin(TAU * f * t) * 0.25) * sin(PI * p))

	_streams["crash"] = _build(0.45, func(t: float, p: float) -> float:
		var thump := sin(TAU * (70.0 - 30.0 * p) * t) * 0.8
		return (thump + _rng.randf_range(-1.0, 1.0) * 0.6) * pow(1.0 - p, 3.0))

	_streams["wipeout"] = _build(0.6, func(t: float, p: float) -> float:
		var f := 420.0 - 320.0 * p
		return _saw(f * t) * 0.35 * (1.0 - p))

	_streams["cone"] = _build(0.12, func(t: float, p: float) -> float:
		return (sin(TAU * 260.0 * t) * 0.5 + _rng.randf_range(-1.0, 1.0) * 0.3) * pow(1.0 - p, 2.0))

	_streams["click"] = _build(0.05, func(t: float, p: float) -> float:
		return _square(700.0 * t) * 0.25 * (1.0 - p))

	_streams["beep"] = _build(0.18, func(t: float, p: float) -> float:
		return _square(440.0 * t) * 0.3 * (1.0 - p * 0.5))

	_streams["go"] = _build(0.45, func(t: float, p: float) -> float:
		return _square(880.0 * t) * 0.3 * (1.0 - p))

	_streams["shield"] = _build(0.4, func(t: float, p: float) -> float:
		var f := 300.0 + 900.0 * p
		return sin(TAU * f * t) * 0.4 * (1.0 - p))

	# Looping tire squeal: a vibrato tone over filtered noise. Integer cycle counts keep the loop seamless.
	var screech_fn := func(t: float, _p: float) -> float:
		_noise_lp = lerpf(_noise_lp, _rng.randf_range(-1.0, 1.0), 0.3)
		var tone := sin(TAU * (900.0 * t + 6.0 * sin(TAU * 6.0 * t) / 6.0))
		return tone * 0.35 + _noise_lp * 0.6
	_streams["screech"] = _build(1.0, screech_fn, true)


func _build(duration: float, gen: Callable, loop := false) -> AudioStreamWAV:
	var n := int(duration * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var s: float = gen.call(t, float(i) / n)
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w


static func _square(cycles: float) -> float:
	return 1.0 if fmod(cycles, 1.0) < 0.5 else -1.0


static func _saw(cycles: float) -> float:
	return fmod(cycles, 1.0) * 2.0 - 1.0
