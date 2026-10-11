using System;
using System.Collections.Generic;
using Godot;

namespace ProjectClaude;

/// <summary>
/// Immutable board coordinate. X = column (left to right), Y = row (row 0 = top,
/// the side of player 1; row Height-1 = bottom, the side of player 0).
/// </summary>
public readonly struct GridPos : IEquatable<GridPos>
{
	/// <summary>The four orthogonal unit offsets: right, left, down (+Y), up (-Y).</summary>
	public static readonly GridPos[] OrthogonalDirections =
	{
		new GridPos(1, 0), new GridPos(-1, 0), new GridPos(0, 1), new GridPos(0, -1),
	};

	public int X { get; }
	public int Y { get; }

	public GridPos(int x, int y)
	{
		X = x;
		Y = y;
	}

	/// <summary>Manhattan (taxicab) distance between two positions.</summary>
	public int ManhattanDistance(GridPos other) => Math.Abs(X - other.X) + Math.Abs(Y - other.Y);

	/// <summary>The four orthogonal neighbors (may lie outside the board).</summary>
	public IEnumerable<GridPos> Neighbors()
	{
		foreach (GridPos d in OrthogonalDirections)
		{
			yield return this + d;
		}
	}

	/// <summary>Converts to a Godot Vector2I (X, Y).</summary>
	public Vector2I ToVector2I() => new Vector2I(X, Y);

	/// <summary>Creates a GridPos from a Godot Vector2I.</summary>
	public static GridPos FromVector2I(Vector2I v) => new GridPos(v.X, v.Y);

	public static GridPos operator +(GridPos a, GridPos b) => new GridPos(a.X + b.X, a.Y + b.Y);
	public static GridPos operator -(GridPos a, GridPos b) => new GridPos(a.X - b.X, a.Y - b.Y);
	public static bool operator ==(GridPos a, GridPos b) => a.X == b.X && a.Y == b.Y;
	public static bool operator !=(GridPos a, GridPos b) => !(a == b);

	public bool Equals(GridPos other) => this == other;
	public override bool Equals(object obj) => obj is GridPos other && this == other;
	public override int GetHashCode() => HashCode.Combine(X, Y);
	public override string ToString() => $"({X}, {Y})";
}
