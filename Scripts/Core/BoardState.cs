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

	public int Width { get; }
	public int Height { get; }
	public Rect2I ScoringZone { get; }
	public int DeployRows { get; }

	public BoardState(GameConfig config)
	{
		Width = config.BoardWidth;
		Height = config.BoardHeight;
		ScoringZone = config.ScoringZone;
		DeployRows = config.DeployRows;
	}

	/// <summary>Copies dimensions and tile effects (occupancy is rebuilt by the cloning GameState).</summary>
	internal BoardState(BoardState other)
	{
		Width = other.Width;
		Height = other.Height;
		ScoringZone = other.ScoringZone;
		DeployRows = other.DeployRows;
		foreach (KeyValuePair<GridPos, TileEffect> kv in other._tileEffects)
		{
			_tileEffects[kv.Key] = kv.Value;
		}
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

	/// <summary>True if the tile carries a Wall (impassable, unoccupiable).</summary>
	public bool IsWall(GridPos pos) => GetTileEffectType(pos) == TileEffectType.Wall;

	/// <summary>True if the tile is on the board and not a wall (pieces may stand on / walk over it).</summary>
	public bool IsPassable(GridPos pos) => IsInside(pos) && !IsWall(pos);

	internal void SetTileEffect(TileEffect effect) => _tileEffects[effect.Position] = effect;

	internal void RemoveTileEffect(GridPos pos) => _tileEffects.Remove(pos);

	// ------------------------------------------------------------------ movement

	/// <summary>
	/// Tiles reachable from 'from' with at most 'movement' orthogonal steps, paths blocked by
	/// occupied tiles and walls. Excludes the start tile. Result is sorted by distance (BFS order).
	/// (Strict variant without friendly pass-through; the move rules use the overload with moverOwner.)
	/// </summary>
	public List<GridPos> GetReachableTiles(GridPos from, int movement)
	{
		var result = new List<GridPos>();
		if (movement <= 0)
		{
			return result;
		}
		var dist = new Dictionary<GridPos, int> { [from] = 0 };
		var queue = new Queue<GridPos>();
		queue.Enqueue(from);
		while (queue.Count > 0)
		{
			GridPos cur = queue.Dequeue();
			int d = dist[cur];
			if (d >= movement)
			{
				continue;
			}
			foreach (GridPos next in cur.Neighbors())
			{
				if (!IsPassable(next) || IsOccupied(next) || dist.ContainsKey(next))
				{
					continue;
				}
				dist[next] = d + 1;
				result.Add(next);
				queue.Enqueue(next);
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

	/// <summary>BFS parent map (start maps to itself). Friendlies passable, enemies / walls block.</summary>
	private Dictionary<GridPos, GridPos> BuildPathTree(GridPos from, int movement, int moverOwner)
	{
		var parents = new Dictionary<GridPos, GridPos> { [from] = from };
		if (movement <= 0)
		{
			return parents;
		}
		var dist = new Dictionary<GridPos, int> { [from] = 0 };
		var queue = new Queue<GridPos>();
		queue.Enqueue(from);
		while (queue.Count > 0)
		{
			GridPos cur = queue.Dequeue();
			int d = dist[cur];
			if (d >= movement)
			{
				continue;
			}
			foreach (GridPos next in cur.Neighbors())
			{
				if (!IsPassable(next) || dist.ContainsKey(next))
				{
					continue;
				}
				Piece occupant = GetPieceAt(next);
				if (occupant != null && occupant.OwnerIndex != moverOwner)
				{
					continue;
				}
				dist[next] = d + 1;
				parents[next] = cur;
				queue.Enqueue(next);
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
