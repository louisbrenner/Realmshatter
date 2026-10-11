using System;
using Godot;

namespace Realmshatter;

/// <summary>
/// Procedural sound synthesis: builds every SfxId as a 16-bit mono AudioStreamWav at startup, no audio files needed.
/// The "physical" character comes from modal synthesis (damped resonant partials for wood, stone, metal, glass, bells)
/// combined with filtered noise (paper, air, fire, rubble) and sparse crackles. Every partial has a soft attack and
/// each sound is gently low-passed so nothing clicks or sounds harsh.
/// </summary>
public static class SfxSynth
{
	public const int SampleRate = 44100;

	private enum Filter
	{
		Low,
		Band,
		High,
	}

	/// <summary>Topology-preserving state variable filter (stable while the cutoff sweeps).</summary>
	private struct Svf
	{
		private float _ic1;
		private float _ic2;

		public void Process(float x, float cutoff, float q, out float low, out float band, out float high)
		{
			float g = MathF.Tan(MathF.PI * Math.Clamp(cutoff, 20f, SampleRate * 0.45f) / SampleRate);
			float k = 1f / Math.Max(0.05f, q);
			float a1 = 1f / (1f + g * (g + k));
			float a2 = g * a1;
			float a3 = g * a2;
			float v3 = x - _ic2;
			float v1 = a1 * _ic1 + a2 * v3;
			float v2 = _ic2 + a2 * _ic1 + a3 * v3;
			_ic1 = 2f * v1 - _ic1;
			_ic2 = 2f * v2 - _ic2;
			low = v2;
			band = v1 * k;
			high = x - k * v1 - v2;
		}
	}

	/// <summary>Synthesizes the sound and wraps it in a playable stream.</summary>
	public static AudioStreamWav Create(SfxId id)
	{
		var rng = new Random((int)id * 7919 + 13);
		float[] b = Generate(id, rng, out float smoothCutoff);
		return ToStream(b, smoothCutoff);
	}

	private static float[] Generate(SfxId id, Random r, out float smooth)
	{
		smooth = 11000f;
		float[] b;
		switch (id)
		{
			case SfxId.CardHover:
				b = New(0.14f);
				Noise(b, r, 0f, 0.11f, 1f, Filter.Band, 2600f, 1700f, 0.9f, 0.012f, 0.035f);
				Noise(b, r, 0f, 0.1f, 0.35f, Filter.Low, 700f, 500f, 0.7f, 0.01f, 0.03f);
				smooth = 7000f;
				break;

			case SfxId.CardPick:
				b = New(0.18f);
				Noise(b, r, 0f, 0.06f, 1f, Filter.Band, 4200f, 2400f, 1.2f, 0.002f, 0.018f);
				Noise(b, r, 0.004f, 0.08f, 0.6f, Filter.Band, 1500f, 1200f, 0.8f, 0.003f, 0.03f);
				Mode(b, 0f, 170f, 0.03f, 0.5f, 0.002f, 120f, 0.03f);
				break;

			case SfxId.CardDeal:
				b = New(0.4f);
				Noise(b, r, 0f, 0.3f, 1f, Filter.Band, 700f, 3200f, 0.7f, 0.09f, 0.07f);
				Noise(b, r, 0.2f, 0.05f, 0.5f, Filter.Band, 3500f, 3000f, 1.5f, 0.001f, 0.012f);
				smooth = 9000f;
				break;

			case SfxId.CardFlip:
				b = New(0.2f);
				Noise(b, r, 0f, 0.04f, 1f, Filter.Band, 3000f, 2800f, 1.5f, 0.001f, 0.01f);
				Noise(b, r, 0.035f, 0.1f, 0.6f, Filter.Band, 1800f, 1200f, 1f, 0.004f, 0.03f);
				Mode(b, 0.035f, 220f, 0.03f, 0.35f);
				break;

			case SfxId.ButtonClick:
				b = New(0.12f);
				Mode(b, 0f, 1050f, 0.012f, 1f, 0.0008f);
				Mode(b, 0f, 2300f, 0.006f, 0.5f, 0.0008f);
				Mode(b, 0f, 420f, 0.02f, 0.5f, 0.001f);
				Noise(b, r, 0f, 0.02f, 0.4f, Filter.Low, 4000f, 4000f, 0.7f, 0.0005f, 0.003f);
				break;

			case SfxId.EndTurn:
				b = New(1.5f);
				Mode(b, 0f, 240f, 0.06f, 1f, 0.001f, 180f, 0.02f);
				Mode(b, 0f, 520f, 0.03f, 0.5f, 0.001f);
				Noise(b, r, 0f, 0.03f, 0.5f, Filter.Low, 2000f, 2000f, 0.7f, 0.0008f, 0.01f);
				Bell(b, 0.05f, 523.25f, 0.5f, 1f);
				break;

			case SfxId.Coin:
				b = New(0.7f);
				CoinClink(b, r, 0f, 1f, 1f);
				CoinClink(b, r, 0.055f, 0.4f, 1.012f);
				break;

			case SfxId.TurnStart:
				b = New(2f);
				Bell(b, 0f, 392f, 1f, 1.2f);
				Bell(b, 0.09f, 587.33f, 0.45f, 0.9f);
				Noise(b, r, 0f, 0.8f, 0.2f, Filter.Low, 300f, 300f, 0.7f, 0.2f, 0.4f);
				break;

			case SfxId.TurnEnemy:
				b = New(2f);
				Bell(b, 0f, 233.08f, 1f, 1.3f);
				Bell(b, 0.1f, 277.18f, 0.5f, 1f);
				Mode(b, 0f, 100f, 0.3f, 0.7f, 0.004f, 70f, 0.06f);
				break;

			case SfxId.Victory:
				b = New(3f);
				float[] up = { 523.25f, 659.25f, 783.99f, 1046.5f };
				for (int i = 0; i < up.Length; i++)
				{
					Bell(b, i * 0.12f, up[i], 0.8f, 1f);
				}
				Chime(b, 0.5f, 523.25f, 0.5f, 1.5f);
				Chime(b, 0.5f, 659.25f, 0.45f, 1.5f);
				Chime(b, 0.5f, 783.99f, 0.4f, 1.5f);
				break;

			case SfxId.Defeat:
				b = New(3f);
				float[] down = { 440f, 349.23f, 293.66f };
				for (int i = 0; i < down.Length; i++)
				{
					Bell(b, i * 0.25f, down[i], 0.8f, 1.1f);
				}
				Bell(b, 0.75f, 146.83f, 0.7f, 1.6f);
				Chime(b, 0.75f, 174.61f, 0.35f, 1.5f);
				smooth = 6000f;
				break;

			case SfxId.Summon:
				b = New(0.7f);
				Mode(b, 0f, 150f, 0.16f, 1f, 0.0015f, 92f, 0.04f);
				Mode(b, 0f, 210f, 0.08f, 0.55f, 0.001f);
				Mode(b, 0f, 470f, 0.045f, 0.35f, 0.001f);
				Mode(b, 0f, 1150f, 0.018f, 0.2f, 0.0008f);
				Noise(b, r, 0f, 0.1f, 0.55f, Filter.Low, 1400f, 900f, 0.7f, 0.001f, 0.025f);
				Noise(b, r, 0.01f, 0.5f, 0.25f, Filter.Low, 700f, 300f, 0.7f, 0.02f, 0.2f);
				break;

			case SfxId.Step:
				b = New(0.16f);
				Mode(b, 0f, 360f, 0.025f, 0.8f, 0.001f);
				Mode(b, 0f, 790f, 0.015f, 0.4f, 0.001f);
				Mode(b, 0f, 150f, 0.035f, 0.6f, 0.0015f);
				Noise(b, r, 0f, 0.02f, 0.35f, Filter.Low, 3000f, 3000f, 0.7f, 0.0005f, 0.004f);
				smooth = 8000f;
				break;

			case SfxId.Land:
				b = New(0.3f);
				Mode(b, 0f, 170f, 0.06f, 1f, 0.0015f, 120f, 0.03f);
				Mode(b, 0f, 300f, 0.04f, 0.6f, 0.001f);
				Mode(b, 0f, 700f, 0.02f, 0.3f, 0.001f);
				Noise(b, r, 0f, 0.05f, 0.5f, Filter.Low, 1800f, 1800f, 0.7f, 0.001f, 0.012f);
				Noise(b, r, 0.005f, 0.2f, 0.2f, Filter.Low, 600f, 400f, 0.7f, 0.01f, 0.08f);
				smooth = 8000f;
				break;

			case SfxId.Blocked:
				b = New(0.3f);
				Mode(b, 0f, 180f, 0.07f, 1f, 0.0015f, 140f, 0.02f);
				Mode(b, 0f, 310f, 0.045f, 0.6f, 0.001f);
				Mode(b, 0f, 655f, 0.02f, 0.3f, 0.001f);
				Noise(b, r, 0f, 0.05f, 0.5f, Filter.Low, 900f, 900f, 0.7f, 0.001f, 0.015f);
				smooth = 6000f;
				break;

			case SfxId.Push:
				b = New(0.5f);
				Noise(b, r, 0f, 0.35f, 0.7f, Filter.Band, 500f, 350f, 0.9f, 0.03f, 0.18f, true);
				Crackle(b, r, 0f, 0.3f, 300f, 0.3f, 6f, 2500f);
				Mode(b, 0f, 140f, 0.12f, 1f, 0.0015f, 95f, 0.03f);
				Mode(b, 0f, 230f, 0.05f, 0.4f, 0.001f);
				break;

			case SfxId.Swing:
				b = New(0.26f);
				Noise(b, r, 0f, 0.22f, 1f, Filter.Band, 450f, 1700f, 1.4f, 0.07f, 0.045f);
				Noise(b, r, 0f, 0.22f, 0.3f, Filter.Band, 900f, 3000f, 1f, 0.07f, 0.04f);
				smooth = 8000f;
				break;

			case SfxId.MeleeHit:
				b = New(0.55f);
				Mode(b, 0f, 130f, 0.14f, 1f, 0.001f, 75f, 0.03f);
				Noise(b, r, 0f, 0.15f, 0.8f, Filter.Low, 2600f, 900f, 0.7f, 0.0008f, 0.035f);
				Mode(b, 0f, 1280f, 0.09f, 0.18f, 0.001f);
				Mode(b, 0f, 2710f, 0.07f, 0.12f, 0.001f);
				Mode(b, 0f, 3960f, 0.05f, 0.08f, 0.001f);
				Mode(b, 0f, 240f, 0.05f, 0.4f, 0.001f);
				break;

			case SfxId.Shoot:
				b = New(0.42f);
				Mode(b, 0f, 200f, 0.09f, 0.7f, 0.001f, 165f, 0.01f);
				Mode(b, 0f, 330f, 0.06f, 0.35f, 0.001f);
				Mode(b, 0f, 495f, 0.04f, 0.2f, 0.001f);
				Noise(b, r, 0.01f, 0.3f, 0.7f, Filter.Band, 2400f, 800f, 1.1f, 0.01f, 0.09f);
				Noise(b, r, 0f, 0.02f, 0.4f, Filter.Low, 5000f, 5000f, 0.7f, 0.0005f, 0.002f);
				break;

			case SfxId.ArrowHit:
				b = New(0.35f);
				Mode(b, 0f, 300f, 0.045f, 1f, 0.001f, 230f, 0.015f);
				Mode(b, 0f, 115f, 0.08f, 0.7f, 0.0015f);
				Noise(b, r, 0f, 0.05f, 0.7f, Filter.Low, 3200f, 3200f, 0.7f, 0.0008f, 0.015f);
				Mode(b, 0f, 900f, 0.02f, 0.25f, 0.001f);
				break;

			case SfxId.Damage:
				b = New(0.35f);
				Noise(b, r, 0f, 0.25f, 1f, Filter.Low, 500f, 250f, 0.8f, 0.002f, 0.06f);
				Mode(b, 0f, 120f, 0.09f, 0.8f, 0.0015f, 85f, 0.03f);
				Noise(b, r, 0f, 0.05f, 0.3f, Filter.Band, 1200f, 1200f, 0.8f, 0.001f, 0.02f);
				smooth = 7000f;
				break;

			case SfxId.ShieldBlock:
				b = New(1.1f);
				Mode(b, 0f, 610f, 0.32f, 1f, 0.001f);
				Mode(b, 0f, 617f, 0.3f, 0.5f, 0.001f);
				Mode(b, 0f, 1475f, 0.22f, 0.6f, 0.001f);
				Mode(b, 0f, 2390f, 0.16f, 0.45f, 0.001f);
				Mode(b, 0f, 3310f, 0.11f, 0.3f, 0.001f);
				Mode(b, 0f, 4620f, 0.07f, 0.2f, 0.001f);
				Mode(b, 0f, 140f, 0.06f, 0.5f, 0.0015f);
				Noise(b, r, 0f, 0.03f, 0.5f, Filter.Band, 3000f, 3000f, 0.7f, 0.0005f, 0.006f);
				break;

			case SfxId.ShieldBreak:
				b = New(1f);
				Noise(b, r, 0f, 0.4f, 0.6f, Filter.High, 2500f, 2500f, 0.7f, 0.001f, 0.12f);
				for (int i = 0; i < 26; i++)
				{
					float f = 1800f * MathF.Pow(7500f / 1800f, (float)r.NextDouble());
					Mode(b, (float)r.NextDouble() * 0.12f, f, Rand(r, 0.03f, 0.18f), Rand(r, 0.15f, 0.4f), 0.0008f);
				}
				Mode(b, 0f, 520f, 0.2f, 0.6f, 0.001f);
				Mode(b, 0f, 1250f, 0.14f, 0.35f, 0.001f);
				Mode(b, 0f, 110f, 0.06f, 0.5f, 0.0015f);
				Crackle(b, r, 0f, 0.3f, 500f, 0.4f, 10f, 6000f);
				break;

			case SfxId.Death:
				b = New(1.1f);
				Mode(b, 0f, 110f, 0.25f, 1f, 0.002f, 62f, 0.05f);
				Noise(b, r, 0f, 0.8f, 0.7f, Filter.Low, 900f, 250f, 0.7f, 0.003f, 0.3f);
				Crackle(b, r, 0.02f, 0.7f, 600f, 0.6f, 5f, 2200f);
				Mode(b, 0f, 180f, 0.07f, 0.4f, 0.001f);
				smooth = 7000f;
				break;

			case SfxId.Soul:
				b = New(1.3f);
				Noise(b, r, 0f, 1f, 0.6f, Filter.Band, 600f, 2600f, 1.2f, 0.3f, 0.25f);
				Chime(b, 0.25f, 1318.5f, 0.4f, 0.5f);
				Chime(b, 0.38f, 1760f, 0.3f, 0.5f);
				break;

			case SfxId.Zap:
				b = New(0.45f);
				Buzz(b, r, 0f, 0.4f, 95f, 140f, 1f, 0.003f, 0.12f, 2600f);
				Crackle(b, r, 0f, 0.3f, 900f, 0.6f, 8f, 7000f);
				Noise(b, r, 0f, 0.2f, 0.3f, Filter.High, 4000f, 4000f, 0.7f, 0.001f, 0.05f);
				smooth = 9000f;
				break;

			case SfxId.EchoRing:
				b = New(1.1f);
				Chime(b, 0f, 784f, 1f, 0.5f);
				Chime(b, 0.12f, 787.9f, 0.45f, 0.4f);
				Chime(b, 0.24f, 784f, 0.2f, 0.35f);
				break;

			case SfxId.Heal:
				b = New(1.5f);
				Chime(b, 0f, 1046.5f, 0.8f, 0.7f);
				Chime(b, 0.07f, 1318.5f, 0.6f, 0.7f);
				Chime(b, 0.14f, 1568f, 0.5f, 0.8f);
				Noise(b, r, 0f, 1f, 0.15f, Filter.Band, 5000f, 7000f, 1f, 0.15f, 0.3f);
				Mode(b, 0f, 523.25f, 0.5f, 0.25f, 0.05f);
				smooth = 9000f;
				break;

			case SfxId.Fire:
				b = New(1f);
				Noise(b, r, 0f, 0.85f, 1f, Filter.Low, 350f, 1900f, 0.7f, 0.05f, 0.35f);
				Noise(b, r, 0f, 0.85f, 0.4f, Filter.Band, 900f, 900f, 0.6f, 0.1f, 0.3f);
				Crackle(b, r, 0f, 0.8f, 70f, 0.7f, 2f, 4500f);
				Mode(b, 0f, 80f, 0.3f, 0.35f, 0.03f, 55f, 0.1f);
				smooth = 8000f;
				break;

			case SfxId.LavaBurn:
				b = New(0.75f);
				Noise(b, r, 0f, 0.6f, 0.6f, Filter.High, 3500f, 3500f, 0.7f, 0.01f, 0.3f);
				Crackle(b, r, 0f, 0.5f, 120f, 0.6f, 3f, 5000f);
				for (int i = 0; i < 3; i++)
				{
					float f = Rand(r, 300f, 600f);
					Mode(b, Rand(r, 0f, 0.35f), f, 0.03f, 0.35f, 0.002f, f * 1.6f, 0.02f);
				}
				Mode(b, 0f, 70f, 0.12f, 0.4f, 0.004f);
				smooth = 8000f;
				break;

			case SfxId.Freeze:
				b = New(1.1f);
				Noise(b, r, 0f, 0.05f, 0.6f, Filter.Band, 2500f, 2500f, 0.8f, 0.0008f, 0.015f);
				for (int i = 0; i < 10; i++)
				{
					Mode(b, Rand(r, 0f, 0.25f), Rand(r, 2600f, 6200f), Rand(r, 0.12f, 0.45f), Rand(r, 0.15f, 0.35f), 0.002f);
				}
				Noise(b, r, 0f, 0.7f, 0.3f, Filter.High, 6000f, 6000f, 0.7f, 0.02f, 0.25f);
				Crackle(b, r, 0f, 0.25f, 400f, 0.4f, 10f, 8000f);
				smooth = 12000f;
				break;

			case SfxId.Thaw:
				b = New(0.5f);
				Crackle(b, r, 0f, 0.2f, 200f, 0.5f, 6f, 6000f);
				Mode(b, 0.08f, 1400f, 0.05f, 0.6f, 0.002f, 2300f, 0.02f);
				Noise(b, r, 0f, 0.3f, 0.15f, Filter.High, 5000f, 5000f, 0.7f, 0.01f, 0.1f);
				break;

			case SfxId.Charge:
				b = New(0.85f);
				Buzz(b, r, 0f, 0.7f, 60f, 240f, 0.8f, 0.25f, 0.35f, 3000f);
				Mode(b, 0f, 220f, 0.3f, 0.25f, 0.2f, 880f, 0.5f);
				Crackle(b, r, 0.1f, 0.6f, 300f, 0.4f, 1f, 7000f);
				smooth = 9000f;
				break;

			case SfxId.ChargeRelease:
				b = New(1.1f);
				Mode(b, 0f, 140f, 0.25f, 1f, 0.0015f, 60f, 0.05f);
				Buzz(b, r, 0f, 0.5f, 140f, 70f, 0.8f, 0.002f, 0.2f, 3500f);
				Crackle(b, r, 0f, 0.4f, 1200f, 0.7f, 8f, 8000f);
				Noise(b, r, 0f, 0.5f, 0.6f, Filter.Low, 2500f, 400f, 0.7f, 0.002f, 0.2f);
				break;

			case SfxId.WallRise:
				b = New(1.1f);
				Noise(b, r, 0f, 0.9f, 1f, Filter.Low, 180f, 420f, 0.8f, 0.12f, 0.35f, true);
				Crackle(b, r, 0f, 0.7f, 250f, 0.5f, 2f, 1600f);
				Mode(b, 0.45f, 100f, 0.2f, 0.9f, 0.002f, 68f, 0.04f);
				Mode(b, 0.45f, 160f, 0.08f, 0.4f, 0.0015f);
				smooth = 6000f;
				break;

			case SfxId.MeteorFall:
				b = New(0.6f);
				Noise(b, r, 0f, 0.55f, 1f, Filter.Band, 3200f, 350f, 1.3f, 0.35f, 0.08f);
				Noise(b, r, 0f, 0.55f, 0.4f, Filter.Low, 600f, 600f, 0.7f, 0.3f, 0.1f);
				break;

			case SfxId.Explosion:
				b = New(1.7f);
				Mode(b, 0f, 95f, 0.55f, 1f, 0.002f, 42f, 0.08f);
				Noise(b, r, 0f, 1.4f, 0.9f, Filter.Low, 2400f, 280f, 0.7f, 0.002f, 0.45f);
				Crackle(b, r, 0f, 1.2f, 500f, 0.6f, 3f, 3000f);
				Mode(b, 0f, 120f, 0.12f, 0.4f, 0.0015f);
				smooth = 7000f;
				break;

			case SfxId.BuffCast:
				b = New(1f);
				Mode(b, 0f, 523f, 0.35f, 0.5f, 0.08f, 1046f, 0.35f);
				Mode(b, 0f, 784f, 0.3f, 0.3f, 0.1f, 1568f, 0.35f);
				for (int i = 0; i < 8; i++)
				{
					Mode(b, Rand(r, 0.1f, 0.5f), Rand(r, 2500f, 6000f), Rand(r, 0.08f, 0.2f), Rand(r, 0.1f, 0.2f), 0.003f);
				}
				Noise(b, r, 0f, 0.8f, 0.3f, Filter.Band, 2000f, 6000f, 1f, 0.2f, 0.2f);
				break;

			case SfxId.DebuffCast:
				b = New(1f);
				Mode(b, 0f, 440f, 0.35f, 0.6f, 0.05f, 247f, 0.4f);
				Mode(b, 0f, 452f, 0.35f, 0.5f, 0.05f, 253f, 0.4f);
				Noise(b, r, 0f, 0.8f, 0.35f, Filter.Band, 900f, 300f, 1f, 0.1f, 0.3f);
				Mode(b, 0f, 110f, 0.3f, 0.3f, 0.05f);
				smooth = 7000f;
				break;

			case SfxId.SpellFade:
				b = New(0.75f);
				Noise(b, r, 0f, 0.6f, 0.5f, Filter.Band, 3500f, 1500f, 1f, 0.1f, 0.25f);
				Chime(b, 0.05f, 1568f, 0.3f, 0.3f);
				break;

			case SfxId.TileFade:
				b = New(0.6f);
				Noise(b, r, 0f, 0.5f, 0.6f, Filter.Low, 900f, 300f, 0.7f, 0.05f, 0.2f);
				smooth = 5000f;
				break;

			default:
				b = New(0.05f);
				break;
		}
		return b;
	}

	// ------------------------------------------------------------------ building blocks

	private static float[] New(float seconds) => new float[Math.Max(1, (int)(seconds * SampleRate))];

	private static float Rand(Random r, float min, float max) => min + (float)r.NextDouble() * (max - min);

	/// <summary>
	/// One damped resonant partial (the basic "physical" building block). The frequency glides exponentially
	/// from f0 to f1 (glide = time constant), the envelope is a soft exponential attack and decay.
	/// </summary>
	private static void Mode(float[] b, float start, float f0, float decay, float amp, float attack = 0.002f, float f1 = -1f, float glide = 0.05f)
	{
		if (f1 <= 0f)
		{
			f1 = f0;
		}
		int s0 = (int)(start * SampleRate);
		int len = Math.Min(b.Length - s0, (int)((decay * 7f + attack * 3f) * SampleRate));
		double phase = 0.0;
		for (int i = 0; i < len; i++)
		{
			float t = i / (float)SampleRate;
			float k = glide > 0f ? 1f - MathF.Exp(-t / glide) : 1f;
			float f = f0 + (f1 - f0) * k;
			phase += 2.0 * Math.PI * f / SampleRate;
			float env = (1f - MathF.Exp(-t / attack)) * MathF.Exp(-t / decay);
			b[s0 + i] += amp * env * (float)Math.Sin(phase);
		}
	}

	/// <summary>
	/// Filtered noise burst. The cutoff sweeps exponentially from cut0 to cut1 over dur; brown = rumbling
	/// integrated noise with a grainy amplitude (stone, scraping).
	/// </summary>
	private static void Noise(float[] b, Random r, float start, float dur, float amp, Filter mode, float cut0, float cut1,
		float q, float attack, float decay, bool rough = false)
	{
		int s0 = (int)(start * SampleRate);
		int len = Math.Min(b.Length - s0, (int)(dur * SampleRate));
		var svf = new Svf();
		float brown = 0f;
		float grain = 1f;
		float grainTarget = 1f;
		int fadeLen = Math.Max(1, (int)(0.012f * SampleRate));
		for (int i = 0; i < len; i++)
		{
			float t = i / (float)SampleRate;
			float white = (float)r.NextDouble() * 2f - 1f;
			float x = white;
			if (rough)
			{
				brown = brown * 0.985f + white * 0.15f;
				x = brown * 2.2f + white * 0.25f;
				if (i % 220 == 0)
				{
					grainTarget = Rand(r, 0.35f, 1f);
				}
				grain += (grainTarget - grain) * 0.004f;
				x *= grain;
			}
			float cutoff = cut0 * MathF.Pow(cut1 / cut0, t / Math.Max(0.001f, dur));
			svf.Process(x, cutoff, q, out float low, out float band, out float high);
			float y = mode switch
			{
				Filter.Low => low,
				Filter.Band => band,
				_ => high,
			};
			float env = (1f - MathF.Exp(-t / attack)) * MathF.Exp(-t / decay);
			if (i > len - fadeLen)
			{
				env *= (len - i) / (float)fadeLen;
			}
			b[s0 + i] += amp * env * y;
		}
	}

	/// <summary>Sparse random pops (fire, rubble, ice) whose density decays exponentially, low-passed.</summary>
	private static void Crackle(float[] b, Random r, float start, float dur, float rate, float amp, float decayRate, float cutoff)
	{
		int s0 = (int)(start * SampleRate);
		int len = Math.Min(b.Length - s0, (int)(dur * SampleRate));
		var svf = new Svf();
		float ring = 0f;
		for (int i = 0; i < len; i++)
		{
			float t = i / (float)SampleRate;
			float density = rate * MathF.Exp(-t * decayRate);
			if (r.NextDouble() < density / SampleRate)
			{
				ring = Rand(r, 0.3f, 1f) * (r.Next(2) == 0 ? -1f : 1f);
			}
			float x = ring * ((float)r.NextDouble() * 2f - 1f);
			ring *= 0.93f;
			svf.Process(x, cutoff, 0.8f, out float low, out _, out _);
			float fade = i > len - 200 ? (len - i) / 200f : 1f;
			b[s0 + i] += amp * 2.5f * low * fade;
		}
	}

	/// <summary>Electric buzz: jittery soft square wave with flickering amplitude, band-limited.</summary>
	private static void Buzz(float[] b, Random r, float start, float dur, float f0, float f1, float amp, float attack, float decay, float cutoff)
	{
		int s0 = (int)(start * SampleRate);
		int len = Math.Min(b.Length - s0, (int)(dur * SampleRate));
		var svf = new Svf();
		double phase = 0.0;
		float jitter = 0f;
		float flicker = 1f;
		int hold = 0;
		for (int i = 0; i < len; i++)
		{
			float t = i / (float)SampleRate;
			float f = f0 * MathF.Pow(f1 / f0, t / Math.Max(0.001f, dur));
			jitter += (((float)r.NextDouble() * 2f - 1f) * 0.3f - jitter) * 0.01f;
			phase += 2.0 * Math.PI * f * (1f + jitter) / SampleRate;
			if (--hold <= 0)
			{
				hold = r.Next(SampleRate / 120, SampleRate / 40);
				flicker = Rand(r, 0.3f, 1f);
			}
			float x = MathF.Tanh(3f * (float)Math.Sin(phase)) * flicker;
			svf.Process(x, cutoff, 0.7f, out float low, out float band, out _);
			float env = (1f - MathF.Exp(-t / attack)) * MathF.Exp(-t / decay);
			float fade = i > len - 300 ? (len - i) / 300f : 1f;
			b[s0 + i] += amp * env * fade * (band * 0.8f + low * 0.4f);
		}
	}

	/// <summary>Warm inharmonic bell (hum, fundamental, bar-like upper partials).</summary>
	private static void Bell(float[] b, float start, float f, float amp, float decay)
	{
		Mode(b, start, f * 0.5f, decay * 1.3f, amp * 0.35f, 0.004f);
		Mode(b, start, f, decay, amp, 0.003f);
		Mode(b, start, f * 1.003f, decay * 0.9f, amp * 0.35f, 0.003f);
		Mode(b, start, f * 2f, decay * 0.6f, amp * 0.45f, 0.003f);
		Mode(b, start, f * 2.76f, decay * 0.4f, amp * 0.25f, 0.002f);
		Mode(b, start, f * 5.4f, decay * 0.2f, amp * 0.1f, 0.002f);
	}

	/// <summary>Soft, nearly harmonic chime (heal / magic).</summary>
	private static void Chime(float[] b, float start, float f, float amp, float decay)
	{
		Mode(b, start, f, decay, amp, 0.006f);
		Mode(b, start, f * 2f, decay * 0.55f, amp * 0.3f, 0.005f);
		Mode(b, start, f * 3f, decay * 0.35f, amp * 0.12f, 0.004f);
		Mode(b, start, f * 4.2f, decay * 0.2f, amp * 0.06f, 0.003f);
	}

	/// <summary>Small metal coin hitting another coin.</summary>
	private static void CoinClink(float[] b, Random r, float start, float amp, float detune)
	{
		Mode(b, start, 2093f * detune, 0.22f, amp, 0.0008f);
		Mode(b, start, 3157f * detune, 0.16f, amp * 0.6f, 0.0008f);
		Mode(b, start, 4570f * detune, 0.1f, amp * 0.4f, 0.0008f);
		Mode(b, start, 5980f * detune, 0.06f, amp * 0.25f, 0.0008f);
		Noise(b, r, start, 0.01f, amp * 0.4f, Filter.Band, 6000f, 6000f, 0.8f, 0.0003f, 0.002f);
	}

	/// <summary>DC block, gentle low-pass, normalization, soft saturation, fades and trimming, then 16-bit PCM.</summary>
	private static AudioStreamWav ToStream(float[] b, float smoothCutoff)
	{
		var svf = new Svf();
		float prevX = 0f;
		float prevY = 0f;
		float peak = 0f;
		for (int i = 0; i < b.Length; i++)
		{
			// One-pole DC blocker, then the smoothing low-pass.
			float x = b[i];
			float y = x - prevX + 0.995f * prevY;
			prevX = x;
			prevY = y;
			svf.Process(y, smoothCutoff, 0.6f, out float low, out _, out _);
			b[i] = low;
			peak = Math.Max(peak, Math.Abs(low));
		}
		float gain = peak > 1e-6f ? 0.92f / peak : 1f;

		int end = b.Length;
		while (end > 1 && Math.Abs(b[end - 1] * gain) < 0.0004f)
		{
			end--;
		}
		end = Math.Min(b.Length, end + 64);
		int fadeIn = Math.Min(end, 24);
		int fadeOut = Math.Min(end, (int)(0.008f * SampleRate));

		var bytes = new byte[end * 2];
		for (int i = 0; i < end; i++)
		{
			float x = MathF.Tanh(b[i] * gain * 1.15f) / MathF.Tanh(1.15f);
			if (i < fadeIn)
			{
				x *= i / (float)fadeIn;
			}
			if (i >= end - fadeOut)
			{
				x *= (end - i) / (float)fadeOut;
			}
			short s = (short)Math.Clamp((int)(x * 32767f), short.MinValue, short.MaxValue);
			bytes[i * 2] = (byte)(s & 0xff);
			bytes[i * 2 + 1] = (byte)((s >> 8) & 0xff);
		}
		return new AudioStreamWav
		{
			Format = AudioStreamWav.FormatEnum.Format16Bits,
			MixRate = SampleRate,
			Stereo = false,
			Data = bytes,
		};
	}
}
