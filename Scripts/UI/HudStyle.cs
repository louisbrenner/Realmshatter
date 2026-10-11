using System.Collections.Generic;
using Godot;

namespace Realmshatter;

/// <summary>
/// Shared palette, style boxes, theme and procedural drawing helpers for the Hearthstone-styled HUD
/// (dark wood plaques with gold trim, parchment ribbons, gold coins, blue mana crystals).
/// </summary>
public static class HudStyle
{
	public static readonly Color WoodDark = new Color(0.13f, 0.075f, 0.04f);
	public static readonly Color WoodMid = new Color(0.27f, 0.16f, 0.08f);
	public static readonly Color WoodLight = new Color(0.42f, 0.26f, 0.13f);
	public static readonly Color Gold = new Color(0.98f, 0.79f, 0.38f);
	public static readonly Color GoldDark = new Color(0.55f, 0.37f, 0.13f);
	public static readonly Color GoldDeep = new Color(0.32f, 0.2f, 0.06f);
	public static readonly Color Parchment = new Color(0.95f, 0.87f, 0.69f);
	public static readonly Color ParchmentDark = new Color(0.78f, 0.64f, 0.42f);
	public static readonly Color Ink = new Color(0.24f, 0.14f, 0.06f);
	public static readonly Color TextLight = new Color(1f, 0.94f, 0.8f);
	public static readonly Color Outline = new Color(0.07f, 0.04f, 0.02f);
	public static readonly Color PlayerBlue = new Color(0.35f, 0.65f, 1f);
	public static readonly Color EnemyRed = new Color(1f, 0.38f, 0.3f);
	public static readonly Color ManaBlue = new Color(0.22f, 0.58f, 1f);
	public static readonly Color ManaLight = new Color(0.7f, 0.92f, 1f);
	public static readonly Color ReadyGreen = new Color(0.35f, 1f, 0.35f);
	public static readonly Color StoneGrey = new Color(0.42f, 0.4f, 0.38f);

	private static Font _font;
	private static Theme _theme;

	/// <summary>The serif HUD font (Resources/UI/CardFont.tres).</summary>
	public static Font Font => _font ??= VfxAssets.CardFont;

	/// <summary>Player accent color (0 = you / blue, 1 = AI / red).</summary>
	public static Color Accent(int player) => player == 0 ? PlayerBlue : EnemyRed;

	/// <summary>Creates a flat style box with rounded corners, border and drop shadow.</summary>
	public static StyleBoxFlat Box(Color bg, Color border, int radius = 10, int borderWidth = 2, int shadow = 6, float shadowAlpha = 0.45f)
	{
		var box = new StyleBoxFlat
		{
			BgColor = bg,
			BorderColor = border,
			ShadowColor = new Color(0f, 0f, 0f, shadowAlpha),
			ShadowSize = shadow,
			ShadowOffset = new Vector2(0f, 2f),
			CornerDetail = 8,
			AntiAliasing = true,
		};
		box.SetCornerRadiusAll(radius);
		box.SetBorderWidthAll(borderWidth);
		return box;
	}

	/// <summary>Dark wood plaque with gold trim; an optional accent colors the top border.</summary>
	public static StyleBoxFlat WoodPanel(Color? accent = null, int padding = 10)
	{
		StyleBoxFlat box = Box(new Color(WoodDark, 0.93f), GoldDark, 12, 2, 10, 0.5f);
		if (accent.HasValue)
		{
			box.BorderColor = accent.Value.Lerp(GoldDark, 0.35f);
			box.BorderWidthTop = 4;
		}
		box.SetContentMarginAll(padding);
		return box;
	}

	/// <summary>Parchment ribbon used for hints and toasts.</summary>
	public static StyleBoxFlat ParchmentPanel(int padH = 18, int padV = 6)
	{
		StyleBoxFlat box = Box(new Color(Parchment, 0.95f), new Color(0.45f, 0.28f, 0.1f), 6, 2, 8, 0.5f);
		box.ContentMarginLeft = padH;
		box.ContentMarginRight = padH;
		box.ContentMarginTop = padV;
		box.ContentMarginBottom = padV;
		return box;
	}

	/// <summary>The HUD theme: serif font, wood/gold buttons, parchment tooltips.</summary>
	public static Theme CreateTheme()
	{
		if (_theme != null)
		{
			return _theme;
		}
		var theme = new Theme
		{
			DefaultFont = Font,
			DefaultFontSize = 16,
		};

		theme.SetColor("font_color", "Label", TextLight);
		// No Label outline in the theme: card labels inside the HUD inherit it. HUD labels set their own.
		theme.SetColor("font_outline_color", "Label", Outline);

		StyleBoxFlat normal = Box(WoodMid, GoldDark, 8, 2, 4);
		StyleBoxFlat hover = Box(WoodLight, Gold, 8, 2, 6);
		StyleBoxFlat pressed = Box(WoodDark, Gold, 8, 2, 2);
		StyleBoxFlat disabled = Box(new Color(0.2f, 0.17f, 0.15f, 0.85f), new Color(0.35f, 0.3f, 0.25f), 8, 2, 2);
		foreach (StyleBoxFlat b in new[] { normal, hover, pressed, disabled })
		{
			b.ContentMarginLeft = 12;
			b.ContentMarginRight = 12;
			b.ContentMarginTop = 4;
			b.ContentMarginBottom = 4;
		}
		theme.SetStylebox("normal", "Button", normal);
		theme.SetStylebox("hover", "Button", hover);
		theme.SetStylebox("pressed", "Button", pressed);
		theme.SetStylebox("disabled", "Button", disabled);
		theme.SetStylebox("focus", "Button", new StyleBoxEmpty());
		theme.SetColor("font_color", "Button", TextLight);
		theme.SetColor("font_hover_color", "Button", new Color(1f, 0.97f, 0.88f));
		theme.SetColor("font_pressed_color", "Button", Gold);
		theme.SetColor("font_disabled_color", "Button", new Color(0.6f, 0.55f, 0.5f));
		theme.SetColor("font_outline_color", "Button", Outline);
		theme.SetConstant("outline_size", "Button", 4);

		theme.SetStylebox("panel", "PanelContainer", WoodPanel());
		theme.SetStylebox("panel", "TooltipPanel", ParchmentPanel(10, 6));
		theme.SetColor("font_color", "TooltipLabel", Ink);
		theme.SetFontSize("font_size", "TooltipLabel", 15);

		theme.SetFont("normal_font", "RichTextLabel", Font);
		theme.SetFont("bold_font", "RichTextLabel", Font);
		theme.SetFontSize("normal_font_size", "RichTextLabel", 13);
		theme.SetFontSize("bold_font_size", "RichTextLabel", 13);
		theme.SetColor("default_color", "RichTextLabel", TextLight);
		theme.SetColor("font_outline_color", "RichTextLabel", Outline);
		theme.SetConstant("outline_size", "RichTextLabel", 2);
		theme.SetConstant("line_separation", "RichTextLabel", 2);
		_theme = theme;
		return theme;
	}

	/// <summary>Points of an ellipse (closed polygon, not repeating the first point).</summary>
	public static Vector2[] Ellipse(Vector2 center, Vector2 radius, int segments = 28, float startAngle = 0f, float arc = Mathf.Tau)
	{
		bool full = Mathf.IsEqualApprox(arc, Mathf.Tau);
		int count = full ? segments : segments + 1;
		var points = new Vector2[count];
		for (int i = 0; i < count; i++)
		{
			float a = startAngle + arc * i / segments;
			points[i] = center + new Vector2(Mathf.Cos(a) * radius.X, Mathf.Sin(a) * radius.Y);
		}
		return points;
	}

	/// <summary>Filled ellipse with an antialiased edge.</summary>
	public static void FillEllipse(CanvasItem ci, Vector2 center, Vector2 radius, Color color, int segments = 28)
	{
		Vector2[] pts = Ellipse(center, radius, segments);
		ci.DrawColoredPolygon(pts, color);
		ci.DrawPolyline(Close(pts), color, 1.2f, true);
	}

	/// <summary>Ellipse outline.</summary>
	public static void StrokeEllipse(CanvasItem ci, Vector2 center, Vector2 radius, Color color, float width = 1.5f, int segments = 28)
	{
		ci.DrawPolyline(Close(Ellipse(center, radius, segments)), color, width, true);
	}

	/// <summary>Appends the first point to close a polyline.</summary>
	public static Vector2[] Close(Vector2[] pts)
	{
		var closed = new Vector2[pts.Length + 1];
		pts.CopyTo(closed, 0);
		closed[pts.Length] = pts[0];
		return closed;
	}

	/// <summary>
	/// Gold coin seen slightly from above. center = middle of the top face; radius = face radius;
	/// thickness = visible edge height. ghost draws only a faint slot outline.
	/// </summary>
	public static void DrawCoin(CanvasItem ci, Vector2 center, float radius, float thickness, float alpha = 1f, float flash = 0f, bool ghost = false)
	{
		var r = new Vector2(radius, radius * 0.42f);
		if (ghost)
		{
			StrokeEllipse(ci, center + new Vector2(0, thickness), r, new Color(Gold, 0.18f * alpha), 1.2f, 24);
			return;
		}
		Color edge = new Color(0.62f, 0.4f, 0.12f, alpha);
		Color edgeDark = new Color(0.36f, 0.22f, 0.06f, alpha);
		// Edge band: bottom ellipse + rectangle between the faces.
		FillEllipse(ci, center + new Vector2(0, thickness), r, edgeDark, 24);
		ci.DrawRect(new Rect2(center.X - radius, center.Y, radius * 2f, thickness), edge);
		// Ridges along the edge.
		for (int i = 1; i < 8; i++)
		{
			float x = center.X - radius + radius * 2f * i / 8f;
			float h = Mathf.Sqrt(Mathf.Max(0f, 1f - Mathf.Pow((x - center.X) / radius, 2f))) * r.Y;
			ci.DrawLine(new Vector2(x, center.Y + h), new Vector2(x, center.Y + h + thickness), new Color(edgeDark, alpha * 0.6f), 1f);
		}
		Color face = new Color(1f, 0.8f, 0.36f, alpha).Lerp(new Color(1f, 1f, 0.85f, alpha), flash);
		FillEllipse(ci, center, r, face, 26);
		FillEllipse(ci, center, r * 0.74f, new Color(0.9f, 0.64f, 0.22f, alpha).Lerp(new Color(1f, 1f, 0.9f, alpha), flash), 22);
		FillEllipse(ci, center + new Vector2(-radius * 0.12f, -r.Y * 0.12f), r * 0.5f, new Color(1f, 0.88f, 0.5f, alpha * 0.9f), 18);
		StrokeEllipse(ci, center, r, new Color(0.45f, 0.28f, 0.08f, alpha), 1.2f, 26);
		// Highlight glint.
		ci.DrawLine(center + new Vector2(-radius * 0.45f, -r.Y * 0.45f), center + new Vector2(-radius * 0.1f, -r.Y * 0.62f),
			new Color(1f, 1f, 0.9f, 0.75f * alpha), 1.5f, true);
	}

	/// <summary>
	/// Hearthstone-like mana crystal (faceted gem). fill 0..1 blends from empty socket to glowing crystal.
	/// </summary>
	public static void DrawCrystal(CanvasItem ci, Vector2 center, float size, float fill, float flash = 0f, float alpha = 1f)
	{
		float w = size * 0.5f;
		float h = size * 0.62f;
		Vector2[] outer =
		{
			center + new Vector2(0, -h), center + new Vector2(w, -h * 0.35f), center + new Vector2(w * 0.8f, h * 0.55f),
			center + new Vector2(0, h), center + new Vector2(-w * 0.8f, h * 0.55f), center + new Vector2(-w, -h * 0.35f),
		};
		Color socket = new Color(0.06f, 0.08f, 0.15f, 0.9f * alpha);
		Color socketRim = new Color(0.3f, 0.32f, 0.4f, alpha);
		ci.DrawColoredPolygon(outer, socket);
		if (fill > 0.001f)
		{
			Color glow = new Color(ManaBlue, 0.35f * fill * alpha);
			FillEllipse(ci, center, new Vector2(w * 1.5f, h * 1.25f), glow, 20);
			Color baseCol = ManaBlue.Lerp(Colors.White, flash * 0.6f);
			Color dark = new Color(0.08f, 0.25f, 0.7f).Lerp(Colors.White, flash * 0.4f);
			Color light = ManaLight.Lerp(Colors.White, flash);
			float k = Mathf.Clamp(fill, 0f, 1f);
			Vector2 c = center;
			Vector2 top = c + new Vector2(0, -h) * k;
			Vector2[] scaled = new Vector2[outer.Length];
			for (int i = 0; i < outer.Length; i++)
			{
				scaled[i] = c + (outer[i] - c) * (0.55f + 0.45f * k);
			}
			ci.DrawColoredPolygon(scaled, new Color(baseCol, alpha * k));
			// Facets: upper-left light, lower-right dark, central table.
			Vector2 mid = c + new Vector2(0, -h * 0.1f) * k;
			ci.DrawColoredPolygon(new[] { scaled[0], scaled[5], mid }, new Color(light, alpha * k));
			ci.DrawColoredPolygon(new[] { scaled[0], scaled[1], mid }, new Color(baseCol.Lerp(light, 0.45f), alpha * k));
			ci.DrawColoredPolygon(new[] { scaled[2], scaled[3], mid }, new Color(dark, alpha * k));
			ci.DrawColoredPolygon(new[] { scaled[3], scaled[4], mid }, new Color(dark.Lerp(baseCol, 0.5f), alpha * k));
			ci.DrawLine(top + new Vector2(-w * 0.25f, h * 0.35f), top + new Vector2(-w * 0.05f, h * 0.15f), new Color(1, 1, 1, 0.8f * alpha * k), 1.5f, true);
		}
		ci.DrawPolyline(Close(outer), fill > 0.5f ? new Color(0.75f, 0.9f, 1f, alpha) : socketRim, 1.6f, true);
	}

	/// <summary>Draws text centered on a point with an outline.</summary>
	public static void DrawTextCentered(CanvasItem ci, string text, Vector2 center, int fontSize, Color color, int outline = 4, Color? outlineColor = null)
	{
		Font font = Font;
		if (font == null || string.IsNullOrEmpty(text))
		{
			return;
		}
		Vector2 size = font.GetStringSize(text, HorizontalAlignment.Left, -1, fontSize);
		float ascent = font.GetAscent(fontSize);
		float descent = font.GetDescent(fontSize);
		var pos = new Vector2(center.X - size.X * 0.5f, center.Y + (ascent - descent) * 0.5f);
		if (outline > 0)
		{
			ci.DrawStringOutline(font, pos, text, HorizontalAlignment.Left, -1, fontSize, outline, outlineColor ?? Outline);
		}
		ci.DrawString(font, pos, text, HorizontalAlignment.Left, -1, fontSize, color);
	}

	/// <summary>Width of a text in the HUD font.</summary>
	public static float TextWidth(string text, int fontSize)
	{
		return Font?.GetStringSize(text ?? "", HorizontalAlignment.Left, -1, fontSize).X ?? 0f;
	}

	/// <summary>Points of a rounded rectangle.</summary>
	public static Vector2[] RoundRect(Rect2 rect, float radius, int cornerSegments = 5)
	{
		var pts = new List<Vector2>();
		radius = Mathf.Min(radius, Mathf.Min(rect.Size.X, rect.Size.Y) * 0.5f);
		Vector2[] centers =
		{
			new Vector2(rect.End.X - radius, rect.Position.Y + radius),
			new Vector2(rect.End.X - radius, rect.End.Y - radius),
			new Vector2(rect.Position.X + radius, rect.End.Y - radius),
			new Vector2(rect.Position.X + radius, rect.Position.Y + radius),
		};
		float[] starts = { -Mathf.Pi * 0.5f, 0f, Mathf.Pi * 0.5f, Mathf.Pi };
		for (int c = 0; c < 4; c++)
		{
			for (int i = 0; i <= cornerSegments; i++)
			{
				float a = starts[c] + Mathf.Pi * 0.5f * i / cornerSegments;
				pts.Add(centers[c] + new Vector2(Mathf.Cos(a), Mathf.Sin(a)) * radius);
			}
		}
		return pts.ToArray();
	}
}
