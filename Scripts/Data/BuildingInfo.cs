using System.Collections.Generic;
using Godot;

namespace Realmshatter;

/// <summary>
/// Stats and texts of the buildings, which class builds what, and the runtime CardData each building piece uses
/// (CardType.Building, never in a deck). Construction time is counted in the owner's turns.
/// Clan versions: a building raised by a clan unit carries that clan ("Ember Turret", "Rime Barricade", ...). It works
/// like the plain building and additionally pulses its clan's aura onto the 8 surrounding tiles at the start of every
/// owner turn (OrderResolver.ResolveBuildingsTurnStart).
/// </summary>
public static class BuildingInfo
{
	private static readonly Dictionary<(BuildingType, Clan), CardData> Cards = new Dictionary<(BuildingType, Clan), CardData>();

	/// <summary>Building a Builder of this class constructs (None = this class cannot build).</summary>
	public static BuildingType ForClass(UnitClass unitClass) => unitClass switch
	{
		UnitClass.Archer => BuildingType.Turret,
		UnitClass.Worker => BuildingType.ManaWell,
		UnitClass.Cleric => BuildingType.Shrine,
		UnitClass.Guardian => BuildingType.Barricade,
		UnitClass.Swordsman => BuildingType.Barricade,
		UnitClass.Mage => BuildingType.Obelisk,
		_ => BuildingType.None,
	};

	public static string GetName(BuildingType type) => type switch
	{
		BuildingType.Turret => "Turret",
		BuildingType.ManaWell => "Mana Well",
		BuildingType.Shrine => "Shrine",
		BuildingType.Barricade => "Barricade",
		BuildingType.Obelisk => "Obelisk",
		_ => "",
	};

	/// <summary>Name prefix of a clan's buildings ("" for neutral ones).</summary>
	public static string ClanPrefix(Clan clan) => clan switch
	{
		Clan.Fire => "Ember",
		Clan.Frost => "Rime",
		Clan.Storm => "Storm",
		Clan.Stone => "Granite",
		Clan.Healing => "Dawn",
		_ => "",
	};

	/// <summary>Name of a building raised by a unit of 'clan' (e.g. "Ember Turret"; neutral = plain name).</summary>
	public static string GetName(BuildingType type, Clan clan) =>
		clan == Clan.None || type == BuildingType.None ? GetName(type) : $"{ClanPrefix(clan)} {GetName(type)}";

	/// <summary>Rule text of a clan building: the plain text plus its turn-start aura pulse.</summary>
	public static string GetDescription(BuildingType type, Clan clan) =>
		clan == Clan.None || type == BuildingType.None
			? GetDescription(type)
			: $"{GetDescription(type)} At the start of your turn it also {TriggerInfo.AuraText(clan)}";

	/// <summary>Rule text of a building.</summary>
	public static string GetDescription(BuildingType type) => type switch
	{
		BuildingType.Turret => "Once per enemy turn it shoots an enemy that moves into range (3 tiles) for 1 damage.",
		BuildingType.ManaWell => "+1 AP for its owner at the start of every turn.",
		BuildingType.Shrine => "Heals your pieces on the 8 surrounding tiles by 1 at the start of your turn.",
		BuildingType.Barricade => "Two sturdy blockers that hold a lane (one build places two).",
		BuildingType.Obelisk => "Empowers your spells aimed within 4 tiles of it: +1 damage, healing, stat change and duration.",
		_ => "",
	};

	/// <summary>AP the build action costs.</summary>
	public static int GetCost(BuildingType type) => type switch
	{
		BuildingType.ManaWell => 2,
		BuildingType.None => 0,
		_ => 1,
	};

	/// <summary>How many buildings one build action places (Barricades come in pairs).</summary>
	public static int GetBuildCount(BuildingType type) => type == BuildingType.Barricade ? 2 : 1;

	/// <summary>Own turns until the building is finished.</summary>
	public static int GetBuildTurns(BuildingType type) => type == BuildingType.ManaWell ? 2 : 1;

	/// <summary>The (shared, runtime) card describing a neutral building piece.</summary>
	public static CardData GetCard(BuildingType type) => GetCard(type, Clan.None);

	/// <summary>The (shared, runtime) card describing a building piece raised by a unit of 'clan'.</summary>
	public static CardData GetCard(BuildingType type, Clan clan)
	{
		if (Cards.TryGetValue((type, clan), out CardData card))
		{
			return card;
		}
		(int hp, int atk, int range, int shield, Color tint) = type switch
		{
			BuildingType.Turret => (4, 1, 3, 0, new Color(0.7f, 0.55f, 0.4f)),
			BuildingType.ManaWell => (3, 0, 1, 0, new Color(0.35f, 0.6f, 1f)),
			BuildingType.Shrine => (3, 0, 1, 0, new Color(1f, 0.9f, 0.55f)),
			BuildingType.Barricade => (3, 0, 1, 1, new Color(0.6f, 0.5f, 0.38f)),
			BuildingType.Obelisk => (3, 0, 1, 0, new Color(0.65f, 0.45f, 1f)),
			_ => (1, 0, 1, 0, Colors.Gray),
		};
		if (clan != Clan.None)
		{
			// Clan buildings are a little sturdier than plain ones.
			tint = tint.Lerp(ClanInfo.GetColor(clan), 0.6f);
			hp += 1;
		}
		card = new CardData
		{
			Name = GetName(type, clan),
			Description = GetDescription(type, clan),
			Clan = clan,
			CardType = CardType.Building,
			Role = UnitRole.Utility,
			Movement = 0,
			Attack = atk,
			Hp = hp,
			Range = range,
			Shield = shield,
			Tint = tint,
			Building = type,
		};
		Cards[(type, clan)] = card;
		return card;
	}
}
