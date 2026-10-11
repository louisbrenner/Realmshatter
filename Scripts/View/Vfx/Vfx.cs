using System;
using System.Threading.Tasks;
using Godot;

namespace ProjectClaude;

/// <summary>
/// Factory for one-shot procedural effects (particles, flashes, popups, projectiles).
/// Every effect parents itself to the given node, positions in world space and frees itself.
/// </summary>
public static class Vfx
{
	private static readonly RandomNumberGenerator Rng = new RandomNumberGenerator();
	private static StandardMaterial3D _coinMaterial;
	private static CylinderMesh _coinMesh;

	/// <summary>Frees a node after the given (scaled) time, if it still exists.</summary>
	public static void AutoFree(Node node, float seconds)
	{
		if (node == null || !node.IsInsideTree())
		{
			node?.QueueFree();
			return;
		}
		SceneTreeTimer timer = node.GetTree().CreateTimer(seconds);
		timer.Timeout += () =>
		{
			if (GodotObject.IsInstanceValid(node))
			{
				node.QueueFree();
			}
		};
	}

	/// <summary>Creates a gradient from a list of colors spread evenly over 0..1.</summary>
	public static Gradient Ramp(params Color[] colors)
	{
		var offsets = new float[colors.Length];
		for (int i = 0; i < colors.Length; i++)
		{
			offsets[i] = colors.Length > 1 ? (float)i / (colors.Length - 1) : 0f;
		}
		return new Gradient { Colors = colors, Offsets = offsets };
	}

	/// <summary>Creates a linear curve from start to end value over the particle lifetime.</summary>
	public static Curve LinearCurve(float start, float end, float mid = -1f)
	{
		var curve = new Curve();
		curve.AddPoint(new Vector2(0f, start));
		if (mid >= 0f)
		{
			curve.AddPoint(new Vector2(0.3f, mid));
		}
		curve.AddPoint(new Vector2(1f, end));
		return curve;
	}

	private static CpuParticles3D CreateBurst(Node3D parent, Vector3 pos, Mesh mesh, int amount, float lifetime)
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
		AutoFree(p, (float)p.Lifetime + 0.6f);
	}

	/// <summary>Hot sparks flying out of an impact point plus a short flare.</summary>
	public static void ImpactSparks(Node3D parent, Vector3 pos, Color color, int amount = 40, float power = 1f)
	{
		if (parent == null)
		{
			return;
		}
		CpuParticles3D p = CreateBurst(parent, pos, VfxAssets.GlowQuad, amount, 0.5f);
		p.Direction = Vector3.Up;
		p.Spread = 85f;
		p.InitialVelocityMin = 2.5f * power;
		p.InitialVelocityMax = 5.5f * power;
		p.Gravity = new Vector3(0, -9f, 0);
		p.DampingMin = 1.5f;
		p.DampingMax = 3f;
		p.ScaleAmountMin = 0.14f;
		p.ScaleAmountMax = 0.34f;
		p.ScaleAmountCurve = LinearCurve(1f, 0f);
		p.ColorRamp = Ramp(new Color(1f, 1f, 0.9f, 1f), color, new Color(color.R, color.G * 0.5f, color.B * 0.3f, 0f));
		p.EmissionShape = CpuParticles3D.EmissionShapeEnum.Sphere;
		p.EmissionSphereRadius = 0.08f;
		Fire(p);
		GlowFlash(parent, pos, color, 1.6f * power, 0.2f);
		Shockwave(parent, new Vector3(pos.X, 0.04f, pos.Z), color, 1.2f * power, 0.32f, 0.12f);
	}

	/// <summary>A big billboard glow that shrinks and fades quickly.</summary>
	public static void GlowFlash(Node3D parent, Vector3 pos, Color color, float size, float duration)
	{
		if (parent == null)
		{
			return;
		}
		var flash = new MeshInstance3D
		{
			Mesh = VfxAssets.GlowQuad,
			CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
		};
		parent.AddChild(flash);
		flash.GlobalPosition = pos;
		flash.Scale = Vector3.One * size * 0.4f;
		flash.SetInstanceShaderParameter("tint", color);
		Tween tween = flash.CreateTween();
		tween.SetParallel(true);
		tween.TweenProperty(flash, "scale", Vector3.One * size, duration * 0.35f).SetTrans(Tween.TransitionType.Expo).SetEase(Tween.EaseType.Out);
		tween.TweenMethod(Callable.From<Color>(c => flash.SetInstanceShaderParameter("tint", c)),
			color, new Color(color.R, color.G, color.B, 0f), duration);
		tween.Chain().TweenCallback(Callable.From(flash.QueueFree));
	}

	/// <summary>Soft rising smoke or dust.</summary>
	public static void SmokePuff(Node3D parent, Vector3 pos, Color color, int amount = 10, float size = 0.6f)
	{
		if (parent == null)
		{
			return;
		}
		CpuParticles3D p = CreateBurst(parent, pos, VfxAssets.SmokeQuad, amount, 0.95f);
		p.Explosiveness = 0.85f;
		p.Direction = Vector3.Up;
		p.Spread = 70f;
		p.InitialVelocityMin = 0.4f;
		p.InitialVelocityMax = 1.3f;
		p.Gravity = new Vector3(0, 0.7f, 0);
		p.DampingMin = 1f;
		p.DampingMax = 2f;
		p.ScaleAmountMin = 0.5f * size;
		p.ScaleAmountMax = 1.0f * size;
		p.ScaleAmountCurve = LinearCurve(0.5f, 1.3f);
		p.EmissionShape = CpuParticles3D.EmissionShapeEnum.Sphere;
		p.EmissionSphereRadius = 0.2f;
		p.ColorRamp = Ramp(new Color(color.R, color.G, color.B, 0.6f), new Color(color.R, color.G, color.B, 0.35f), new Color(color.R, color.G, color.B, 0f));
		Fire(p);
	}

	/// <summary>A ring of dust rolling outwards along the ground.</summary>
	public static void DustRing(Node3D parent, Vector3 pos, Color color, float radius = 0.45f, int amount = 18)
	{
		if (parent == null)
		{
			return;
		}
		CpuParticles3D p = CreateBurst(parent, pos + new Vector3(0, 0.08f, 0), VfxAssets.SmokeQuad, amount, 0.7f);
		p.EmissionShape = CpuParticles3D.EmissionShapeEnum.Ring;
		p.EmissionRingAxis = Vector3.Up;
		p.EmissionRingRadius = radius;
		p.EmissionRingInnerRadius = radius * 0.85f;
		p.EmissionRingHeight = 0.02f;
		p.Direction = new Vector3(1, 0, 0);
		p.Spread = 180f;
		p.Flatness = 1f;
		p.InitialVelocityMin = 0.3f;
		p.InitialVelocityMax = 0.8f;
		p.RadialAccelMin = 2.5f;
		p.RadialAccelMax = 4f;
		p.DampingMin = 2f;
		p.DampingMax = 3f;
		p.Gravity = new Vector3(0, 0.3f, 0);
		p.ScaleAmountMin = 0.25f;
		p.ScaleAmountMax = 0.45f;
		p.ScaleAmountCurve = LinearCurve(0.6f, 1.4f);
		p.ColorRamp = Ramp(new Color(color.R, color.G, color.B, 0.65f), new Color(color.R, color.G, color.B, 0f));
		Fire(p);
	}

	/// <summary>Breaks a token into tumbling fragments with a flash and a puff of smoke.</summary>
	public static void Shatter(Node3D parent, Vector3 pos, Color bodyColor, Color accentColor)
	{
		if (parent == null)
		{
			return;
		}
		var mat = new StandardMaterial3D
		{
			VertexColorUseAsAlbedo = true,
			Roughness = 0.4f,
			EmissionEnabled = true,
			Emission = accentColor * 0.4f,
		};
		var shard = new PrismMesh { Size = new Vector3(0.16f, 0.1f, 0.12f), Material = mat };
		CpuParticles3D p = CreateBurst(parent, pos, shard, 22, 0.85f);
		p.Direction = Vector3.Up;
		p.Spread = 75f;
		p.InitialVelocityMin = 2.5f;
		p.InitialVelocityMax = 5f;
		p.Gravity = new Vector3(0, -13f, 0);
		p.ParticleFlagRotateY = true;
		p.AngleMin = 0f;
		p.AngleMax = 360f;
		p.AngularVelocityMin = -720f;
		p.AngularVelocityMax = 720f;
		p.ScaleAmountMin = 0.6f;
		p.ScaleAmountMax = 1.4f;
		p.ScaleAmountCurve = LinearCurve(1f, 0f, 1f);
		p.EmissionShape = CpuParticles3D.EmissionShapeEnum.Sphere;
		p.EmissionSphereRadius = 0.3f;
		p.ColorRamp = Ramp(bodyColor.Lightened(0.2f), accentColor, bodyColor.Darkened(0.4f));
		Fire(p);

		var goldShard = new BoxMesh { Size = new Vector3(0.09f, 0.03f, 0.05f), Material = VfxAssets.CreateGoldMaterial(0.6f) };
		CpuParticles3D g = CreateBurst(parent, pos, goldShard, 12, 0.8f);
		g.Direction = Vector3.Up;
		g.Spread = 90f;
		g.InitialVelocityMin = 2f;
		g.InitialVelocityMax = 4.5f;
		g.Gravity = new Vector3(0, -12f, 0);
		g.ParticleFlagRotateY = true;
		g.AngularVelocityMin = -900f;
		g.AngularVelocityMax = 900f;
		g.ScaleAmountCurve = LinearCurve(1f, 0f, 1f);
		g.EmissionShape = CpuParticles3D.EmissionShapeEnum.Ring;
		g.EmissionRingAxis = Vector3.Up;
		g.EmissionRingRadius = 0.42f;
		g.EmissionRingInnerRadius = 0.36f;
		g.EmissionRingHeight = 0.05f;
		Fire(g);

		ImpactSparks(parent, pos + new Vector3(0, 0.15f, 0), accentColor.Lightened(0.3f), 24, 0.8f);
		SmokePuff(parent, pos, new Color(0.25f, 0.22f, 0.2f), 12, 0.9f);
		GlowFlash(parent, pos + new Vector3(0, 0.3f, 0), new Color(1f, 0.6f, 0.3f), 1.9f, 0.3f);
	}

	/// <summary>Golden shards and a ring when a shield is broken.</summary>
	public static void ShieldShatter(Node3D parent, Vector3 pos)
	{
		if (parent == null)
		{
			return;
		}
		var gold = new Color(1f, 0.82f, 0.35f);
		var shard = new PrismMesh { Size = new Vector3(0.12f, 0.04f, 0.1f), Material = VfxAssets.CreateGoldMaterial(1.5f) };
		CpuParticles3D p = CreateBurst(parent, pos, shard, 26, 0.7f);
		p.EmissionShape = CpuParticles3D.EmissionShapeEnum.Sphere;
		p.EmissionSphereRadius = 0.5f;
		p.Direction = Vector3.Up;
		p.Spread = 180f;
		p.InitialVelocityMin = 1.5f;
		p.InitialVelocityMax = 3.5f;
		p.Gravity = new Vector3(0, -8f, 0);
		p.ParticleFlagRotateY = true;
		p.AngularVelocityMin = -800f;
		p.AngularVelocityMax = 800f;
		p.ScaleAmountCurve = LinearCurve(1f, 0f, 1f);
		Fire(p);
		Sparkle(parent, pos, gold, 18, 0.6f);
		Shockwave(parent, new Vector3(pos.X, 0.05f, pos.Z), gold, 1.3f, 0.4f, 0.1f);
		GlowFlash(parent, pos, gold, 1.8f, 0.25f);
		LightFlash(parent, pos + new Vector3(0, 0.5f, 0), gold, 3f, 3f, 0.3f);
	}

	/// <summary>Small golden ripple when a shield absorbs damage but holds.</summary>
	public static void ShieldBlock(Node3D parent, Vector3 pos)
	{
		var gold = new Color(1f, 0.85f, 0.4f);
		Shockwave(parent, new Vector3(pos.X, 0.05f, pos.Z), gold, 1.0f, 0.3f, 0.08f);
		Sparkle(parent, pos, gold, 8, 0.45f);
	}

	/// <summary>Twinkling star sparkles drifting upwards.</summary>
	public static void Sparkle(Node3D parent, Vector3 pos, Color color, int amount = 16, float lifetime = 0.8f, float radius = 0.45f)
	{
		if (parent == null)
		{
			return;
		}
		CpuParticles3D p = CreateBurst(parent, pos, VfxAssets.SparkleQuad, amount, lifetime);
		p.Explosiveness = 0.55f;
		p.EmissionShape = CpuParticles3D.EmissionShapeEnum.Sphere;
		p.EmissionSphereRadius = radius;
		p.Direction = Vector3.Up;
		p.Spread = 40f;
		p.InitialVelocityMin = 0.2f;
		p.InitialVelocityMax = 0.8f;
		p.Gravity = new Vector3(0, 0.6f, 0);
		p.ScaleAmountMin = 0.22f;
		p.ScaleAmountMax = 0.45f;
		p.ScaleAmountCurve = LinearCurve(0f, 0f, 1f);
		p.ColorRamp = Ramp(new Color(1f, 1f, 1f, 1f), color, new Color(color.R, color.G, color.B, 0f));
		Fire(p);
	}

	/// <summary>Gold coins popping out of a tile plus sparkles.</summary>
	public static void CoinFountain(Node3D parent, Vector3 pos, int coins = 6)
	{
		if (parent == null)
		{
			return;
		}
		_coinMaterial ??= VfxAssets.CreateGoldMaterial(0.9f);
		_coinMesh ??= new CylinderMesh { TopRadius = 0.075f, BottomRadius = 0.075f, Height = 0.02f, RadialSegments = 12, Rings = 1, Material = _coinMaterial };
		CpuParticles3D p = CreateBurst(parent, pos + new Vector3(0, 0.1f, 0), _coinMesh, coins, 0.95f);
		p.Explosiveness = 0.8f;
		p.Direction = Vector3.Up;
		p.Spread = 28f;
		p.InitialVelocityMin = 3f;
		p.InitialVelocityMax = 4.3f;
		p.Gravity = new Vector3(0, -8f, 0);
		p.ParticleFlagRotateY = true;
		p.AngularVelocityMin = 300f;
		p.AngularVelocityMax = 700f;
		p.ScaleAmountCurve = LinearCurve(1f, 0.2f, 1f);
		Fire(p);
		Sparkle(parent, pos + new Vector3(0, 0.3f, 0), new Color(1f, 0.85f, 0.35f), 12, 0.8f, 0.4f);
	}

	/// <summary>Expanding ground ring.</summary>
	public static void Shockwave(Node3D parent, Vector3 pos, Color color, float radius, float duration, float thickness = 0.12f)
	{
		if (parent == null)
		{
			return;
		}
		ShaderMaterial mat = VfxAssets.CreateMaterial("shockwave", 3);
		mat.SetShaderParameter("color", color);
		mat.SetShaderParameter("thickness", thickness);
		var ring = new MeshInstance3D
		{
			Mesh = new PlaneMesh { Size = new Vector2(radius * 2f, radius * 2f) },
			MaterialOverride = mat,
			CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
		};
		parent.AddChild(ring);
		ring.GlobalPosition = pos;
		Tween tween = ring.CreateTween();
		tween.TweenMethod(Callable.From<float>(v => mat.SetShaderParameter("progress", v)), 0f, 1f, duration)
			.SetTrans(Tween.TransitionType.Cubic).SetEase(Tween.EaseType.Out);
		tween.TweenCallback(Callable.From(ring.QueueFree));
	}

	/// <summary>A short-lived point light flash.</summary>
	public static void LightFlash(Node3D parent, Vector3 pos, Color color, float energy, float range, float duration)
	{
		if (parent == null)
		{
			return;
		}
		var light = new OmniLight3D
		{
			LightColor = color,
			LightEnergy = energy,
			OmniRange = range,
			ShadowEnabled = false,
		};
		parent.AddChild(light);
		light.GlobalPosition = pos;
		Tween tween = light.CreateTween();
		tween.TweenProperty(light, "light_energy", 0f, duration).SetTrans(Tween.TransitionType.Quad).SetEase(Tween.EaseType.Out);
		tween.TweenCallback(Callable.From(light.QueueFree));
	}

	/// <summary>Big punchy damage number on a splat that pops, arcs upward and fades.</summary>
	public static void DamageNumber(Node3D parent, Vector3 pos, string text, Color splatColor)
	{
		if (parent == null)
		{
			return;
		}
		var root = new Node3D { Name = "DamageNumber" };
		parent.AddChild(root);
		root.GlobalPosition = pos + new Vector3(0, 0.75f, 0);
		root.Scale = Vector3.One * 0.2f;

		MeshInstance3D splat = VfxAssets.CreateBadge(4, 0.95f, splatColor, 40);
		root.AddChild(splat);
		Label3D label = VfxAssets.CreateLabel(text, 104, 0.0042f, Colors.White, 20, 42);
		root.AddChild(label);
		var splatMat = (ShaderMaterial)splat.MaterialOverride;

		float side = Rng.RandfRange(-0.25f, 0.25f);
		Vector3 start = root.GlobalPosition;
		Tween tween = root.CreateTween();
		tween.TweenProperty(root, "scale", Vector3.One * 1.35f, 0.1f).SetTrans(Tween.TransitionType.Back).SetEase(Tween.EaseType.Out);
		tween.TweenProperty(root, "scale", Vector3.One, 0.08f);
		Tween move = root.CreateTween();
		move.TweenMethod(Callable.From<float>(t =>
		{
			if (GodotObject.IsInstanceValid(root))
			{
				root.GlobalPosition = start + new Vector3(side * t, 0.55f * Mathf.Sin(t * Mathf.Pi * 0.5f), 0);
			}
		}), 0f, 1f, 0.85f);
		Tween fade = root.CreateTween();
		fade.SetParallel(true);
		fade.TweenMethod(Callable.From<float>(a => splatMat.SetShaderParameter("alpha", a)), 1f, 0f, 0.3f).SetDelay(0.6f);
		fade.TweenProperty(label, "modulate:a", 0f, 0.3f).SetDelay(0.6f);
		fade.TweenProperty(label, "outline_modulate:a", 0f, 0.3f).SetDelay(0.6f);
		fade.Chain().TweenCallback(Callable.From(root.QueueFree));
	}

	/// <summary>Popping, rising text (info, "+1", "Chain!", ...).</summary>
	public static void PopupText(Node3D parent, Vector3 pos, string text, Color color, int fontSize = 64, float lift = 1.2f)
	{
		if (parent == null)
		{
			return;
		}
		Label3D label = VfxAssets.CreateLabel(text, fontSize, 0.004f, color, 14, 44);
		parent.AddChild(label);
		label.GlobalPosition = pos + new Vector3(0, lift, 0);
		label.Scale = Vector3.One * 0.3f;
		Tween tween = label.CreateTween();
		tween.TweenProperty(label, "scale", Vector3.One * 1.15f, 0.1f).SetTrans(Tween.TransitionType.Back).SetEase(Tween.EaseType.Out);
		tween.TweenProperty(label, "scale", Vector3.One, 0.08f);
		tween.SetParallel(true);
		tween.TweenProperty(label, "global_position", label.GlobalPosition + new Vector3(0, 0.55f, 0), 0.8f)
			.SetTrans(Tween.TransitionType.Quad).SetEase(Tween.EaseType.Out);
		tween.TweenProperty(label, "modulate:a", 0f, 0.35f).SetDelay(0.45f);
		tween.TweenProperty(label, "outline_modulate:a", 0f, 0.35f).SetDelay(0.45f);
		tween.Chain().TweenCallback(Callable.From(label.QueueFree));
	}

	/// <summary>Fires a glowing projectile with a trail along an arc. Completes on impact.</summary>
	public static async Task Projectile(Node3D parent, Vector3 from, Vector3 to, Color color, float duration)
	{
		if (parent == null)
		{
			return;
		}
		var root = new Node3D { Name = "Projectile" };
		parent.AddChild(root);
		root.GlobalPosition = from;

		var head = new MeshInstance3D { Mesh = VfxAssets.GlowQuad, Scale = Vector3.One * 0.7f, CastShadow = GeometryInstance3D.ShadowCastingSetting.Off };
		head.SetInstanceShaderParameter("tint", color);
		root.AddChild(head);
		var core = new MeshInstance3D { Mesh = VfxAssets.GlowQuad, Scale = Vector3.One * 0.22f, CastShadow = GeometryInstance3D.ShadowCastingSetting.Off };
		core.SetInstanceShaderParameter("tint", new Color(1f, 1f, 0.95f));
		root.AddChild(core);
		var light = new OmniLight3D { LightColor = color, LightEnergy = 2.5f, OmniRange = 2.2f };
		root.AddChild(light);

		var trail = new CpuParticles3D
		{
			Mesh = VfxAssets.GlowQuad,
			Amount = 48,
			Lifetime = 0.32f,
			LocalCoords = false,
			Explosiveness = 0f,
			Spread = 180f,
			InitialVelocityMin = 0.05f,
			InitialVelocityMax = 0.3f,
			Gravity = Vector3.Zero,
			ScaleAmountMin = 0.25f,
			ScaleAmountMax = 0.42f,
			ScaleAmountCurve = LinearCurve(1f, 0f),
			ColorRamp = Ramp(new Color(1f, 1f, 0.9f, 0.9f), color, new Color(color.R, color.G, color.B, 0f)),
			CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
		};
		root.AddChild(trail);
		trail.Emitting = true;

		float dist = from.DistanceTo(to);
		float height = 0.25f + 0.14f * dist;
		Tween tween = root.CreateTween();
		tween.TweenMethod(Callable.From<float>(t =>
		{
			if (GodotObject.IsInstanceValid(root))
			{
				root.GlobalPosition = from.Lerp(to, t) + new Vector3(0, height * 4f * t * (1f - t), 0);
			}
		}), 0f, 1f, duration).SetTrans(Tween.TransitionType.Sine).SetEase(Tween.EaseType.In);
		await root.ToSignal(tween, Tween.SignalName.Finished);
		if (!GodotObject.IsInstanceValid(root))
		{
			return;
		}
		trail.Emitting = false;
		head.Visible = false;
		core.Visible = false;
		light.Visible = false;
		AutoFree(root, 0.45f);
	}

	/// <summary>Crackling lightning arc between two world points.</summary>
	public static void Lightning(Node3D parent, Vector3 from, Vector3 to, Color color, float duration)
	{
		if (parent == null)
		{
			return;
		}
		var arc = new LightningArc { Name = "Lightning" };
		arc.Setup(from, to, color, duration);
		parent.AddChild(arc);
		GlowFlash(parent, from, color, 1.0f, 0.2f);
		GlowFlash(parent, to, color, 1.4f, 0.25f);
		LightFlash(parent, (from + to) * 0.5f + new Vector3(0, 0.5f, 0), color, 3f, 4f, duration);
	}

	/// <summary>Glowing motes spiralling into a piece, ending in a burst.</summary>
	public static SwirlEffect SpellSwirl(Node3D parent, Vector3 pos, Color primary, Color secondary, float duration)
	{
		if (parent == null)
		{
			return null;
		}
		var swirl = new SwirlEffect { Name = "SpellSwirl" };
		swirl.Setup(primary, secondary, duration);
		parent.AddChild(swirl);
		swirl.GlobalPosition = pos;
		return swirl;
	}
}
