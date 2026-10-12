using System.Collections.Generic;
using Godot;

namespace Realmshatter;

/// <summary>
/// Vendor window: "Buy" lists the vendor's stock with prices (affordable cards glow), "Sell" lists every owned
/// card with its sell price and how many copies are owned / in the deck. Hover a card for its full rules.
/// </summary>
public partial class ShopPanel : OverlayWindow
{
	private const float CardScale = 0.62f;

	private VendorData _vendor;
	private bool _sellMode;
	private Button _buyTab;
	private Button _sellTab;
	private GridContainer _grid;
	private Label _message;

	/// <summary>Opens the shop of a vendor on the Buy tab.</summary>
	public void OpenFor(VendorData vendor)
	{
		_vendor = vendor;
		_sellMode = false;
		Open();
		BuildLayout();
		TitleLabel.Text = vendor.Name;
		Rebuild();
	}

	private void BuildLayout()
	{
		if (_grid != null)
		{
			return;
		}
		_buyTab = MakeButton("Buy");
		_buyTab.Pressed += () => SetMode(false);
		_sellTab = MakeButton("Sell");
		_sellTab.Pressed += () => SetMode(true);
		HeaderButtons.AddChild(_buyTab);
		HeaderButtons.AddChild(_sellTab);

		_message = new Label { HorizontalAlignment = HorizontalAlignment.Center, MouseFilter = MouseFilterEnum.Ignore };
		_message.AddThemeFontOverride("font", VfxAssets.CardTextFont);
		_message.AddThemeFontSizeOverride("font_size", 15);
		_message.AddThemeColorOverride("font_color", HudStyle.TextLight);
		Body.AddChild(_message);

		var scroll = new ScrollContainer
		{
			SizeFlagsVertical = SizeFlags.ExpandFill,
			HorizontalScrollMode = ScrollContainer.ScrollMode.Disabled,
			CustomMinimumSize = new Vector2(0, 470),
		};
		Body.AddChild(scroll);
		_grid = new GridContainer { Columns = 8, SizeFlagsHorizontal = SizeFlags.ExpandFill, MouseFilter = MouseFilterEnum.Ignore };
		_grid.AddThemeConstantOverride("h_separation", 14);
		_grid.AddThemeConstantOverride("v_separation", 12);
		scroll.AddChild(_grid);
	}

	private void SetMode(bool sell)
	{
		Sfx.Play(SfxId.ButtonClick);
		_sellMode = sell;
		Rebuild();
	}

	private void Rebuild()
	{
		RefreshGold();
		_buyTab.Disabled = !_sellMode;
		_sellTab.Disabled = _sellMode;
		SubtitleLabel.Text = _sellMode ? "Sell cards you don't need." : (_vendor?.Title ?? "");
		_message.Text = _sellMode
			? "Selling a card used in your deck removes it from the deck."
			: (_vendor?.Greeting ?? "");
		CardInfo.HidePanel();
		ClearChildren(_grid);

		var cards = new List<CardData>();
		if (_sellMode)
		{
			cards.AddRange(PlayerProfile.GetOwnedCards());
		}
		else if (_vendor != null)
		{
			foreach (CardData c in _vendor.Stock)
			{
				if (c != null && !cards.Contains(c))
				{
					cards.Add(c);
				}
			}
		}
		cards.Sort(DeckBuilderPanel.CompareCards);
		foreach (CardData card in cards)
		{
			var slot = new CardSlot();
			slot.Setup(card, CardScale, true);
			_grid.AddChild(slot);
			TrackHover(slot);
			int owned = PlayerProfile.OwnedCount(card);
			if (_sellMode)
			{
				slot.SetCaption($"Own {owned} · Deck {PlayerProfile.InDeckCount(card)}", HudStyle.TextLight);
				slot.SetButton($"Sell {CardEconomy.SellPrice(card)}g", true);
			}
			else
			{
				int price = CardEconomy.BuyPrice(card);
				bool affordable = PlayerProfile.Gold >= price;
				slot.SetCaption(owned > 0 ? $"{card.Rarity} · own {owned}" : card.Rarity.ToString(), CardEconomy.RarityColor(card.Rarity).Lightened(0.35f));
				slot.SetButton($"Buy {price}g", affordable);
				slot.SetHighlight(affordable);
				slot.SetDimmed(!affordable);
			}
			slot.Activated += OnSlotActivated;
		}
	}

	private void OnSlotActivated(CardSlot slot)
	{
		CardData card = slot.Card;
		string error;
		bool ok = _sellMode ? PlayerProfile.TrySell(card, out error) : PlayerProfile.TryBuy(card, out error);
		if (!ok)
		{
			_message.Text = error;
			Sfx.Play(SfxId.Blocked);
			return;
		}
		Sfx.Play(SfxId.Coin);
		string text = _sellMode
			? $"Sold {card.Name} for {CardEconomy.SellPrice(card)} gold."
			: $"Bought {card.Name}! Add it to your deck in the deck builder (Tab).";
		Callable.From(() =>
		{
			Rebuild();
			_message.Text = text;
		}).CallDeferred();
	}
}
