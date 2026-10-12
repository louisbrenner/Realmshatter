using System;
using System.Collections.Generic;

namespace Realmshatter;

/// <summary>Complete game state for two players. Pure C#, no scene tree access.</summary>
public sealed class GameState
{
	public const int PlayerCount = 2;

	private readonly List<Piece> _pieces = new List<Piece>();
	private int _nextPieceId = 1;

	public GameConfig Config { get; }
	public BoardState Board { get; }
	public PlayerState[] Players { get; }
	public Random Random { get; }

	public int CurrentPlayerIndex { get; internal set; }
	/// <summary>Global turn counter starting at 1; increments on every EndTurn (each player's turn counts).</summary>
	public int TurnNumber { get; internal set; } = 1;
	public GamePhase Phase { get; internal set; } = GamePhase.NotStarted;
	/// <summary>Index of the winning player, or -1 while the game is running.</summary>
	public int Winner { get; internal set; } = -1;

	/// <summary>All living pieces of both players.</summary>
	public IReadOnlyList<Piece> Pieces => _pieces;

	public PlayerState CurrentPlayer => Players[CurrentPlayerIndex];
	public PlayerState Opponent => Players[1 - CurrentPlayerIndex];

	/// <summary>Creates a new game. 'random' is used for all draws (inject a seeded instance for determinism).</summary>
	public GameState(GameConfig config, IEnumerable<CardData> deckPlayer0, IEnumerable<CardData> deckPlayer1, Random random)
	{
		Config = config ?? new GameConfig();
		Random = random ?? new Random();
		Board = new BoardState(Config);
		Players = new[] { new PlayerState(0, deckPlayer0), new PlayerState(1, deckPlayer1) };
	}

	private GameState(GameState other)
	{
		Config = other.Config;
		Random = new Random(0);
		Board = new BoardState(other.Board);
		Players = new PlayerState[other.Players.Length];
		for (int i = 0; i < other.Players.Length; i++)
		{
			Players[i] = new PlayerState(other.Players[i]);
		}
		CurrentPlayerIndex = other.CurrentPlayerIndex;
		TurnNumber = other.TurnNumber;
		Phase = other.Phase;
		Winner = other.Winner;
		_nextPieceId = other._nextPieceId;
		foreach (Piece p in other._pieces)
		{
			var copy = new Piece(p);
			_pieces.Add(copy);
			Board.Place(copy, copy.Position);
		}
	}

	/// <summary>
	/// Deep copy for simulations/previews (pieces, spells, statuses, tile effects, card lists).
	/// Cards and the config are shared; the clone gets its own (fixed-seed) Random.
	/// </summary>
	public GameState Clone() => new GameState(this);

	/// <summary>Returns the piece with the given id, or null.</summary>
	public Piece GetPiece(int id)
	{
		foreach (Piece p in _pieces)
		{
			if (p.Id == id)
			{
				return p;
			}
		}
		return null;
	}

	/// <summary>All living pieces owned by the player.</summary>
	public List<Piece> GetPiecesOf(int playerIndex)
	{
		var list = new List<Piece>();
		foreach (Piece p in _pieces)
		{
			if (p.OwnerIndex == playerIndex)
			{
				list.Add(p);
			}
		}
		return list;
	}

	/// <summary>
	/// Creates a piece from a unit card and places it WITHOUT any rule checks or AP cost
	/// (for setup/tests/AI simulation). The piece is summoning sick for the current TurnNumber.
	/// Returns null if the tile is outside or occupied.
	/// </summary>
	public Piece SpawnPiece(CardData card, int ownerIndex, GridPos pos)
	{
		if (card == null || !Board.IsPassable(pos) || Board.IsOccupied(pos))
		{
			return null;
		}
		var piece = new Piece(_nextPieceId++, ownerIndex, card, pos, TurnNumber);
		_pieces.Add(piece);
		Board.Place(piece, pos);
		return piece;
	}

	/// <summary>Places an unfinished building (finished at the start of turn completeTurn) for its builder.</summary>
	public Piece SpawnBuilding(BuildingType type, int ownerIndex, GridPos pos, int completeTurn, int builderId)
	{
		Piece b = SpawnPiece(BuildingInfo.GetCard(type), ownerIndex, pos);
		if (b != null)
		{
			b.UnderConstruction = completeTurn > TurnNumber;
			b.CompleteTurn = completeTurn;
			b.BuilderId = builderId;
		}
		return b;
	}

	/// <summary>Removes a piece from the board and the piece list.</summary>
	public void RemovePiece(Piece piece)
	{
		Board.Remove(piece);
		_pieces.Remove(piece);
	}
}
