using System.Collections.Generic;
using Godot;

namespace Realmshatter;

/// <summary>
/// Stats and texts of the buildings, which class builds what, and the runtime CardData each building piece uses
/// (CardType.Building, never in a deck). Construction time is counted in the owner's turns.
/// </summary>
public static class BuildingInfo
{
	private static readonly Dictionary<BuildingType, CardData> Cards = new Dictionary<BuildingType, CardData>();

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
		BuildingType.Barricade => 1,
		BuildingType.None => 0,
		_ => 2,
	};

	/// <summary>How many buildings one build action places (Barricades come in pairs).</summary>
	public static int GetBuildCount(BuildingType type) => type == BuildingType.Barricade ? 2 : 1;

	/// <summary>Own turns until the building is finished.</summary>
	public static int GetBuildTurns(BuildingType type) => type == BuildingType.Barricade ? 1 : 2;

	/// <summary>The (shared, runtime) card describing a building piece.</summary>
	public static CardData GetCard(BuildingType type)
	{
		if (Cards.TryGetValue(type, out CardData card))
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
		card = new CardData
		{
			Name = GetName(type),
			Description = GetDescription(type),
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
		Cards[type] = card;
		return card;
	}
}
