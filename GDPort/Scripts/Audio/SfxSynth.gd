class_name SfxSynth
extends RefCounted
## Procedural sound synthesis: builds every SfxId as a 16-bit mono AudioStreamWAV, no audio files needed.
## The "physical" character comes from modal synthesis (damped resonant partials for wood, stone, metal, glass, bells)
## combined with filtered noise (paper, air, fire, rubble) and sparse crackles. Every partial has a soft attack and
## each sound is gently low-passed so nothing clicks or sounds harsh.
## Port note: everything runs single-threaded (web build). Exponential envelopes / sweeps are evaluated with
## per-sample multiplicative recurrences instead of exp()/pow() per sample (mathematically identical, faster).

const SAMPLE_RATE := 44100

enum Filter { LOW, BAND, HIGH }


## Topology-preserving state variable filter (stable while the cutoff sweeps).
## process() writes its outputs to low / band / high (C# out parameters).
class Svf:
	var _ic1: float = 0.0
	var _ic2: float = 0.0
	var low: float = 0.0
	var band: float = 0.0
	var high: float = 0.0

	func process(x: float, cutoff: float, q: float) -> void:
		var g: float = tan(PI * clampf(cutoff, 20.0, SAMPLE_RATE * 0.45) / SAMPLE_RATE)
		var k: float = 1.0 / maxf(0.05, q)
		var a1: float = 1.0 / (1.0 + g * (g + k))
		var a2: float = g * a1
		var a3: float = g * a2
		var v3: float = x - _ic2
		var v1: float = a1 * _ic1 + a2 * v3
		var v2: float = _ic2 + a2 * _ic1 + a3 * v3
		_ic1 = 2.0 * v1 - _ic1
		_ic2 = 2.0 * v2 - _ic2
		low = v2
		band = v1 * k
		high = x - k * v1 - v2

	func copy() -> Svf:
		var s := Svf.new()
		s._ic1 = _ic1
		s._ic2 = _ic2
		return s


## Synthesizes the sound and wraps it in a playable stream.
static func create(id: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = id * 7919 + 13
	var smooth_box: Array[float] = [11000.0]
	var b: PackedFloat32Array = _generate(id, rng, smooth_box)
	return _to_stream(b, smooth_box[0])


## smooth_box[0] receives the smoothing cutoff (C# out parameter).
static func _generate(id: int, r: RandomNumberGenerator, smooth_box: Array[float]) -> PackedFloat32Array:
	smooth_box[0] = 11000.0
	var b: PackedFloat32Array
	match id:
		SfxId.CARD_HOVER:
			b = _new(0.14)
			_noise(b, r, 0.0, 0.11, 1.0, Filter.BAND, 2600.0, 1700.0, 0.9, 0.012, 0.035)
			_noise(b, r, 0.0, 0.1, 0.35, Filter.LOW, 700.0, 500.0, 0.7, 0.01, 0.03)
			smooth_box[0] = 7000.0

		SfxId.CARD_PICK:
			b = _new(0.18)
			_noise(b, r, 0.0, 0.06, 1.0, Filter.BAND, 4200.0, 2400.0, 1.2, 0.002, 0.018)
			_noise(b, r, 0.004, 0.08, 0.6, Filter.BAND, 1500.0, 1200.0, 0.8, 0.003, 0.03)
			_mode(b, 0.0, 170.0, 0.03, 0.5, 0.002, 120.0, 0.03)

		SfxId.CARD_DEAL:
			b = _new(0.4)
			_noise(b, r, 0.0, 0.3, 1.0, Filter.BAND, 700.0, 3200.0, 0.7, 0.09, 0.07)
			_noise(b, r, 0.2, 0.05, 0.5, Filter.BAND, 3500.0, 3000.0, 1.5, 0.001, 0.012)
			smooth_box[0] = 9000.0

		SfxId.CARD_FLIP:
			b = _new(0.2)
			_noise(b, r, 0.0, 0.04, 1.0, Filter.BAND, 3000.0, 2800.0, 1.5, 0.001, 0.01)
			_noise(b, r, 0.035, 0.1, 0.6, Filter.BAND, 1800.0, 1200.0, 1.0, 0.004, 0.03)
			_mode(b, 0.035, 220.0, 0.03, 0.35)

		SfxId.BUTTON_CLICK:
			b = _new(0.12)
			_mode(b, 0.0, 1050.0, 0.012, 1.0, 0.0008)
			_mode(b, 0.0, 2300.0, 0.006, 0.5, 0.0008)
			_mode(b, 0.0, 420.0, 0.02, 0.5, 0.001)
			_noise(b, r, 0.0, 0.02, 0.4, Filter.LOW, 4000.0, 4000.0, 0.7, 0.0005, 0.003)

		SfxId.END_TURN:
			b = _new(1.5)
			_mode(b, 0.0, 240.0, 0.06, 1.0, 0.001, 180.0, 0.02)
			_mode(b, 0.0, 520.0, 0.03, 0.5, 0.001)
			_noise(b, r, 0.0, 0.03, 0.5, Filter.LOW, 2000.0, 2000.0, 0.7, 0.0008, 0.01)
			_bell(b, 0.05, 523.25, 0.5, 1.0)

		SfxId.COIN:
			b = _new(0.7)
			_coin_clink(b, r, 0.0, 1.0, 1.0)
			_coin_clink(b, r, 0.055, 0.4, 1.012)

		SfxId.TURN_START:
			b = _new(2.0)
			_bell(b, 0.0, 392.0, 1.0, 1.2)
			_bell(b, 0.09, 587.33, 0.45, 0.9)
			_noise(b, r, 0.0, 0.8, 0.2, Filter.LOW, 300.0, 300.0, 0.7, 0.2, 0.4)

		SfxId.TURN_ENEMY:
			b = _new(2.0)
			_bell(b, 0.0, 233.08, 1.0, 1.3)
			_bell(b, 0.1, 277.18, 0.5, 1.0)
			_mode(b, 0.0, 100.0, 0.3, 0.7, 0.004, 70.0, 0.06)

		SfxId.VICTORY:
			b = _new(3.0)
			var up: Array[float] = [523.25, 659.25, 783.99, 1046.5]
			for i in up.size():
				_bell(b, i * 0.12, up[i], 0.8, 1.0)
			_chime(b, 0.5, 523.25, 0.5, 1.5)
			_chime(b, 0.5, 659.25, 0.45, 1.5)
			_chime(b, 0.5, 783.99, 0.4, 1.5)

		SfxId.DEFEAT:
			b = _new(3.0)
			var down: Array[float] = [440.0, 349.23, 293.66]
			for i in down.size():
				_bell(b, i * 0.25, down[i], 0.8, 1.1)
			_bell(b, 0.75, 146.83, 0.7, 1.6)
			_chime(b, 0.75, 174.61, 0.35, 1.5)
			smooth_box[0] = 6000.0

		SfxId.SUMMON:
			b = _new(0.7)
			_mode(b, 0.0, 150.0, 0.16, 1.0, 0.0015, 92.0, 0.04)
			_mode(b, 0.0, 210.0, 0.08, 0.55, 0.001)
			_mode(b, 0.0, 470.0, 0.045, 0.35, 0.001)
			_mode(b, 0.0, 1150.0, 0.018, 0.2, 0.0008)
			_noise(b, r, 0.0, 0.1, 0.55, Filter.LOW, 1400.0, 900.0, 0.7, 0.001, 0.025)
			_noise(b, r, 0.01, 0.5, 0.25, Filter.LOW, 700.0, 300.0, 0.7, 0.02, 0.2)

		SfxId.STEP:
			b = _new(0.16)
			_mode(b, 0.0, 360.0, 0.025, 0.8, 0.001)
			_mode(b, 0.0, 790.0, 0.015, 0.4, 0.001)
			_mode(b, 0.0, 150.0, 0.035, 0.6, 0.0015)
			_noise(b, r, 0.0, 0.02, 0.35, Filter.LOW, 3000.0, 3000.0, 0.7, 0.0005, 0.004)
			smooth_box[0] = 8000.0

		SfxId.LAND:
			b = _new(0.3)
			_mode(b, 0.0, 170.0, 0.06, 1.0, 0.0015, 120.0, 0.03)
			_mode(b, 0.0, 300.0, 0.04, 0.6, 0.001)
			_mode(b, 0.0, 700.0, 0.02, 0.3, 0.001)
			_noise(b, r, 0.0, 0.05, 0.5, Filter.LOW, 1800.0, 1800.0, 0.7, 0.001, 0.012)
			_noise(b, r, 0.005, 0.2, 0.2, Filter.LOW, 600.0, 400.0, 0.7, 0.01, 0.08)
			smooth_box[0] = 8000.0

		SfxId.BLOCKED:
			b = _new(0.3)
			_mode(b, 0.0, 180.0, 0.07, 1.0, 0.0015, 140.0, 0.02)
			_mode(b, 0.0, 310.0, 0.045, 0.6, 0.001)
			_mode(b, 0.0, 655.0, 0.02, 0.3, 0.001)
			_noise(b, r, 0.0, 0.05, 0.5, Filter.LOW, 900.0, 900.0, 0.7, 0.001, 0.015)
			smooth_box[0] = 6000.0

		SfxId.PUSH:
			b = _new(0.5)
			_noise(b, r, 0.0, 0.35, 0.7, Filter.BAND, 500.0, 350.0, 0.9, 0.03, 0.18, true)
			_crackle(b, r, 0.0, 0.3, 300.0, 0.3, 6.0, 2500.0)
			_mode(b, 0.0, 140.0, 0.12, 1.0, 0.0015, 95.0, 0.03)
			_mode(b, 0.0, 230.0, 0.05, 0.4, 0.001)

		SfxId.SWING:
			b = _new(0.26)
			_noise(b, r, 0.0, 0.22, 1.0, Filter.BAND, 450.0, 1700.0, 1.4, 0.07, 0.045)
			_noise(b, r, 0.0, 0.22, 0.3, Filter.BAND, 900.0, 3000.0, 1.0, 0.07, 0.04)
			smooth_box[0] = 8000.0

		SfxId.MELEE_HIT:
			b = _new(0.55)
			_mode(b, 0.0, 130.0, 0.14, 1.0, 0.001, 75.0, 0.03)
			_noise(b, r, 0.0, 0.15, 0.8, Filter.LOW, 2600.0, 900.0, 0.7, 0.0008, 0.035)
			_mode(b, 0.0, 1280.0, 0.09, 0.18, 0.001)
			_mode(b, 0.0, 2710.0, 0.07, 0.12, 0.001)
			_mode(b, 0.0, 3960.0, 0.05, 0.08, 0.001)
			_mode(b, 0.0, 240.0, 0.05, 0.4, 0.001)

		SfxId.SHOOT:
			b = _new(0.42)
			_mode(b, 0.0, 200.0, 0.09, 0.7, 0.001, 165.0, 0.01)
			_mode(b, 0.0, 330.0, 0.06, 0.35, 0.001)
			_mode(b, 0.0, 495.0, 0.04, 0.2, 0.001)
			_noise(b, r, 0.01, 0.3, 0.7, Filter.BAND, 2400.0, 800.0, 1.1, 0.01, 0.09)
			_noise(b, r, 0.0, 0.02, 0.4, Filter.LOW, 5000.0, 5000.0, 0.7, 0.0005, 0.002)

		SfxId.ARROW_HIT:
			b = _new(0.35)
			_mode(b, 0.0, 300.0, 0.045, 1.0, 0.001, 230.0, 0.015)
			_mode(b, 0.0, 115.0, 0.08, 0.7, 0.0015)
			_noise(b, r, 0.0, 0.05, 0.7, Filter.LOW, 3200.0, 3200.0, 0.7, 0.0008, 0.015)
			_mode(b, 0.0, 900.0, 0.02, 0.25, 0.001)

		SfxId.DAMAGE:
			b = _new(0.35)
			_noise(b, r, 0.0, 0.25, 1.0, Filter.LOW, 500.0, 250.0, 0.8, 0.002, 0.06)
			_mode(b, 0.0, 120.0, 0.09, 0.8, 0.0015, 85.0, 0.03)
			_noise(b, r, 0.0, 0.05, 0.3, Filter.BAND, 1200.0, 1200.0, 0.8, 0.001, 0.02)
			smooth_box[0] = 7000.0

		SfxId.SHIELD_BLOCK:
			b = _new(1.1)
			_mode(b, 0.0, 610.0, 0.32, 1.0, 0.001)
			_mode(b, 0.0, 617.0, 0.3, 0.5, 0.001)
			_mode(b, 0.0, 1475.0, 0.22, 0.6, 0.001)
			_mode(b, 0.0, 2390.0, 0.16, 0.45, 0.001)
			_mode(b, 0.0, 3310.0, 0.11, 0.3, 0.001)
			_mode(b, 0.0, 4620.0, 0.07, 0.2, 0.001)
			_mode(b, 0.0, 140.0, 0.06, 0.5, 0.0015)
			_noise(b, r, 0.0, 0.03, 0.5, Filter.BAND, 3000.0, 3000.0, 0.7, 0.0005, 0.006)

		SfxId.SHIELD_BREAK:
			b = _new(1.0)
			_noise(b, r, 0.0, 0.4, 0.6, Filter.HIGH, 2500.0, 2500.0, 0.7, 0.001, 0.12)
			for i in 26:
				var f: float = 1800.0 * pow(7500.0 / 1800.0, r.randf())
				_mode(b, r.randf() * 0.12, f, _rand(r, 0.03, 0.18), _rand(r, 0.15, 0.4), 0.0008)
			_mode(b, 0.0, 520.0, 0.2, 0.6, 0.001)
			_mode(b, 0.0, 1250.0, 0.14, 0.35, 0.001)
			_mode(b, 0.0, 110.0, 0.06, 0.5, 0.0015)
			_crackle(b, r, 0.0, 0.3, 500.0, 0.4, 10.0, 6000.0)

		SfxId.DEATH:
			b = _new(1.1)
			_mode(b, 0.0, 110.0, 0.25, 1.0, 0.002, 62.0, 0.05)
			_noise(b, r, 0.0, 0.8, 0.7, Filter.LOW, 900.0, 250.0, 0.7, 0.003, 0.3)
			_crackle(b, r, 0.02, 0.7, 600.0, 0.6, 5.0, 2200.0)
			_mode(b, 0.0, 180.0, 0.07, 0.4, 0.001)
			smooth_box[0] = 7000.0

		SfxId.SOUL:
			b = _new(1.3)
			_noise(b, r, 0.0, 1.0, 0.6, Filter.BAND, 600.0, 2600.0, 1.2, 0.3, 0.25)
			_chime(b, 0.25, 1318.5, 0.4, 0.5)
			_chime(b, 0.38, 1760.0, 0.3, 0.5)

		SfxId.ZAP:
			b = _new(0.45)
			_buzz(b, r, 0.0, 0.4, 95.0, 140.0, 1.0, 0.003, 0.12, 2600.0)
			_crackle(b, r, 0.0, 0.3, 900.0, 0.6, 8.0, 7000.0)
			_noise(b, r, 0.0, 0.2, 0.3, Filter.HIGH, 4000.0, 4000.0, 0.7, 0.001, 0.05)
			smooth_box[0] = 9000.0

		SfxId.ECHO_RING:
			b = _new(1.1)
			_chime(b, 0.0, 784.0, 1.0, 0.5)
			_chime(b, 0.12, 787.9, 0.45, 0.4)
			_chime(b, 0.24, 784.0, 0.2, 0.35)

		SfxId.HEAL:
			b = _new(1.5)
			_chime(b, 0.0, 1046.5, 0.8, 0.7)
			_chime(b, 0.07, 1318.5, 0.6, 0.7)
			_chime(b, 0.14, 1568.0, 0.5, 0.8)
			_noise(b, r, 0.0, 1.0, 0.15, Filter.BAND, 5000.0, 7000.0, 1.0, 0.15, 0.3)
			_mode(b, 0.0, 523.25, 0.5, 0.25, 0.05)
			smooth_box[0] = 9000.0

		SfxId.FIRE:
			b = _new(1.0)
			_noise(b, r, 0.0, 0.85, 1.0, Filter.LOW, 350.0, 1900.0, 0.7, 0.05, 0.35)
			_noise(b, r, 0.0, 0.85, 0.4, Filter.BAND, 900.0, 900.0, 0.6, 0.1, 0.3)
			_crackle(b, r, 0.0, 0.8, 70.0, 0.7, 2.0, 4500.0)
			_mode(b, 0.0, 80.0, 0.3, 0.35, 0.03, 55.0, 0.1)
			smooth_box[0] = 8000.0

		SfxId.LAVA_BURN:
			b = _new(0.75)
			_noise(b, r, 0.0, 0.6, 0.6, Filter.HIGH, 3500.0, 3500.0, 0.7, 0.01, 0.3)
			_crackle(b, r, 0.0, 0.5, 120.0, 0.6, 3.0, 5000.0)
			for i in 3:
				var f: float = _rand(r, 300.0, 600.0)
				_mode(b, _rand(r, 0.0, 0.35), f, 0.03, 0.35, 0.002, f * 1.6, 0.02)
			_mode(b, 0.0, 70.0, 0.12, 0.4, 0.004)
			smooth_box[0] = 8000.0

		SfxId.FREEZE:
			b = _new(1.1)
			_noise(b, r, 0.0, 0.05, 0.6, Filter.BAND, 2500.0, 2500.0, 0.8, 0.0008, 0.015)
			for i in 10:
				_mode(b, _rand(r, 0.0, 0.25), _rand(r, 2600.0, 6200.0), _rand(r, 0.12, 0.45), _rand(r, 0.15, 0.35), 0.002)
			_noise(b, r, 0.0, 0.7, 0.3, Filter.HIGH, 6000.0, 6000.0, 0.7, 0.02, 0.25)
			_crackle(b, r, 0.0, 0.25, 400.0, 0.4, 10.0, 8000.0)
			smooth_box[0] = 12000.0

		SfxId.THAW:
			b = _new(0.5)
			_crackle(b, r, 0.0, 0.2, 200.0, 0.5, 6.0, 6000.0)
			_mode(b, 0.08, 1400.0, 0.05, 0.6, 0.002, 2300.0, 0.02)
			_noise(b, r, 0.0, 0.3, 0.15, Filter.HIGH, 5000.0, 5000.0, 0.7, 0.01, 0.1)

		SfxId.CHARGE:
			b = _new(0.85)
			_buzz(b, r, 0.0, 0.7, 60.0, 240.0, 0.8, 0.25, 0.35, 3000.0)
			_mode(b, 0.0, 220.0, 0.3, 0.25, 0.2, 880.0, 0.5)
			_crackle(b, r, 0.1, 0.6, 300.0, 0.4, 1.0, 7000.0)
			smooth_box[0] = 9000.0

		SfxId.CHARGE_RELEASE:
			b = _new(1.1)
			_mode(b, 0.0, 140.0, 0.25, 1.0, 0.0015, 60.0, 0.05)
			_buzz(b, r, 0.0, 0.5, 140.0, 70.0, 0.8, 0.002, 0.2, 3500.0)
			_crackle(b, r, 0.0, 0.4, 1200.0, 0.7, 8.0, 8000.0)
			_noise(b, r, 0.0, 0.5, 0.6, Filter.LOW, 2500.0, 400.0, 0.7, 0.002, 0.2)

		SfxId.WALL_RISE:
			b = _new(1.1)
			_noise(b, r, 0.0, 0.9, 1.0, Filter.LOW, 180.0, 420.0, 0.8, 0.12, 0.35, true)
			_crackle(b, r, 0.0, 0.7, 250.0, 0.5, 2.0, 1600.0)
			_mode(b, 0.45, 100.0, 0.2, 0.9, 0.002, 68.0, 0.04)
			_mode(b, 0.45, 160.0, 0.08, 0.4, 0.0015)
			smooth_box[0] = 6000.0

		SfxId.METEOR_FALL:
			b = _new(0.6)
			_noise(b, r, 0.0, 0.55, 1.0, Filter.BAND, 3200.0, 350.0, 1.3, 0.35, 0.08)
			_noise(b, r, 0.0, 0.55, 0.4, Filter.LOW, 600.0, 600.0, 0.7, 0.3, 0.1)

		SfxId.EXPLOSION:
			b = _new(1.7)
			_mode(b, 0.0, 95.0, 0.55, 1.0, 0.002, 42.0, 0.08)
			_noise(b, r, 0.0, 1.4, 0.9, Filter.LOW, 2400.0, 280.0, 0.7, 0.002, 0.45)
			_crackle(b, r, 0.0, 1.2, 500.0, 0.6, 3.0, 3000.0)
			_mode(b, 0.0, 120.0, 0.12, 0.4, 0.0015)
			smooth_box[0] = 7000.0

		SfxId.BUFF_CAST:
			b = _new(1.0)
			_mode(b, 0.0, 523.0, 0.35, 0.5, 0.08, 1046.0, 0.35)
			_mode(b, 0.0, 784.0, 0.3, 0.3, 0.1, 1568.0, 0.35)
			for i in 8:
				_mode(b, _rand(r, 0.1, 0.5), _rand(r, 2500.0, 6000.0), _rand(r, 0.08, 0.2), _rand(r, 0.1, 0.2), 0.003)
			_noise(b, r, 0.0, 0.8, 0.3, Filter.BAND, 2000.0, 6000.0, 1.0, 0.2, 0.2)

		SfxId.DEBUFF_CAST:
			b = _new(1.0)
			_mode(b, 0.0, 440.0, 0.35, 0.6, 0.05, 247.0, 0.4)
			_mode(b, 0.0, 452.0, 0.35, 0.5, 0.05, 253.0, 0.4)
			_noise(b, r, 0.0, 0.8, 0.35, Filter.BAND, 900.0, 300.0, 1.0, 0.1, 0.3)
			_mode(b, 0.0, 110.0, 0.3, 0.3, 0.05)
			smooth_box[0] = 7000.0

		SfxId.SPELL_FADE:
			b = _new(0.75)
			_noise(b, r, 0.0, 0.6, 0.5, Filter.BAND, 3500.0, 1500.0, 1.0, 0.1, 0.25)
			_chime(b, 0.05, 1568.0, 0.3, 0.3)

		SfxId.TILE_FADE:
			b = _new(0.6)
			_noise(b, r, 0.0, 0.5, 0.6, Filter.LOW, 900.0, 300.0, 0.7, 0.05, 0.2)
			smooth_box[0] = 5000.0

		_:
			b = _new(0.05)
	return b


# ------------------------------------------------------------------ building blocks

static func _new(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(maxi(1, int(seconds * SAMPLE_RATE)))
	b.fill(0.0)
	return b


static func _rand(r: RandomNumberGenerator, min_value: float, max_value: float) -> float:
	return min_value + r.randf() * (max_value - min_value)


## One damped resonant partial (the basic "physical" building block). The frequency glides exponentially
## from f0 to f1 (glide = time constant), the envelope is a soft exponential attack and decay.
static func _mode(b: PackedFloat32Array, start: float, f0: float, decay: float, amp: float, attack: float = 0.002,
		f1: float = -1.0, glide: float = 0.05) -> void:
	if f1 <= 0.0:
		f1 = f0
	var s0: int = int(start * SAMPLE_RATE)
	var length: int = mini(b.size() - s0, int((decay * 7.0 + attack * 3.0) * SAMPLE_RATE))
	var phase: float = 0.0
	var inv_sr: float = 1.0 / SAMPLE_RATE
	# exp(-t / x) evaluated incrementally: value(i) = step^i.
	var glide_exp: float = 1.0
	var glide_step: float = exp(-inv_sr / glide) if glide > 0.0 else 0.0
	var attack_exp: float = 1.0
	var attack_step: float = exp(-inv_sr / attack)
	var decay_exp: float = 1.0
	var decay_step: float = exp(-inv_sr / decay)
	var two_pi_over_sr: float = TAU * inv_sr
	var df: float = f1 - f0
	for i in length:
		var k: float = 1.0 - glide_exp if glide > 0.0 else 1.0
		var f: float = f0 + df * k
		phase += two_pi_over_sr * f
		var env: float = (1.0 - attack_exp) * decay_exp
		b[s0 + i] += amp * env * sin(phase)
		glide_exp *= glide_step
		attack_exp *= attack_step
		decay_exp *= decay_step


## Filtered noise burst. The cutoff sweeps exponentially from cut0 to cut1 over dur; rough = rumbling
## integrated (brown) noise with a grainy amplitude (stone, scraping).
static func _noise(b: PackedFloat32Array, r: RandomNumberGenerator, start: float, dur: float, amp: float, mode: int,
		cut0: float, cut1: float, q: float, attack: float, decay: float, rough: bool = false) -> void:
	var s0: int = int(start * SAMPLE_RATE)
	var length: int = mini(b.size() - s0, int(dur * SAMPLE_RATE))
	var svf := Svf.new()
	var brown: float = 0.0
	var grain: float = 1.0
	var grain_target: float = 1.0
	var fade_len: int = maxi(1, int(0.012 * SAMPLE_RATE))
	var inv_sr: float = 1.0 / SAMPLE_RATE
	var cutoff: float = cut0
	var cutoff_step: float = pow(cut1 / cut0, inv_sr / maxf(0.001, dur))
	var attack_exp: float = 1.0
	var attack_step: float = exp(-inv_sr / attack)
	var decay_exp: float = 1.0
	var decay_step: float = exp(-inv_sr / decay)
	for i in length:
		var white: float = r.randf() * 2.0 - 1.0
		var x: float = white
		if rough:
			brown = brown * 0.985 + white * 0.15
			x = brown * 2.2 + white * 0.25
			if i % 220 == 0:
				grain_target = _rand(r, 0.35, 1.0)
			grain += (grain_target - grain) * 0.004
			x *= grain
		svf.process(x, cutoff, q)
		var y: float
		match mode:
			Filter.LOW:
				y = svf.low
			Filter.BAND:
				y = svf.band
			_:
				y = svf.high
		var env: float = (1.0 - attack_exp) * decay_exp
		if i > length - fade_len:
			env *= (length - i) / float(fade_len)
		b[s0 + i] += amp * env * y
		cutoff *= cutoff_step
		attack_exp *= attack_step
		decay_exp *= decay_step


## Sparse random pops (fire, rubble, ice) whose density decays exponentially, low-passed.
static func _crackle(b: PackedFloat32Array, r: RandomNumberGenerator, start: float, dur: float, rate: float, amp: float,
		decay_rate: float, cutoff: float) -> void:
	var s0: int = int(start * SAMPLE_RATE)
	var length: int = mini(b.size() - s0, int(dur * SAMPLE_RATE))
	var svf := Svf.new()
	var ring: float = 0.0
	var inv_sr: float = 1.0 / SAMPLE_RATE
	var density_exp: float = 1.0
	var density_step: float = exp(-inv_sr * decay_rate)
	for i in length:
		var density: float = rate * density_exp
		if r.randf() < density / SAMPLE_RATE:
			ring = _rand(r, 0.3, 1.0) * (-1.0 if r.randi_range(0, 1) == 0 else 1.0)
		var x: float = ring * (r.randf() * 2.0 - 1.0)
		ring *= 0.93
		svf.process(x, cutoff, 0.8)
		var fade: float = (length - i) / 200.0 if i > length - 200 else 1.0
		b[s0 + i] += amp * 2.5 * svf.low * fade
		density_exp *= density_step


## Electric buzz: jittery soft square wave with flickering amplitude, band-limited.
static func _buzz(b: PackedFloat32Array, r: RandomNumberGenerator, start: float, dur: float, f0: float, f1: float,
		amp: float, attack: float, decay: float, cutoff: float) -> void:
	var s0: int = int(start * SAMPLE_RATE)
	var length: int = mini(b.size() - s0, int(dur * SAMPLE_RATE))
	var svf := Svf.new()
	var phase: float = 0.0
	var jitter: float = 0.0
	var flicker: float = 1.0
	var hold: int = 0
	var inv_sr: float = 1.0 / SAMPLE_RATE
	var f: float = f0
	var f_step: float = pow(f1 / f0, inv_sr / maxf(0.001, dur))
	var attack_exp: float = 1.0
	var attack_step: float = exp(-inv_sr / attack)
	var decay_exp: float = 1.0
	var decay_step: float = exp(-inv_sr / decay)
	var two_pi_over_sr: float = TAU * inv_sr
	for i in length:
		jitter += ((r.randf() * 2.0 - 1.0) * 0.3 - jitter) * 0.01
		phase += two_pi_over_sr * f * (1.0 + jitter)
		hold -= 1
		if hold <= 0:
			hold = r.randi_range(SAMPLE_RATE / 120, SAMPLE_RATE / 40 - 1)
			flicker = _rand(r, 0.3, 1.0)
		var x: float = tanh(3.0 * sin(phase)) * flicker
		svf.process(x, cutoff, 0.7)
		var env: float = (1.0 - attack_exp) * decay_exp
		var fade: float = (length - i) / 300.0 if i > length - 300 else 1.0
		b[s0 + i] += amp * env * fade * (svf.band * 0.8 + svf.low * 0.4)
		f *= f_step
		attack_exp *= attack_step
		decay_exp *= decay_step


## Warm inharmonic bell (hum, fundamental, bar-like upper partials).
static func _bell(b: PackedFloat32Array, start: float, f: float, amp: float, decay: float) -> void:
	_mode(b, start, f * 0.5, decay * 1.3, amp * 0.35, 0.004)
	_mode(b, start, f, decay, amp, 0.003)
	_mode(b, start, f * 1.003, decay * 0.9, amp * 0.35, 0.003)
	_mode(b, start, f * 2.0, decay * 0.6, amp * 0.45, 0.003)
	_mode(b, start, f * 2.76, decay * 0.4, amp * 0.25, 0.002)
	_mode(b, start, f * 5.4, decay * 0.2, amp * 0.1, 0.002)


## Soft, nearly harmonic chime (heal / magic).
static func _chime(b: PackedFloat32Array, start: float, f: float, amp: float, decay: float) -> void:
	_mode(b, start, f, decay, amp, 0.006)
	_mode(b, start, f * 2.0, decay * 0.55, amp * 0.3, 0.005)
	_mode(b, start, f * 3.0, decay * 0.35, amp * 0.12, 0.004)
	_mode(b, start, f * 4.2, decay * 0.2, amp * 0.06, 0.003)


## Small metal coin hitting another coin.
static func _coin_clink(b: PackedFloat32Array, r: RandomNumberGenerator, start: float, amp: float, detune: float) -> void:
	_mode(b, start, 2093.0 * detune, 0.22, amp, 0.0008)
	_mode(b, start, 3157.0 * detune, 0.16, amp * 0.6, 0.0008)
	_mode(b, start, 4570.0 * detune, 0.1, amp * 0.4, 0.0008)
	_mode(b, start, 5980.0 * detune, 0.06, amp * 0.25, 0.0008)
	_noise(b, r, start, 0.01, amp * 0.4, Filter.BAND, 6000.0, 6000.0, 0.8, 0.0003, 0.002)


## DC block, gentle low-pass, normalization, soft saturation, fades and trimming, then 16-bit PCM.
static func _to_stream(b: PackedFloat32Array, smooth_cutoff: float) -> AudioStreamWAV:
	var svf := Svf.new()
	var prev_x: float = 0.0
	var prev_y: float = 0.0
	var peak: float = 0.0
	var count: int = b.size()
	for i in count:
		# One-pole DC blocker, then the smoothing low-pass.
		var x: float = b[i]
		var y: float = x - prev_x + 0.995 * prev_y
		prev_x = x
		prev_y = y
		svf.process(y, smooth_cutoff, 0.6)
		b[i] = svf.low
		peak = maxf(peak, absf(svf.low))
	var gain: float = 0.92 / peak if peak > 1e-6 else 1.0

	var end: int = count
	while end > 1 and absf(b[end - 1] * gain) < 0.0004:
		end -= 1
	end = mini(count, end + 64)
	var fade_in: int = mini(end, 24)
	var fade_out: int = mini(end, int(0.008 * SAMPLE_RATE))

	var bytes := PackedByteArray()
	bytes.resize(end * 2)
	var norm: float = 1.0 / tanh(1.15)
	for i in end:
		var x: float = tanh(b[i] * gain * 1.15) * norm
		if i < fade_in:
			x *= i / float(fade_in)
		if i >= end - fade_out:
			x *= (end - i) / float(fade_out)
		var s: int = clampi(int(x * 32767.0), -32768, 32767)
		bytes.encode_s16(i * 2, s)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	return stream
