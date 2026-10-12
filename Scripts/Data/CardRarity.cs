namespace Realmshatter;

/// <summary>Rarity of a card: drives its shop price and the colour of its type plate.</summary>
public enum CardRarity
{
	Common,
	Rare,
	Epic,
	/// <summary>One unique unit per clan with a one-of-a-kind effect (LegendEffect); max 1 copy per deck, very expensive.</summary>
	Legendary,
}
