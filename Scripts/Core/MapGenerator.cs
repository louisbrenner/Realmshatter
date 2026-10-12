using System;
using System.Collections.Generic;

namespace Realmshatter;

/// <summary>
/// Random battlefield at game start. Every map has ONE theme so it stays readable:
/// Open Field (nothing), Riverlands (a river on each side with bridges; water slows movement), Volcanic Wastes
/// (lava patches), Ancient Ruins (breakable rock walls) or Sacred Springs (healing pools). The amount varies per
/// map, from a few tiles up to about every third tile of the open middle. Maps are point-symmetric (rotated 180°),
/// so both players face the same ground; deploy rows and the crown field stay free, and every map keeps a
/// walkable route from each player's back rows to the crown. A river or wall that runs through the crown field is
/// only drawn there (BoardState.Decor: a ford / low rubble) - the crown always plays as plain ground.
/// </summary>
public static class MapGenerator
{
	/// <summary>Name and one-line description of a generated map.</summary>
	public readonly record struct MapInfo(string Name, string Description);

	private const int MaxAttempts = 30;
	private const double MinDensity = 0.04;
	private const double MaxDensity = 0.33;

	/// <summary>Generates terrain and permanent map effects on the state's board (uses state.Random).</summary>
	public static MapInfo Generate(GameState state)
	{
		Random rng = state.Random;
		BoardState board = state.Board;
		int roll = rng.Next(100);
		double density = MinDensity + rng.NextDouble() * (MaxDensity - MinDensity);
		for (int attempt = 0; attempt < MaxAttempts; attempt++)
		{
			var terrain = new Dictionary<GridPos, TerrainType>();
			var effects = new Dictionary<GridPos, TileEffectType>();
			var decor = new Dictionary<GridPos, TerrainType>();
			MapInfo info;
			if (roll < 15)
			{
				info = new MapInfo("Open Field", "Clear ground - nothing in the way.");
			}
			else if (roll < 40)
			{
				info = new MapInfo("Riverlands", "Rivers slow every unit that wades through. Cross at the bridges.");
				BuildRivers(board, rng, density, terrain, decor);
			}
			else if (roll < 60)
			{
				info = new MapInfo("Volcanic Wastes", "Lava fields burn whoever ends a turn on them.");
				foreach (GridPos p in Blobs(board, rng, density, 1, 4, terrain, effects))
				{
					effects[p] = TileEffectType.Lava;
				}
			}
			else if (roll < 85)
			{
				info = new MapInfo("Ancient Ruins", "Crumbling rock walls block the way - break them with attacks.");
				foreach (GridPos p in Segments(board, rng, density * 0.8, terrain, effects, decor))
				{
					terrain[p] = TerrainType.Rock;
				}
			}
			else
			{
				info = new MapInfo("Sacred Springs", "Healing pools mend whoever rests in them.");
				foreach (GridPos p in Blobs(board, rng, density * 0.45, 1, 3, terrain, effects))
				{
					effects[p] = TileEffectType.Healing;
				}
			}
			if (!IsConnected(board, terrain) && attempt < MaxAttempts - 1)
			{
				continue;
			}
			Commit(state, terrain, effects, decor, info.Name);
			return info;
		}
		board.ClearMap();
		return new MapInfo("Open Field", "Clear ground - nothing in the way.");
	}

	private static void Commit(GameState state, Dictionary<GridPos, TerrainType> terrain, Dictionary<GridPos, TileEffectType> effects,
		Dictionary<GridPos, TerrainType> decor, string name)
	{
		BoardState board = state.Board;
		board.ClearMap();
		foreach (KeyValuePair<GridPos, TerrainType> kv in decor)
		{
			board.SetDecor(kv.Key, kv.Value);
		}
		foreach (KeyValuePair<GridPos, TerrainType> kv in terrain)
		{
			board.SetTerrain(kv.Key, kv.Value, kv.Value == TerrainType.Rock ? Math.Max(1, state.Config.RockHp) : 0);
		}
		foreach (KeyValuePair<GridPos, TileEffectType> kv in effects)
		{
			board.SetTileEffect(new TileEffect(kv.Value, kv.Key, -1, 0, TileEffect.Permanent, name));
		}
	}

	/// <summary>Point mirror (rotation by 180°) of a tile.</summary>
	private static GridPos Mirror(BoardState b, GridPos p) => new GridPos(b.Width - 1 - p.X, b.Height - 1 - p.Y);

	/// <summary>Open middle tiles where map features may go: no deploy rows, no crown field.</summary>
	private static bool IsEligible(BoardState b, GridPos p) =>
		b.IsInside(p) && p.Y >= b.DeployRows && p.Y < b.Height - b.DeployRows && !b.IsInHotZone(p);

	private static int EligibleCount(BoardState b)
	{
		int n = 0;
		for (int y = 0; y < b.Height; y++)
		{
			for (int x = 0; x < b.Width; x++)
			{
				n += IsEligible(b, new GridPos(x, y)) ? 1 : 0;
			}
		}
		return n;
	}

	private static bool IsFree(BoardState b, GridPos p, Dictionary<GridPos, TerrainType> terrain, Dictionary<GridPos, TileEffectType> effects) =>
		IsEligible(b, p) && !terrain.ContainsKey(p) && !effects.ContainsKey(p);

	/// <summary>Random patches of 'minSize'..'maxSize' tiles (plus their mirror images) until the density is reached.</summary>
	private static List<GridPos> Blobs(BoardState b, Random rng, double density, int minSize, int maxSize,
		Dictionary<GridPos, TerrainType> terrain, Dictionary<GridPos, TileEffectType> effects)
	{
		var placed = new HashSet<GridPos>();
		int target = (int)Math.Round(density * EligibleCount(b));
		for (int tries = 0; placed.Count < target && tries < 400; tries++)
		{
			var seed = new GridPos(rng.Next(b.Width), rng.Next(b.DeployRows, b.Height / 2));
			if (!IsFree(b, seed, terrain, effects) || placed.Contains(seed))
			{
				continue;
			}
			var blob = new List<GridPos> { seed };
			int size = rng.Next(minSize, maxSize + 1);
			for (int grow = 0; grow < size * 4 && blob.Count < size; grow++)
			{
				GridPos from = blob[rng.Next(blob.Count)];
				var around = new List<GridPos>(from.Neighbors());
				GridPos next = around[rng.Next(around.Count)];
				if (IsFree(b, next, terrain, effects) && !placed.Contains(next) && !blob.Contains(next))
				{
					blob.Add(next);
				}
			}
			foreach (GridPos p in blob)
			{
				placed.Add(p);
				GridPos m = Mirror(b, p);
				if (IsFree(b, m, terrain, effects))
				{
					placed.Add(m);
				}
			}
		}
		return new List<GridPos>(placed);
	}

	/// <summary>Short straight wall segments (1-3 tiles, plus mirror images) until the density is reached.</summary>
	private static List<GridPos> Segments(BoardState b, Random rng, double density,
		Dictionary<GridPos, TerrainType> terrain, Dictionary<GridPos, TileEffectType> effects, Dictionary<GridPos, TerrainType> decor)
	{
		var placed = new HashSet<GridPos>();
		int target = (int)Math.Round(density * EligibleCount(b));
		for (int tries = 0; placed.Count < target && tries < 400; tries++)
		{
			var start = new GridPos(rng.Next(b.Width), rng.Next(b.DeployRows, b.Height / 2));
			bool horizontal = rng.Next(2) == 0;
			int length = rng.Next(1, 4);
			var segment = new List<GridPos>();
			for (int i = 0; i < length; i++)
			{
				var p = horizontal ? new GridPos(start.X + i, start.Y) : new GridPos(start.X, start.Y + i);
				if (b.IsInHotZone(p))
				{
					// The wall runs on through the crown field as low rubble only.
					decor[p] = TerrainType.Rock;
					decor[Mirror(b, p)] = TerrainType.Rock;
					continue;
				}
				if (!IsFree(b, p, terrain, effects) || placed.Contains(p))
				{
					break;
				}
				segment.Add(p);
			}
			foreach (GridPos p in segment)
			{
				placed.Add(p);
				placed.Add(Mirror(b, p));
			}
		}
		return new List<GridPos>(placed);
	}

	/// <summary>
	/// One winding river across the board in front of each player (the second is the mirror image of the first),
	/// one or two tiles wide depending on the density, with 2-3 bridges each.
	/// </summary>
	private static void BuildRivers(BoardState b, Random rng, double density, Dictionary<GridPos, TerrainType> terrain,
		Dictionary<GridPos, TerrainType> decor)
	{
		if (rng.Next(3) == 0)
		{
			BuildCentralRiver(b, rng, terrain, decor);
			return;
		}
		bool wide = density > 0.2;
		int minRow = b.DeployRows + 1;
		int maxRow = b.Height / 2 - (wide ? 3 : 2);
		int row = rng.Next(minRow, maxRow + 1);
		var river = new List<GridPos>();
		int previous = row;
		for (int x = 0; x < b.Width; x++)
		{
			if (x > 0 && rng.Next(3) == 0)
			{
				row = Math.Clamp(row + (rng.Next(2) == 0 ? -1 : 1), minRow, maxRow);
			}
			// Keep the river connected orthogonally where it steps up or down.
			for (int y = Math.Min(row, previous); y <= Math.Max(row, previous); y++)
			{
				river.Add(new GridPos(x, y));
				if (wide)
				{
					river.Add(new GridPos(x, y + 1));
				}
			}
			previous = row;
		}
		int bridges = rng.Next(2, 4);
		var bridgeColumns = new HashSet<int>();
		for (int tries = 0; bridgeColumns.Count < bridges && tries < 50; tries++)
		{
			int c = rng.Next(1, b.Width - 1);
			if (!bridgeColumns.Contains(c - 1) && !bridgeColumns.Contains(c + 1))
			{
				bridgeColumns.Add(c);
			}
		}
		foreach (GridPos p in river)
		{
			if (!b.IsInside(p) || b.IsInHotZone(p))
			{
				continue;
			}
			TerrainType type = bridgeColumns.Contains(p.X) ? TerrainType.Bridge : TerrainType.Water;
			terrain[p] = type;
			terrain[Mirror(b, p)] = type;
		}
	}

	/// <summary>
	/// One straight river through the middle of the board (the two centre rows). Where it crosses the crown field it
	/// becomes a shallow ford (decoration only); 1-2 bridges on each side.
	/// </summary>
	private static void BuildCentralRiver(BoardState b, Random rng, Dictionary<GridPos, TerrainType> terrain, Dictionary<GridPos, TerrainType> decor)
	{
		int top = b.Height / 2 - 1;
		var bridgeColumns = new HashSet<int>();
		int bridges = rng.Next(1, 3);
		for (int tries = 0; bridgeColumns.Count < bridges && tries < 50; tries++)
		{
			int c = rng.Next(0, b.Width / 2);
			bool nearCrown = c >= b.HotZone.Position.X - 1 && c < b.HotZone.End.X + 1;
			if (!nearCrown && !bridgeColumns.Contains(c - 1) && !bridgeColumns.Contains(c + 1))
			{
				bridgeColumns.Add(c);
				bridgeColumns.Add(b.Width - 1 - c);
			}
		}
		for (int x = 0; x < b.Width; x++)
		{
			for (int y = top; y <= top + 1; y++)
			{
				var p = new GridPos(x, y);
				if (b.IsInHotZone(p))
				{
					decor[p] = TerrainType.Water;
					continue;
				}
				terrain[p] = bridgeColumns.Contains(x) ? TerrainType.Bridge : TerrainType.Water;
			}
		}
	}

	/// <summary>True if every back-row tile of player 0 can walk (ignoring pieces) to the crown field and to the enemy rows.</summary>
	private static bool IsConnected(BoardState b, Dictionary<GridPos, TerrainType> terrain)
	{
		var seen = new HashSet<GridPos>();
		var queue = new Queue<GridPos>();
		for (int x = 0; x < b.Width; x++)
		{
			var start = new GridPos(x, b.Height - 1);
			seen.Add(start);
			queue.Enqueue(start);
		}
		while (queue.Count > 0)
		{
			GridPos cur = queue.Dequeue();
			foreach (GridPos next in cur.Neighbors())
			{
				if (!b.IsInside(next) || seen.Contains(next) || (terrain.TryGetValue(next, out TerrainType t) && t == TerrainType.Rock))
				{
					continue;
				}
				seen.Add(next);
				queue.Enqueue(next);
			}
		}
		for (int y = 0; y < b.Height; y++)
		{
			for (int x = 0; x < b.Width; x++)
			{
				var p = new GridPos(x, y);
				bool needed = b.IsInHotZone(p) || y == 0;
				if (needed && !seen.Contains(p))
				{
					return false;
				}
				// No pocket of open ground may be cut off entirely.
				if (!seen.Contains(p) && !(terrain.TryGetValue(p, out TerrainType t) && t == TerrainType.Rock))
				{
					return false;
				}
			}
		}
		return true;
	}
}
