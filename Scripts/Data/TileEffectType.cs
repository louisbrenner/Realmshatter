namespace Realmshatter;

/// <summary>Map-altering effect on a board tile (one effect per tile, a newer one replaces the older).</summary>
public enum TileEffectType
{
	None,
	/// <summary>Damages the occupant at the start of its owner's turn (GameConfig.LavaDamage). Passable.</summary>
	Lava,
	/// <summary>Impassable and unoccupiable; blocks movement, pushes, deploys and sideways chain shots.</summary>
	Wall,
	/// <summary>Heals the occupant at the start of its owner's turn (GameConfig.HealingTileAmount). Passable.</summary>
	Healing,
	/// <summary>Ruins of a destroyed building: impassable like a Wall until it expires.</summary>
	Rubble,
	/// <summary>Frozen ground (Frost attacks): a piece moving onto it slides to a halt there. Passable.</summary>
	Ice,
	/// <summary>Storm cell (Arc attacks): at the start of the occupant owner's turn, 1 damage to it and to every piece next to it.</summary>
	Storm,
	/// <summary>Mud (Push attacks): entering costs 2 movement. Passable.</summary>
	Mud,
}
