class_name SoundBank
## Small, natural-sounding effects synthesised at start-up (no bleeps): a latch clunk when a job is
## done, a switch click, a ratchet, a soft sack thud, a gentle low bell for rewards and a loop of
## rust grit pouring while you unload.

const RATE := 22050


static func make(name: String) -> AudioStreamWAV:
	match name:
		"latch":
			return _latch()
		"click":
			return _click()
		"ratchet":
			return _ratchet()
		"sack":
			return _sack()
		"bell":
			return _bell()
		"pour":
			return _pour()
	return null


static func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = samples.size()
	return w


static func _buf(seconds: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(seconds * RATE))
	return s


## Adds a damped knock: a short noise tick through a one-pole low-pass plus a decaying tone.
static func _knock(s: PackedFloat32Array, at: float, tone_hz: float, decay: float, amp: float, bright := 0.3) -> void:
	var start := int(at * RATE)
	var lp := 0.0
	var phase := 0.0
	for i in range(start, mini(start + int(RATE * 6.0 / decay), s.size())):
		var t := float(i - start) / RATE
		var env := exp(-decay * t)
		lp += (randf_range(-1.0, 1.0) - lp) * bright
		phase += TAU * tone_hz * (1.0 - 0.25 * minf(t * 8.0, 1.0)) / RATE  # pitch sags a little
		s[i] += amp * env * (0.55 * sin(phase) + 0.45 * lp * exp(-decay * 3.0 * t))


static func _latch() -> AudioStreamWAV:
	var s := _buf(0.45)
	_knock(s, 0.0, 180.0, 40.0, 0.35, 0.55)  # catch
	_knock(s, 0.07, 72.0, 14.0, 0.75, 0.2)  # body settles
	return _wav(s)


static func _click() -> AudioStreamWAV:
	var s := _buf(0.09)
	_knock(s, 0.0, 1900.0, 160.0, 0.3, 0.8)
	_knock(s, 0.025, 1300.0, 200.0, 0.18, 0.8)
	return _wav(s)


static func _ratchet() -> AudioStreamWAV:
	var s := _buf(0.6)
	for k in 7:
		_knock(s, k * 0.075, 900.0 + randf_range(-80.0, 80.0), 120.0, 0.28, 0.7)
	_knock(s, 0.53, 140.0, 30.0, 0.3, 0.3)
	return _wav(s)


static func _sack() -> AudioStreamWAV:
	var s := _buf(0.4)
	# Grit in a cloth bag: a dull low thump and a short dry hiss.
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += (randf_range(-1.0, 1.0) - lp) * 0.12
		s[i] = 0.55 * sin(TAU * 58.0 * t) * exp(-22.0 * t) + 0.9 * lp * exp(-14.0 * t)
	return _wav(s)


## Two soft sine-bell strikes a fourth apart (G3, C4) with a slow decay: calm, not a fanfare.
static func _bell() -> AudioStreamWAV:
	var s := _buf(2.2)
	for note in [[0.0, 196.0], [0.16, 261.63]]:
		var start := int(float(note[0]) * RATE)
		var f: float = note[1]
		for i in range(start, s.size()):
			var t := float(i - start) / RATE
			var env := minf(t / 0.006, 1.0) * exp(-2.2 * t)
			s[i] += 0.16 * env * (sin(TAU * f * t) + 0.35 * sin(TAU * f * 2.0 * t) * exp(-3.0 * t) + 0.12 * sin(TAU * f * 2.76 * t) * exp(-5.0 * t))
	return _wav(s)


## Rust grit sliding out of a chute: band-limited noise with random grain swells. 1.5 s, looped
## with a crossfade so the seam is inaudible.
static func _pour() -> AudioStreamWAV:
	var n := int(1.5 * RATE)
	var fade := int(0.15 * RATE)
	var raw := _buf(1.5 + 0.15)
	var lp := 0.0
	var lp2 := 0.0
	var swell := 0.6
	for i in raw.size():
		if i % 400 == 0:
			swell = clampf(swell + randf_range(-0.25, 0.25), 0.35, 1.0)
		lp += (randf_range(-1.0, 1.0) - lp) * 0.35
		lp2 += (lp - lp2) * 0.5
		var grain := 1.0 if randf() > 0.995 else 0.0
		raw[i] = 0.32 * swell * (lp - lp2 * 0.6) + 0.25 * grain * randf_range(-1.0, 1.0)
	var s := _buf(1.5)
	for i in n:
		s[i] = raw[i]
		if i < fade:
			var k := float(i) / fade
			s[i] = raw[i] * k + raw[n + i] * (1.0 - k)
	return _wav(s, true)
