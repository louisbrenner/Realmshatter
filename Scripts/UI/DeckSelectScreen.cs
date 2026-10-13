using System.Collections.Generic;
using Godot;

namespace Realmshatter;

/// <summary>
/// Full-screen deck selection shown before a game: one wooden plaque per themed deck with its name, signature
/// card, description and composition. Hovering a plaque lifts it and shows the full deck list; clicking it emits
/// DeckChosen. Built entirely in code (Hud adds it to its root); blocks all input below while visible.
/// </summary>
public partial class DeckSelectScreen : Control
{
	[Signal] public delegate void DeckChosenEventHandler(int deckIndex);

	/// <summary>Card scene used for the signature cards (Scenes/UI/Card.tscn).</summary>
	[Export] public PackedScene CardScene { get; set; }
	[Export] public float PlaqueWidth { get; set; } = 198f;
	[Export] public float CardScale { get; set; } = 0.78f;

	private ColorRect _dim;
	private VBoxContainer _content;
	private HBoxContainer _row;
	private Label _title;
	private Label _subtitle;
	private InfoPanel _info;
	private readonly List<PanelContainer> _plaques = new List<PanelContainer>();
	private readonly List<StyleBoxFlat> _styles = new List<StyleBoxFlat>();
	private readonly List<Color> _accents = new List<Color>();
	private IReadOnlyList<DeckData> _decks = new List<DeckData>();
	private bool _choosing;
	private int _hovered = -1;

	public override void _Ready()
	{
		EnsureBuilt();
	}

	/// <summary>Shows the screen with one plaque per deck; 'title' replaces "Choose your deck" (e.g. hotseat).</summary>
	public void Present(IReadOnlyList<DeckData> decks, string title = null)
	{
		EnsureBuilt();
		_title.Text = string.IsNullOrEmpty(title) ? "Choose your deck" : title;
		ClearPlaques();
		_decks = decks ?? new List<DeckData>();
		_choosing = false;
		_hovered = -1;
		for (int i = 0; i < _decks.Count; i++)
		{
			BuildPlaque(i, _decks[i]);
		}

		SetAnchorsAndOffsetsPreset(LayoutPreset.FullRect);
		Visible = true;
		Modulate = new Color(1f, 1f, 1f, 0f);
		Tween fade = CreateTween();
		fade.TweenProperty(this, "modulate:a", 1f, 0.3f);
		_title.PivotOffset = _title.Size * 0.5f;
		_title.Scale = new Vector2(1.3f, 1.3f);
		fade.Parallel().TweenProperty(_title, "scale", Vector2.One, 0.4f).SetTrans(Tween.TransitionType.Back).SetEase(Tween.EaseType.Out);
		Callable.From(PopInPlaques).CallDeferred();
	}

	/// <summary>Hides the screen immediately.</summary>
	public void HideScreen()
	{
		_info?.HidePanel();
		Visible = false;
	}

	private void PopInPlaques()
	{
		for (int i = 0; i < _plaques.Count; i++)
		{
			PanelContainer plaque = _plaques[i];
			plaque.PivotOffset = plaque.Size * 0.5f;
			plaque.Scale = new Vector2(0.85f, 0.85f);
			plaque.Modulate = new Color(1f, 1f, 1f, 0f);
			float delay = 0.15f + i * 0.09f;
			Tween tween = plaque.CreateTween();
			tween.TweenInterval(delay);
			tween.SetParallel(true);
			tween.TweenProperty(plaque, "modulate:a", 1f, 0.2f);
			tween.TweenProperty(plaque, "scale", Vector2.One, 0.3f).SetTrans(Tween.TransitionType.Back).SetEase(Tween.EaseType.Out);
			Sfx.PlayDelayed(SfxId.CardDeal, delay);
		}
	}

	private void BuildPlaque(int index, DeckData deck)
	{
		Color accent = deck?.AccentColor ?? HudStyle.Gold;
		StyleBoxFlat style = HudStyle.WoodPanel(accent, 12);
		style.BorderWidthTop = 6;
		var plaque = new PanelContainer
		{
			Name = $"Deck{index}",
			CustomMinimumSize = new Vector2(PlaqueWidth, 0f),
			MouseFilter = MouseFilterEnum.Stop,
			MouseDefaultCursorShape = CursorShape.PointingHand,
		};
		plaque.AddThemeStyleboxOverride("panel", style);
		_row.AddChild(plaque);
		_plaques.Add(plaque);
		_styles.Add(style);
		_accents.Add(accent);

		var box = new VBoxContainer { MouseFilter = MouseFilterEnum.Ignore };
		box.AddThemeConstantOverride("separation", 8);
		plaque.AddChild(box);

		var name = new Label
		{
			Text = deck?.Name ?? "Deck",
			HorizontalAlignment = HorizontalAlignment.Center,
			MouseFilter = MouseFilterEnum.Ignore,
		};
		name.AddThemeFontOverride("font", VfxAssets.CardTextBoldFont);
		name.AddThemeFontSizeOverride("font_size", 21);
		name.AddThemeColorOverride("font_color", accent.Lerp(Colors.White, 0.35f));
		name.AddThemeColorOverride("font_outline_color", HudStyle.Outline);
		name.AddThemeConstantOverride("outline_size", 6);
		box.AddChild(name);

		CardData showcase = deck?.Showcase;
		if (showcase == null && deck != null && deck.Cards.Count > 0)
		{
			showcase = deck.Cards[0];
		}
		if (showcase != null && CardScene != null)
		{
			var holder = new Control
			{
				CustomMinimumSize = new Vector2(150f, 210f) * CardScale + new Vector2(0f, 6f),
				MouseFilter = MouseFilterEnum.Ignore,
			};
			box.AddChild(holder);
			var card = CardScene.Instantiate<CardView>();
			holder.AddChild(card);
			card.Setup(showcase, showcase.ApCost > 0 ? showcase.ApCost : (showcase.CardType == CardType.Unit ? 1 : 2));
			card.SetPlayable(false);
			card.Modulate = Colors.White;
			card.MouseFilter = MouseFilterEnum.Ignore;
			card.PivotOffset = Vector2.Zero;
			card.Scale = new Vector2(CardScale, CardScale);
			card.Position = new Vector2((PlaqueWidth - 24f - 150f * CardScale) * 0.5f, 4f);
		}

		var description = new Label
		{
			Text = deck?.Description ?? "",
			AutowrapMode = TextServer.AutowrapMode.WordSmart,
			HorizontalAlignment = HorizontalAlignment.Center,
			CustomMinimumSize = new Vector2(PlaqueWidth - 24f, 0f),
			MouseFilter = MouseFilterEnum.Ignore,
		};
		description.AddThemeFontOverride("font", VfxAssets.CardTextFont);
		description.AddThemeFontSizeOverride("font_size", 13);
		description.AddThemeColorOverride("font_color", HudStyle.TextLight);
		description.AddThemeConstantOverride("outline_size", 0);
		box.AddChild(description);

		int units = 0;
		int spells = 0;
		if (deck != null)
		{
			foreach (CardData c in deck.Cards)
			{
				if (c == null)
				{
					continue;
				}
				if (c.CardType == CardType.Unit)
				{
					units++;
				}
				else
				{
					spells++;
				}
			}
		}
		var composition = new Label
		{
			Text = $"{units} units  ·  {spells} spells",
			HorizontalAlignment = HorizontalAlignment.Center,
			MouseFilter = MouseFilterEnum.Ignore,
		};
		composition.AddThemeFontOverride("font", VfxAssets.CardTextBoldFont);
		composition.AddThemeFontSizeOverride("font_size", 13);
		composition.AddThemeColorOverride("font_color", HudStyle.Gold);
		composition.AddThemeConstantOverride("outline_size", 0);
		box.AddChild(composition);

		plaque.MouseEntered += () => OnPlaqueHover(index, true);
		plaque.MouseExited += () => OnPlaqueHover(index, false);
		plaque.GuiInput += e => OnPlaqueInput(index, e);
	}

	private void OnPlaqueHover(int index, bool hovered)
	{
		if (index < 0 || index >= _plaques.Count || _choosing)
		{
			return;
		}
		PanelContainer plaque = _plaques[index];
		StyleBoxFlat style = _styles[index];
		Color accent = _accents[index];
		plaque.PivotOffset = plaque.Size * 0.5f;
		Tween tween = plaque.CreateTween();
		tween.SetParallel(true);
		tween.TweenProperty(plaque, "scale", hovered ? new Vector2(1.04f, 1.04f) : Vector2.One, 0.12f)
			.SetTrans(Tween.TransitionType.Cubic).SetEase(Tween.EaseType.Out);
		style.BorderColor = hovered ? accent.Lerp(HudStyle.Gold, 0.3f) : accent.Lerp(HudStyle.GoldDark, 0.35f);
		style.ShadowColor = hovered ? new Color(accent, 0.55f) : new Color(0f, 0f, 0f, 0.5f);
		style.ShadowSize = hovered ? 22 : 10;
		style.SetBorderWidthAll(hovered ? 3 : 2);
		style.BorderWidthTop = 6;
		if (hovered)
		{
			_hovered = index;
			Sfx.Play(SfxId.CardHover);
			_info.ShowBeside(plaque, InfoText.Deck(_decks[index]));
		}
		else if (_hovered == index)
		{
			_hovered = -1;
			_info.HidePanel();
		}
	}

	private void OnPlaqueInput(int index, InputEvent e)
	{
		if (_choosing || e is not InputEventMouseButton mouse || !mouse.Pressed || mouse.ButtonIndex != MouseButton.Left)
		{
			return;
		}
		AcceptEvent();
		_choosing = true;
		_info.HidePanel();
		Sfx.Play(SfxId.CardPick);
		Sfx.Play(SfxId.Summon, -6f);
		PanelContainer plaque = _plaques[index];
		Tween tween = CreateTween();
		tween.TweenProperty(plaque, "scale", new Vector2(1.1f, 1.1f), 0.12f).SetTrans(Tween.TransitionType.Back).SetEase(Tween.EaseType.Out);
		tween.TweenProperty(this, "modulate:a", 0f, 0.3f);
		tween.TweenCallback(Callable.From(() =>
		{
			Visible = false;
			EmitSignal(SignalName.DeckChosen, index);
		}));
	}

	private void ClearPlaques()
	{
		foreach (PanelContainer plaque in _plaques)
		{
			_row.RemoveChild(plaque);
			plaque.QueueFree();
		}
		_plaques.Clear();
		_styles.Clear();
		_accents.Clear();
	}

	private void EnsureBuilt()
	{
		if (_dim != null)
		{
			return;
		}
		SetAnchorsAndOffsetsPreset(LayoutPreset.FullRect);
		MouseFilter = MouseFilterEnum.Stop;
		Visible = false;

		_dim = new ColorRect
		{
			Name = "Dim",
			Color = new Color(0.03f, 0.02f, 0.01f, 0.84f),
			MouseFilter = MouseFilterEnum.Stop,
		};
		_dim.SetAnchorsAndOffsetsPreset(LayoutPreset.FullRect);
		AddChild(_dim);

		var center = new CenterContainer { Name = "Center", MouseFilter = MouseFilterEnum.Ignore };
		center.SetAnchorsAndOffsetsPreset(LayoutPreset.FullRect);
		AddChild(center);

		_content = new VBoxContainer { MouseFilter = MouseFilterEnum.Ignore };
		_content.AddThemeConstantOverride("separation", 6);
		center.AddChild(_content);

		var gameTitle = new Label
		{
			Text = "REALMSHATTER",
			HorizontalAlignment = HorizontalAlignment.Center,
			MouseFilter = MouseFilterEnum.Ignore,
		};
		gameTitle.AddThemeFontOverride("font", new FontVariation { BaseFont = VfxAssets.CardTextBoldFont, SpacingGlyph = 6 });
		gameTitle.AddThemeFontSizeOverride("font_size", 46);
		gameTitle.AddThemeColorOverride("font_color", HudStyle.Gold);
		gameTitle.AddThemeColorOverride("font_shadow_color", new Color(1f, 0.45f, 0.1f, 0.55f));
		gameTitle.AddThemeConstantOverride("shadow_outline_size", 8);
		gameTitle.AddThemeColorOverride("font_outline_color", new Color(0.12f, 0.06f, 0.02f));
		gameTitle.AddThemeConstantOverride("outline_size", 8);
		_content.AddChild(gameTitle);

		_title = new Label
		{
			Text = "Choose your deck",
			HorizontalAlignment = HorizontalAlignment.Center,
			MouseFilter = MouseFilterEnum.Ignore,
		};
		_title.AddThemeFontOverride("font", VfxAssets.CardTextBoldFont);
		_title.AddThemeFontSizeOverride("font_size", 24);
		_title.AddThemeColorOverride("font_color", new Color(1f, 0.86f, 0.5f));
		_title.AddThemeColorOverride("font_outline_color", new Color(0.12f, 0.06f, 0.02f));
		_title.AddThemeConstantOverride("outline_size", 8);
		_content.AddChild(_title);

		_subtitle = new Label
		{
			Text = "Every deck has a theme - and a few cards borrowed from the others. Hover a deck to see its list.",
			HorizontalAlignment = HorizontalAlignment.Center,
			MouseFilter = MouseFilterEnum.Ignore,
		};
		_subtitle.AddThemeFontOverride("font", VfxAssets.CardTextFont);
		_subtitle.AddThemeFontSizeOverride("font_size", 14);
		_subtitle.AddThemeColorOverride("font_color", HudStyle.TextLight);
		_subtitle.AddThemeConstantOverride("outline_size", 0);
		_content.AddChild(_subtitle);

		var spacer = new Control { CustomMinimumSize = new Vector2(0f, 8f), MouseFilter = MouseFilterEnum.Ignore };
		_content.AddChild(spacer);

		_row = new HBoxContainer { MouseFilter = MouseFilterEnum.Ignore, Alignment = BoxContainer.AlignmentMode.Center };
		_row.AddThemeConstantOverride("separation", 14);
		_content.AddChild(_row);

		_info = new InfoPanel { Name = "DeckInfo", TextWidth = 230f, FontSize = 13 };
		AddChild(_info);
	}
}
