using System.Collections.Generic;
using Godot;

namespace Realmshatter;

/// <summary>
/// Lazily loaded, shared shaders, meshes and fonts for the procedural visuals and VFX.
/// </summary>
public static class VfxAssets
{
	public const string ShaderDir = "res://Assets/Shaders/";
	public const string CardFontPath = "res://Resources/UI/CardFont.tres";

	private static readonly Dictionary<string, Shader> Shaders = new Dictionary<string, Shader>();
	private static Font _font;
	private static ShaderMaterial _glowMaterial;
	private static ShaderMaterial _sparkleMaterial;
	private static ShaderMaterial _smokeMaterial;
	private static QuadMesh _glowQuad;
	private static QuadMesh _sparkleQuad;
	private static QuadMesh _smokeQuad;
	private static ShaderMaterial _ringMaterial;
	private static QuadMesh _ringQuad;

	/// <summary>Loads (once) a shader from Assets/Shaders by file name without extension.</summary>
	public static Shader GetShader(string name)
	{
		if (Shaders.TryGetValue(name, out Shader shader) && shader != null)
		{
			return shader;
		}
		shader = GD.Load<Shader>(ShaderDir + name + ".gdshader");
		Shaders[name] = shader;
		return shader;
	}

	/// <summary>Creates a new (unshared) ShaderMaterial using the named shader.</summary>
	public static ShaderMaterial CreateMaterial(string shaderName, int renderPriority = 0)
	{
		return new ShaderMaterial { Shader = GetShader(shaderName), RenderPriority = renderPriority };
	}

	/// <summary>The bold serif font used for cards, badges and popups.</summary>
	public static Font CardFont => _font ??= GD.Load<Font>(CardFontPath);

	/// <summary>Regular serif for card body text and info panels (MSDF: stays sharp when cards are scaled).</summary>
	public static Font CardTextFont => _textFont ??= CreateSharpFont(400);

	/// <summary>Bold serif for card titles, badges and keyword names (MSDF).</summary>
	public static Font CardTextBoldFont => _textBoldFont ??= CreateSharpFont(700);

	private static Font _textFont;
	private static Font _textBoldFont;

	private static SystemFont CreateSharpFont(int weight)
	{
		return new SystemFont
		{
			FontNames = new[] { "Georgia", "Palatino Linotype", "Book Antiqua", "Times New Roman", "Serif" },
			FontWeight = weight,
			MultichannelSignedDistanceField = true,
			MsdfPixelRange = 16,
			MsdfSize = 48,
			GenerateMipmaps = true,
		};
	}

	/// <summary>Billboard quad with an additive soft glow dot (shared material, tint via instance uniform).</summary>
	public static QuadMesh GlowQuad
	{
		get
		{
			if (_glowQuad == null)
			{
				_glowMaterial = CreateMaterial("vfx_particle", 4);
				_glowMaterial.SetShaderParameter("shape", 0);
				_glowQuad = new QuadMesh { Size = new Vector2(1f, 1f), Material = _glowMaterial };
			}
			return _glowQuad;
		}
	}

	/// <summary>Billboard quad with an additive four-point star sparkle.</summary>
	public static QuadMesh SparkleQuad
	{
		get
		{
			if (_sparkleQuad == null)
			{
				_sparkleMaterial = CreateMaterial("vfx_particle", 4);
				_sparkleMaterial.SetShaderParameter("shape", 1);
				_sparkleMaterial.SetShaderParameter("energy", 4.0f);
				_sparkleQuad = new QuadMesh { Size = new Vector2(1f, 1f), Material = _sparkleMaterial };
			}
			return _sparkleQuad;
		}
	}

	/// <summary>Billboard quad with an alpha-blended smoke puff.</summary>
	public static QuadMesh SmokeQuad
	{
		get
		{
			if (_smokeQuad == null)
			{
				_smokeMaterial = CreateMaterial("vfx_smoke", 2);
				_smokeQuad = new QuadMesh { Size = new Vector2(1f, 1f), Material = _smokeMaterial };
			}
			return _smokeQuad;
		}
	}

	/// <summary>Billboard quad with an additive thin ring (bubbles, ripples).</summary>
	public static QuadMesh RingQuad
	{
		get
		{
			if (_ringQuad == null)
			{
				_ringMaterial = CreateMaterial("vfx_particle", 4);
				_ringMaterial.SetShaderParameter("shape", 2);
				_ringQuad = new QuadMesh { Size = new Vector2(1f, 1f), Material = _ringMaterial };
			}
			return _ringQuad;
		}
	}

	/// <summary>Creates an SDF icon sprite (see fx_icon.gdshader for shapes), camera facing and always on top.</summary>
	public static MeshInstance3D CreateIcon(int shape, float size, Color fg, Color bg, bool background = true, int priority = 30)
	{
		ShaderMaterial mat = CreateMaterial("fx_icon", priority);
		mat.SetShaderParameter("shape", shape);
		mat.SetShaderParameter("fg_color", fg);
		mat.SetShaderParameter("bg_color", bg);
		mat.SetShaderParameter("background", background);
		return new MeshInstance3D
		{
			Mesh = new QuadMesh { Size = new Vector2(size, size) },
			MaterialOverride = mat,
			CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
		};
	}

	/// <summary>Creates a gold metal material (used for rims, trims, coins).</summary>
	public static StandardMaterial3D CreateGoldMaterial(float emission = 0.08f)
	{
		return new StandardMaterial3D
		{
			AlbedoColor = new Color(1.0f, 0.77f, 0.36f),
			Metallic = 0.85f,
			Roughness = 0.3f,
			MetallicSpecular = 0.7f,
			EmissionEnabled = emission > 0f,
			Emission = new Color(1.0f, 0.7f, 0.3f),
			EmissionEnergyMultiplier = emission,
		};
	}

	/// <summary>Creates a camera-facing Label3D in the card font.</summary>
	public static Label3D CreateLabel(string text, int fontSize, float pixelSize, Color color, int outline = 14, int priority = 30)
	{
		return new Label3D
		{
			Text = text,
			Font = CardFont,
			FontSize = fontSize,
			OutlineSize = outline,
			PixelSize = pixelSize,
			Modulate = color,
			OutlineModulate = new Color(0.05f, 0.03f, 0.02f),
			Billboard = BaseMaterial3D.BillboardModeEnum.Enabled,
			NoDepthTest = true,
			Shaded = false,
			RenderPriority = priority,
			OutlineRenderPriority = priority - 1,
			CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
		};
	}

	/// <summary>Creates a billboard badge quad (see badge.gdshader for shapes).</summary>
	public static MeshInstance3D CreateBadge(int shape, float size, Color fill, int priority = 28)
	{
		ShaderMaterial mat = CreateMaterial("badge", priority);
		mat.SetShaderParameter("shape", shape);
		mat.SetShaderParameter("fill_color", fill);
		return new MeshInstance3D
		{
			Mesh = new QuadMesh { Size = new Vector2(size, size) },
			MaterialOverride = mat,
			CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
		};
	}
}
