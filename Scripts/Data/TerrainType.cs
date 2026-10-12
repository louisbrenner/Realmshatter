namespace Realmshatter;

/// <summary>
/// Permanent ground of a tile, placed by the MapGenerator at game start (separate from the temporary tile effects,
/// so spells never wash a river away).
/// </summary>
public enum TerrainType
{
	None,
	/// <summary>River / pond: passable, but entering costs GameConfig.WaterMoveCost movement.</summary>
	Water,
	/// <summary>Bridge over a river: normal ground.</summary>
	Bridge,
	/// <summary>Breakable rock wall: impassable until attacks reduce its HP (GameConfig.RockHp) to 0.</summary>
	Rock,
}
