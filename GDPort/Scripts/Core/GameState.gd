class_name GameState
extends RefCounted
## Complete game state for two players. Pure data, no scene tree access.

const PLAYER_COUNT: int = 2

var _pieces: Array[Piece] = []
var _next_piece_id: int = 1

var config: GameConfig
var board: BoardState
var players: Array[PlayerState] = []
var random: RandomNumberGenerator

var current_player_index: int = 0
## Global turn counter starting at 1; increments on every EndTurn (each player's turn counts).
var turn_number: int = 1
## GamePhase value.
var phase: int = GamePhase.NOT_STARTED
## Index of the winning player, or -1 while the game is running.
var winner: int = -1

## All living pieces of both players (read-only).
var pieces: Array[Piece]:
	get:
		return _pieces

var current_player: PlayerState:
	get:
		return players[current_player_index]
var opponent: PlayerState:
	get:
		return players[1 - current_player_index]


## Creates a new game. 'p_random' is used for all draws (inject a seeded instance for determinism).
## Decks are Arrays of CardData.
func _init(p_config: GameConfig = null, deck_player0: Array = [], deck_player1: Array = [],
		p_random: RandomNumberGenerator = null, p_is_copy: bool = false) -> void:
	if p_is_copy:
		return
	config = p_config if p_config != null else GameConfig.new()
	if p_random != null:
		random = p_random
	else:
		random = RandomNumberGenerator.new()
		random.randomize()
	board = BoardState.new(config)
	players = [PlayerState.new(0, deck_player0), PlayerState.new(1, deck_player1)]


## C# private copy constructor.
static func _copy_of(other: GameState) -> GameState:
	var s := GameState.new(null, [], [], null, true)
	s.config = other.config
	s.random = RandomNumberGenerator.new()
	s.random.seed = 0
	s.board = BoardState.copy_of(other.board)
	s.players = []
	for i: int in other.players.size():
		s.players.append(PlayerState.copy_of(other.players[i]))
	s.current_player_index = other.current_player_index
	s.turn_number = other.turn_number
	s.phase = other.phase
	s.winner = other.winner
	s._next_piece_id = other._next_piece_id
	for p: Piece in other._pieces:
		var copy := Piece.copy_of(p)
		s._pieces.append(copy)
		s.board.place(copy, copy.position)
	return s


## Deep copy for simulations/previews (pieces, spells, statuses, tile effects, card lists).
## Cards and the config are shared; the clone gets its own (fixed-seed) RandomNumberGenerator.
func clone() -> GameState:
	return GameState._copy_of(self)


## Returns the piece with the given id, or null.
func get_piece(id: int) -> Piece:
	for p: Piece in _pieces:
		if p.id == id:
			return p
	return null


## All living pieces owned by the player.
func get_pieces_of(player_index: int) -> Array[Piece]:
	var list: Array[Piece] = []
	for p: Piece in _pieces:
		if p.owner_index == player_index:
			list.append(p)
	return list


## Creates a piece from a unit card and places it WITHOUT any rule checks or AP cost
## (for setup/tests/AI simulation). The piece is summoning sick for the current turn_number.
## Returns null if the tile is outside or occupied.
func spawn_piece(card: CardData, owner_index: int, pos: Vector2i) -> Piece:
	if card == null or not board.is_passable(pos) or board.is_occupied(pos):
		return null
	var piece := Piece.new(_next_piece_id, owner_index, card, pos, turn_number)
	_next_piece_id += 1
	_pieces.append(piece)
	board.place(piece, pos)
	return piece


## Places an unfinished building (finished at the start of turn complete_turn) for its builder.
func spawn_building(type: int, owner_index: int, pos: Vector2i, complete_turn: int, builder_id: int) -> Piece:
	var b: Piece = spawn_piece(BuildingInfo.get_card(type), owner_index, pos)
	if b != null:
		b.under_construction = complete_turn > turn_number
		b.complete_turn = complete_turn
		b.builder_id = builder_id
	return b


## Removes a piece from the board and the piece list.
func remove_piece(piece: Piece) -> void:
	board.remove(piece)
	_pieces.erase(piece)
