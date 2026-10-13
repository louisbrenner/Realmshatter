using System.Collections.Generic;

namespace Realmshatter;

/// <summary>Display names and rule texts of deathrattles and first-hit effects (cards, tooltips, log).</summary>
public static class TriggerInfo
{
	/// <summary>Display name of a deathrattle.</summary>
	public static string GetName(DeathrattleType type) => type switch
	{
		DeathrattleType.Explode => "Explode",
		DeathrattleType.Shockwave => "Shockwave",
		DeathrattleType.LavaPool => "Lava Pool",
		DeathrattleType.HealAllies => "Last Blessing",
		DeathrattleType.RaiseWalls => "Landslide",
		DeathrattleType.DrawCard => "Last Word",
		DeathrattleType.FrostNova => "Frost Nova",
		DeathrattleType.Tribute => "Tribute",
		_ => "",
	};

	/// <summary>The standard deathrattle of a clan (special cards may differ).</summary>
	public static DeathrattleType ClanDeathrattle(Clan clan) => clan switch
	{
		Clan.Fire => DeathrattleType.LavaPool,
		Clan.Healing => DeathrattleType.HealAllies,
		Clan.Frost => DeathrattleType.FrostNova,
		Clan.Storm => DeathrattleType.Explode,
		Clan.Stone => DeathrattleType.RaiseWalls,
		_ => DeathrattleType.None,
	};

	/// <summary>The standard first-hit effect of a class (special cards may differ).</summary>
	public static FirstHitType ClassFirstHit(UnitClass unitClass) => unitClass switch
	{
		UnitClass.Swordsman => FirstHitType.Enrage,
		UnitClass.Guardian => FirstHitType.Harden,
		UnitClass.Brute => FirstHitType.Shockwave,
		UnitClass.Archer => FirstHitType.Repel,
		UnitClass.Mage => FirstHitType.Repel,
		UnitClass.Lancer => FirstHitType.Thorns,
		_ => FirstHitType.None,
	};

	/// <summary>Name of a clan's aura.</summary>
	public static string AuraName(Clan clan) => clan switch
	{
		Clan.Fire => "Heat Aura",
		Clan.Healing => "Mending Aura",
		Clan.Frost => "Chill Aura",
		Clan.Storm => "Static Aura",
		Clan.Stone => "Bulwark Aura",
		_ => "Aura",
	};

	/// <summary>What a clan's aura does at the owner's turn start on the 8 surrounding tiles.</summary>
	public static string AuraText(Clan clan) => clan switch
	{
		Clan.Fire => "deals 1 damage to every adjacent enemy.",
		Clan.Healing => "heals every adjacent ally by 1.",
		Clan.Frost => "freezes every adjacent enemy.",
		Clan.Storm => "gives every adjacent ally +1 Attack this turn.",
		Clan.Stone => "gives every adjacent ally +1 Shield (up to 2).",
		_ => "has no effect.",
	};

	/// <summary>Display name of a first-hit effect.</summary>
	public static string GetName(FirstHitType type) => type switch
	{
		FirstHitType.Thorns => "Thorns",
		FirstHitType.Repel => "Repel",
		FirstHitType.Harden => "Harden",
		FirstHitType.Enrage => "Enrage",
		FirstHitType.Shockwave => "Shockwave",
		_ => "",
	};

	/// <summary>Rule text of a deathrattle with its strength.</summary>
	public static string Describe(DeathrattleType type, int amount) => type switch
	{
		DeathrattleType.Explode => $"deals {amount} damage to every piece next to it - friend or foe.",
		DeathrattleType.Shockwave => "pushes every piece next to it 1 tile away.",
		DeathrattleType.LavaPool => "its tile and the tiles next to it turn into Lava.",
		DeathrattleType.HealAllies => $"heals your pieces within 2 tiles by {amount} HP.",
		DeathrattleType.RaiseWalls => "raises Walls on the free tiles next to it.",
		DeathrattleType.DrawCard => amount == 1 ? "you draw a card from your deck." : $"you draw {amount} cards from your deck.",
		DeathrattleType.FrostNova => "every enemy next to it is Frozen.",
		DeathrattleType.Tribute => $"you gain {amount} AP at the start of your next turn.",
		_ => "",
	};

	/// <summary>Rule text of a first-hit effect with its strength.</summary>
	public static string Describe(FirstHitType type, int amount) => type switch
	{
		FirstHitType.Thorns => $"the attacker takes {amount} damage.",
		FirstHitType.Repel => "the attacker is pushed 1 tile away.",
		FirstHitType.Harden => $"it gains {amount} Shield.",
		FirstHitType.Enrage => $"it gains +{amount} Attack for the rest of the game.",
		FirstHitType.Shockwave => "it pushes every piece next to it 1 tile away.",
		_ => "",
	};

	/// <summary>Short card-face lines, e.g. "Deathrattle: Explode 2" / "First hit: Thorns 1".</summary>
	public static List<string> CardFaceLines(CardData card)
	{
		var lines = new List<string>();
		if (card == null || card.CardType != CardType.Unit)
		{
			return lines;
		}
		if (card.HasKeyword(Keyword.Builder) && BuildingInfo.ForClass(card.Class) != BuildingType.None)
		{
			lines.Add($"Builds: {BuildingInfo.GetName(BuildingInfo.ForClass(card.Class), card.Clan)}");
		}
		if (card.HasKeyword(Keyword.Aura))
		{
			lines.Add($"Aura: {AuraName(card.Clan)}");
		}
		if (card.OnFirstHit != FirstHitType.None)
		{
			lines.Add($"First hit: {GetName(card.OnFirstHit)}{AmountSuffix(card.OnFirstHit, card.OnFirstHitAmount)}");
		}
		if (card.Deathrattle != DeathrattleType.None)
		{
			lines.Add($"Deathrattle: {GetName(card.Deathrattle)}{AmountSuffix(card.Deathrattle, card.DeathrattleAmount)}");
		}
		return lines;
	}

	private static string AmountSuffix(DeathrattleType type, int amount) =>
		type is DeathrattleType.Explode or DeathrattleType.HealAllies or DeathrattleType.DrawCard ? $" {amount}"
			: (type == DeathrattleType.Tribute ? $" +{amount} AP" : "");

	private static string AmountSuffix(FirstHitType type, int amount) =>
		type is FirstHitType.Thorns or FirstHitType.Harden or FirstHitType.Enrage ? $" {amount}" : "";
}
