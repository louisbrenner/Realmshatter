using System;
using System.Collections.Generic;
using Godot;

namespace ProjectClaude;

/// <summary>
/// Sound effect player. Synthesizes all SfxId sounds once (SfxSynth) and plays them through a small voice pool on
/// a runtime "Sfx" bus with a soft room reverb and a limiter. Each play gets a slight random pitch so repeated
/// sounds feel natural; very fast repeats of the same sound are throttled. Use the static Sfx.Play from anywhere;
/// it is a no-op while no Sfx node is in the tree (e.g. headless self tests).
/// </summary>
public partial class Sfx : Node
{
	public const string BusName = "Sfx";
	private const int VoiceCount = 20;

	private static Sfx _instance;

	/// <summary>Master volume of all sound effects in dB.</summary>
	[Export] public float VolumeDb { get; set; } = -3f;

	private readonly Dictionary<SfxId, AudioStreamWav> _streams = new Dictionary<SfxId, AudioStreamWav>();
	private readonly Dictionary<SfxId, double> _lastPlayed = new Dictionary<SfxId, double>();
	private readonly List<AudioStreamPlayer> _voices = new List<AudioStreamPlayer>();
	private readonly Random _random = new Random();
	private int _nextVoice;

	/// <summary>Mutes all sound effects (e.g. during --autoplay).</summary>
	public static bool Muted { get; set; }

	public override void _EnterTree()
	{
		_instance = this;
	}

	public override void _ExitTree()
	{
		if (_instance == this)
		{
			_instance = null;
		}
	}

	public override void _Ready()
	{
		EnsureBus();
		foreach (SfxId id in Enum.GetValues<SfxId>())
		{
			_streams[id] = SfxSynth.Create(id);
		}
		for (int i = 0; i < VoiceCount; i++)
		{
			var voice = new AudioStreamPlayer { Name = $"Voice{i}", Bus = BusName };
			AddChild(voice);
			_voices.Add(voice);
		}
	}

	/// <summary>Plays a sound effect. volumeDb is added to the sound's own level, pitch multiplies its random pitch.</summary>
	public static void Play(SfxId id, float volumeDb = 0f, float pitch = 1f)
	{
		_instance?.PlayInternal(id, volumeDb, pitch);
	}

	/// <summary>Plays a sound effect after a delay in seconds (fire and forget).</summary>
	public static void PlayDelayed(SfxId id, float delay, float volumeDb = 0f, float pitch = 1f)
	{
		Sfx sfx = _instance;
		if (sfx == null || !sfx.IsInsideTree())
		{
			return;
		}
		if (delay <= 0f)
		{
			sfx.PlayInternal(id, volumeDb, pitch);
			return;
		}
		SceneTreeTimer timer = sfx.GetTree().CreateTimer(delay);
		timer.Timeout += () =>
		{
			if (IsInstanceValid(sfx))
			{
				sfx.PlayInternal(id, volumeDb, pitch);
			}
		};
	}

	private void PlayInternal(SfxId id, float volumeDb, float pitch)
	{
		if (Muted || !_streams.TryGetValue(id, out AudioStreamWav stream) || _voices.Count == 0)
		{
			return;
		}
		(float db, float variance, float throttle) = Settings(id);
		double now = Time.GetTicksMsec() / 1000.0;
		if (_lastPlayed.TryGetValue(id, out double last) && now - last < throttle)
		{
			return;
		}
		_lastPlayed[id] = now;

		AudioStreamPlayer voice = null;
		for (int i = 0; i < _voices.Count; i++)
		{
			AudioStreamPlayer candidate = _voices[(_nextVoice + i) % _voices.Count];
			if (!candidate.Playing)
			{
				voice = candidate;
				break;
			}
		}
		voice ??= _voices[_nextVoice];
		_nextVoice = (_voices.IndexOf(voice) + 1) % _voices.Count;

		float randomPitch = 1f + ((float)_random.NextDouble() * 2f - 1f) * variance;
		voice.Stream = stream;
		voice.VolumeDb = VolumeDb + db + volumeDb;
		voice.PitchScale = Mathf.Max(0.05f, randomPitch * pitch);
		voice.Play();
	}

	/// <summary>Per-sound mix level (dB), random pitch variance and minimum repeat interval (seconds).</summary>
	private static (float db, float variance, float throttle) Settings(SfxId id) => id switch
	{
		SfxId.CardHover => (-17f, 0.08f, 0.04f),
		SfxId.CardPick => (-9f, 0.05f, 0.04f),
		SfxId.CardDeal => (-10f, 0.06f, 0.06f),
		SfxId.CardFlip => (-9f, 0.06f, 0.05f),
		SfxId.ButtonClick => (-10f, 0.04f, 0.04f),
		SfxId.EndTurn => (-7f, 0.02f, 0.2f),
		SfxId.Coin => (-10f, 0.05f, 0.05f),
		SfxId.TurnStart => (-9f, 0f, 0.5f),
		SfxId.TurnEnemy => (-9f, 0f, 0.5f),
		SfxId.Victory => (-5f, 0f, 1f),
		SfxId.Defeat => (-5f, 0f, 1f),
		SfxId.Summon => (-5f, 0.05f, 0.05f),
		SfxId.Step => (-15f, 0.1f, 0.05f),
		SfxId.Land => (-11f, 0.08f, 0.05f),
		SfxId.Blocked => (-8f, 0.06f, 0.06f),
		SfxId.Push => (-7f, 0.06f, 0.06f),
		SfxId.Swing => (-11f, 0.08f, 0.04f),
		SfxId.MeleeHit => (-5f, 0.07f, 0.04f),
		SfxId.Shoot => (-9f, 0.07f, 0.04f),
		SfxId.ArrowHit => (-7f, 0.07f, 0.04f),
		SfxId.Damage => (-8f, 0.07f, 0.04f),
		SfxId.ShieldBlock => (-10f, 0.04f, 0.05f),
		SfxId.ShieldBreak => (-8f, 0.04f, 0.08f),
		SfxId.Death => (-5f, 0.06f, 0.08f),
		SfxId.Soul => (-8f, 0.03f, 0.2f),
		SfxId.Zap => (-10f, 0.08f, 0.05f),
		SfxId.EchoRing => (-12f, 0.02f, 0.1f),
		SfxId.Heal => (-11f, 0.03f, 0.12f),
		SfxId.Fire => (-7f, 0.08f, 0.15f),
		SfxId.LavaBurn => (-9f, 0.08f, 0.1f),
		SfxId.Freeze => (-9f, 0.05f, 0.1f),
		SfxId.Thaw => (-13f, 0.08f, 0.08f),
		SfxId.Charge => (-10f, 0.03f, 0.15f),
		SfxId.ChargeRelease => (-7f, 0.04f, 0.15f),
		SfxId.WallRise => (-6f, 0.05f, 0.2f),
		SfxId.MeteorFall => (-7f, 0.03f, 0.2f),
		SfxId.Explosion => (-3f, 0.04f, 0.2f),
		SfxId.BuffCast => (-10f, 0.03f, 0.1f),
		SfxId.DebuffCast => (-9f, 0.03f, 0.1f),
		SfxId.SpellFade => (-15f, 0.05f, 0.1f),
		SfxId.TileFade => (-15f, 0.08f, 0.1f),
		_ => (-10f, 0.05f, 0.04f),
	};

	private static void EnsureBus()
	{
		if (AudioServer.GetBusIndex(BusName) >= 0)
		{
			return;
		}
		AudioServer.AddBus();
		int index = AudioServer.BusCount - 1;
		AudioServer.SetBusName(index, BusName);
		AudioServer.SetBusSend(index, "Master");
		AudioServer.AddBusEffect(index, new AudioEffectReverb
		{
			RoomSize = 0.32f,
			Damping = 0.65f,
			Spread = 0.7f,
			Hipass = 0.25f,
			Dry = 1f,
			Wet = 0.13f,
			PredelayMsec = 12f,
			PredelayFeedback = 0.2f,
		});
		AudioServer.AddBusEffect(index, new AudioEffectHardLimiter { CeilingDb = -0.5f });
	}
}
