using System.Collections.Generic;
using System.Threading.Tasks;
using Godot;

namespace ProjectClaude;

/// <summary>
/// Visual of one tile effect: molten lava (embers, bubbles, heat shimmer, glow), a raised stone wall
/// with rubble, or a glowing healing rune circle with rising sparkles; plus a small duration badge.
/// Ghost mode is a translucent preview without particles/lights/badge (spell and attack previews).
/// Created by TileEffectLayer and OrderOverlay; the node origin is the tile's top center.
/// </summary>
public partial class TileEffectVisual : Node3D
{
	private static readonly Color LavaTimerColor = new Color(1f, 0.5f, 0.12f);
	private static readonly Color WallTimerColor = new Color(0.85f, 0.78f, 0.62f);
	private static readonly Color HealTimerColor = new Color(0.45f, 1f, 0.55f);

	private readonly List<CpuParticles3D> _emitters = new List<CpuParticles3D>();
	private ShaderMaterial _surfaceMat;
	private ShaderMaterial _hazeMat;
	private readonly List<ShaderMaterial> _wallMats = new List<ShaderMaterial>();
	private ShaderMaterial _ghostMat;
	private Node3D _wallRoot;
	private OmniLight3D _light;
	private float _lightBase;
	private Node3D _timer;
	private ShaderMaterial _timerMat;
	private Label3D _timerLabel;
	private float _tileSize = 1f;
	private float _seed;
	private float _time;
	private int _remaining = -1;
	private float _appearLight = 1f;
	private Color _timerColor = Colors.White;
	private Tween _tween;

	/// <summary>Remaining turns shown on the badge (-1 = none).</summary>
	public int Remaining => _remaining;

	/// <summary>The kind of effect shown.</summary>
	public TileEffectType Type { get; private set; }

	/// <summary>True for translucent previews.</summary>
	public bool IsGhost { get; private set; }

	/// <summary>Turn in which the shown effect expires (for diffing), or -1.</summary>
	public int ExpiryTurn { get; set; } = -1;

	/// <summary>True once PlayVanish started (the node frees itself afterwards).</summary>
	public bool IsVanishing { get; private set; }

	/// <summary>Builds the visual. Call once, before or right after adding it to the tree.</summary>
	public void Setup(TileEffectType type, float tileSize, bool ghost, float seed)
	{
		Type = type;
		IsGhost = ghost;
		_tileSize = Mathf.Max(0.1f, tileSize);
		_seed = seed;
		Name = $"{type}{(ghost ? "Ghost" : "")}";
		switch (type)
		{
			case TileEffectType.Lava:
				BuildLava();
				break;
			case TileEffectType.Wall:
				BuildWall();
				break;
			case TileEffectType.Healing:
				BuildHealing();
				break;
			default:
				BuildGeneric();
				break;
		}
		if (!ghost)
		{
			BuildTimer();
		}
	}

	/// <summary>Updates the duration badge: number and lit pips (hidden when turns is below 1).</summary>
	public void SetRemaining(int turns, int total = -1)
	{
		_remaining = turns;
		if (_timer == null)
		{
			return;
		}
		_timer.Visible = turns > 0;
		_timerLabel.Text = turns.ToString();
		int all = Mathf.Clamp(total > 0 ? Mathf.Max(total, turns) : turns, 1, 6);
		_timerMat.SetShaderParameter("total", all);
		_timerMat.SetShaderParameter("lit", Mathf.Clamp(turns, 0, 6));
	}

	/// <summary>Shows the effect fully formed without animation.</summary>
	public void ShowInstant()
	{
		_tween?.Kill();
		SetAppear(1f);
	}

	/// <summary>Animated appearance: lava spreads with a splash, the wall rises with dust, runes bloom.</summary>
	public async Task PlayAppear()
	{
		_tween?.Kill();
		SetAppear(0f);
		Node3D parent = GetParent() as Node3D;
		Vector3 pos = GlobalPosition;
		float duration = Type == TileEffectType.Wall ? 0.32f : 0.38f;
		if (!IsGhost && parent != null)
		{
			switch (Type)
			{
				case TileEffectType.Lava:
					RuleVfx.FireBurst(parent, pos, 0.8f);
					Vfx.Shockwave(parent, pos + new Vector3(0, 0.04f, 0), RuleVfx.FireColor, 1.1f, 0.35f, 0.14f);
					break;
				case TileEffectType.Wall:
					Vfx.DustRing(parent, pos, new Color(0.62f, 0.55f, 0.46f), 0.5f, 16);
					break;
				case TileEffectType.Healing:
					Vfx.Sparkle(parent, pos + new Vector3(0, 0.2f, 0), RuleVfx.HealGold, 14, 0.8f, 0.4f);
					Vfx.GlowFlash(parent, pos + new Vector3(0, 0.15f, 0), RuleVfx.HealColor, 1.4f, 0.35f);
					break;
			}
		}
		_tween = CreateTween();
		Tween.TransitionType trans = Type == TileEffectType.Wall ? Tween.TransitionType.Back : Tween.TransitionType.Cubic;
		_tween.TweenMethod(Callable.From<float>(SetAppear), 0f, 1f, duration).SetTrans(trans).SetEase(Tween.EaseType.Out);
		if (Type == TileEffectType.Wall && !IsGhost)
		{
			_tween.TweenCallback(Callable.From(() =>
			{
				if (GetParent() is Node3D p)
				{
					RuleVfx.RubbleBurst(p, GlobalPosition, 0.6f);
				}
			}));
		}
		await ToSignal(_tween, Tween.SignalName.Finished);
	}

	/// <summary>Animated removal (lava cools to crust, the wall crumbles and sinks, runes fade); frees the node.</summary>
	public async Task PlayVanish()
	{
		if (IsVanishing)
		{
			return;
		}
		IsVanishing = true;
		_tween?.Kill();
		foreach (CpuParticles3D e in _emitters)
		{
			e.Emitting = false;
		}
		if (_timer != null)
		{
			_timer.Visible = false;
		}
		Node3D parent = GetParent() as Node3D;
		Vector3 pos = GlobalPosition;
		if (!IsGhost && parent != null)
		{
			switch (Type)
			{
				case TileEffectType.Lava:
					Vfx.SmokePuff(parent, pos + new Vector3(0, 0.1f, 0), new Color(0.3f, 0.27f, 0.25f), 10, 0.7f);
					break;
				case TileEffectType.Wall:
					RuleVfx.RubbleBurst(parent, pos, 1.1f);
					break;
				case TileEffectType.Healing:
					Vfx.Sparkle(parent, pos + new Vector3(0, 0.2f, 0), RuleVfx.HealColor, 10, 0.7f, 0.4f);
					break;
			}
		}
		_tween = CreateTween();
		_tween.TweenMethod(Callable.From<float>(SetVanish), 0f, 1f, IsGhost ? 0.12f : 0.45f)
			.SetTrans(Tween.TransitionType.Quad).SetEase(Tween.EaseType.In);
		await ToSignal(_tween, Tween.SignalName.Finished);
		QueueFree();
	}

	/// <summary>Short pulse to re-draw attention (effect refreshed on an already active tile).</summary>
	public void Pulse()
	{
		Tween t = CreateTween();
		t.TweenProperty(this, "scale", new Vector3(1.08f, 1.08f, 1.08f), 0.08f);
		t.TweenProperty(this, "scale", Vector3.One, 0.2f).SetTrans(Tween.TransitionType.Back).SetEase(Tween.EaseType.Out);
	}

	public override void _Process(double delta)
	{
		_time += (float)delta;
		if (_light != null && !IsVanishing)
		{
			float flicker = Type == TileEffectType.Lava
				? 0.8f + 0.2f * Mathf.Sin(_time * 7.3f + _seed) + 0.12f * Mathf.Sin(_time * 17.1f)
				: 0.85f + 0.15f * Mathf.Sin(_time * 2.2f + _seed);
			_light.LightEnergy = _lightBase * flicker * _appearLight;
		}
		if (_timer != null && _timer.Visible)
		{
			float s = 1f + 0.05f * Mathf.Sin(_time * 3f + _seed);
			_timer.Scale = Vector3.One * s;
		}
	}

	private void SetAppear(float t)
	{
		_appearLight = t;
		switch (Type)
		{
			case TileEffectType.Lava:
				_surfaceMat?.SetShaderParameter(IsGhost ? "opacity" : "appear", t);
				_hazeMat?.SetShaderParameter("strength", t);
				break;
			case TileEffectType.Healing:
				_surfaceMat?.SetShaderParameter("appear", t);
				break;
			case TileEffectType.Wall:
				if (_wallRoot != null)
				{
					float h = 0.62f;
					_wallRoot.Position = new Vector3(0f, -h * (1f - t), 0f);
					_wallRoot.Scale = new Vector3(1f, Mathf.Max(0.05f, t), 1f);
				}
				break;
			default:
				_surfaceMat?.SetShaderParameter("opacity", t);
				break;
		}
		if (_timer != null)
		{
			_timerMat.SetShaderParameter("alpha", t);
			_timerLabel.Modulate = new Color(_timerColor.R, _timerColor.G, _timerColor.B, t);
			_timerLabel.OutlineModulate = new Color(0.05f, 0.03f, 0.02f, t);
		}
	}

	private void SetVanish(float t)
	{
		_appearLight = 1f - t;
		switch (Type)
		{
			case TileEffectType.Lava:
				if (IsGhost)
				{
					_surfaceMat?.SetShaderParameter("opacity", 1f - t);
				}
				else
				{
					_surfaceMat?.SetShaderParameter("cool", Mathf.Clamp(t * 1.6f, 0f, 1f));
					_surfaceMat?.SetShaderParameter("appear", 1f - Mathf.Clamp((t - 0.45f) / 0.55f, 0f, 1f));
				}
				_hazeMat?.SetShaderParameter("strength", 1f - t);
				break;
			case TileEffectType.Healing:
				_surfaceMat?.SetShaderParameter("opacity", 1f - t);
				_surfaceMat?.SetShaderParameter("appear", 1f + t * 0.3f);
				break;
			case TileEffectType.Wall:
				foreach (ShaderMaterial m in _wallMats)
				{
					m.SetShaderParameter("crumble", t);
				}
				_ghostMat?.SetShaderParameter("opacity", 1f - t);
				if (_wallRoot != null)
				{
					_wallRoot.Position = new Vector3(0f, -0.45f * t * t, 0f);
				}
				break;
			default:
				_surfaceMat?.SetShaderParameter("opacity", 1f - t);
				break;
		}
	}

	// ------------------------------------------------------------------ builders

	private void BuildLava()
	{
		float s = _tileSize * 0.97f;
		_surfaceMat = VfxAssets.CreateMaterial(IsGhost ? "tile_lava_ghost" : "tile_lava", IsGhost ? 6 : 0);
		if (!IsGhost)
		{
			_surfaceMat.SetShaderParameter("seed", _seed);
		}
		AddChild(new MeshInstance3D
		{
			Name = "LavaSurface",
			Mesh = new PlaneMesh { Size = new Vector2(s, s) },
			MaterialOverride = _surfaceMat,
			Position = new Vector3(0, IsGhost ? 0.03f : 0.006f, 0),
			CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
		});
		if (IsGhost)
		{
			return;
		}

		_hazeMat = VfxAssets.CreateMaterial("heat_haze", 1);
		AddChild(new MeshInstance3D
		{
			Name = "HeatHaze",
			Mesh = new PlaneMesh { Size = new Vector2(s * 0.95f, s * 0.95f) },
			MaterialOverride = _hazeMat,
			Position = new Vector3(0, 0.32f, 0),
			CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
		});

		var embers = new CpuParticles3D
		{
			Name = "Embers",
			Mesh = VfxAssets.GlowQuad,
			Amount = 9,
			Lifetime = 1.5f,
			LocalCoords = false,
			Randomness = 0.6f,
			EmissionShape = CpuParticles3D.EmissionShapeEnum.Box,
			EmissionBoxExtents = new Vector3(s * 0.38f, 0.02f, s * 0.38f),
			Direction = Vector3.Up,
			Spread = 22f,
			InitialVelocityMin = 0.35f,
			InitialVelocityMax = 0.85f,
			Gravity = new Vector3(0, 0.12f, 0),
			DampingMin = 0.2f,
			DampingMax = 0.5f,
			ScaleAmountMin = 0.05f,
			ScaleAmountMax = 0.12f,
			ScaleAmountCurve = Vfx.LinearCurve(1f, 0f, 1f),
			ColorRamp = Vfx.Ramp(new Color(1f, 0.9f, 0.5f, 1f), new Color(1f, 0.45f, 0.08f, 0.9f), new Color(0.6f, 0.08f, 0.02f, 0f)),
			CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
			Position = new Vector3(0, 0.05f, 0),
		};
		AddEmitter(embers);

		var bubbles = new CpuParticles3D
		{
			Name = "Bubbles",
			Mesh = VfxAssets.RingQuad,
			Amount = 3,
			Lifetime = 0.8f,
			LocalCoords = false,
			Randomness = 0.8f,
			EmissionShape = CpuParticles3D.EmissionShapeEnum.Box,
			EmissionBoxExtents = new Vector3(s * 0.3f, 0f, s * 0.3f),
			Direction = Vector3.Up,
			Spread = 0f,
			InitialVelocityMin = 0.02f,
			InitialVelocityMax = 0.08f,
			Gravity = Vector3.Zero,
			ScaleAmountMin = 0.12f,
			ScaleAmountMax = 0.22f,
			ScaleAmountCurve = Vfx.LinearCurve(0.2f, 1.2f),
			ColorRamp = Vfx.Ramp(new Color(1f, 0.75f, 0.3f, 0.9f), new Color(1f, 0.4f, 0.05f, 0f)),
			CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
			Position = new Vector3(0, 0.04f, 0),
		};
		AddEmitter(bubbles);

		_light = new OmniLight3D
		{
			Name = "Glow",
			LightColor = new Color(1f, 0.45f, 0.12f),
			OmniRange = 1.3f * _tileSize,
			OmniAttenuation = 1.8f,
			ShadowEnabled = false,
			Position = new Vector3(0, 0.12f, 0),
		};
		_lightBase = 0.55f;
		AddChild(_light);
	}

	private void BuildWall()
	{
		_wallRoot = new Node3D { Name = "Block" };
		AddChild(_wallRoot);
		float ts = _tileSize;
		if (IsGhost)
		{
			_ghostMat = VfxAssets.CreateMaterial("ghost_preview", 6);
			_ghostMat.SetShaderParameter("half_size", new Vector3(0.43f * ts, 0.31f, 0.43f * ts));
			_wallRoot.AddChild(new MeshInstance3D
			{
				Mesh = new BoxMesh { Size = new Vector3(0.86f * ts, 0.62f, 0.86f * ts) },
				MaterialOverride = _ghostMat,
				Position = new Vector3(0, 0.31f, 0),
				CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
			});
			return;
		}

		ShaderMaterial main = CreateWallMaterial(0f);
		ShaderMaterial cap = CreateWallMaterial(1.7f);
		ShaderMaterial rubble = CreateWallMaterial(3.1f);
		_wallRoot.AddChild(new MeshInstance3D
		{
			Name = "Body",
			Mesh = new BoxMesh { Size = new Vector3(0.84f * ts, 0.5f, 0.84f * ts) },
			MaterialOverride = main,
			Position = new Vector3(0, 0.25f, 0),
		});
		_wallRoot.AddChild(new MeshInstance3D
		{
			Name = "Cap",
			Mesh = new BoxMesh { Size = new Vector3(0.9f * ts, 0.12f, 0.9f * ts) },
			MaterialOverride = cap,
			Position = new Vector3(0, 0.55f, 0),
			Rotation = new Vector3(0, 0.05f + 0.04f * Mathf.Sin(_seed), 0),
		});
		// Crenellations on top.
		var merlon = new BoxMesh { Size = new Vector3(0.22f * ts, 0.12f, 0.22f * ts) };
		for (int i = 0; i < 4; i++)
		{
			float sx = (i % 2 == 0) ? -1f : 1f;
			float sz = (i < 2) ? -1f : 1f;
			_wallRoot.AddChild(new MeshInstance3D
			{
				Mesh = merlon,
				MaterialOverride = cap,
				Position = new Vector3(sx * 0.3f * ts, 0.67f, sz * 0.3f * ts),
			});
		}
		// Rubble at the foot.
		var rng = new RandomNumberGenerator { Seed = (ulong)(Mathf.Abs(_seed) * 1000f) + 7ul };
		for (int i = 0; i < 5; i++)
		{
			float ang = Mathf.Tau * i / 5f + rng.RandfRange(-0.4f, 0.4f);
			float size = rng.RandfRange(0.08f, 0.15f);
			var rock = new MeshInstance3D
			{
				Mesh = new BoxMesh { Size = new Vector3(size * 1.3f, size * 0.8f, size) },
				MaterialOverride = rubble,
				Position = new Vector3(Mathf.Cos(ang) * 0.44f * ts, size * 0.35f, Mathf.Sin(ang) * 0.44f * ts),
				Rotation = new Vector3(rng.RandfRange(-0.4f, 0.4f), rng.RandfRange(0f, Mathf.Tau), rng.RandfRange(-0.4f, 0.4f)),
			};
			_wallRoot.AddChild(rock);
		}
		foreach (Node child in _wallRoot.GetChildren())
		{
			if (child is MeshInstance3D mi && mi.Mesh is BoxMesh box)
			{
				mi.SetInstanceShaderParameter("top_size", new Vector2(box.Size.X, box.Size.Z));
			}
		}
	}

	private ShaderMaterial CreateWallMaterial(float seedOffset)
	{
		ShaderMaterial m = VfxAssets.CreateMaterial("stone_wall");
		m.SetShaderParameter("seed", _seed + seedOffset);
		_wallMats.Add(m);
		return m;
	}

	private void BuildHealing()
	{
		float s = _tileSize * 0.97f;
		_surfaceMat = VfxAssets.CreateMaterial("tile_healing", IsGhost ? 6 : 1);
		_surfaceMat.SetShaderParameter("seed", _seed);
		if (IsGhost)
		{
			_surfaceMat.SetShaderParameter("opacity", 0.75f);
			_surfaceMat.SetShaderParameter("hatch", 1f);
		}
		AddChild(new MeshInstance3D
		{
			Name = "Runes",
			Mesh = new PlaneMesh { Size = new Vector2(s, s) },
			MaterialOverride = _surfaceMat,
			Position = new Vector3(0, IsGhost ? 0.03f : 0.012f, 0),
			CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
		});
		if (IsGhost)
		{
			return;
		}
		var sparkles = new CpuParticles3D
		{
			Name = "Sparkles",
			Mesh = VfxAssets.SparkleQuad,
			Amount = 6,
			Lifetime = 1.6f,
			LocalCoords = false,
			Randomness = 0.6f,
			EmissionShape = CpuParticles3D.EmissionShapeEnum.Box,
			EmissionBoxExtents = new Vector3(s * 0.34f, 0.02f, s * 0.34f),
			Direction = Vector3.Up,
			Spread = 12f,
			InitialVelocityMin = 0.25f,
			InitialVelocityMax = 0.5f,
			Gravity = new Vector3(0, 0.05f, 0),
			ScaleAmountMin = 0.07f,
			ScaleAmountMax = 0.15f,
			ScaleAmountCurve = Vfx.LinearCurve(0f, 0f, 1f),
			ColorRamp = Vfx.Ramp(new Color(1f, 1f, 1f, 1f), RuleVfx.HealColor, new Color(RuleVfx.HealGold.R, RuleVfx.HealGold.G, RuleVfx.HealGold.B, 0f)),
			CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
			Position = new Vector3(0, 0.05f, 0),
		};
		AddEmitter(sparkles);
		_light = new OmniLight3D
		{
			Name = "Glow",
			LightColor = RuleVfx.HealColor,
			OmniRange = 1.2f * _tileSize,
			OmniAttenuation = 1.8f,
			ShadowEnabled = false,
			Position = new Vector3(0, 0.3f, 0),
		};
		_lightBase = 0.45f;
		AddChild(_light);
	}

	private void BuildGeneric()
	{
		float s = _tileSize * 0.97f;
		_surfaceMat = VfxAssets.CreateMaterial("highlight", 6);
		_surfaceMat.SetShaderParameter("color", new Color(0.75f, 0.35f, 1f, 0.7f));
		_surfaceMat.SetShaderParameter("pattern", 3);
		AddChild(new MeshInstance3D
		{
			Mesh = new PlaneMesh { Size = new Vector2(s, s) },
			MaterialOverride = _surfaceMat,
			Position = new Vector3(0, 0.03f, 0),
			CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
		});
	}

	private void BuildTimer()
	{
		Color color = Type switch
		{
			TileEffectType.Lava => LavaTimerColor,
			TileEffectType.Wall => WallTimerColor,
			TileEffectType.Healing => HealTimerColor,
			_ => Colors.White,
		};
		Vector3 pos = Type == TileEffectType.Wall
			? new Vector3(0.28f * _tileSize, 0.8f, 0.28f * _tileSize)
			: new Vector3(0.37f * _tileSize, 0.1f, -0.37f * _tileSize);
		_timer = new Node3D { Name = "Timer", Position = pos };
		AddChild(_timer);
		_timerMat = VfxAssets.CreateMaterial("tile_timer", 24);
		_timerMat.SetShaderParameter("color", color);
		_timer.AddChild(new MeshInstance3D
		{
			Mesh = new QuadMesh { Size = new Vector2(0.38f, 0.38f) },
			MaterialOverride = _timerMat,
			CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
		});
		_timerLabel = VfxAssets.CreateLabel("", 64, 0.0031f, Colors.White, 12, 26);
		_timerColor = color.Lightened(0.6f);
		_timerLabel.Modulate = _timerColor;
		_timer.AddChild(_timerLabel);
		_timer.Visible = false;
	}

	private void AddEmitter(CpuParticles3D p)
	{
		AddChild(p);
		p.Emitting = true;
		_emitters.Add(p);
	}
}
