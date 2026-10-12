using Godot;

namespace Realmshatter;

/// <summary>
/// A card shown in a grid (shop, deck builder): a scaled CardView, a caption line and an optional action button.
/// Clicking the card or the button emits Activated; hovering emits HoverChanged (for the card info panel).
/// </summary>
public partial class CardSlot : VBoxContainer
{
	[Signal] public delegate void ActivatedEventHandler(CardSlot slot);
	[Signal] public delegate void HoverChangedEventHandler(CardSlot slot, bool hovered);

	public const string CardScenePath = "res://Scenes/UI/Card.tscn";
	private static PackedScene _cardScene;

	private CardView _view;
	private Label _caption;
	private Button _button;
	private float _scale = 0.62f;

	/// <summary>The card shown.</summary>
	public CardData Card { get; private set; }

	/// <summary>The card view (for anchoring the info panel).</summary>
	public CardView View => _view;

	/// <summary>Builds the slot for a card at the given scale (call before adding it to the tree).</summary>
	public void Setup(CardData card, float scale, bool withButton)
	{
		Card = card;
		_scale = scale;
		MouseFilter = MouseFilterEnum.Ignore;
		AddThemeConstantOverride("separation", 4);

		var holder = new Control
		{
			CustomMinimumSize = new Vector2(150f, 210f) * scale,
			MouseFilter = MouseFilterEnum.Ignore,
		};
		AddChild(holder);
		_cardScene ??= GD.Load<PackedScene>(CardScenePath);
		_view = _cardScene.Instantiate<CardView>();
		_view.ManagedLayout = true;
		holder.AddChild(_view);
		_view.PivotOffset = Vector2.Zero;
		_view.Scale = new Vector2(scale, scale);
		_view.Setup(card, card.ApCost > 0 ? card.ApCost : (card.CardType == CardType.Unit ? 1 : 2));
		_view.SetPlayable(false);
		_view.Modulate = Colors.White;
		_view.CardClicked += _ => EmitSignal(SignalName.Activated, this);
		_view.HoverChanged += (_, hovered) => EmitSignal(SignalName.HoverChanged, this, hovered);

		_caption = new Label
		{
			HorizontalAlignment = HorizontalAlignment.Center,
			CustomMinimumSize = new Vector2(150f * scale, 0f),
			ClipText = true,
			TextOverrunBehavior = TextServer.OverrunBehavior.TrimEllipsis,
			MouseFilter = MouseFilterEnum.Ignore,
		};
		_caption.AddThemeFontOverride("font", VfxAssets.CardTextBoldFont);
		_caption.AddThemeFontSizeOverride("font_size", 11);
		_caption.AddThemeConstantOverride("outline_size", 4);
		AddChild(_caption);

		if (withButton)
		{
			_button = new Button { FocusMode = FocusModeEnum.None, CustomMinimumSize = new Vector2(150f * scale, 24f), ClipText = true };
			_button.AddThemeFontSizeOverride("font_size", 13);
			_button.Pressed += () => EmitSignal(SignalName.Activated, this);
			AddChild(_button);
		}
	}

	/// <summary>Sets the caption under the card.</summary>
	public void SetCaption(string text, Color color)
	{
		_caption.Text = text;
		_caption.AddThemeColorOverride("font_color", color);
	}

	/// <summary>Sets the action button (if any).</summary>
	public void SetButton(string text, bool enabled)
	{
		if (_button == null)
		{
			return;
		}
		_button.Text = text;
		_button.Disabled = !enabled;
	}

	/// <summary>Greys the card out (e.g. not affordable, all copies in the deck).</summary>
	public void SetDimmed(bool dimmed)
	{
		_view.Modulate = dimmed ? new Color(0.55f, 0.55f, 0.55f) : Colors.White;
	}

	/// <summary>Green glow (e.g. affordable / addable).</summary>
	public void SetHighlight(bool on)
	{
		_view.SetPlayable(on);
		if (_view.Modulate != Colors.White && on)
		{
			_view.Modulate = Colors.White;
		}
	}
}
