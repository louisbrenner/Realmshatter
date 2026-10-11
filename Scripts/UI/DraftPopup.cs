using System;
using System.Collections.Generic;
using Godot;

namespace ProjectClaude;

/// <summary>
/// Modal "choose 1 of N" popup. While visible, the full-rect dim background blocks all board input.
/// Cards are revealed dramatically (fly in as card backs, flip, flash gold).
/// </summary>
public partial class DraftPopup : Control
{
	[Signal] public delegate void CardChosenEventHandler(int offerIndex);

	/// <summary>An offered card was hovered (true) or left (false); used for the card info panel.</summary>
	[Signal] public delegate void CardHoverChangedEventHandler(CardView card, bool hovered);

	[Export] public PackedScene CardScene { get; set; }
	/// <summary>Delay between the reveals of consecutive cards, in seconds.</summary>
	[Export] public float RevealStagger { get; set; } = 0.14f;

	private HBoxContainer _cardRow;
	private Label _titleLabel;
	private Control _panel;
	private readonly List<CardView> _cards = new List<CardView>();

	public override void _Ready()
	{
		_cardRow = GetNode<HBoxContainer>("Center/Panel/Margin/VBox/Cards");
		_titleLabel = GetNode<Label>("Center/Panel/Margin/VBox/Title");
		_panel = GetNodeOrNull<Control>("Center/Panel");
		MouseFilter = MouseFilterEnum.Ignore;
		Visible = false;
		ApplyStyle();
	}

	/// <summary>Shows the offer and makes the popup visible.</summary>
	public void ShowOffer(IReadOnlyList<CardData> offer, Func<CardData, int> costOf)
	{
		ClearCards();
		if (CardScene == null)
		{
			GD.PushError("DraftPopup: CardScene is not assigned.");
			return;
		}

		if (offer != null)
		{
			foreach (CardData card in offer)
			{
				var view = CardScene.Instantiate<CardView>();
				_cardRow.AddChild(view);
				view.Setup(card, costOf != null ? costOf(card) : card.ApCost);
				view.CardClicked += OnCardClicked;
				view.HoverChanged += OnCardHoverChanged;
				_cards.Add(view);
			}
		}

		_titleLabel.Text = "Choose a card";
		Visible = true;
		Sfx.Play(SfxId.CardDeal);
		PlayOpen();
		for (int i = 0; i < _cards.Count; i++)
		{
			_ = _cards[i].PlayReveal(0.12f + i * RevealStagger);
		}
	}

	/// <summary>Hides the popup and removes the offered cards.</summary>
	public void HidePopup()
	{
		Visible = false;
		ClearCards();
	}

	private void PlayOpen()
	{
		if (_panel == null)
		{
			return;
		}
		_panel.PivotOffset = _panel.Size * 0.5f;
		_panel.Scale = new Vector2(0.85f, 0.85f);
		_panel.Modulate = new Color(1, 1, 1, 0);
		Tween tween = _panel.CreateTween();
		tween.SetParallel(true);
		tween.TweenProperty(_panel, "scale", Vector2.One, 0.2f).SetTrans(Tween.TransitionType.Back).SetEase(Tween.EaseType.Out);
		tween.TweenProperty(_panel, "modulate:a", 1f, 0.15f);
		_titleLabel.PivotOffset = _titleLabel.Size * 0.5f;
		_titleLabel.Scale = new Vector2(1.4f, 1.4f);
		tween.TweenProperty(_titleLabel, "scale", Vector2.One, 0.3f).SetTrans(Tween.TransitionType.Back).SetEase(Tween.EaseType.Out);
	}

	private void ApplyStyle()
	{
		if (_panel is PanelContainer panel)
		{
			var style = new StyleBoxFlat
			{
				BgColor = new Color(0.14f, 0.085f, 0.05f, 0.96f),
				BorderColor = new Color(0.92f, 0.72f, 0.34f),
				ShadowColor = new Color(0f, 0f, 0f, 0.6f),
				ShadowSize = 24,
				CornerDetail = 8,
				AntiAliasing = true,
			};
			style.SetCornerRadiusAll(16);
			style.SetBorderWidthAll(3);
			panel.AddThemeStyleboxOverride("panel", style);
		}
		Font font = VfxAssets.CardFont;
		if (font != null)
		{
			_titleLabel.AddThemeFontOverride("font", font);
		}
		_titleLabel.AddThemeFontSizeOverride("font_size", 30);
		_titleLabel.AddThemeColorOverride("font_color", new Color(1f, 0.86f, 0.5f));
		_titleLabel.AddThemeColorOverride("font_outline_color", new Color(0.12f, 0.06f, 0.02f));
		_titleLabel.AddThemeConstantOverride("outline_size", 8);
		_cardRow.AddThemeConstantOverride("separation", 28);
	}

	private void OnCardClicked(CardView card)
	{
		int index = _cards.IndexOf(card);
		if (index >= 0)
		{
			Sfx.Play(SfxId.CardPick);
			EmitSignal(SignalName.CardChosen, index);
		}
	}

	private void OnCardHoverChanged(CardView card, bool hovered)
	{
		if (hovered)
		{
			Sfx.Play(SfxId.CardHover);
		}
		EmitSignal(SignalName.CardHoverChanged, card, hovered);
	}

	private void ClearCards()
	{
		foreach (CardView view in _cards)
		{
			view.CardClicked -= OnCardClicked;
			view.HoverChanged -= OnCardHoverChanged;
			EmitSignal(SignalName.CardHoverChanged, view, false);
			_cardRow.RemoveChild(view);
			view.QueueFree();
		}
		_cards.Clear();
	}
}
