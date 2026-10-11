using System;
using System.Threading.Tasks;
using Godot;

namespace Realmshatter;

/// <summary>
/// One-shot effects for the v3 rules (keywords, tile effects, statuses, card returns). Like Vfx, every
/// effect parents itself to the given node, positions itself in world space and frees itself.
/// </summary>
public static class RuleVfx
{
	public static readonly Color FireColor = new Color(1f, 0.45f, 0.08f);
	public static readonly Color IceColor = new Color(0.55f, 0.85f, 1f);
	public static readonly Color ChargeColor = new Color(0.75f, 0.6f, 1f);
	public static readonly Color HealColor = new Color(0.45f, 1f, 0.5f);
	public static readonly Color HealGold = new Color(1f, 0.86f, 0.42f);
	public static readonly Color SoulColor = new Color(0.55f, 1f, 0.9f);
	public static readonly Color StoneColor = new Color(0.55f, 0.5f, 0.44f);

	private static readonly RandomNumberGenerator Rng = new RandomNumberGenerator();
	private static StandardMaterial3D _iceMaterial;
	private static StandardMaterial3D _stoneMaterial;
	private static StandardMaterial3D _rockMaterial;

	private static StandardMaterial3D IceMaterial => _iceMaterial ??= new StandardMaterial3D
	{
		Transparency = BaseMaterial3D.TransparencyEnum.Alpha,
		AlbedoColor = new Color(0.75f, 0.93f, 1f, 0.8f),
		Metallic = 0.2f,
		Roughness = 0.08f,
		EmissionEnabled = true,
		Emission = new Color(0.35f, 0.7f, 1f),
		EmissionEnergyMultiplier = 1.3f,
		RimEnabled = true,
		Rim = 0.8f,
	};

	private static StandardMaterial3D StoneMaterial => _stoneMaterial ??= new StandardMaterial3D
	{
		VertexColorUseAsAlbedo = true,
		AlbedoColor = StoneColor,
		Roughness = 0.95f,
	};

	private static StandardMaterial3D RockMaterial => _rockMaterial ??= new StandardMaterial3D
	{
		AlbedoColor = new Color(0.16f, 0.09f, 0.06f),
		Roughness = 0.8f,
		EmissionEnabled = true,
		Emission = new Color(1f, 0.35f, 0.05f),
		EmissionEnergyMultiplier = 1.6f,
	};

	private static CpuParticles3D Burst(Node3D parent, Vector3 pos, Mesh mesh, int amount, float lifetime)
	{
		var p = new CpuParticles3D
		{
			Mesh = mesh,
			Amount = Math.Max(1, amount),
			Lifetime = lifetime,
			OneShot = true,
			Explosiveness = 1f,
			LocalCoords = false,
			Emitting = false,
			CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
		};
		parent.AddChild(p);
		p.GlobalPosition = pos;
		return p;
	}

	private static void Fire(CpuParticles3D p)
	{
		p.Emitting = true;
		Vfx.AutoFree(p, (float)p.Lifetime + 0.6f);
	}

	/// <summary>Licking flames bursting upward (Burning hits).</summary>
	public static void FireBurst(Node3D parent, Vector3 pos, float power = 1f)
	{
		if (parent == null)
		{
			return;
		}
		CpuParticles3D p = Burst(parent, pos, VfxAssets.GlowQuad, (int)(34 * power), 0.55f);
		p.Explosiveness = 0.8f;
		p.EmissionShape = CpuParticles3D.EmissionShapeEnum.Sphere;
		p.EmissionSphereRadius = 0.25f;
		p.Direction = Vector3.Up;
		p.Spread = 25f;
		p.InitialVelocityMin = 1.2f * power;
		p.InitialVelocityMax = 2.6f * power;
		p.Gravity = new Vector3(0, 1.5f, 0);
		p.DampingMin = 1.5f;
		p.DampingMax = 3f;
		p.ScaleAmountMin = 0.25f;
		p.ScaleAmountMax = 0.5f;
		p.ScaleAmountCurve = Vfx.LinearCurve(0.6f, 0f, 1f);
		p.ColorRamp = Vfx.Ramp(new Color(1f, 0.95f, 0.6f, 1f), FireColor, new Color(0.7f, 0.08f, 0.02f, 0.6f), new Color(0.2f, 0.02f, 0f, 0f));
		Fire(p);
		Vfx.GlowFlash(parent, pos + new Vector3(0, 0.2f, 0), FireColor, 1.6f * power, 0.3f);
		Vfx.SmokePuff(parent, pos + new Vector3(0, 0.4f, 0), new Color(0.2f, 0.15f, 0.12f), 6, 0.6f);
		Vfx.LightFlash(parent, pos + new Vector3(0, 0.6f, 0), FireColor, 3.5f * power, 2.6f, 0.4f);
	}

	/// <summary>Lava eruption on a tile (turn-start lava damage): flames, molten blobs and smoke.</summary>
	public static void LavaEruption(Node3D parent, Vector3 pos)
	{
		if (parent == null)
		{
			return;
		}
		FireBurst(parent, pos, 1.2f);
		CpuParticles3D blobs = Burst(parent, pos + new Vector3(0, 0.05f, 0), VfxAssets.GlowQuad, 16, 0.75f);
		blobs.Direction = Vector3.Up;
		blobs.Spread = 35f;
		blobs.InitialVelocityMin = 2.2f;
		blobs.InitialVelocityMax = 3.8f;
		blobs.Gravity = new Vector3(0, -11f, 0);
		blobs.ScaleAmountMin = 0.12f;
		blobs.ScaleAmountMax = 0.24f;
		blobs.ScaleAmountCurve = Vfx.LinearCurve(1f, 0.3f);
		blobs.ColorRamp = Vfx.Ramp(new Color(1f, 0.85f, 0.4f), new Color(1f, 0.35f, 0.05f), new Color(0.5f, 0.05f, 0f, 0f));
		Fire(blobs);
		Vfx.Shockwave(parent, pos + new Vector3(0, 0.04f, 0), FireColor, 1.1f, 0.35f, 0.14f);
	}

	/// <summary>Ice shatter with crystals sprouting around the base and cold mist (Frozen applied).</summary>
	public static void IceBurst(Node3D parent, Vector3 pos)
	{
		if (parent == null)
		{
			return;
		}
		var shard = new PrismMesh { Size = new Vector3(0.09f, 0.2f, 0.06f), Material = IceMaterial };
		CpuParticles3D p = Burst(parent, pos + new Vector3(0, 0.3f, 0), shard, 18, 0.7f);
		p.EmissionShape = CpuParticles3D.EmissionShapeEnum.Sphere;
		p.EmissionSphereRadius = 0.25f;
		p.Direction = Vector3.Up;
		p.Spread = 70f;
		p.InitialVelocityMin = 1.5f;
		p.InitialVelocityMax = 3.2f;
		p.Gravity = new Vector3(0, -9f, 0);
		p.ParticleFlagRotateY = true;
		p.AngularVelocityMin = -600f;
		p.AngularVelocityMax = 600f;
		p.ScaleAmountCurve = Vfx.LinearCurve(1f, 0f, 1f);
		Fire(p);
		IceCrystals(parent, pos, 7, 0.36f, 0.75f);
		Vfx.Sparkle(parent, pos + new Vector3(0, 0.35f, 0), IceColor, 18, 0.8f, 0.45f);
		Vfx.SmokePuff(parent, pos + new Vector3(0, 0.15f, 0), new Color(0.8f, 0.92f, 1f), 10, 0.7f);
		Vfx.Shockwave(parent, pos + new Vector3(0, 0.04f, 0), IceColor, 1.3f, 0.4f, 0.12f);
		Vfx.GlowFlash(parent, pos + new Vector3(0, 0.35f, 0), IceColor, 1.8f, 0.3f);
		Vfx.LightFlash(parent, pos + new Vector3(0, 0.7f, 0), IceColor, 3f, 3f, 0.45f);
	}

	/// <summary>A ring of ice crystals that grow out of the ground, hold and shrink away.</summary>
	public static void IceCrystals(Node3D parent, Vector3 pos, int count, float radius, float hold)
	{
		if (parent == null)
		{
			return;
		}
		for (int i = 0; i < count; i++)
		{
			float ang = Mathf.Tau * i / count + Rng.RandfRange(-0.2f, 0.2f);
			float h = Rng.RandfRange(0.22f, 0.42f);
			var crystal = new MeshInstance3D
			{
				Mesh = new PrismMesh { Size = new Vector3(0.11f, h, 0.09f) },
				MaterialOverride = IceMaterial,
				CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
			};
			parent.AddChild(crystal);
			var dir = new Vector3(Mathf.Cos(ang), 0f, Mathf.Sin(ang));
			crystal.GlobalPosition = pos + dir * radius + new Vector3(0, h * 0.4f, 0);
			crystal.LookAt(crystal.GlobalPosition + dir, Vector3.Up);
			crystal.RotateObjectLocal(Vector3.Right, -0.45f);
			crystal.Scale = new Vector3(1f, 0.01f, 1f);
			Tween tween = crystal.CreateTween();
			tween.TweenProperty(crystal, "scale", Vector3.One, 0.14f + 0.02f * i).SetTrans(Tween.TransitionType.Back).SetEase(Tween.EaseType.Out);
			tween.TweenInterval(hold);
			tween.TweenProperty(crystal, "scale", new Vector3(0.3f, 0.01f, 0.3f), 0.25f).SetTrans(Tween.TransitionType.Quad).SetEase(Tween.EaseType.In);
			tween.TweenCallback(Callable.From(crystal.QueueFree));
		}
	}

	/// <summary>Small icy crack when Frozen wears off.</summary>
	public static void Thaw(Node3D parent, Vector3 pos)
	{
		if (parent == null)
		{
			return;
		}
		var shard = new PrismMesh { Size = new Vector3(0.06f, 0.12f, 0.05f), Material = IceMaterial };
		CpuParticles3D p = Burst(parent, pos + new Vector3(0, 0.2f, 0), shard, 10, 0.5f);
		p.EmissionShape = CpuParticles3D.EmissionShapeEnum.Sphere;
		p.EmissionSphereRadius = 0.3f;
		p.Direction = Vector3.Up;
		p.Spread = 80f;
		p.InitialVelocityMin = 0.8f;
		p.InitialVelocityMax = 1.8f;
		p.Gravity = new Vector3(0, -8f, 0);
		p.ScaleAmountCurve = Vfx.LinearCurve(1f, 0f);
		Fire(p);
		Vfx.SmokePuff(parent, pos + new Vector3(0, 0.15f, 0), new Color(0.8f, 0.92f, 1f), 6, 0.5f);
	}

	/// <summary>Electric crackle around a point: short lightning arcs radiating out plus a glow.</summary>
	public static void ChargeCrackle(Node3D parent, Vector3 pos, Color color, int arcs = 5, float radius = 0.65f, float duration = 0.35f)
	{
		if (parent == null)
		{
			return;
		}
		float offset = Rng.Randf() * Mathf.Tau;
		for (int i = 0; i < arcs; i++)
		{
			float ang = offset + Mathf.Tau * i / arcs;
			var end = pos + new Vector3(Mathf.Cos(ang) * radius, Rng.RandfRange(-0.1f, 0.35f), Mathf.Sin(ang) * radius);
			var arc = new LightningArc { Name = "Crackle" };
			arc.Setup(pos, end, color, duration * Rng.RandfRange(0.7f, 1.1f));
			parent.AddChild(arc);
		}
		Vfx.GlowFlash(parent, pos, color, 2f, 0.3f);
		Vfx.Sparkle(parent, pos, color, 14, 0.5f, radius * 0.6f);
		Vfx.LightFlash(parent, pos + new Vector3(0, 0.4f, 0), color, 4f, 3f, duration + 0.1f);
	}

	/// <summary>Soft green-gold heal: rising sparkles, a glowing ring and a "+" glyph flash.</summary>
	public static void HealBurst(Node3D parent, Vector3 pos)
	{
		if (parent == null)
		{
			return;
		}
		Vfx.Sparkle(parent, pos + new Vector3(0, 0.25f, 0), HealColor, 18, 0.9f, 0.4f);
		Vfx.Sparkle(parent, pos + new Vector3(0, 0.4f, 0), HealGold, 10, 1.0f, 0.3f);
		Vfx.Shockwave(parent, pos + new Vector3(0, 0.05f, 0), HealColor, 1.1f, 0.5f, 0.1f);
		Vfx.GlowFlash(parent, pos + new Vector3(0, 0.3f, 0), HealColor, 1.5f, 0.35f);
		Vfx.LightFlash(parent, pos + new Vector3(0, 0.6f, 0), HealColor, 2.5f, 2.5f, 0.45f);
	}

	/// <summary>Straight piercing beam between two world points.</summary>
	public static void Beam(Node3D parent, Vector3 from, Vector3 to, Color color, float duration = 0.4f, float width = 0.24f)
	{
		if (parent == null)
		{
			return;
		}
		var beam = new BeamEffect { Name = "Beam" };
		beam.Setup(from, to, color, duration, width);
		parent.AddChild(beam);
		var core = new BeamEffect { Name = "BeamCore" };
		core.Setup(from, to, new Color(1f, 1f, 0.95f), duration * 0.8f, width * 0.35f);
		parent.AddChild(core);
		Vfx.GlowFlash(parent, from, color, 1.2f, 0.2f);
		Vfx.LightFlash(parent, (from + to) * 0.5f + new Vector3(0, 0.4f, 0), color, 3f, 4f, duration);
	}

	/// <summary>Echo: two expanding brass rings and a chime sparkle.</summary>
	public static void EchoRing(Node3D parent, Vector3 pos, Color color)
	{
		if (parent == null)
		{
			return;
		}
		Vfx.Shockwave(parent, pos + new Vector3(0, 0.05f, 0), color, 1.6f, 0.45f, 0.08f);
		Vfx.Shockwave(parent, pos + new Vector3(0, 0.07f, 0), color.Lightened(0.3f), 2.4f, 0.65f, 0.06f);
		CpuParticles3D p = Burst(parent, pos + new Vector3(0, 0.35f, 0), VfxAssets.RingQuad, 3, 0.55f);
		p.Explosiveness = 0.6f;
		p.Gravity = Vector3.Zero;
		p.InitialVelocityMax = 0f;
		p.ScaleAmountMin = 0.8f;
		p.ScaleAmountMax = 0.8f;
		p.ScaleAmountCurve = Vfx.LinearCurve(0.3f, 2.2f);
		p.ColorRamp = Vfx.Ramp(new Color(color.R, color.G, color.B, 0.9f), new Color(color.R, color.G, color.B, 0f));
		Fire(p);
		Vfx.Sparkle(parent, pos + new Vector3(0, 0.4f, 0), color, 10, 0.6f, 0.4f);
	}

	/// <summary>Stone chunks and dust (walls rising or crumbling).</summary>
	public static void RubbleBurst(Node3D parent, Vector3 pos, float power = 1f)
	{
		if (parent == null)
		{
			return;
		}
		var chunk = new BoxMesh { Size = new Vector3(0.09f, 0.07f, 0.08f), Material = StoneMaterial };
		CpuParticles3D p = Burst(parent, pos + new Vector3(0, 0.15f, 0), chunk, (int)(14 * power), 0.8f);
		p.EmissionShape = CpuParticles3D.EmissionShapeEnum.Box;
		p.EmissionBoxExtents = new Vector3(0.4f, 0.15f, 0.4f);
		p.Direction = Vector3.Up;
		p.Spread = 60f;
		p.InitialVelocityMin = 1.2f * power;
		p.InitialVelocityMax = 2.6f * power;
		p.Gravity = new Vector3(0, -12f, 0);
		p.ParticleFlagRotateY = true;
		p.AngularVelocityMin = -500f;
		p.AngularVelocityMax = 500f;
		p.ScaleAmountMin = 0.6f;
		p.ScaleAmountMax = 1.4f;
		p.ScaleAmountCurve = Vfx.LinearCurve(1f, 0.2f, 1f);
		p.ColorRamp = Vfx.Ramp(StoneColor.Lightened(0.15f), StoneColor.Darkened(0.35f));
		Fire(p);
		Vfx.DustRing(parent, pos, new Color(0.62f, 0.55f, 0.46f), 0.5f, (int)(18 * power));
		Vfx.SmokePuff(parent, pos + new Vector3(0, 0.2f, 0), new Color(0.55f, 0.5f, 0.43f), (int)(8 * power), 0.8f);
	}

	/// <summary>Arcane circle flash on the ground (generic tile spell cast).</summary>
	public static void MagicCircle(Node3D parent, Vector3 pos, Color color)
	{
		if (parent == null)
		{
			return;
		}
		Vfx.Shockwave(parent, pos + new Vector3(0, 0.05f, 0), color, 2.2f, 0.5f, 0.06f);
		Vfx.Shockwave(parent, pos + new Vector3(0, 0.06f, 0), color.Lightened(0.4f), 1.2f, 0.35f, 0.1f);
		Vfx.GlowFlash(parent, pos + new Vector3(0, 0.3f, 0), color, 2.2f, 0.35f);
		Vfx.Sparkle(parent, pos + new Vector3(0, 0.3f, 0), color, 16, 0.7f, 0.6f);
	}

	/// <summary>A flaming rock falling from the sky onto 'to'. Completes on impact (caller adds the explosion).</summary>
	public static async Task Meteor(Node3D parent, Vector3 from, Vector3 to, float duration)
	{
		if (parent == null)
		{
			return;
		}
		var root = new Node3D { Name = "Meteor" };
		parent.AddChild(root);
		root.GlobalPosition = from;
		var rock = new MeshInstance3D { Mesh = new SphereMesh { Radius = 0.2f, Height = 0.36f, RadialSegments = 10, Rings = 6 }, MaterialOverride = RockMaterial };
		root.AddChild(rock);
		var glow = new MeshInstance3D { Mesh = VfxAssets.GlowQuad, Scale = Vector3.One * 1.2f, CastShadow = GeometryInstance3D.ShadowCastingSetting.Off };
		glow.SetInstanceShaderParameter("tint", FireColor);
		root.AddChild(glow);
		var light = new OmniLight3D { LightColor = FireColor, LightEnergy = 4f, OmniRange = 4f };
		root.AddChild(light);
		var trail = new CpuParticles3D
		{
			Mesh = VfxAssets.GlowQuad,
			Amount = 70,
			Lifetime = 0.4f,
			LocalCoords = false,
			Spread = 180f,
			InitialVelocityMin = 0.1f,
			InitialVelocityMax = 0.5f,
			Gravity = new Vector3(0, 0.5f, 0),
			ScaleAmountMin = 0.35f,
			ScaleAmountMax = 0.7f,
			ScaleAmountCurve = Vfx.LinearCurve(1f, 0f),
			ColorRamp = Vfx.Ramp(new Color(1f, 0.9f, 0.5f), FireColor, new Color(0.3f, 0.05f, 0.02f, 0f)),
			CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
		};
		root.AddChild(trail);
		trail.Emitting = true;
		Tween tween = root.CreateTween();
		tween.TweenProperty(root, "global_position", to, duration).SetTrans(Tween.TransitionType.Quad).SetEase(Tween.EaseType.In);
		await root.ToSignal(tween, Tween.SignalName.Finished);
		if (!GodotObject.IsInstanceValid(root))
		{
			return;
		}
		trail.Emitting = false;
		rock.Visible = false;
		glow.Visible = false;
		light.Visible = false;
		Vfx.AutoFree(root, 0.5f);
	}

	/// <summary>
	/// Undying: a pale soul wisp rises from 'from' and flies off in an arc toward 'to' (the owner's deck).
	/// Completes when it arrives.
	/// </summary>
	public static async Task SoulWisp(Node3D parent, Vector3 from, Vector3 to, float duration)
	{
		if (parent == null)
		{
			return;
		}
		var root = new Node3D { Name = "SoulWisp" };
		parent.AddChild(root);
		root.GlobalPosition = from;
		var glow = new MeshInstance3D { Mesh = VfxAssets.GlowQuad, Scale = Vector3.One * 0.9f, CastShadow = GeometryInstance3D.ShadowCastingSetting.Off };
		glow.SetInstanceShaderParameter("tint", SoulColor);
		root.AddChild(glow);
		MeshInstance3D skull = VfxAssets.CreateIcon((int)FxIconShape.Skull, 0.36f, new Color(0.85f, 1f, 0.95f), new Color(0f, 0f, 0f, 0f), false, 34);
		root.AddChild(skull);
		var light = new OmniLight3D { LightColor = SoulColor, LightEnergy = 2.5f, OmniRange = 2.5f };
		root.AddChild(light);
		var trail = new CpuParticles3D
		{
			Mesh = VfxAssets.GlowQuad,
			Amount = 50,
			Lifetime = 0.5f,
			LocalCoords = false,
			Spread = 180f,
			InitialVelocityMin = 0.05f,
			InitialVelocityMax = 0.35f,
			Gravity = new Vector3(0, 0.6f, 0),
			ScaleAmountMin = 0.2f,
			ScaleAmountMax = 0.45f,
			ScaleAmountCurve = Vfx.LinearCurve(1f, 0f),
			ColorRamp = Vfx.Ramp(new Color(1f, 1f, 1f, 0.9f), SoulColor, new Color(0.2f, 0.6f, 0.7f, 0f)),
			CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
		};
		root.AddChild(trail);
		trail.Emitting = true;

		Vector3 p1 = from + new Vector3(0, 1.8f, 0);
		Vector3 p2 = to + new Vector3(0, 1.4f, 0);
		Tween tween = root.CreateTween();
		tween.TweenMethod(Callable.From<float>(t =>
		{
			if (!GodotObject.IsInstanceValid(root))
			{
				return;
			}
			float u = 1f - t;
			root.GlobalPosition = from * (u * u * u) + p1 * (3f * u * u * t) + p2 * (3f * u * t * t) + to * (t * t * t)
				+ new Vector3(Mathf.Sin(t * 18f) * 0.08f, 0f, 0f);
			root.Scale = Vector3.One * (1f - 0.45f * t);
		}), 0f, 1f, duration).SetTrans(Tween.TransitionType.Sine).SetEase(Tween.EaseType.InOut);
		await root.ToSignal(tween, Tween.SignalName.Finished);
		if (!GodotObject.IsInstanceValid(root))
		{
			return;
		}
		Vfx.GlowFlash(parent, to, SoulColor, 1.4f, 0.3f);
		trail.Emitting = false;
		glow.Visible = false;
		skull.Visible = false;
		light.Visible = false;
		Vfx.AutoFree(root, 0.6f);
	}

	/// <summary>A small card back flips out of 'from' and flies in an arc to 'to' (card returns to the deck).</summary>
	public static async Task CardToDeck(Node3D parent, Vector3 from, Vector3 to, Color ownerColor, float duration)
	{
		if (parent == null)
		{
			return;
		}
		var root = new Node3D { Name = "CardToDeck" };
		parent.AddChild(root);
		root.GlobalPosition = from;
		var back = new StandardMaterial3D
		{
			AlbedoColor = new Color(0.14f, 0.12f, 0.3f).Lerp(ownerColor, 0.25f),
			Roughness = 0.5f,
			EmissionEnabled = true,
			Emission = ownerColor,
			EmissionEnergyMultiplier = 0.35f,
		};
		root.AddChild(new MeshInstance3D { Mesh = new BoxMesh { Size = new Vector3(0.42f, 0.012f, 0.58f) }, MaterialOverride = VfxAssets.CreateGoldMaterial(0.5f) });
		root.AddChild(new MeshInstance3D { Mesh = new BoxMesh { Size = new Vector3(0.36f, 0.02f, 0.52f) }, MaterialOverride = back });
		var trail = new CpuParticles3D
		{
			Mesh = VfxAssets.SparkleQuad,
			Amount = 20,
			Lifetime = 0.4f,
			LocalCoords = false,
			Spread = 180f,
			InitialVelocityMin = 0.05f,
			InitialVelocityMax = 0.3f,
			Gravity = Vector3.Zero,
			ScaleAmountMin = 0.1f,
			ScaleAmountMax = 0.2f,
			ScaleAmountCurve = Vfx.LinearCurve(1f, 0f),
			ColorRamp = Vfx.Ramp(new Color(1f, 0.9f, 0.6f), new Color(ownerColor.R, ownerColor.G, ownerColor.B, 0f)),
			CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
		};
		root.AddChild(trail);
		trail.Emitting = true;
		root.Scale = Vector3.One * 0.2f;

		float height = 1.1f + 0.08f * from.DistanceTo(to);
		Tween tween = root.CreateTween();
		tween.TweenMethod(Callable.From<float>(t =>
		{
			if (!GodotObject.IsInstanceValid(root))
			{
				return;
			}
			root.GlobalPosition = from.Lerp(to, t) + new Vector3(0, height * 4f * t * (1f - t) + 0.4f * t, 0);
			float s = t < 0.15f ? Mathf.Lerp(0.2f, 1f, t / 0.15f) : Mathf.Lerp(1f, 0.55f, (t - 0.15f) / 0.85f);
			root.Scale = Vector3.One * s;
			root.Rotation = new Vector3(Mathf.Sin(t * Mathf.Pi) * 0.9f, t * Mathf.Tau * 1.5f, 0f);
		}), 0f, 1f, duration).SetTrans(Tween.TransitionType.Sine).SetEase(Tween.EaseType.InOut);
		await root.ToSignal(tween, Tween.SignalName.Finished);
		if (!GodotObject.IsInstanceValid(root))
		{
			return;
		}
		Vfx.GlowFlash(parent, root.GlobalPosition, ownerColor.Lightened(0.4f), 1f, 0.25f);
		root.QueueFree();
	}
}
