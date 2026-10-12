using Godot;

namespace Realmshatter;

/// <summary>
/// Screen UI of the town (scaled uniformly like the battle HUD): a status plaque (gold, deck size, duels won),
/// a Deck button, the interaction prompt, a toast line, the dialogue box, the shop and the deck builder.
/// </summary>
public partial class OverworldUi : CanvasLayer
{
	[Signal] public delegate void DeckButtonPressedEventHandler();

	[Export] public Vector2 ReferenceResolution { get; set; } = new Vector2(1152, 648);

	private Control _root;
	private Label _gold;
	private Label _deck;
	private Label _wins;
	private PanelContainer _prompt;
	private Label _promptLabel;
	private PanelContainer _toast;
	private Label _toastLabel;
	private Tween _toastTween;

	public DialogueBox Dialogue { get; private set; }
	public ShopPanel Shop { get; private set; }
	public DeckBuilderPanel DeckBuilder { get; private set; }

	/// <summary>True while any modal UI (dialogue, shop, deck builder) is open.</summary>
	public bool IsBusy => Dialogue.IsOpen || Shop.IsOpen || DeckBuilder.IsOpen;

	public override void _Ready()
	{
		_root = new Control { Name = "Root", MouseFilter = Control.MouseFilterEnum.Ignore, Theme = HudStyle.CreateTheme() };
		AddChild(_root);

		var status = new PanelContainer { Position = new Vector2(10, 10), MouseFilter = Control.MouseFilterEnum.Ignore };
		status.AddThemeStyleboxOverride("panel", HudStyle.WoodPanel(HudStyle.Gold, 10));
		_root.AddChild(status);
		var row = new HBoxContainer { MouseFilter = Control.MouseFilterEnum.Ignore };
		row.AddThemeConstantOverride("separation", 18);
		status.AddChild(row);
		_gold = MakeStat(row, HudStyle.Gold);
		_deck = MakeStat(row, HudStyle.TextLight);
		_wins = MakeStat(row, new Color(1f, 0.82f, 0.4f));

		var deckButton = new Button
		{
			Text = "Deck Builder (Tab)",
			FocusMode = Control.FocusModeEnum.None,
			AnchorLeft = 1f,
			AnchorRight = 1f,
			OffsetLeft = -200,
			OffsetRight = -10,
			OffsetTop = 12,
			OffsetBottom = 48,
		};
		deckButton.AddThemeFontSizeOverride("font_size", 16);
		deckButton.Pressed += () =>
		{
			Sfx.Play(SfxId.ButtonClick);
			EmitSignal(SignalName.DeckButtonPressed);
		};
		_root.AddChild(deckButton);

		var help = new Label
		{
			Text = "WASD / arrows: walk   E / Space: talk   Tab: deck builder",
			AnchorTop = 1f,
			AnchorBottom = 1f,
			OffsetLeft = 12,
			OffsetTop = -30,
			OffsetBottom = -8,
			MouseFilter = Control.MouseFilterEnum.Ignore,
		};
		help.AddThemeFontSizeOverride("font_size", 13);
		help.AddThemeConstantOverride("outline_size", 4);
		help.Modulate = new Color(1, 1, 1, 0.8f);
		_root.AddChild(help);

		_prompt = MakeRibbon(out _promptLabel);
		_prompt.AnchorTop = 1f;
		_prompt.AnchorBottom = 1f;
		_root.AddChild(_prompt);
		_toast = MakeRibbon(out _toastLabel);
		_root.AddChild(_toast);

		Dialogue = new DialogueBox { Name = "Dialogue" };
		_root.AddChild(Dialogue);
		Shop = new ShopPanel { Name = "Shop" };
		_root.AddChild(Shop);
		DeckBuilder = new DeckBuilderPanel { Name = "DeckBuilder" };
		_root.AddChild(DeckBuilder);
		Shop.Closed += RefreshStatus;
		DeckBuilder.Closed += RefreshStatus;

		PlayerProfile.Changed += RefreshStatus;
		GetViewport().SizeChanged += ApplyScale;
		ApplyScale();
		RefreshStatus();
	}

	public override void _ExitTree()
	{
		PlayerProfile.Changed -= RefreshStatus;
		Viewport viewport = GetViewport();
		if (viewport != null)
		{
			viewport.SizeChanged -= ApplyScale;
		}
	}

	public override void _Process(double delta)
	{
		// Keep floating ribbons centred (their size depends on the text).
		Vector2 size = _root.Size;
		_prompt.Position = new Vector2((size.X - _prompt.Size.X) * 0.5f, size.Y - 70f);
		_toast.Position = new Vector2((size.X - _toast.Size.X) * 0.5f, 60f);
		Dialogue.Position = new Vector2((size.X - Dialogue.Size.X) * 0.5f, size.Y - Dialogue.Size.Y - 16f);
	}

	/// <summary>Shows / hides the interaction prompt ("E: Talk to ...").</summary>
	public void SetPrompt(string text)
	{
		_promptLabel.Text = text ?? "";
		_prompt.Visible = !string.IsNullOrEmpty(text) && !IsBusy;
		_prompt.ResetSize();
	}

	/// <summary>Shows a message ribbon at the top for a few seconds.</summary>
	public void ShowToast(string text, float seconds = 3.5f)
	{
		_toastLabel.Text = text;
		_toast.ResetSize();
		_toast.Visible = true;
		_toast.Modulate = Colors.White;
		_toastTween?.Kill();
		_toastTween = CreateTween();
		_toastTween.TweenInterval(seconds);
		_toastTween.TweenProperty(_toast, "modulate:a", 0f, 0.5f);
		_toastTween.TweenCallback(Callable.From(() => _toast.Visible = false));
	}

	/// <summary>Refreshes gold / deck / duel counters.</summary>
	public void RefreshStatus()
	{
		if (_gold == null)
		{
			return;
		}
		_gold.Text = $"{PlayerProfile.Gold} gold";
		_deck.Text = $"Deck {PlayerProfile.DeckCount}" + (PlayerProfile.DeckIsValid ? "" : " (!)");
		_deck.AddThemeColorOverride("font_color", PlayerProfile.DeckIsValid ? HudStyle.TextLight : new Color(1f, 0.5f, 0.4f));
		_wins.Text = $"Duels won {PlayerProfile.DefeatedCount}";
	}

	private static Label MakeStat(Container parent, Color color)
	{
		var label = new Label { MouseFilter = Control.MouseFilterEnum.Ignore };
		label.AddThemeFontOverride("font", VfxAssets.CardTextBoldFont);
		label.AddThemeFontSizeOverride("font_size", 18);
		label.AddThemeColorOverride("font_color", color);
		label.AddThemeConstantOverride("outline_size", 5);
		parent.AddChild(label);
		return label;
	}

	private static PanelContainer MakeRibbon(out Label label)
	{
		var ribbon = new PanelContainer { Visible = false, MouseFilter = Control.MouseFilterEnum.Ignore };
		ribbon.AddThemeStyleboxOverride("panel", HudStyle.ParchmentPanel(20, 6));
		label = new Label { MouseFilter = Control.MouseFilterEnum.Ignore, HorizontalAlignment = HorizontalAlignment.Center };
		label.AddThemeFontOverride("font", VfxAssets.CardTextBoldFont);
		label.AddThemeFontSizeOverride("font_size", 17);
		label.AddThemeColorOverride("font_color", HudStyle.Ink);
		label.AddThemeConstantOverride("outline_size", 0);
		ribbon.AddChild(label);
		return ribbon;
	}

	private void ApplyScale()
	{
		Vector2 viewport = GetViewport().GetVisibleRect().Size;
		float scale = Mathf.Max(0.7f, Mathf.Min(viewport.X / ReferenceResolution.X, viewport.Y / ReferenceResolution.Y));
		_root.Scale = new Vector2(scale, scale);
		_root.Size = viewport / scale;
	}
}
