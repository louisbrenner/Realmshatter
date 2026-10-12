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
	[Export] public int BoardWidth { get; set; } = 12;
	[Export] public int BoardHeight { get; set; } = 16;
	/// <summary>
	/// Scoring zone as (x, y, width, height): an 8x8 area with a 2-tile neutral border around it
	/// (columns 2-9, rows 4-11 on the 12x16 board; rows 0-1 and 14-15 are the deploy rows).
	/// </summary>
	[Export] public Rect2I ScoringZone { get; set; } = new Rect2I(2, 4, 8, 8);
	/// <summary>The "crown" field inside the scoring zone: pieces there score HotZonePoints instead of 1.</summary>
	[Export] public Rect2I HotZone { get; set; } = new Rect2I(5, 7, 2, 2);
	/// <summary>VP per piece standing on the crown field at the start of its owner's turn.</summary>
	[Export] public int HotZonePoints { get; set; } = 2;
	/// <summary>Extra AP per finished Mana Well (building) at the start of its owner's turn.</summary>
	[Export] public int ManaWellAp { get; set; } = 1;
	/// <summary>Spells may only be cast on tiles within this many tiles (Manhattan) of one of your units.</summary>
	[Export] public int SpellCastRadius { get; set; } = 4;
	/// <summary>Your spells aimed within this many tiles (Manhattan) of your finished Obelisk are empowered (+1).</summary>
	[Export] public int ObeliskEmpowerRadius { get; set; } = 4;
	/// <summary>Duration (global turns) of the rubble a destroyed building leaves behind.</summary>
	[Export] public int RubbleDuration { get; set; } = 4;
	/// <summary>Number of back rows each player may deploy into.</summary>
	[Export] public int DeployRows { get; set; } = 2;

	[ExportGroup("Rules")]
	[Export] public int BaseAp { get; set; } = 3;
	[Export] public int UnitApCost { get; set; } = 1;
	[Export] public int SpellApCost { get; set; } = 2;
	[Export] public int PointsTarget { get; set; } = 25;
	[Export] public int StartingHandSize { get; set; } = 5;
	[Export] public int DraftOfferSize { get; set; } = 3;
	/// <summary>AP cost of the Draw action (draft offer of up to DraftOfferSize cards, keep one).</summary>
	[Export] public int DrawApCost { get; set; } = 1;
	/// <summary>AP cost of commanding a piece (its move + attack resolve immediately; once per piece and turn).</summary>
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
	[Export] public int BurningLavaDuration { get; set; } = 4;
	/// <summary>Duration (global turns) of the Ice, Storm cells, Healing springs and Mud that clan attacks leave behind.</summary>
	[Export] public int AttackGroundDuration { get; set; } = 4;
	/// <summary>Duration (global turns) of Frozen; 1 = through the victim owner's next turn.</summary>
	[Export] public int FrostDuration { get; set; } = 1;
	/// <summary>Heal of a Mending hit on a friendly.</summary>
	[Export] public int MendingHeal { get; set; } = 1;
	/// <summary>Damage of an Echo piece's second strike.</summary>
	[Export] public int EchoBonusDamage { get; set; } = 1;
	/// <summary>Damage multiplier of an Overcharged piece's next attack.</summary>
	[Export] public int OverchargeMultiplier { get; set; } = 2;
	/// <summary>Damage of an Arc piece's zap on each piece next to its target.</summary>
	[Export] public int ArcDamage { get; set; } = 1;
	/// <summary>Duration (global turns) of statuses granted by spells (e.g. Overcharged).</summary>
	[Export] public int SpellStatusDuration { get; set; } = 2;
	/// <summary>Duration (global turns) of Lava / Walls created by deathrattles.</summary>
	[Export] public int TriggerEffectDuration { get; set; } = 4;
	/// <summary>Damage a pushed piece takes when it is shoved into another piece, a building, a wall or a rock.</summary>
	[Export] public int PushCollisionDamage { get; set; } = 1;
	/// <summary>Maximum number of friendlies a single move can push in a row.</summary>
	[Export] public int MaxPushChain { get; set; } = 3;
	/// <summary>Movement a unit spends to enter a Water tile (rivers, ponds).</summary>
	[Export] public int WaterMoveCost { get; set; } = 2;
	/// <summary>Hit points of a breakable Rock wall.</summary>
	[Export] public int RockHp { get; set; } = 3;
	/// <summary>AP cost of setting a trap (Trapper keyword; replaces the attack of the unit's action).</summary>
	[Export] public int TrapApCost { get; set; } = 1;
	/// <summary>Traps one Trapper may have at once; setting another replaces its oldest.</summary>
	[Export] public int MaxTrapsPerTrapper { get; set; } = 2;
	/// <summary>Planted units may be deployed up to this many tiles (Manhattan) from one of their owner's units.</summary>
	[Export] public int PlantRadius { get; set; } = 2;
}
