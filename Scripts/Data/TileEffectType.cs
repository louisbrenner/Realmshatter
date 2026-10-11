namespace ProjectClaude;

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
}
