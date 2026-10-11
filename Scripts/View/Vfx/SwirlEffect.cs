using System.Collections.Generic;
using Godot;

namespace ProjectClaude;

/// <summary>
/// Glowing motes that spiral down into the node's position and finish with a burst
/// (spell cast). Create via Vfx.SpellSwirl; frees itself when done.
/// </summary>
public partial class SwirlEffect : Node3D
{
	private readonly List<MeshInstance3D> _motes = new List<MeshInstance3D>();
	private Color _primary = new Color(0.4f, 1f, 0.5f);
	private Color _secondary = new Color(1f, 0.85f, 0.35f);
	private float _duration = 0.6f;
	private float _radius = 0.65f;
	private int _count = 16;
	private float _time;
	private bool _finished;

	/// <summary>Configures colors and duration. Call before adding to the tree.</summary>
	public void Setup(Color primary, Color secondary, float duration, float radius = 0.65f, int count = 16)
	{
		_primary = primary;
		_secondary = secondary;
		_duration = Mathf.Max(0.1f, duration);
		_radius = radius;
		_count = Mathf.Max(3, count);
	}

	public override void _Ready()
	{
		for (int i = 0; i < _count; i++)
		{
			var mote = new MeshInstance3D
			{
				Mesh = i % 3 == 0 ? VfxAssets.SparkleQuad : VfxAssets.GlowQuad,
				CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
				Scale = Vector3.One * 0.2f,
			};
			mote.SetInstanceShaderParameter("tint", i % 2 == 0 ? _primary : _secondary);
			AddChild(mote);
			_motes.Add(mote);
		}

		var dust = new CpuParticles3D
		{
			Mesh = VfxAssets.GlowQuad,
			Amount = 30,
			Lifetime = 0.4f,
			LocalCoords = false,
			EmissionShape = CpuParticles3D.EmissionShapeEnum.Sphere,
			EmissionSphereRadius = _radius * 0.8f,
			Gravity = new Vector3(0, -0.5f, 0),
			InitialVelocityMin = 0f,
			InitialVelocityMax = 0.2f,
			ScaleAmountMin = 0.1f,
			ScaleAmountMax = 0.22f,
			ScaleAmountCurve = Vfx.LinearCurve(1f, 0f),
			ColorRamp = Vfx.Ramp(_secondary, new Color(_primary.R, _primary.G, _primary.B, 0f)),
			CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
			Position = new Vector3(0, 0.5f, 0),
		};
		AddChild(dust);
		dust.Emitting = true;
		UpdateMotes(0f);
	}

	public override void _Process(double delta)
	{
		if (_finished)
		{
			return;
		}
		_time += (float)delta;
		float t = Mathf.Clamp(_time / _duration, 0f, 1f);
		UpdateMotes(t);
		if (t >= 1f)
		{
			Finish();
		}
	}

	private void UpdateMotes(float t)
	{
		float eased = 1f - (1f - t) * (1f - t);
		for (int i = 0; i < _motes.Count; i++)
		{
			float f = (float)i / _motes.Count;
			float angle = f * Mathf.Tau + eased * Mathf.Tau * 1.6f;
			float r = _radius * (1f - 0.85f * eased) + 0.05f;
			float y = 1.3f * (1f - eased) + 0.3f + 0.15f * Mathf.Sin(f * 17f + t * 6f) * (1f - t);
			_motes[i].Position = new Vector3(Mathf.Cos(angle) * r, y, Mathf.Sin(angle) * r);
			_motes[i].Scale = Vector3.One * (0.3f + 0.12f * Mathf.Sin(t * 12f + f * 9f) * (1f - t) + 0.1f * t);
		}
	}

	private void Finish()
	{
		_finished = true;
		Node3D parent = GetParent() as Node3D;
		Vector3 center = GlobalPosition + new Vector3(0, 0.35f, 0);
		if (parent != null)
		{
			Vfx.Sparkle(parent, center, _primary, 20, 0.7f, 0.35f);
			Vfx.GlowFlash(parent, center, _primary, 1.8f, 0.3f);
			Vfx.Shockwave(parent, new Vector3(center.X, 0.05f, center.Z), _secondary, 1.1f, 0.35f, 0.1f);
			Vfx.LightFlash(parent, center + new Vector3(0, 0.4f, 0), _primary, 3f, 3f, 0.35f);
		}
		foreach (MeshInstance3D mote in _motes)
		{
			mote.Visible = false;
		}
		Vfx.AutoFree(this, 0.5f);
	}
}
