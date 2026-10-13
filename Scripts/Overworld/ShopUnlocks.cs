namespace Realmshatter;

/// <summary>
/// Which cards the vendors offer, based on the player's progress. Neutral 1-AP commons are always for sale, other
/// neutral commons after NeutralCommonWins wins and neutral rares after NeutralRareWins wins. Clan cards unlock clan by
/// clan: every clan card has a rank (Rank), and beating a clan's duelists (Initiate, Apprentice, Adept, Champion - any
/// order) raises that clan's progress by one each; beating the clan Leader unlocks every card of the clan, its
/// Legendary included.
/// </summary>
public static class ShopUnlocks
{
	/// <summary>Total wins (any NPC) before neutral commons of 2+ AP are sold.</summary>
	public const int NeutralCommonWins = 1;
	/// <summary>Total wins (any NPC) before neutral Rare cards are sold.</summary>
	public const int NeutralRareWins = 3;

	/// <summary>
	/// Unlock rank of a clan card: 0 = from the start (1-AP common units), 1 = the other commons, 2 = 1-AP rares and rare
	/// spells, 3 = 2-AP rare units, 4 = the expensive rares and the Epic, 5 = the Legendary (only after the Leader).
	/// </summary>
	public static int Rank(CardData card)
	{
		int cost = card.ApCost > 0 ? card.ApCost : 1;
		bool unit = card.CardType == CardType.Unit;
		return card.Rarity switch
		{
			CardRarity.Common => unit && cost <= 1 ? 0 : 1,
			CardRarity.Rare => cost <= 1 || !unit ? 2 : (cost == 2 ? 3 : 4),
			CardRarity.Epic => 4,
			_ => 5,
		};
	}

	/// <summary>NPC id prefix of a clan's duelists ("fire_", ...).</summary>
	public static string IdPrefix(Clan clan) => clan == Clan.None ? "" : clan.ToString().ToLowerInvariant() + "_";

	/// <summary>True once the clan's Leader has been beaten.</summary>
	public static bool LeaderDefeated(Clan clan) => clan != Clan.None && PlayerProfile.HasDefeated(IdPrefix(clan) + "leader");

	/// <summary>Number of the clan's four duelists (not the Leader) the player has beaten.</summary>
	public static int ClanProgress(Clan clan)
	{
		int n = 0;
		foreach (string rank in new[] { "initiate", "apprentice", "adept", "champion" })
		{
			n += PlayerProfile.HasDefeated(IdPrefix(clan) + rank) ? 1 : 0;
		}
		return n;
	}

	/// <summary>True if the vendors currently sell this card.</summary>
	public static bool IsAvailable(CardData card)
	{
		if (card == null)
		{
			return false;
		}
		if (card.Clan == Clan.None)
		{
			int cost = card.ApCost > 0 ? card.ApCost : 1;
			return card.Rarity == CardRarity.Common
				? cost <= 1 || PlayerProfile.DefeatedCount >= NeutralCommonWins
				: PlayerProfile.DefeatedCount >= NeutralRareWins;
		}
		return LeaderDefeated(card.Clan) || Rank(card) <= ClanProgress(card.Clan);
	}
}
