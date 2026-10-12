using System;
using Godot;

namespace Realmshatter;

/// <summary>Shop prices of cards (rarity, AP cost and effects) and the rarity colours.</summary>
public static class CardEconomy
{
	/// <summary>Gold a vendor asks for the card.</summary>
	public static int BuyPrice(CardData card)
	{
		if (card == null)
		{
			return 0;
		}
		int price = card.Rarity switch
		{
			CardRarity.Legendary => 900,
			CardRarity.Epic => 160,
			CardRarity.Rare => 60,
			_ => 25,
		};
		int cost = card.ApCost > 0 ? card.ApCost : (card.CardType == CardType.Unit ? 1 : 2);
		price += cost * 10;
		price += KeywordInfo.Split(card.Keywords).Count * 5;
		price += card.Deathrattle != DeathrattleType.None ? 10 : 0;
		price += card.OnFirstHit != FirstHitType.None ? 10 : 0;
		return price;
	}

	/// <summary>Gold a vendor pays for the card (40 % of its price).</summary>
	public static int SellPrice(CardData card) => card == null ? 0 : Math.Max(5, BuyPrice(card) * 2 / 5);

	/// <summary>Colour of a rarity (type plate, labels).</summary>
	public static Color RarityColor(CardRarity rarity) => rarity switch
	{
		CardRarity.Legendary => new Color(1f, 0.62f, 0.15f),
		CardRarity.Epic => new Color(0.66f, 0.34f, 0.92f),
		CardRarity.Rare => new Color(0.24f, 0.5f, 0.95f),
		_ => new Color(0.42f, 0.36f, 0.3f),
	};
}
