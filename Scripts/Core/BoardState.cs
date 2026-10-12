using System.Collections.Generic;
using Godot;

namespace Realmshatter;

/// <summary>
/// Grid and occupancy. Coordinate convention: X = column (0 = left), Y = row (0 = top).
/// Deploy ownership: player 0 owns the bottom DeployRows rows (Height-DeployRows .. Height-1)
/// and faces up (toward row 0, forward = -Y). Player 1 owns the top rows (0 .. DeployRows-1)
/// and faces down (forward = +Y).
/// </summary>
public sealed class BoardState
{
	private readonly Dictionary<GridPos, Piece> _occupancy = new Dictionary<GridPos, Piece>();
	private readonly Dictionary<GridPos, TileEffect> _tileEffects = new Dictionary<GridPos, TileEffect>();
	private readonly Dictionary<GridPos, TerrainType> _terrain = new Dictionary<GridPos, TerrainType>();
	private readonly Dictionary<GridPos, int> _terrainHp = new Dictionary<GridPos, int>();
	private readonly Dictionary<GridPos, TerrainType> _decor = new Dictionary<GridPos, TerrainType>();
	private readonly Dictionary<GridPos, Trap> _traps = new Dictionary<GridPos, Trap>();
	private int _trapSerial;

	public int Width { get; }
	public int Height { get; }
	public Rect2I ScoringZone { get; }
	/// <summary>The crown field inside the scoring zone (worth HotZonePoints per piece).</summary>
	public Rect2I HotZone { get; }
	public int HotZonePoints { get; }
	public int DeployRows { get; }
	/// <summary>Movement spent to enter a Water tile.</summary>
	public int WaterMoveCost { get; }

	public BoardState(GameConfig config)
	{
		WaterMoveCost = System.Math.Max(1, config.WaterMoveCost);
		Width = config.BoardWidth;
		Height = config.BoardHeight;
		ScoringZone = config.ScoringZone;
		HotZone = config.HotZone;
		HotZonePoints = config.HotZonePoints;
		DeployRows = config.DeployRows;
	}

	/// <summary>Copies dimensions and tile effects (occupancy is rebuilt by the cloning GameState).</summary>
	internal BoardState(BoardState other)
	{
		Width = other.Width;
		Height = other.Height;
		ScoringZone = other.ScoringZone;
		HotZone = other.HotZone;
		HotZonePoints = other.HotZonePoints;
		DeployRows = other.DeployRows;
		WaterMoveCost = other.WaterMoveCost;
		foreach (KeyValuePair<GridPos, TileEffect> kv in other._tileEffects)
		{
			_tileEffects[kv.Key] = kv.Value;
		}
		foreach (KeyValuePair<GridPos, TerrainType> kv in other._terrain)
		{
			_terrain[kv.Key] = kv.Value;
		}
		foreach (KeyValuePair<GridPos, int> kv in other._terrainHp)
		{
			_terrainHp[kv.Key] = kv.Value;
		}
		foreach (KeyValuePair<GridPos, TerrainType> kv in other._decor)
		{
			_decor[kv.Key] = kv.Value;
		}
		foreach (KeyValuePair<GridPos, Trap> kv in other._traps)
		{
			_traps[kv.Key] = kv.Value;
		}
		_trapSerial = other._trapSerial;
	}

	/// <summary>Tiles of an area shape anchored at 'anchor', clipped to the board.</summary>
	public List<GridPos> GetAreaTiles(GridPos anchor, AreaShape shape)
	{
		var offsets = shape switch
		{
			AreaShape.Plus => new[] { new GridPos(0, 0), new GridPos(0, -1), new GridPos(-1, 0), new GridPos(1, 0), new GridPos(0, 1) },
			AreaShape.Row3 => new[] { new GridPos(-1, 0), new GridPos(0, 0), new GridPos(1, 0) },
			AreaShape.Column3 => new[] { new GridPos(0, -1), new GridPos(0, 0), new GridPos(0, 1) },
			AreaShape.Square2 => new[] { new GridPos(0, 0), new GridPos(1, 0), new GridPos(0, 1), new GridPos(1, 1) },
			_ => new[] { new GridPos(0, 0) },
		};
		var result = new List<GridPos>();
		foreach (GridPos o in offsets)
		{
			GridPos p = anchor + o;
			if (IsInside(p))
			{
				result.Add(p);
			}
		}
		return result;
	}

	/// <summary>All occupied tiles and their pieces.</summary>
	public IReadOnlyDictionary<GridPos, Piece> Occupancy => _occupancy;

	/// <summary>True if the position lies on the board.</summary>
	public bool IsInside(GridPos pos) => pos.X >= 0 && pos.Y >= 0 && pos.X < Width && pos.Y < Height;

	/// <summary>True if a piece stands on the tile.</summary>
	public bool IsOccupied(GridPos pos) => _occupancy.ContainsKey(pos);

	/// <summary>Returns the piece on the tile, or null.</summary>
	public Piece GetPieceAt(GridPos pos) => _occupancy.TryGetValue(pos, out Piece p) ? p : null;

	/// <summary>True if the tile is inside the scoring zone.</summary>
	public bool IsInScoringZone(GridPos pos) =>
		pos.X >= ScoringZone.Position.X && pos.X < ScoringZone.End.X &&
		pos.Y >= ScoringZone.Position.Y && pos.Y < ScoringZone.End.Y;

	/// <summary>True if the tile is on the crown field (inside the scoring zone, worth more VP).</summary>
	public bool IsInHotZone(GridPos pos) =>
		HotZone.Size.X > 0 && HotZone.Size.Y > 0 && IsInScoringZone(pos) &&
		pos.X >= HotZone.Position.X && pos.X < HotZone.End.X &&
		pos.Y >= HotZone.Position.Y && pos.Y < HotZone.End.Y;

	/// <summary>VP a piece on this tile scores at its owner's turn start: HotZonePoints on the crown field, 1 in the zone, else 0.</summary>
	public int ScoreValue(GridPos pos) => IsInHotZone(pos) ? HotZonePoints : (IsInScoringZone(pos) ? 1 : 0);

	/// <summary>True if the tile is in the given player's deploy rows (player 0 bottom, player 1 top).</summary>
	public bool IsInDeployZone(int playerIndex, GridPos pos)
	{
		if (!IsInside(pos))
		{
			return false;
		}
		return playerIndex == 0 ? pos.Y >= Height - DeployRows : pos.Y < DeployRows;
	}

	/// <summary>Forward row direction of a player: -1 for player 0 (up), +1 for player 1 (down).</summary>
	public static int ForwardDirection(int playerIndex) => playerIndex == 0 ? -1 : 1;

	/// <summary>
	/// Column offset of the player's LEFT side, as seen from that player's facing.
	/// Player 0 faces up, so left = -X; player 1 faces down, so left = +X.
	/// </summary>
	public static int LeftDirection(int playerIndex) => playerIndex == 0 ? -1 : 1;

	// ------------------------------------------------------------------ tile effects

	/// <summary>All active tile effects by position (at most one per tile).</summary>
	public IReadOnlyDictionary<GridPos, TileEffect> TileEffects => _tileEffects;

	/// <summary>The tile effect on pos, or null.</summary>
	public TileEffect GetTileEffect(GridPos pos) => _tileEffects.TryGetValue(pos, out TileEffect e) ? e : null;

	/// <summary>Type of the tile effect on pos (None if there is none).</summary>
	public TileEffectType GetTileEffectType(GridPos pos) => _tileEffects.TryGetValue(pos, out TileEffect e) ? e.Type : TileEffectType.None;

	/// <summary>True if the tile carries a Wall or Rubble, or is a Rock (impassable, unoccupiable).</summary>
	public bool IsWall(GridPos pos) => GetTileEffectType(pos) is TileEffectType.Wall or TileEffectType.Rubble || GetTerrain(pos) == TerrainType.Rock;

	/// <summary>True if the tile is on the board and not a wall (pieces may stand on / walk over it).</summary>
	public bool IsPassable(GridPos pos) => IsInside(pos) && !IsWall(pos);

	internal void SetTileEffect(TileEffect effect) => _tileEffects[effect.Position] = effect;

	internal void RemoveTileEffect(GridPos pos) => _tileEffects.Remove(pos);

	// ------------------------------------------------------------------ terrain

	/// <summary>All terrain tiles (water, bridges, rocks) by position.</summary>
	public IReadOnlyDictionary<GridPos, TerrainType> Terrain => _terrain;

	/// <summary>Terrain of the tile (None = plain ground).</summary>
	public TerrainType GetTerrain(GridPos pos) => _terrain.TryGetValue(pos, out TerrainType t) ? t : TerrainType.None;

	/// <summary>
	/// Purely visual terrain (no rules): where a river or a ruined wall runs through the crown field it is shown as
	/// a shallow ford / low rubble there, but the tiles play as plain ground.
	/// </summary>
	public IReadOnlyDictionary<GridPos, TerrainType> Decor => _decor;

	internal void SetDecor(GridPos pos, TerrainType type)
	{
		if (type == TerrainType.None)
		{
			_decor.Remove(pos);
		}
		else
		{
			_decor[pos] = type;
		}
	}

	/// <summary>All hidden traps by tile (the view shows only the viewer's own ones).</summary>
	public IReadOnlyDictionary<GridPos, Trap> Traps => _traps;

	/// <summary>The trap on the tile, or null.</summary>
	public Trap GetTrap(GridPos pos) => _traps.TryGetValue(pos, out Trap t) ? t : null;

	internal Trap AddTrap(GridPos pos, int owner, TrapType type, int sourcePieceId)
	{
		var trap = new Trap(pos, owner, type, sourcePieceId, ++_trapSerial);
		_traps[pos] = trap;
		return trap;
	}

	internal void RemoveTrap(GridPos pos) => _traps.Remove(pos);

	/// <summary>Remaining hit points of a Rock (0 for other tiles).</summary>
	public int GetTerrainHp(GridPos pos) => _terrainHp.TryGetValue(pos, out int hp) ? hp : 0;

	/// <summary>Movement needed to step onto the tile (Water costs WaterMoveCost, everything else 1).</summary>
	public int MoveCost(GridPos pos) =>
		GetTerrain(pos) == TerrainType.Water ? WaterMoveCost : (GetTileEffectType(pos) == TileEffectType.Mud ? 2 : 1);

	internal void SetTerrain(GridPos pos, TerrainType type, int hp = 0)
	{
		if (type == TerrainType.None)
		{
			_terrain.Remove(pos);
			_terrainHp.Remove(pos);
			return;
		}
		_terrain[pos] = type;
		if (hp > 0)
		{
			_terrainHp[pos] = hp;
		}
		else
		{
			_terrainHp.Remove(pos);
		}
	}

	/// <summary>Damages a Rock; at 0 HP it crumbles to plain ground. Returns the remaining HP (-1 if no rock).</summary>
	internal int DamageRock(GridPos pos, int amount)
	{
		if (GetTerrain(pos) != TerrainType.Rock)
		{
			return -1;
		}
		int hp = System.Math.Max(0, GetTerrainHp(pos) - System.Math.Max(0, amount));
		if (hp <= 0)
		{
			SetTerrain(pos, TerrainType.None);
		}
		else
		{
			_terrainHp[pos] = hp;
		}
		return hp;
	}

	/// <summary>Removes all terrain and permanent map effects (the map generator starts from a clean board).</summary>
	internal void ClearMap()
	{
		_terrain.Clear();
		_terrainHp.Clear();
		_decor.Clear();
		var permanent = new List<GridPos>();
		foreach (KeyValuePair<GridPos, TileEffect> kv in _tileEffects)
		{
			if (kv.Value.IsPermanent)
			{
				permanent.Add(kv.Key);
			}
		}
		foreach (GridPos pos in permanent)
		{
			_tileEffects.Remove(pos);
		}
	}

	// ------------------------------------------------------------------ movement

	/// <summary>
	/// Tiles reachable from 'from' with at most 'movement' movement (Water costs WaterMoveCost per tile), paths
	/// blocked by occupied tiles and walls. Excludes the start tile.
	/// (Strict variant without friendly pass-through; the move rules use the overload with moverOwner.)
	/// </summary>
	public List<GridPos> GetReachableTiles(GridPos from, int movement)
	{
		var result = new List<GridPos>();
		foreach (GridPos pos in BuildPathTree(from, movement, -2).Keys)
		{
			if (pos != from)
			{
				result.Add(pos);
			}
		}
		return result;
	}

	/// <summary>True if 'to' equals 'from' or is reachable within 'movement' steps (strict variant).</summary>
	public bool CanReach(GridPos from, GridPos to, int movement) =>
		from == to || GetReachableTiles(from, movement).Contains(to);

	/// <summary>
	/// Move rules (v3): tiles a piece of 'moverOwner' can move to from 'from' in at most 'movement' orthogonal
	/// steps. FRIENDLY pieces do not block (they can be passed and the move may end on them - they get pushed
	/// at resolution); enemies and walls block. Excludes the start tile. BFS order.
	/// </summary>
	public List<GridPos> GetReachableTiles(GridPos from, int movement, int moverOwner)
	{
		var result = new List<GridPos>();
		foreach (GridPos pos in BuildPathTree(from, movement, moverOwner).Keys)
		{
			if (pos != from)
			{
				result.Add(pos);
			}
		}
		return result;
	}

	/// <summary>
	/// Shortest orthogonal path (move rules v3, see GetReachableTiles with moverOwner) from 'from' to 'to'
	/// within 'movement' steps. Returns the tiles AFTER 'from' (ending with 'to'), an empty list if
	/// from == to, or null if unreachable. Deterministic (neighbor order right, left, down, up).
	/// </summary>
	public List<GridPos> FindPath(GridPos from, GridPos to, int movement, int moverOwner)
	{
		if (from == to)
		{
			return new List<GridPos>();
		}
		Dictionary<GridPos, GridPos> parents = BuildPathTree(from, movement, moverOwner);
		if (!parents.ContainsKey(to))
		{
			return null;
		}
		var path = new List<GridPos>();
		GridPos cur = to;
		while (cur != from)
		{
			path.Add(cur);
			cur = parents[cur];
		}
		path.Reverse();
		return path;
	}

	/// <summary>
	/// Cheapest-path parent map (start maps to itself; Dijkstra, entering Water costs WaterMoveCost). Friendlies
	/// of 'moverOwner' are passable, enemies / buildings / walls block (moverOwner -2: every piece blocks).
	/// Deterministic: ties keep the first found path (neighbor order right, left, down, up).
	/// </summary>
	private Dictionary<GridPos, GridPos> BuildPathTree(GridPos from, int movement, int moverOwner)
	{
		var parents = new Dictionary<GridPos, GridPos> { [from] = from };
		if (movement <= 0)
		{
			return parents;
		}
		var dist = new Dictionary<GridPos, int> { [from] = 0 };
		var open = new List<GridPos> { from };
		var done = new HashSet<GridPos>();
		while (open.Count > 0)
		{
			int best = 0;
			for (int i = 1; i < open.Count; i++)
			{
				if (dist[open[i]] < dist[open[best]])
				{
					best = i;
				}
			}
			GridPos cur = open[best];
			open.RemoveAt(best);
			if (!done.Add(cur))
			{
				continue;
			}
			foreach (GridPos next in cur.Neighbors())
			{
				if (!IsPassable(next) || done.Contains(next))
				{
					continue;
				}
				Piece occupant = GetPieceAt(next);
				if (occupant != null && (moverOwner == -2 || occupant.OwnerIndex != moverOwner || occupant.IsBuilding))
				{
					continue;
				}
				int nd = dist[cur] + MoveCost(next);
				if (nd > movement || (dist.TryGetValue(next, out int old) && old <= nd))
				{
					continue;
				}
				dist[next] = nd;
				parents[next] = cur;
				open.Add(next);
			}
		}
		return parents;
	}

	/// <summary>Tiles with Manhattan distance 1..range from 'center' that are on the board.</summary>
	public List<GridPos> GetTilesInRange(GridPos center, int range)
	{
		var result = new List<GridPos>();
		for (int dy = -range; dy <= range; dy++)
		{
			for (int dx = -range; dx <= range; dx++)
			{
				int d = System.Math.Abs(dx) + System.Math.Abs(dy);
				if (d == 0 || d > range)
				{
					continue;
				}
				var pos = new GridPos(center.X + dx, center.Y + dy);
				if (IsInside(pos))
				{
					result.Add(pos);
				}
			}
		}
		return result;
	}

	/// <summary>True if 'target' is on the board and within Manhattan distance 1..range.</summary>
	public bool IsInAttackRange(GridPos from, GridPos target, int range)
	{
		int d = from.ManhattanDistance(target);
		return IsInside(target) && d >= 1 && d <= range;
	}

	internal void Place(Piece piece, GridPos pos)
	{
		_occupancy[pos] = piece;
		piece.Position = pos;
	}

	internal void MovePiece(Piece piece, GridPos to)
	{
		_occupancy.Remove(piece.Position);
		_occupancy[to] = piece;
		piece.Position = to;
	}

	internal void Remove(Piece piece)
	{
		if (_occupancy.TryGetValue(piece.Position, out Piece p) && p == piece)
		{
			_occupancy.Remove(piece.Position);
		}
	}
}
