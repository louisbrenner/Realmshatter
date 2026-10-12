using System.Collections.Generic;
using Godot;

namespace Realmshatter;

/// <summary>
/// Deck builder: the left grid shows every owned card (click to add a copy to the deck; caption = copies in deck /
/// owned), the right column lists the deck (mana gem with the cost, name, copies; click an entry to remove a copy,
/// hover it to see the full card beside the list). Cards are ordered by clan, then rarity, then cost and name.
/// Filters: All / Units / Spells. The deck must hold PlayerProfile.DeckMin..DeckMax cards with at most MaxCopies
/// copies of a card.
/// </summary>
public partial class DeckBuilderPanel : OverlayWindow
{
	private const float CardScale = 0.56f;
	private const float PreviewScale = 0.95f;
	private const float GemSize = 24f;

	private enum Filter
	{
		All,
		Units,
		Spells,
	}

	private Filter _filter = Filter.All;
	private GridContainer _grid;
	private VBoxContainer _deckList;
	private Label _deckTitle;
	private Label _deckStatus;
	private Label _message;
	private readonly List<Button> _filterButtons = new List<Button>();
	private PanelContainer _deckPanel;
	private CardView _preview;
	private Control _previewOwner;

	public override void Open()
	{
		base.Open();
		BuildLayout();
		TitleLabel.Text = "Deck Builder";
		SubtitleLabel.Text = "Click a card to add it, click a deck entry to remove it.";
		_message.Text = "";
		Rebuild();
	}

	private void BuildLayout()
	{
		if (_grid != null)
		{
			return;
		}
		foreach ((string label, Filter f) in new[] { ("All", Filter.All), ("Units", Filter.Units), ("Spells", Filter.Spells) })
		{
			Button b = MakeButton(label);
			b.Pressed += () =>
			{
				Sfx.Play(SfxId.ButtonClick);
				_filter = f;
				Rebuild();
			};
			HeaderButtons.AddChild(b);
			_filterButtons.Add(b);
		}

		var columns = new HBoxContainer { SizeFlagsVertical = SizeFlags.ExpandFill, MouseFilter = MouseFilterEnum.Ignore };
		columns.AddThemeConstantOverride("separation", 14);
		Body.AddChild(columns);

		var scroll = new ScrollContainer
		{
			SizeFlagsHorizontal = SizeFlags.ExpandFill,
			SizeFlagsVertical = SizeFlags.ExpandFill,
			HorizontalScrollMode = ScrollContainer.ScrollMode.Disabled,
			CustomMinimumSize = new Vector2(760, 500),
		};
		columns.AddChild(scroll);
		_grid = new GridContainer { Columns = 8, MouseFilter = MouseFilterEnum.Ignore };
		_grid.AddThemeConstantOverride("h_separation", 10);
		_grid.AddThemeConstantOverride("v_separation", 10);
		scroll.AddChild(_grid);

		var deckPanel = new PanelContainer { CustomMinimumSize = new Vector2(260, 0), MouseFilter = MouseFilterEnum.Ignore };
		_deckPanel = deckPanel;
		deckPanel.AddThemeStyleboxOverride("panel", HudStyle.Box(new Color(0.08f, 0.05f, 0.03f, 0.9f), HudStyle.GoldDark, 10, 2, 4));
		columns.AddChild(deckPanel);
		var deckBox = new VBoxContainer { MouseFilter = MouseFilterEnum.Ignore };
		deckBox.AddThemeConstantOverride("separation", 6);
		deckPanel.AddChild(deckBox);
		_deckTitle = new Label { HorizontalAlignment = HorizontalAlignment.Center, MouseFilter = MouseFilterEnum.Ignore };
		_deckTitle.AddThemeFontOverride("font", VfxAssets.CardTextBoldFont);
		_deckTitle.AddThemeFontSizeOverride("font_size", 20);
		_deckTitle.AddThemeColorOverride("font_color", HudStyle.Gold);
		_deckTitle.AddThemeConstantOverride("outline_size", 5);
		deckBox.AddChild(_deckTitle);
		_deckStatus = new Label
		{
			HorizontalAlignment = HorizontalAlignment.Center,
			AutowrapMode = TextServer.AutowrapMode.WordSmart,
			MouseFilter = MouseFilterEnum.Ignore,
		};
		_deckStatus.AddThemeFontOverride("font", VfxAssets.CardTextFont);
		_deckStatus.AddThemeFontSizeOverride("font_size", 13);
		deckBox.AddChild(_deckStatus);
		var deckScroll = new ScrollContainer
		{
			SizeFlagsVertical = SizeFlags.ExpandFill,
			HorizontalScrollMode = ScrollContainer.ScrollMode.Disabled,
			CustomMinimumSize = new Vector2(240, 360),
		};
		deckBox.AddChild(deckScroll);
		_deckList = new VBoxContainer { SizeFlagsHorizontal = SizeFlags.ExpandFill, MouseFilter = MouseFilterEnum.Ignore };
		_deckList.AddThemeConstantOverride("separation", 3);
		deckScroll.AddChild(_deckList);
		_message = new Label
		{
			HorizontalAlignment = HorizontalAlignment.Center,
			AutowrapMode = TextServer.AutowrapMode.WordSmart,
			MouseFilter = MouseFilterEnum.Ignore,
		};
		_message.AddThemeFontOverride("font", VfxAssets.CardTextFont);
		_message.AddThemeFontSizeOverride("font_size", 13);
		_message.AddThemeColorOverride("font_color", new Color(1f, 0.6f, 0.45f));
		deckBox.AddChild(_message);
	}

	private void Rebuild()
	{
		RefreshGold();
		for (int i = 0; i < _filterButtons.Count; i++)
		{
			_filterButtons[i].Disabled = (int)_filter == i;
		}
		CardInfo.HidePanel();
		HidePreview();
		ClearChildren(_grid);
		var ownedCards = new List<CardData>(PlayerProfile.GetOwnedCards());
		ownedCards.Sort(CompareCards);
		foreach (CardData card in ownedCards)
		{
			if ((_filter == Filter.Units && card.CardType != CardType.Unit) || (_filter == Filter.Spells && card.CardType != CardType.Spell))
			{
				continue;
			}
			var slot = new CardSlot();
			slot.Setup(card, CardScale, false);
			_grid.AddChild(slot);
			TrackHover(slot);
			int owned = PlayerProfile.OwnedCount(card);
			int inDeck = PlayerProfile.InDeckCount(card);
			bool canAdd = inDeck < owned && inDeck < PlayerProfile.MaxCopies && PlayerProfile.DeckCount < PlayerProfile.DeckMax;
			slot.SetCaption($"{inDeck} / {owned} in deck", inDeck > 0 ? HudStyle.Gold : HudStyle.TextLight);
			slot.SetHighlight(canAdd);
			slot.SetDimmed(!canAdd && inDeck >= owned);
			slot.Activated += OnAddCard;
		}
		RebuildDeckList();
	}

	private void RebuildDeckList()
	{
		ClearChildren(_deckList);
		int count = PlayerProfile.DeckCount;
		_deckTitle.Text = $"Your Deck ({count})";
		bool valid = PlayerProfile.DeckIsValid;
		_deckStatus.Text = valid
			? $"Ready for battle. ({PlayerProfile.DeckMin}-{PlayerProfile.DeckMax} cards, max {PlayerProfile.MaxCopies} copies)"
			: $"Needs {PlayerProfile.DeckMin}-{PlayerProfile.DeckMax} cards to battle.";
		_deckStatus.AddThemeColorOverride("font_color", valid ? new Color(0.55f, 1f, 0.55f) : new Color(1f, 0.55f, 0.45f));

		var counts = new List<(CardData Card, int Count)>();
		foreach (CardData card in PlayerProfile.GetDeck())
		{
			int i = counts.FindIndex(e => e.Card == card);
			if (i >= 0)
			{
				counts[i] = (card, counts[i].Count + 1);
			}
			else
			{
				counts.Add((card, 1));
			}
		}
		counts.Sort((a, b) => CompareCards(a.Card, b.Card));
		foreach ((CardData card, int n) in counts)
		{
			_deckList.AddChild(BuildDeckEntry(card, n));
		}
	}

	/// <summary>Clan (basic cards first), then rarity, then AP cost, then name.</summary>
	public static int CompareCards(CardData a, CardData b)
	{
		if (a.Clan != b.Clan)
		{
			return a.Clan.CompareTo(b.Clan);
		}
		if (a.Rarity != b.Rarity)
		{
			return a.Rarity.CompareTo(b.Rarity);
		}
		int ca = CostOf(a);
		int cb = CostOf(b);
		return ca != cb ? ca.CompareTo(cb) : string.Compare(a.Name, b.Name, System.StringComparison.Ordinal);
	}

	private static int CostOf(CardData card) => card.ApCost > 0 ? card.ApCost : (card.CardType == CardType.Unit ? 1 : 2);

	/// <summary>One deck row: clan stripe, mana gem with the cost, name (rarity colour) and the number of copies.</summary>
	private Button BuildDeckEntry(CardData card, int copies)
	{
		var entry = new Button
		{
			FocusMode = FocusModeEnum.None,
			TooltipText = "Click to remove one copy",
			SizeFlagsHorizontal = SizeFlags.ExpandFill,
			CustomMinimumSize = new Vector2(0f, 30f),
		};
		var row = new HBoxContainer { MouseFilter = MouseFilterEnum.Ignore };
		row.SetAnchorsPreset(LayoutPreset.FullRect);
		row.OffsetLeft = 6f;
		row.OffsetRight = -8f;
		row.AddThemeConstantOverride("separation", 7);
		entry.AddChild(row);

		var stripe = new ColorRect
		{
			Color = card.Clan == Clan.None ? new Color(0.3f, 0.28f, 0.26f) : ClanInfo.GetColor(card.Clan),
			CustomMinimumSize = new Vector2(4f, 22f),
			SizeFlagsVertical = SizeFlags.ShrinkCenter,
			MouseFilter = MouseFilterEnum.Ignore,
		};
		row.AddChild(stripe);

		var gem = new ColorRect
		{
			CustomMinimumSize = new Vector2(GemSize, GemSize),
			Size = new Vector2(GemSize, GemSize),
			SizeFlagsVertical = SizeFlags.ShrinkCenter,
			MouseFilter = MouseFilterEnum.Ignore,
		};
		var mat = new ShaderMaterial { Shader = VfxAssets.GetShader("card_badge") };
		mat.SetShaderParameter("shape", 3);
		mat.SetShaderParameter("fill_color", new Color(0.22f, 0.5f, 1f));
		mat.SetShaderParameter("rect_size", new Vector2(GemSize, GemSize));
		gem.Material = mat;
		var cost = new Label
		{
			Text = CostOf(card).ToString(),
			HorizontalAlignment = HorizontalAlignment.Center,
			VerticalAlignment = VerticalAlignment.Center,
			MouseFilter = MouseFilterEnum.Ignore,
		};
		cost.SetAnchorsPreset(LayoutPreset.FullRect);
		cost.AddThemeFontOverride("font", VfxAssets.NumberFont);
		cost.AddThemeFontSizeOverride("font_size", 14);
		cost.AddThemeColorOverride("font_color", Colors.White);
		cost.AddThemeColorOverride("font_outline_color", new Color(0.02f, 0.05f, 0.16f));
		cost.AddThemeConstantOverride("outline_size", 4);
		gem.AddChild(cost);
		row.AddChild(gem);

		var name = new Label
		{
			Text = card.Name,
			SizeFlagsHorizontal = SizeFlags.ExpandFill,
			VerticalAlignment = VerticalAlignment.Center,
			ClipText = true,
			TextOverrunBehavior = TextServer.OverrunBehavior.TrimEllipsis,
			MouseFilter = MouseFilterEnum.Ignore,
		};
		name.AddThemeFontOverride("font", VfxAssets.CardTextBoldFont);
		name.AddThemeFontSizeOverride("font_size", 14);
		name.AddThemeColorOverride("font_color", CardEconomy.RarityColor(card.Rarity).Lightened(0.55f));
		name.AddThemeConstantOverride("outline_size", 4);
		row.AddChild(name);

		var count = new Label { Text = $"x{copies}", VerticalAlignment = VerticalAlignment.Center, MouseFilter = MouseFilterEnum.Ignore };
		count.AddThemeFontOverride("font", VfxAssets.NumberFont);
		count.AddThemeFontSizeOverride("font_size", 14);
		count.AddThemeColorOverride("font_color", HudStyle.Gold);
		count.AddThemeConstantOverride("outline_size", 4);
		row.AddChild(count);

		entry.MouseEntered += () => ShowPreview(entry, card);
		entry.MouseExited += () =>
		{
			if (_previewOwner == entry)
			{
				HidePreview();
			}
		};
		entry.Pressed += () =>
		{
			Sfx.Play(SfxId.CardHover);
			PlayerProfile.RemoveFromDeck(card);
			_message.Text = "";
			Callable.From(Rebuild).CallDeferred();
		};
		return entry;
	}

	/// <summary>Shows the full card left of the deck list, level with the hovered entry (kept inside the window).</summary>
	private void ShowPreview(Control entry, CardData card)
	{
		if (_preview == null)
		{
			_cardScene ??= GD.Load<PackedScene>(CardSlot.CardScenePath);
			_preview = _cardScene.Instantiate<CardView>();
			_preview.ManagedLayout = true;
			_preview.ZIndex = 40;
			AddChild(_preview);
			_preview.MouseFilter = MouseFilterEnum.Ignore;
			_preview.PivotOffset = Vector2.Zero;
			_preview.Scale = new Vector2(PreviewScale, PreviewScale);
		}
		_previewOwner = entry;
		_preview.Setup(card, CostOf(card));
		_preview.SetPlayable(false);
		_preview.Modulate = Colors.White;
		Transform2D toLocal = GetGlobalTransform().AffineInverse();
		Vector2 panelPos = toLocal * _deckPanel.GetGlobalRect().Position;
		Vector2 entryPos = toLocal * entry.GetGlobalRect().Position;
		Vector2 size = new Vector2(150f, 210f) * PreviewScale;
		float x = panelPos.X - size.X - 12f;
		float y = Mathf.Clamp(entryPos.Y - size.Y * 0.4f, 8f, Mathf.Max(8f, Size.Y - size.Y - 8f));
		_preview.Position = new Vector2(x, y);
		_preview.Visible = true;
		Sfx.Play(SfxId.CardHover);
	}

	private void HidePreview()
	{
		_previewOwner = null;
		if (_preview != null)
		{
			_preview.Visible = false;
		}
	}

	private static PackedScene _cardScene;

	private void OnAddCard(CardSlot slot)
	{
		if (!PlayerProfile.TryAddToDeck(slot.Card, out string error))
		{
			_message.Text = error;
			Sfx.Play(SfxId.Blocked);
			return;
		}
		Sfx.Play(SfxId.CardPick);
		_message.Text = "";
		Callable.From(Rebuild).CallDeferred();
	}
}
