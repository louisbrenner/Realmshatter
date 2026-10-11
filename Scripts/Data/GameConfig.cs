using Godot;

namespace Realmshatter;

/// <summary>
/// Global rule configuration. Coordinates: X = column (0..BoardWidth-1, left to right),
/// Y = row (0..BoardHeight-1, row 0 is the top / far side of player 0).
/// </summary>
[GlobalClass]
public partial class GameConfig : Resource
{
	[ExportGroup("Board")]
	[Export] public int BoardWidth { get; set; } = 10;
	[Export] public int BoardHeight { get; set; } = 8;
	/// <summary>Scoring zone as (x, y, width, height). Default: columns 2-7, rows 3-4.</summary>
	[Export] public Rect2I ScoringZone { get; set; } = new Rect2I(2, 3, 6, 2);
	/// <summary>Number of back rows each player may deploy into.</summary>
	[Export] public int DeployRows { get; set; } = 2;

	[ExportGroup("Rules")]
	[Export] public int BaseAp { get; set; } = 3;
	[Export] public int UnitApCost { get; set; } = 1;
	[Export] public int SpellApCost { get; set; } = 2;
	[Export] public int PointsTarget { get; set; } = 20;
	[Export] public int StartingHandSize { get; set; } = 3;
	[Export] public int DraftOfferSize { get; set; } = 3;
	/// <summary>AP cost of the Draw action (draft offer of up to DraftOfferSize cards, keep one).</summary>
	[Export] public int DrawApCost { get; set; } = 1;
	/// <summary>AP cost of giving a piece a new order (replacing an existing order is free).</summary>
	[Export] public int OrderApCost { get; set; } = 1;
	/// <summary>Maximum victory points a player may convert into action points per turn (1 VP -> 1 AP).</summary>
	[Export] public int MaxVpToApPerTurn { get; set; } = 2;
	/// <summary>Extra AP for the second player (player 1) on its first turn.</summary>
	[Export] public int SecondPlayerFirstTurnBonusAp { get; set; } = 1;

	/// <summary>Damage dealt by Lava at the start of the occupant owner's turn.</summary>
	[ExportGroup("Map Effects & Keywords")]
	[Export] public int LavaDamage { get; set; } = 1;
	/// <summary>HP healed by a Healing tile at the start of the occupant owner's turn.</summary>
	[Export] public int HealingTileAmount { get; set; } = 1;
	/// <summary>Duration (global turns) of the Lava left by Burning attacks.</summary>
	[Export] public int BurningLavaDuration { get; set; } = 2;
	/// <summary>Duration (global turns) of Frozen; 1 = through the victim owner's next turn.</summary>
	[Export] public int FrostDuration { get; set; } = 1;
	/// <summary>Heal of a Mending hit on a friendly.</summary>
	[Export] public int MendingHeal { get; set; } = 1;
	/// <summary>Extra damage of Echo pieces' chain shots.</summary>
	[Export] public int EchoBonusDamage { get; set; } = 1;
	/// <summary>Damage multiplier of an Overcharged piece's chain shots.</summary>
	[Export] public int OverchargeMultiplier { get; set; } = 2;
	/// <summary>Duration (global turns) of statuses granted by spells (e.g. Overcharged).</summary>
	[Export] public int SpellStatusDuration { get; set; } = 2;
	/// <summary>Maximum number of friendlies a single move can push in a row.</summary>
	[Export] public int MaxPushChain { get; set; } = 3;
}
