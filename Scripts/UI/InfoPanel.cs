using Godot;

namespace Realmshatter;

/// <summary>
/// Dark hover panel that renders an InfoSheet (built in code, never blocks the mouse): a header strip in the sheet's
/// accent colour with title, type line, owner tag and AP gem, stat chips with the card badge icons, rule rows with
/// keyword emblems and short coloured notes. It either follows the mouse cursor (board info) or sits beside a target
/// control such as a hovered card, flipping sides and clamping so it always stays inside its parent. Fades in softly.
/// </summary>
public partial class InfoPanel : PanelContainer
{
	/// <summary>Width of the content area in pixels (parent space).</summary>
	[Export] public float TextWidth { get; set; } = 250f;
	/// <summary>Font size of the rule texts (title and notes scale from it).</summary>
	[Export] public int FontSize { get; set; } = 13;

	private const float CursorOffset = 22f;
	private const float Gap = 10f;
	private const float Margin = 6f;
	private const float RowIconSize = 22f;
	private const float StatIconSize = 22f;

	private VBoxContainer _content;
	private Tween _fade;
	private Control _target;
	private bool _followCursor;
	private string _key = "";

	public override void _Ready()
	{
		EnsureBuilt();
	}

	/// <summary>Shows the sheet next to the mouse cursor and keeps following it.</summary>
	public void ShowAtCursor(InfoSheet sheet)
	{
		_target = null;
		_followCursor = true;
		ShowSheet(sheet);
	}

	/// <summary>Shows the sheet beside the target control (right side preferred) and tracks it while it moves.</summary>
	public void ShowBeside(Control target, InfoSheet sheet)
	{
		_target = target;
		_followCursor = false;
		ShowSheet(sheet);
	}

	/// <summary>Hides the panel.</summary>
	public void HidePanel()
	{
		_target = null;
		_fade?.Kill();
		Visible = false;
	}

	public override void _Process(double delta)
	{
		if (!Visible)
		{
			return;
		}
		if (!_followCursor && (_target == null || !IsInstanceValid(_target) || !_target.IsVisibleInTree()))
		{
			HidePanel();
			return;
		}
		Place();
	}

	private void ShowSheet(InfoSheet sheet)
	{
		EnsureBuilt();
		if (sheet == null || sheet.IsEmpty)
		{
			HidePanel();
			return;
		}
		string key = sheet.Key();
		if (key != _key)
		{
			_key = key;
			Rebuild(sheet);
		}
		if (!Visible)
		{
			Visible = true;
			Modulate = new Color(1f, 1f, 1f, 0f);
			_fade?.Kill();
			_fade = CreateTween();
			_fade.TweenProperty(this, "modulate:a", 1f, 0.12f);
		}
		Place();
	}

	private void Rebuild(InfoSheet sheet)
	{
		foreach (Node child in _content.GetChildren())
		{
			_content.RemoveChild(child);
			child.QueueFree();
		}
		_content.AddChild(BuildHeader(sheet));

		var body = new MarginContainer { MouseFilter = MouseFilterEnum.Ignore };
		body.AddThemeConstantOverride("margin_left", 9);
		body.AddThemeConstantOverride("margin_right", 9);
		body.AddThemeConstantOverride("margin_top", 2);
		body.AddThemeConstantOverride("margin_bottom", 8);
		var column = new VBoxContainer { MouseFilter = MouseFilterEnum.Ignore };
		column.AddThemeConstantOverride("separation", 5);
		body.AddChild(column);

		if (!string.IsNullOrWhiteSpace(sheet.Flavor))
		{
			column.AddChild(Rich($"[i][color={InfoSheet.HexMuted}]{sheet.Flavor}[/color][/i]", FontSize - 1, TextWidth));
		}
		if (sheet.Stats.Count > 0)
		{
			var stats = new HFlowContainer { MouseFilter = MouseFilterEnum.Ignore, CustomMinimumSize = new Vector2(TextWidth, 0f) };
			stats.AddThemeConstantOverride("h_separation", 10);
			stats.AddThemeConstantOverride("v_separation", 2);
			foreach (InfoSheet.Stat stat in sheet.Stats)
			{
				stats.AddChild(BuildStat(stat));
			}
			column.AddChild(stats);
		}
		foreach (string line in sheet.Lines)
		{
			column.AddChild(Rich(line, FontSize, TextWidth));
		}
		if (sheet.Rows.Count > 0)
		{
			column.AddChild(Divider());
			foreach (InfoSheet.Row row in sheet.Rows)
			{
				column.AddChild(BuildRow(row));
			}
		}
		if (sheet.Notes.Count > 0)
		{
			column.AddChild(Divider());
			foreach (string note in sheet.Notes)
			{
				column.AddChild(Rich($"[color={InfoSheet.HexMuted}]•[/color] {note}", FontSize - 1, TextWidth));
			}
		}
		_content.AddChild(body);
		ResetSize();
	}

	private Control BuildHeader(InfoSheet sheet)
	{
		var header = new PanelContainer { MouseFilter = MouseFilterEnum.Ignore };
		var style = new StyleBoxFlat
		{
			BgColor = new Color(sheet.Accent.Darkened(0.45f), 0.95f),
			BorderColor = sheet.Accent.Lightened(0.1f),
			BorderWidthBottom = 2,
			CornerRadiusTopLeft = 7,
			CornerRadiusTopRight = 7,
			ContentMarginLeft = 8,
			ContentMarginRight = 8,
			ContentMarginTop = 5,
			ContentMarginBottom = 5,
		};
		header.AddThemeStyleboxOverride("panel", style);
		var row = new HBoxContainer { MouseFilter = MouseFilterEnum.Ignore };
		row.AddThemeConstantOverride("separation", 7);
		header.AddChild(row);

		if (sheet.ApCost >= 0)
		{
			ColorRect gem = Badge(3, new Color(0.22f, 0.5f, 1f), 28f);
			gem.SizeFlagsVertical = SizeFlags.ShrinkCenter;
			var cost = new Label
			{
				Text = sheet.ApCost.ToString(),
				HorizontalAlignment = HorizontalAlignment.Center,
				VerticalAlignment = VerticalAlignment.Center,
				MouseFilter = MouseFilterEnum.Ignore,
			};
			cost.SetAnchorsPreset(LayoutPreset.FullRect);
			StyleLabel(cost, 16, Colors.White, 5, VfxAssets.CardFont);
			gem.AddChild(cost);
			row.AddChild(gem);
		}

		var titles = new VBoxContainer { MouseFilter = MouseFilterEnum.Ignore, SizeFlagsHorizontal = SizeFlags.ExpandFill };
		titles.AddThemeConstantOverride("separation", -2);
		var title = new Label { Text = sheet.Title, MouseFilter = MouseFilterEnum.Ignore };
		StyleLabel(title, FontSize + 5, sheet.TitleColor, 4, VfxAssets.CardFont);
		titles.AddChild(title);
		if (!string.IsNullOrEmpty(sheet.Subtitle))
		{
			var subtitle = new Label
			{
				Text = sheet.Subtitle,
				MouseFilter = MouseFilterEnum.Ignore,
				AutowrapMode = TextServer.AutowrapMode.WordSmart,
				CustomMinimumSize = new Vector2(TextWidth - (sheet.ApCost >= 0 ? 90f : 60f), 0f),
			};
			StyleLabel(subtitle, FontSize - 1, InfoSheet.MutedColor.Lightened(0.15f), 0, VfxAssets.CardTextFont);
			titles.AddChild(subtitle);
		}
		row.AddChild(titles);

		if (!string.IsNullOrEmpty(sheet.Tag))
		{
			var tag = new Label { Text = sheet.Tag, MouseFilter = MouseFilterEnum.Ignore, SizeFlagsVertical = SizeFlags.ShrinkBegin };
			StyleLabel(tag, FontSize - 1, sheet.TagColor, 3, VfxAssets.CardTextBoldFont);
			row.AddChild(tag);
		}
		return header;
	}

	private Control BuildStat(InfoSheet.Stat stat)
	{
		var chip = new HBoxContainer { MouseFilter = MouseFilterEnum.Ignore, TooltipText = stat.Tooltip };
		chip.AddThemeConstantOverride("separation", 3);
		ColorRect icon = stat.Kind switch
		{
			InfoSheet.StatKind.Attack => Badge(0, new Color(1f, 0.78f, 0.18f), StatIconSize),
			InfoSheet.StatKind.Health => Badge(1, new Color(0.92f, 0.13f, 0.1f), StatIconSize),
			InfoSheet.StatKind.Shield => Badge(2, new Color(0.78f, 0.8f, 0.86f), StatIconSize),
			InfoSheet.StatKind.Ap => Badge(3, new Color(0.22f, 0.5f, 1f), StatIconSize),
			InfoSheet.StatKind.Move => Emblem(FxIconShape.Chevrons, new Color(0.75f, 1f, 0.7f), new Color(0.14f, 0.32f, 0.16f, 0.97f), StatIconSize),
			InfoSheet.StatKind.Range => Emblem(FxIconShape.Crosshair, new Color(1f, 0.88f, 0.65f), new Color(0.38f, 0.22f, 0.1f, 0.97f), StatIconSize),
			_ => Emblem(FxIconShape.Bell, Colors.White, new Color(0.25f, 0.2f, 0.15f, 0.97f), StatIconSize),
		};
		icon.SizeFlagsVertical = SizeFlags.ShrinkCenter;
		chip.AddChild(icon);
		var value = new Label { Text = stat.Value, MouseFilter = MouseFilterEnum.Ignore, VerticalAlignment = VerticalAlignment.Center };
		StyleLabel(value, FontSize + 2, stat.Color, 4, VfxAssets.CardFont);
		chip.AddChild(value);
		return chip;
	}

	private Control BuildRow(InfoSheet.Row row)
	{
		var line = new HBoxContainer { MouseFilter = MouseFilterEnum.Ignore };
		line.AddThemeConstantOverride("separation", 6);
		ColorRect icon = Emblem(row.Icon, row.IconFg, row.IconBg, RowIconSize);
		icon.SizeFlagsVertical = SizeFlags.ShrinkBegin;
		line.AddChild(icon);
		string head = string.IsNullOrEmpty(row.Title) ? "" : $"[b][color=#{row.TitleColor.ToHtml(false)}]{row.Title}[/color][/b]  ";
		line.AddChild(Rich(head + row.Text, FontSize - 1, TextWidth - RowIconSize - 6f));
		return line;
	}

	private RichTextLabel Rich(string bbcode, int size, float width)
	{
		var text = new RichTextLabel
		{
			BbcodeEnabled = true,
			FitContent = true,
			ScrollActive = false,
			AutowrapMode = TextServer.AutowrapMode.WordSmart,
			MouseFilter = MouseFilterEnum.Ignore,
			CustomMinimumSize = new Vector2(width, 0f),
			Text = bbcode,
		};
		text.AddThemeFontOverride("normal_font", VfxAssets.CardTextFont);
		text.AddThemeFontOverride("bold_font", VfxAssets.CardTextBoldFont);
		text.AddThemeFontOverride("italics_font", new FontVariation
		{
			BaseFont = VfxAssets.CardTextFont,
			VariationTransform = new Transform2D(new Vector2(1f, 0f), new Vector2(0.2f, 1f), Vector2.Zero),
		});
		text.AddThemeFontSizeOverride("normal_font_size", size);
		text.AddThemeFontSizeOverride("bold_font_size", size);
		text.AddThemeFontSizeOverride("italics_font_size", size);
		text.AddThemeColorOverride("default_color", InfoSheet.TextColor);
		text.AddThemeConstantOverride("outline_size", 0);
		text.AddThemeConstantOverride("line_separation", 0);
		return text;
	}

	private static Control Divider() => new ColorRect
	{
		Color = new Color(HudStyle.GoldDark, 0.45f),
		CustomMinimumSize = new Vector2(0f, 1f),
		MouseFilter = MouseFilterEnum.Ignore,
	};

	/// <summary>Card face badge (card_badge.gdshader): 0 attack, 1 health, 2 shield, 3 mana gem.</summary>
	private static ColorRect Badge(int shape, Color fill, float size)
	{
		var rect = new ColorRect { CustomMinimumSize = new Vector2(size, size), Size = new Vector2(size, size), MouseFilter = MouseFilterEnum.Ignore };
		var mat = new ShaderMaterial { Shader = VfxAssets.GetShader("card_badge") };
		mat.SetShaderParameter("shape", shape);
		mat.SetShaderParameter("fill_color", fill);
		mat.SetShaderParameter("rect_size", new Vector2(size, size));
		rect.Material = mat;
		return rect;
	}

	/// <summary>Round keyword emblem (keyword_icon.gdshader) with a glyph.</summary>
	private static ColorRect Emblem(FxIconShape shape, Color fg, Color bg, float size)
	{
		var rect = new ColorRect { CustomMinimumSize = new Vector2(size, size), Size = new Vector2(size, size), MouseFilter = MouseFilterEnum.Ignore };
		var mat = new ShaderMaterial { Shader = VfxAssets.GetShader("keyword_icon") };
		mat.SetShaderParameter("shape", (int)shape);
		mat.SetShaderParameter("fg_color", fg);
		mat.SetShaderParameter("bg_color", bg);
		mat.SetShaderParameter("rim_color", new Color(0.85f, 0.66f, 0.32f));
		rect.Material = mat;
		return rect;
	}

	private static void StyleLabel(Label label, int size, Color color, int outline, Font font)
	{
		label.AddThemeFontOverride("font", font);
		label.AddThemeFontSizeOverride("font_size", size);
		label.AddThemeColorOverride("font_color", color);
		label.AddThemeColorOverride("font_outline_color", HudStyle.Outline);
		label.AddThemeConstantOverride("outline_size", outline);
	}

	private void Place()
	{
		if (GetParent() is not Control parent)
		{
			return;
		}
		ResetSize();
		Vector2 size = GetCombinedMinimumSize();
		Vector2 bounds = parent.Size;
		Vector2 pos;
		if (_followCursor)
		{
			Vector2 mouse = parent.GetLocalMousePosition();
			pos = mouse + new Vector2(CursorOffset, CursorOffset);
			if (pos.X + size.X > bounds.X - Margin)
			{
				pos.X = mouse.X - CursorOffset - size.X;
			}
			if (pos.Y + size.Y > bounds.Y - Margin)
			{
				pos.Y = mouse.Y - CursorOffset * 0.5f - size.Y;
			}
		}
		else
		{
			Transform2D toParent = parent.GetGlobalTransform().AffineInverse();
			Rect2 global = _target.GetGlobalRect();
			Vector2 a = toParent * global.Position;
			Vector2 b = toParent * global.End;
			var rect = new Rect2(new Vector2(Mathf.Min(a.X, b.X), Mathf.Min(a.Y, b.Y)), (b - a).Abs());
			pos = new Vector2(rect.End.X + Gap, rect.Position.Y + 8f);
			if (pos.X + size.X > bounds.X - Margin)
			{
				pos.X = rect.Position.X - Gap - size.X;
			}
		}
		pos.X = Mathf.Clamp(pos.X, Margin, Mathf.Max(Margin, bounds.X - size.X - Margin));
		pos.Y = Mathf.Clamp(pos.Y, Margin, Mathf.Max(Margin, bounds.Y - size.Y - Margin));
		Position = pos;
	}

	private void EnsureBuilt()
	{
		if (_content != null)
		{
			return;
		}
		MouseFilter = MouseFilterEnum.Ignore;
		Visible = false;
		ZIndex = 50;
		StyleBoxFlat style = HudStyle.Box(new Color(0.1f, 0.065f, 0.04f, 0.96f), HudStyle.GoldDark, 8, 2, 12, 0.55f);
		style.ContentMarginLeft = 0;
		style.ContentMarginRight = 0;
		style.ContentMarginTop = 0;
		style.ContentMarginBottom = 0;
		AddThemeStyleboxOverride("panel", style);
		_content = new VBoxContainer { Name = "Content", MouseFilter = MouseFilterEnum.Ignore };
		_content.AddThemeConstantOverride("separation", 4);
		AddChild(_content);
	}
}
