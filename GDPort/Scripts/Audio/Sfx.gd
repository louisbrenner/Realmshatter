class_name Sfx
extends Node
## Sound effect player. Synthesizes all SfxId sounds (SfxSynth) and plays them through a small voice pool on
## a runtime "Sfx" bus with a soft room reverb and a limiter. Each play gets a slight random pitch so repeated
## sounds feel natural; very fast repeats of the same sound are throttled. Use the static Sfx.play from anywhere;
## it is a no-op while no Sfx node is in the tree (e.g. headless self tests).
## Port note: GDScript synthesis is much slower than C#, so instead of building every sound in _ready (a long
## freeze, especially on the single-threaded web build) the sounds are synthesized one per frame in the
## background after _ready; a sound requested before it is ready is synthesized on demand.

const BUS_NAME := "Sfx"
const _VOICE_COUNT := 20

static var _instance: Sfx

## Master volume of all sound effects in dB.
@export var volume_db: float = -3.0

var _streams: Dictionary = {}  # SfxId (int) -> AudioStreamWAV
var _last_played: Dictionary = {}  # SfxId (int) -> float seconds
var _voices: Array[AudioStreamPlayer] = []
var _random: RandomNumberGenerator = RandomNumberGenerator.new()
var _next_voice: int = 0

## Mutes all sound effects (e.g. during --autoplay).
static var muted: bool = false


func _enter_tree() -> void:
	_instance = self


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _ready() -> void:
	_random.randomize()
	_ensure_bus()
	for i in _VOICE_COUNT:
		var voice := AudioStreamPlayer.new()
		voice.name = "Voice%d" % i
		voice.bus = BUS_NAME
		add_child(voice)
		_voices.append(voice)
	_synthesize_all()


## Builds every sound, one per frame, so startup does not freeze.
func _synthesize_all() -> void:
	for id in SfxId.COUNT:
		if not is_inside_tree():
			return
		_get_stream(id)
		await get_tree().process_frame


func _get_stream(id: int) -> AudioStreamWAV:
	if not _streams.has(id):
		_streams[id] = SfxSynth.create(id)
	return _streams[id]


## Plays a sound effect. volume_db_offset is added to the sound's own level, pitch multiplies its random pitch.
static func play(id: int, volume_db_offset: float = 0.0, pitch: float = 1.0) -> void:
	if _instance != null:
		_instance._play_internal(id, volume_db_offset, pitch)


## Plays a sound effect after a delay in seconds (fire and forget).
static func play_delayed(id: int, delay: float, volume_db_offset: float = 0.0, pitch: float = 1.0) -> void:
	var sfx: Sfx = _instance
	if sfx == null or not sfx.is_inside_tree():
		return
	if delay <= 0.0:
		sfx._play_internal(id, volume_db_offset, pitch)
		return
	var timer: SceneTreeTimer = sfx.get_tree().create_timer(delay)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(sfx):
			sfx._play_internal(id, volume_db_offset, pitch)
	)


func _play_internal(id: int, volume_db_offset: float, pitch: float) -> void:
	if muted or id < 0 or id >= SfxId.COUNT or _voices.size() == 0:
		return
	var settings: Vector3 = _settings(id)
	var db: float = settings.x
	var variance: float = settings.y
	var throttle: float = settings.z
	var now: float = Time.get_ticks_msec() / 1000.0
	if _last_played.has(id) and now - float(_last_played[id]) < throttle:
		return
	_last_played[id] = now
	var stream: AudioStreamWAV = _get_stream(id)

	var voice: AudioStreamPlayer = null
	for i in _voices.size():
		var candidate: AudioStreamPlayer = _voices[(_next_voice + i) % _voices.size()]
		if not candidate.playing:
			voice = candidate
			break
	if voice == null:
		voice = _voices[_next_voice]
	_next_voice = (_voices.find(voice) + 1) % _voices.size()

	var random_pitch: float = 1.0 + (_random.randf() * 2.0 - 1.0) * variance
	voice.stream = stream
	voice.volume_db = volume_db + db + volume_db_offset
	voice.pitch_scale = maxf(0.05, random_pitch * pitch)
	voice.play()


## Per-sound mix level (dB) = x, random pitch variance = y and minimum repeat interval (seconds) = z.
static func _settings(id: int) -> Vector3:
	match id:
		SfxId.CARD_HOVER: return Vector3(-17.0, 0.08, 0.04)
		SfxId.CARD_PICK: return Vector3(-9.0, 0.05, 0.04)
		SfxId.CARD_DEAL: return Vector3(-10.0, 0.06, 0.06)
		SfxId.CARD_FLIP: return Vector3(-9.0, 0.06, 0.05)
		SfxId.BUTTON_CLICK: return Vector3(-10.0, 0.04, 0.04)
		SfxId.END_TURN: return Vector3(-7.0, 0.02, 0.2)
		SfxId.COIN: return Vector3(-10.0, 0.05, 0.05)
		SfxId.TURN_START: return Vector3(-9.0, 0.0, 0.5)
		SfxId.TURN_ENEMY: return Vector3(-9.0, 0.0, 0.5)
		SfxId.VICTORY: return Vector3(-5.0, 0.0, 1.0)
		SfxId.DEFEAT: return Vector3(-5.0, 0.0, 1.0)
		SfxId.SUMMON: return Vector3(-5.0, 0.05, 0.05)
		SfxId.STEP: return Vector3(-15.0, 0.1, 0.05)
		SfxId.LAND: return Vector3(-11.0, 0.08, 0.05)
		SfxId.BLOCKED: return Vector3(-8.0, 0.06, 0.06)
		SfxId.PUSH: return Vector3(-7.0, 0.06, 0.06)
		SfxId.SWING: return Vector3(-11.0, 0.08, 0.04)
		SfxId.MELEE_HIT: return Vector3(-5.0, 0.07, 0.04)
		SfxId.SHOOT: return Vector3(-9.0, 0.07, 0.04)
		SfxId.ARROW_HIT: return Vector3(-7.0, 0.07, 0.04)
		SfxId.DAMAGE: return Vector3(-8.0, 0.07, 0.04)
		SfxId.SHIELD_BLOCK: return Vector3(-10.0, 0.04, 0.05)
		SfxId.SHIELD_BREAK: return Vector3(-8.0, 0.04, 0.08)
		SfxId.DEATH: return Vector3(-5.0, 0.06, 0.08)
		SfxId.SOUL: return Vector3(-8.0, 0.03, 0.2)
		SfxId.ZAP: return Vector3(-10.0, 0.08, 0.05)
		SfxId.ECHO_RING: return Vector3(-12.0, 0.02, 0.1)
		SfxId.HEAL: return Vector3(-11.0, 0.03, 0.12)
		SfxId.FIRE: return Vector3(-7.0, 0.08, 0.15)
		SfxId.LAVA_BURN: return Vector3(-9.0, 0.08, 0.1)
		SfxId.FREEZE: return Vector3(-9.0, 0.05, 0.1)
		SfxId.THAW: return Vector3(-13.0, 0.08, 0.08)
		SfxId.CHARGE: return Vector3(-10.0, 0.03, 0.15)
		SfxId.CHARGE_RELEASE: return Vector3(-7.0, 0.04, 0.15)
		SfxId.WALL_RISE: return Vector3(-6.0, 0.05, 0.2)
		SfxId.METEOR_FALL: return Vector3(-7.0, 0.03, 0.2)
		SfxId.EXPLOSION: return Vector3(-3.0, 0.04, 0.2)
		SfxId.BUFF_CAST: return Vector3(-10.0, 0.03, 0.1)
		SfxId.DEBUFF_CAST: return Vector3(-9.0, 0.03, 0.1)
		SfxId.SPELL_FADE: return Vector3(-15.0, 0.05, 0.1)
		SfxId.TILE_FADE: return Vector3(-15.0, 0.08, 0.1)
	return Vector3(-10.0, 0.05, 0.04)


static func _ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS_NAME) >= 0:
		return
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, BUS_NAME)
	AudioServer.set_bus_send(index, &"Master")
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.32
	reverb.damping = 0.65
	reverb.spread = 0.7
	reverb.hipass = 0.25
	reverb.dry = 1.0
	reverb.wet = 0.13
	reverb.predelay_msec = 12.0
	reverb.predelay_feedback = 0.2
	AudioServer.add_bus_effect(index, reverb)
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -0.5
	AudioServer.add_bus_effect(index, limiter)
