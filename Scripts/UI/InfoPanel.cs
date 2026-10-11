using Godot;

namespace Realmshatter;

/// <summary>
/// Parchment hover panel with rich text (built in code, never blocks the mouse). It either follows the mouse
/// cursor (board info) or sits beside a target control such as a hovered card, flipping sides and clamping so it
/// always stays inside its parent. Fades in softly.
/// </summary>
public partial class InfoPanel : PanelContainer
{
	/// <summary>Width of the text area in pixels (parent space).</summary>
	[Export] public float TextWidth { get; set; } = 250f;
	[Export] public int FontSize { get; set; } = 14;

	private const float CursorOffset = 22f;
	private const float Gap = 10f;
	private const float Margin = 6f;

	private RichTextLabel _text;
	private Tween _fade;
	private Control _target;
	private bool _followCursor;
	private string _content = "";

	public override void _Ready()
	{
		EnsureBuilt();
	}

	/// <summary>Shows the text next to the mouse cursor and keeps following it.</summary>
	public void ShowAtCursor(string bbcode)
	{
		_target = null;
		_followCursor = true;
		ShowText(bbcode);
	}

	/// <summary>Shows the text beside the target control (right side preferred) and tracks it while it moves.</summary>
	public void ShowBeside(Control target, string bbcode)
	{
		_target = target;
		_followCursor = false;
		ShowText(bbcode);
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

	private void ShowText(string bbcode)
	{
		EnsureBuilt();
		if (string.IsNullOrEmpty(bbcode))
		{
			HidePanel();
			return;
		}
		if (bbcode != _content)
		{
			_content = bbcode;
			_text.Text = bbcode;
			ResetSize();
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
		if (_text != null)
		{
			return;
		}
		MouseFilter = MouseFilterEnum.Ignore;
		Visible = false;
		ZIndex = 50;
		StyleBoxFlat style = HudStyle.ParchmentPanel(12, 9);
		style.BorderColor = new Color(0.42f, 0.26f, 0.09f);
		style.SetBorderWidthAll(2);
		style.ShadowSize = 12;
		style.ShadowColor = new Color(0f, 0f, 0f, 0.5f);
		style.SetCornerRadiusAll(8);
		AddThemeStyleboxOverride("panel", style);

		_text = new RichTextLabel
		{
			Name = "Text",
			BbcodeEnabled = true,
			FitContent = true,
			ScrollActive = false,
			AutowrapMode = TextServer.AutowrapMode.WordSmart,
			MouseFilter = MouseFilterEnum.Ignore,
			CustomMinimumSize = new Vector2(TextWidth, 0f),
		};
		_text.AddThemeFontOverride("normal_font", VfxAssets.CardTextFont);
		_text.AddThemeFontOverride("bold_font", VfxAssets.CardTextBoldFont);
		_text.AddThemeFontOverride("italics_font", new FontVariation
		{
			BaseFont = VfxAssets.CardTextFont,
			VariationTransform = new Transform2D(new Vector2(1f, 0f), new Vector2(0.2f, 1f), Vector2.Zero),
		});
		_text.AddThemeFontSizeOverride("normal_font_size", FontSize);
		_text.AddThemeFontSizeOverride("bold_font_size", FontSize);
		_text.AddThemeFontSizeOverride("italics_font_size", FontSize);
		_text.AddThemeColorOverride("default_color", HudStyle.Ink);
		_text.AddThemeConstantOverride("outline_size", 0);
		_text.AddThemeConstantOverride("line_separation", 1);
		AddChild(_text);
	}
}
