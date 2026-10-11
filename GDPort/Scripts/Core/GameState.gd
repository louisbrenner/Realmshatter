class_name GameState
extends RefCounted
## Complete game state for two players. Pure logic, no scene tree access.

const PLAYER_COUNT := 2

var _pieces: Array[Piece] = []
var _next_piece_id: int = 1
var _next_order_index: int = 0

var config: GameConfig
var board: BoardState
var players: Array[PlayerState] = []
var random: RandomNumberGenerator

var current_player_index: int = 0
## Global turn counter starting at 1; increments on every end_turn (each player's turn counts).
var turn_number: int = 1
## GamePhase value.
var phase: int = GamePhase.NOT_STARTED
## Index of the winning player, or -1 while the game is running.
var winner: int = -1

## All living pieces of both players (do not mutate; use spawn_piece / remove_piece).
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
func _init(p_config: GameConfig = null, deck_player0: Variant = null, deck_player1: Variant = null, p_random: RandomNumberGenerator = null) -> void:
	config = p_config if p_config != null else GameConfig.new()
	if p_random != null:
		random = p_random
	else:
		random = RandomNumberGenerator.new()
		random.randomize()
	board = BoardState.new(config)
	players = [PlayerState.new(0, deck_player0), PlayerState.new(1, deck_player1)]


## Deep copy for simulations/previews (pieces, spells, statuses, orders, tile effects, card lists).
## Cards and the config are shared; the clone gets its own (fixed-seed) RandomNumberGenerator.
func clone() -> GameState:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0
	var c := GameState.new(config, null, null, rng)
	# C# BoardState copy constructor: same dimensions (from the shared config) + tile effects.
	for e: TileEffect in board.tile_effects.values():
		c.board.set_tile_effect(e)
	c.players.clear()
	for p: PlayerState in players:
		c.players.append(p.copy())
	c.current_player_index = current_player_index
	c.turn_number = turn_number
	c.phase = phase
	c.winner = winner
	c._next_piece_id = _next_piece_id
	c._next_order_index = _next_order_index
	for p: Piece in _pieces:
		var piece_copy: Piece = p.copy()
		c._pieces.append(piece_copy)
		c.board.place(piece_copy, piece_copy.position)
	return c


## Returns the piece with the given id, or null.
func get_piece(p_id: int) -> Piece:
	for p: Piece in _pieces:
		if p.id == p_id:
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


## Removes a piece from the board and the piece list.
func remove_piece(piece: Piece) -> void:
	board.remove(piece)
	_pieces.erase(piece)


func take_order_index() -> int:
	var i: int = _next_order_index
	_next_order_index += 1
	return i


func reset_order_index() -> void:
	_next_order_index = 0
