using Godot;

namespace Realmshatter;

/// <summary>
/// Base for full-screen modal windows in the town (shop, deck builder): dim background, a wooden panel with a
/// title row, gold display and a close button. Derived classes fill Body. Emits Closed when dismissed.
/// </summary>
public partial class OverlayWindow : Control
{
	[Signal] public delegate void ClosedEventHandler();

	/// <summary>Panel size in HUD pixels.</summary>
	[Export] public Vector2 PanelSize { get; set; } = new Vector2(1080, 600);

	protected Label TitleLabel { get; private set; }
	protected Label SubtitleLabel { get; private set; }
	protected Label GoldLabel { get; private set; }
	protected HBoxContainer HeaderButtons { get; private set; }
	protected VBoxContainer Body { get; private set; }
	protected InfoPanel CardInfo { get; private set; }

	private CardSlot _infoOwner;

	/// <summary>True while open.</summary>
	public bool IsOpen => Visible;

	public override void _Ready()
	{
		EnsureBuilt();
	}

	/// <summary>Shows the window (derived classes refresh their content first).</summary>
	public virtual void Open()
	{
		EnsureBuilt();
		Visible = true;
		Modulate = new Color(1, 1, 1, 0);
		Tween tween = CreateTween();
		tween.TweenProperty(this, "modulate:a", 1f, 0.15f);
		RefreshGold();
	}

	/// <summary>Hides the window and emits Closed.</summary>
	public void Close()
	{
		if (!Visible)
		{
			return;
		}
		CardInfo?.HidePanel();
		Visible = false;
		Sfx.Play(SfxId.ButtonClick);
		EmitSignal(SignalName.Closed);
	}

	/// <summary>Updates the gold display.</summary>
	protected void RefreshGold()
	{
		if (GoldLabel != null)
		{
			GoldLabel.Text = $"{PlayerProfile.Gold} gold";
		}
	}

	/// <summary>Connects a slot's hover to the shared card info panel.</summary>
	protected void TrackHover(CardSlot slot)
	{
		slot.HoverChanged += (s, hovered) =>
		{
			if (hovered)
			{
				_infoOwner = s;
				Sfx.Play(SfxId.CardHover);
				CardInfo.ShowBeside(s.View, InfoText.Card(s.Card, s.Card.ApCost > 0 ? s.Card.ApCost : (s.Card.CardType == CardType.Unit ? 1 : 2)));
			}
			else if (_infoOwner == s)
			{
				_infoOwner = null;
				CardInfo.HidePanel();
			}
		};
	}

	/// <summary>Builds a wood-styled small toggle/tab button.</summary>
	protected static Button MakeButton(string text, int fontSize = 15)
	{
		var b = new Button { Text = text, FocusMode = FocusModeEnum.None, CustomMinimumSize = new Vector2(96, 30) };
		b.AddThemeFontSizeOverride("font_size", fontSize);
		return b;
	}

	/// <summary>Removes all children of a container.</summary>
	protected static void ClearChildren(Node node)
	{
		foreach (Node child in node.GetChildren())
		{
			node.RemoveChild(child);
			child.QueueFree();
		}
	}

	private void EnsureBuilt()
	{
		if (Body != null)
		{
			return;
		}
		SetAnchorsAndOffsetsPreset(LayoutPreset.FullRect);
		MouseFilter = MouseFilterEnum.Stop;
		Visible = false;

		var dim = new ColorRect { Color = new Color(0.02f, 0.01f, 0f, 0.72f), MouseFilter = MouseFilterEnum.Stop };
		dim.SetAnchorsAndOffsetsPreset(LayoutPreset.FullRect);
		AddChild(dim);
		var center = new CenterContainer { MouseFilter = MouseFilterEnum.Ignore };
		center.SetAnchorsAndOffsetsPreset(LayoutPreset.FullRect);
		AddChild(center);

		var panel = new PanelContainer { CustomMinimumSize = PanelSize, MouseFilter = MouseFilterEnum.Stop };
		StyleBoxFlat style = HudStyle.WoodPanel(HudStyle.Gold, 14);
		style.SetCornerRadiusAll(14);
		panel.AddThemeStyleboxOverride("panel", style);
		center.AddChild(panel);

		var outer = new VBoxContainer { MouseFilter = MouseFilterEnum.Ignore };
		outer.AddThemeConstantOverride("separation", 8);
		panel.AddChild(outer);

		var header = new HBoxContainer { MouseFilter = MouseFilterEnum.Ignore };
		header.AddThemeConstantOverride("separation", 14);
		outer.AddChild(header);
		TitleLabel = new Label { MouseFilter = MouseFilterEnum.Ignore };
		TitleLabel.AddThemeFontOverride("font", VfxAssets.CardTextBoldFont);
		TitleLabel.AddThemeFontSizeOverride("font_size", 26);
		TitleLabel.AddThemeColorOverride("font_color", HudStyle.Gold);
		TitleLabel.AddThemeConstantOverride("outline_size", 6);
		header.AddChild(TitleLabel);
		SubtitleLabel = new Label { MouseFilter = MouseFilterEnum.Ignore, SizeFlagsVertical = SizeFlags.ShrinkCenter, SizeFlagsHorizontal = SizeFlags.ExpandFill };
		SubtitleLabel.AddThemeFontOverride("font", VfxAssets.CardTextFont);
		SubtitleLabel.AddThemeFontSizeOverride("font_size", 15);
		SubtitleLabel.AddThemeColorOverride("font_color", HudStyle.TextLight);
		header.AddChild(SubtitleLabel);
		HeaderButtons = new HBoxContainer { MouseFilter = MouseFilterEnum.Ignore };
		HeaderButtons.AddThemeConstantOverride("separation", 6);
		header.AddChild(HeaderButtons);
		GoldLabel = new Label { MouseFilter = MouseFilterEnum.Ignore, SizeFlagsVertical = SizeFlags.ShrinkCenter };
		GoldLabel.AddThemeFontOverride("font", VfxAssets.CardTextBoldFont);
		GoldLabel.AddThemeFontSizeOverride("font_size", 20);
		GoldLabel.AddThemeColorOverride("font_color", HudStyle.Gold);
		GoldLabel.AddThemeConstantOverride("outline_size", 5);
		header.AddChild(GoldLabel);
		Button close = MakeButton("Close", 16);
		close.Pressed += Close;
		header.AddChild(close);

		Body = new VBoxContainer { MouseFilter = MouseFilterEnum.Ignore, SizeFlagsVertical = SizeFlags.ExpandFill };
		Body.AddThemeConstantOverride("separation", 8);
		outer.AddChild(Body);

		CardInfo = new InfoPanel { Name = "CardInfo", TextWidth = 240f };
		AddChild(CardInfo);
	}

	public override void _GuiInput(InputEvent @event)
	{
		if (@event is InputEventKey key && key.Pressed && key.Keycode == Key.Escape)
		{
			Close();
			AcceptEvent();
		}
	}
}
