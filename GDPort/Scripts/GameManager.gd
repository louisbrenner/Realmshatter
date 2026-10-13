class_name GameManager
extends Node
## Root script of Main.tscn. Wires the pure rules (GameState / TurnController) to the board view,
## animator, order overlay, camera, HUD and the AI, and runs the human input state machine (player 0).
## User args: --selftest prints the rules and AI self-tests, --autoplay lets a second SimpleAi
## play the human side until game over and then quits (debug), --hotseat starts a local two-player match.
## Hotseat (HotseatSession or --hotseat): both sides are human; _human_player follows the player whose turn it
## is, and a curtain hides the hand and traps while the device is passed on.

const AI_PLAYER := 1
const HOTSEAT_NAMES: Array[String] = ["Player 1", "Player 2"]
const MAX_AUTOMATED_TURNS := 1000

@export_group("Rules")
@export var config: GameConfig
@export var player_deck: Array[CardData] = []
@export var ai_deck: Array[CardData] = []
## Optional deck resource for the player; overrides PlayerDeck when set (e.g. Resources/Decks/StarterDeck.tres).
@export var player_deck_data: DeckData
## Optional deck resource for the AI; overrides AiDeck when set.
@export var ai_deck_data: DeckData
## Themed decks offered on the deck selection screen at the start of every game (the AI plays a random other
## theme). When empty, PlayerDeckData / AiDeckData are used directly without a selection screen.
@export var theme_decks: Array[DeckData] = []
## When the battle scene is launched without a pending town battle (BattleSession), switch to the overworld
## instead (ignored with --autoplay / --selftest, which keep the old deck-selection flow).
@export var start_in_overworld: bool = true
## Random seed for draws (0 = random every game).
@export var seed: int = 0
## Pause in seconds before and after the AI plays its cards.
@export var ai_step_delay: float = 0.9
## Pause in seconds between two consecutive AI actions, so each one can be followed.
@export var ai_action_pause: float = 0.4

@export_group("Nodes")
@export var board: BoardView
@export var animator: BoardAnimator
@export var camera_rig: CameraRig
@export var hud: Hud
## Move / attack planning arrows and attack previews (created at the origin if not assigned).
@export var overlay: OrderOverlay

var _state: GameState
var _controller: TurnController
var _ai: SimpleAi
var _autoplay_ai: SimpleAi
var _autoplay: bool = false
var _generation: int = 0

var _mode: int = InputMode.IDLE
var _selected_hand_index: int = -1
var _selected_card: CardData
var _selected_piece: Piece
var _planned_move: Variant = null  # Vector2i or null

var _pending_log: Array[String] = []
var _piece_names: Dictionary = {}  # int -> String
var _captured_spell_events: Array = []  # of Array[ResolutionEvent]
var _captured_action_events: Array = []  # of Array[ResolutionEvent]
var _capture_spells: bool = false
var _pending_score_tiles: Array[Vector2i] = []
var _pending_score_player: int = -1
var _player_theme: DeckData
var _ai_theme: DeckData
var _hover_tile: Variant = null  # Vector2i or null
## Tiles already chosen for the current build (Barricades: up to two).
var _build_tiles: Array[Vector2i] = []
## Hand card under the mouse (for the spell range overlay), or null.
var _hovered_hand_card: CardData
var _range_tiles: Array[Vector2i] = []
var _return_to_town: bool = false
var _theme_random: RandomNumberGenerator = RandomNumberGenerator.new()
var _hotseat: bool = false
## Player whose view (hand, traps, info) is shown: always 0 outside hotseat matches.
var _view_player: int = 0
## Hotseat deck selection: which player is choosing (0, then 1).
var _hotseat_picking: int = 0
## Hotseat: the hand is hidden while the device is handed over.
var _conceal_hand: bool = false
var _curtain: HotseatCurtain

var _human_player: int:
	get: return _view_player


func _ready() -> void:
	if board == null or animator == null or camera_rig == null or hud == null:
		push_error("GameManager: Board, Animator, CameraRig and Hud must be assigned.")
		return
	_theme_random.randomize()
	var sfx := Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)
	if overlay == null:
		overlay = OrderOverlay.new()
		overlay.name = "OrderOverlay"
		add_child(overlay)

	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	_autoplay = user_args.has("--autoplay")
	Sfx.muted = _autoplay
	if user_args.has("--selftest"):
		print(RulesSelfTest.run())
		print(AiSelfTest.run())
	if _autoplay:
		Engine.time_scale = 8.0
		print("GameManager: autoplay enabled (both sides played by SimpleAi).")
	var selftest: bool = user_args.has("--selftest")
	_hotseat = not _autoplay and (HotseatSession.is_active or user_args.has("--hotseat"))
	if not BattleSession.get_is_active() and not _hotseat and start_in_overworld and not _autoplay and not selftest \
			and ResourceLoader.exists(BattleSession.OVERWORLD_SCENE):
		(func() -> void: get_tree().change_scene_to_file(BattleSession.OVERWORLD_SCENE)).call_deferred()
		return

	# Turn banners are driven explicitly (awaited at every turn start).
	hud.auto_turn_banner = false
	animator.deck_world_provider = _get_deck_world

	board.tile_clicked.connect(_on_tile_clicked)
	board.tile_hovered.connect(_on_tile_hovered)
	hud.end_turn_pressed.connect(_on_end_turn_pressed)
	hud.view_toggle_pressed.connect(_on_view_toggle_pressed)
	hud.cancel_pressed.connect(_on_cancel_pressed)
	hud.restart_pressed.connect(_on_restart_pressed)
	hud.draw_pressed.connect(_on_draw_pressed)
	hud.convert_vp_pressed.connect(on_convert_vp_pressed)
	hud.hand.card_selected.connect(_on_hand_card_selected)
	hud.hand.card_hover_changed.connect(_on_hand_card_hover_changed)
	hud.draft.card_chosen.connect(_on_draft_card_chosen)
	hud.deck_select.deck_chosen.connect(_on_deck_chosen)
	camera_rig.view_mode_changed.connect(_on_view_mode_changed)
	if user_args.has("--view=3d"):
		camera_rig.set_mode(ViewMode.THREE_D, false)
	elif user_args.has("--view=2.5d"):
		camera_rig.set_mode(ViewMode.TWO_POINT_FIVE_D, false)
	_on_view_mode_changed(camera_rig.mode)
	if _hotseat:
		_curtain = HotseatCurtain.new()
		_curtain.name = "HotseatCurtain"
		add_child(_curtain)
		hud.set_view_player(0, HOTSEAT_NAMES)

	_begin_new_game()


## Shows the deck selection (when ThemeDecks are set and not autoplaying), otherwise starts right away.
func _begin_new_game() -> void:
	if BattleSession.get_is_active():
		# Town battle: the player's own deck against the NPC's deck, no deck selection.
		_player_theme = BattleSession.build_player_deck()
		_ai_theme = BattleSession.opponent.deck
		hud.set_opponent_name(BattleSession.opponent.name)
		start_new_game()
		return
	var themes: Array[DeckData] = _theme_list()
	if _hotseat and themes.size() > 0:
		# Both players pick their deck one after the other.
		_hotseat_picking = 0
		_view_player = 0
		hud.set_view_player(0, HOTSEAT_NAMES)
		_show_deck_selection(themes, "%s: choose your deck" % HOTSEAT_NAMES[0])
		return
	if themes.size() == 0:
		start_new_game()
		return
	if _autoplay:
		_player_theme = themes[_theme_random.randi_range(0, themes.size() - 1)]
		_ai_theme = _pick_other_theme(themes, _player_theme)
		start_new_game()
		return
	_show_deck_selection(themes)


## Clears the table and shows the deck selection screen; the game starts in OnDeckChosen.
func _show_deck_selection(themes: Array[DeckData], title: String = "") -> void:
	_generation += 1
	_unsubscribe_controller()
	_reset_selection()
	_mode = InputMode.BUSY
	_hover_tile = null

	var cfg: GameConfig = config if config != null else GameConfig.new()
	var fit := Vector2(cfg.board_width, cfg.board_height)
	if camera_rig.board_fit_size != fit:
		camera_rig.board_fit_size = fit
		camera_rig.set_mode(camera_rig.mode, false)
	board.build(BoardState.new(cfg))
	_range_tiles.clear()
	animator.clear_all()
	overlay.clear_all()
	hud.hide_win_screen()
	hud.draft.hide_popup()
	hud.hide_board_info()
	var empty_hand: Array[CardData] = []
	hud.hand.show_hand(empty_hand, Callable(), Callable())
	hud.set_end_turn_enabled(false)
	hud.set_draw_enabled(false)
	hud.set_cancel_enabled(false)
	hud.set_hint("")
	hud.deck_select.present(themes, title)


func _on_deck_chosen(index: int) -> void:
	var themes: Array[DeckData] = _theme_list()
	if index < 0 or index >= themes.size():
		return
	if _hotseat:
		if _hotseat_picking == 0:
			_player_theme = themes[index]
			_hotseat_picking = 1
			(func() -> void: hud.deck_select.present(_theme_list(), "%s: choose your deck" % HOTSEAT_NAMES[1])).call_deferred()
			return
		_ai_theme = themes[index]
		start_new_game()
		return
	_player_theme = themes[index]
	_ai_theme = _pick_other_theme(themes, _player_theme)
	start_new_game()


func _pick_other_theme(themes: Array[DeckData], exclude: DeckData) -> DeckData:
	var others: Array[DeckData] = []
	for d in themes:
		if d != exclude:
			others.append(d)
	return others[_theme_random.randi_range(0, others.size() - 1)] if others.size() > 0 else exclude


func _theme_list() -> Array[DeckData]:
	var list: Array[DeckData] = []
	if theme_decks != null:
		for deck in theme_decks:
			if deck != null and deck.cards.size() > 0:
				list.append(deck)
	return list


func _exit_tree() -> void:
	_generation += 1
	_unsubscribe_controller()


## Creates a fresh game (state, controller, AI), rebuilds the board and starts turn 1.
func start_new_game() -> void:
	_generation += 1
	var generation: int = _generation
	_unsubscribe_controller()

	var cfg: GameConfig = config if config != null else GameConfig.new()
	var player_deck_res: DeckData = _player_theme if _player_theme != null else player_deck_data
	var ai_deck_res: DeckData = _ai_theme if _ai_theme != null else ai_deck_data
	var deck0: Array[CardData] = _to_list(player_deck_res.cards) if player_deck_res != null else _to_list(player_deck)
	var deck1: Array[CardData] = _to_list(ai_deck_res.cards) if ai_deck_res != null else _to_list(ai_deck)
	if deck0.size() == 0 or deck1.size() == 0:
		push_error("GameManager: PlayerDeck and AiDeck should contain cards.")
	var random := RandomNumberGenerator.new()
	if seed != 0:
		random.seed = seed
	else:
		random.randomize()

	_state = GameState.new(cfg, deck0, deck1, random)
	if BattleSession.get_is_active():
		_state.players[AI_PLAYER].bonus_ap_per_turn = BattleSession.opponent.bonus_ap_per_turn
	var map: MapGenerator.MapInfo = MapGenerator.generate(_state)
	_controller = TurnController.new(_state)
	_ai = null if _hotseat else SimpleAi.new(_controller, AI_PLAYER)
	_autoplay_ai = SimpleAi.new(_controller, _human_player) if _autoplay else null
	_subscribe_controller()

	_pending_log.clear()
	_piece_names.clear()
	_captured_spell_events.clear()
	_captured_action_events.clear()
	_pending_score_tiles.clear()
	_pending_score_player = -1
	_hover_tile = null
	_reset_selection()
	_mode = InputMode.IDLE
	if _hotseat:
		_view_player = 0
		_conceal_hand = true
		hud.set_view_player(0, HOTSEAT_NAMES)
		camera_rig.set_flipped(false, false)
		animator.set_flipped(false, 0.0)
		animator.trap_viewer = -1
	if player_deck_res != null and ai_deck_res != null:
		_pending_log.append("%s deck: %s. %s deck: %s." % [_possessive_label(0), player_deck_res.name, _possessive_label(1), ai_deck_res.name])
	_pending_log.append("Battlefield: %s. %s" % [map.name, map.description])
	hud.show_message("%s - %s" % [map.name, map.description], 4.0)

	var fit := Vector2(cfg.board_width, cfg.board_height)
	if camera_rig.board_fit_size != fit:
		camera_rig.board_fit_size = fit
		camera_rig.set_mode(camera_rig.mode, false)

	board.build(_state.board)
	board.sync_terrain(_state.board, cfg.rock_hp)
	_range_tiles.clear()
	animator.clear_all()
	animator.sync_all(_state)
	overlay.clear_all()
	overlay.set_state(_state)
	hud.hide_win_screen()
	hud.draft.hide_popup()
	hud.clear_log()

	_controller.start_game()
	_flush_pending_log()
	_run_game_async(generation)


## Turn 1 intro (banner), then the automated turns / the human turn.
func _run_game_async(generation: int) -> void:
	_mode = InputMode.BUSY
	_refresh()
	await _hand_over_async(generation)
	if not _is_current(generation):
		return
	await _turn_intro_async(generation)
	if not _is_current(generation):
		return
	_mode = InputMode.IDLE
	await _run_automated_turns_async(generation)


# ------------------------------------------------------------------ controller events

func _subscribe_controller() -> void:
	_controller.turn_started.connect(_on_turn_started)
	_controller.victory_points_scored.connect(_on_victory_points_scored)
	_controller.game_over.connect(_on_game_over)
	_controller.spell_resolved.connect(_on_spell_resolved)
	_controller.action_resolved.connect(_on_action_resolved)


func _unsubscribe_controller() -> void:
	if _controller == null:
		return
	if _controller.turn_started.is_connected(_on_turn_started):
		_controller.turn_started.disconnect(_on_turn_started)
	if _controller.victory_points_scored.is_connected(_on_victory_points_scored):
		_controller.victory_points_scored.disconnect(_on_victory_points_scored)
	if _controller.game_over.is_connected(_on_game_over):
		_controller.game_over.disconnect(_on_game_over)
	if _controller.spell_resolved.is_connected(_on_spell_resolved):
		_controller.spell_resolved.disconnect(_on_spell_resolved)
	if _controller.action_resolved.is_connected(_on_action_resolved):
		_controller.action_resolved.disconnect(_on_action_resolved)


func _on_turn_started(player: int) -> void:
	_pending_log.append("--- Turn %d: %s (%d AP) ---" % [_state.turn_number, _player_label(player), _state.players[player].action_points])
	if player == 1 and _state.players[player].turns_started == 1 and _state.config.second_player_first_turn_bonus_ap > 0:
		_pending_log.append("%s moves second: +%d AP this turn." % [_player_label(player), _state.config.second_player_first_turn_bonus_ap])
	var wells: int = 0
	for p: Piece in _state.get_pieces_of(player):
		wells += 1 if p.building == BuildingType.MANA_WELL and not p.under_construction else 0
	if wells > 0:
		_pending_log.append("%s: +%d AP from mana wells." % [_player_label(player), wells * _state.config.mana_well_ap])


func _on_victory_points_scored(player: int, points: int) -> void:
	_pending_log.append("%s scored %d VP (total %d)." % [_player_label(player), points, _state.players[player].victory_points])
	_pending_score_player = player
	_pending_score_tiles.clear()
	for p: Piece in _state.get_pieces_of(player):
		if p.can_score and _state.board.is_in_scoring_zone(p.position):
			_pending_score_tiles.append(p.position)


func _on_game_over(winner: int) -> void:
	_pending_log.append("%s reached %d VP and wins!" % [_player_label(winner), _state.config.points_target])


func _on_spell_resolved(events: Array) -> void:
	if _capture_spells and events != null:
		_captured_spell_events.append(_copy_events(events))


func _on_action_resolved(events: Array) -> void:
	if _capture_spells and events != null:
		_captured_action_events.append(_copy_events(events))


# ------------------------------------------------------------------ turn flow

## Plays all consecutive AI-controlled turns, then hands control to the human (or shows the win screen).
func _run_automated_turns_async(generation: int) -> void:
	var turns: int = 0
	while _is_current(generation) and _state.winner < 0:
		var ai: SimpleAi = _get_ai_for(_state.current_player_index)
		if ai == null:
			break
		turns += 1
		if turns > MAX_AUTOMATED_TURNS:
			push_warning("GameManager: automated turn limit reached.")
			if _autoplay:
				print("AUTOPLAY RESULT: turn limit reached without a winner.")
				get_tree().quit()
			return
		var ok: bool = await _run_ai_turn_async(ai, generation)
		if not ok:
			break
	if _is_current(generation):
		_enter_human_turn_or_game_over()


## One full AI turn: draft + cards + orders (animated), then EndTurn. False if it could not end the turn.
func _run_ai_turn_async(ai: SimpleAi, generation: int) -> bool:
	_mode = InputMode.BUSY
	hud.draft.hide_popup()
	hud.set_hint("%s is thinking..." % _player_label(ai.player_index))
	_refresh()
	_update_order_overlay()

	await _delay_async(ai_step_delay)
	if not _is_current(generation):
		return false

	_cache_piece_names()
	_captured_spell_events.clear()
	_captured_action_events.clear()
	_capture_spells = true
	var actions: Array = ai.take_turn()
	_capture_spells = false
	if _state.phase == GamePhase.DRAFT and _state.current_player.draft_offer.size() > 0:
		_controller.choose_draft_card(0)

	await _animate_ai_actions_async(actions, generation)
	if not _is_current(generation):
		return false
	animator.sync_all(_state)
	_cache_piece_names()
	_flush_pending_log()
	_refresh()
	_update_order_overlay()

	await _delay_async(ai_step_delay)
	if not _is_current(generation):
		return false
	var ended: bool = await _end_turn_async(generation)
	return ended


## Logs and animates the AI's executed actions in order (summons, spell events).
func _animate_ai_actions_async(actions: Array, generation: int) -> void:
	var spell_index: int = 0
	var action_index: int = 0
	for action: AiAction in actions:
		_log("%s: %s" % [_player_label(action.player_index), action.description])
		match action.kind:
			AiActionKind.PLAY_UNIT:
				var piece: Piece = _state.get_piece(action.piece_id)
				if piece != null:
					_piece_names[piece.id] = _piece_name_for(piece)
					animator.spawn_view(piece)
					await animator.play_summon(piece.id)
			AiActionKind.PLAY_SPELL:
				if spell_index < _captured_spell_events.size():
					var events: Array[ResolutionEvent] = _captured_spell_events[spell_index]
					spell_index += 1
					await animator.play_events(events, _state, false)
					for e: ResolutionEvent in events:
						if e.type != ResolutionEventType.SPELL_CAST:
							_log(_describe_event(e))
			AiActionKind.COMMAND, AiActionKind.BUILD, AiActionKind.TRAP:
				if action_index < _captured_action_events.size():
					var events: Array[ResolutionEvent] = _captured_action_events[action_index]
					action_index += 1
					await animator.play_events(events, _state, false)
					for e: ResolutionEvent in events:
						_log(_describe_event(e))
			AiActionKind.CONVERT_VP:
				hud.show_message("%s converted 1 VP into 1 AP." % _player_label(action.player_index))
		if not _is_current(generation):
			return
		await _delay_async(ai_action_pause)
		if not _is_current(generation):
			return


## Ends the current turn: animates the expiring effects and the next turn's tile ticks, logs them.
func _end_turn_async(generation: int) -> bool:
	if _state.phase != GamePhase.MAIN:
		hud.show_message("You can only end the turn in the main phase.")
		return false

	_mode = InputMode.BUSY
	hud.set_hint("Ending turn...")
	_refresh()

	_cache_piece_names()
	var events: Array[ResolutionEvent] = _copy_events(_controller.end_turn())
	var turn_start_events: Array[ResolutionEvent] = _copy_events(_controller.last_turn_start_events)
	if _hotseat:
		_conceal_view()

	overlay.clear_all()
	await animator.play_events(events, _state, turn_start_events.size() == 0)
	if not _is_current(generation):
		return false
	if turn_start_events.size() > 0:
		# Lava / healing ticks at the start of the new turn.
		await animator.play_events(turn_start_events, _state)
		if not _is_current(generation):
			return false

	_cache_piece_names()
	for e: ResolutionEvent in events:
		_log(_describe_event(e))
	for e: ResolutionEvent in turn_start_events:
		_log(_describe_event(e))
	_flush_pending_log()
	_refresh()

	await _hand_over_async(generation)
	if not _is_current(generation):
		return false
	await _turn_intro_async(generation)
	if not _is_current(generation):
		return false
	_refresh()
	return true


## Start of a turn: turn banner, then the VP scoring animation of the zone pieces.
func _turn_intro_async(generation: int) -> void:
	if _state.winner < 0:
		await hud.show_turn_banner(_state.current_player_index, _state.turn_number)
		if not _is_current(generation):
			return
	if _pending_score_player >= 0 and _pending_score_tiles.size() > 0:
		var tiles: Array[Vector2i] = _pending_score_tiles.duplicate()
		var player: int = _pending_score_player
		_pending_score_tiles.clear()
		_pending_score_player = -1
		var board_state: BoardState = _state.board
		await animator.play_score(tiles, player, board_state.score_value)
	_pending_score_player = -1


## Hotseat: hides the outgoing player's hand and traps (the board stays visible).
func _conceal_view() -> void:
	_conceal_hand = true
	animator.trap_viewer = -1
	board.sync_traps(_state.board, -1)
	var empty_hand: Array[CardData] = []
	hud.hand.show_hand(empty_hand, Callable(), Callable())


## Hotseat: switches the view (hand, traps, HUD windows) to 'player'.
func _set_view(player: int) -> void:
	_view_player = player
	_conceal_hand = false
	animator.trap_viewer = player
	board.sync_traps(_state.board, player)
	hud.set_view_player(player, HOTSEAT_NAMES)
	# Each player sees the board from their own side.
	camera_rig.set_flipped(player == 1)
	animator.set_flipped(player == 1, camera_rig.tween_duration)


## Hotseat: covers the screen until the player whose turn starts is ready, then shows their view.
## Does nothing outside hotseat matches or once the game is over.
func _hand_over_async(generation: int) -> void:
	if not _hotseat or _curtain == null or _state.winner >= 0:
		return
	var next: int = _state.current_player_index
	_conceal_view()
	_refresh()
	await _curtain.show_async("%s's turn" % HOTSEAT_NAMES[next],
		"Pass the device to %s.\nThe other player should look away from the hand." % HOTSEAT_NAMES[next], HudStyle.accent(next))
	if not _is_current(generation):
		return
	_set_view(next)
	_refresh()


func _enter_human_turn_or_game_over() -> void:
	_reset_selection()
	_clear_all_highlights()
	animator.clear_selection()
	overlay.clear_preview()
	overlay.clear_attack_preview()
	overlay.clear_spell_area_preview()

	if _state.winner >= 0:
		_mode = InputMode.IDLE
		if _hotseat:
			_set_view(_state.winner)
		_refresh()
		hud.set_hint("Game over.")
		if _hotseat:
			var winner_name: String = HOTSEAT_NAMES[_state.winner]
			var subtitle: String = "%s reached the victory points target!" % winner_name
			if HotseatSession.is_active:
				HotseatSession.complete("Hotseat match: %s won after %d turns." % [winner_name, _state.turn_number])
				_return_to_town = true
				hud.show_win_screen(_state.winner, subtitle, "Return to town")
			else:
				hud.show_win_screen(_state.winner, subtitle, "Play again")
		elif BattleSession.get_is_active():
			var result: String = BattleSession.complete(_state.winner == _human_player)
			_return_to_town = true
			hud.show_win_screen(_state.winner, result, "Return to town")
		elif not _return_to_town:
			hud.show_win_screen(_state.winner)
		if _autoplay:
			print("AUTOPLAY RESULT: winner = %s after %d turns, VP %d : %d, pieces alive %d." % [
				_player_label(_state.winner), _state.turn_number,
				_state.players[0].victory_points, _state.players[1].victory_points, _state.pieces.size()])
			get_tree().quit()
		return

	_mode = InputMode.IDLE
	# Turns start in Main phase; this only resumes an unfinished (already paid) draw.
	if _state.current_player_index == _human_player and _state.phase == GamePhase.DRAFT and not _autoplay:
		hud.draft.show_offer(_state.current_player.draft_offer, _controller.get_card_cost)
	_update_hint()
	_refresh()
	_update_order_overlay()


# ------------------------------------------------------------------ HUD signal handlers

func _on_end_turn_pressed() -> void:
	if not _can_human_act():
		return
	var generation: int = _generation
	_cancel_selection()
	var ended: bool = await _end_turn_async(generation)
	if not ended or not _is_current(generation):
		if _is_current(generation):
			_enter_human_turn_or_game_over()
		return
	await _run_automated_turns_async(generation)


func _on_view_toggle_pressed() -> void:
	camera_rig.cycle_mode()


func _on_view_mode_changed(mode: int) -> void:
	var mode_name: String
	match mode:
		ViewMode.TWO_POINT_FIVE_D:
			mode_name = "2.5D"
		ViewMode.THREE_D:
			mode_name = "3D"
		_:
			mode_name = "2D"
	hud.set_view_mode_label(mode_name)


func _on_cancel_pressed() -> void:
	if _is_selecting():
		_cancel_selection()


func _on_restart_pressed() -> void:
	if _return_to_town:
		get_tree().change_scene_to_file(BattleSession.OVERWORLD_SCENE)
		return
	_begin_new_game()


func _on_draw_pressed() -> void:
	if not _can_human_act():
		return
	_cancel_selection()
	if not _controller.draw():
		hud.show_message(_controller.last_error)
		return
	_log("%s paid %d AP to draw." % [_player_label(_human_player), _state.config.draw_ap_cost])
	hud.draft.show_offer(_state.current_player.draft_offer, _controller.get_card_cost)
	_update_hint()
	_refresh()


## Converts 1 VP into 1 AP for the human (HUD conversion slots or keyboard C).
func on_convert_vp_pressed() -> void:
	if not _can_human_act():
		return
	if not _controller.convert_vp_to_ap():
		hud.show_message(_controller.last_error)
		return
	_log("%s converted 1 VP into 1 AP (%d conversion(s) left this turn)." % [_player_label(_human_player), _controller.remaining_vp_conversions])
	hud.show_message("+1 AP for 1 VP (%d left this turn)." % _controller.remaining_vp_conversions)
	_update_hint()
	_refresh()


func _on_draft_card_chosen(offer_index: int) -> void:
	if _mode == InputMode.BUSY or _state.current_player_index != _human_player or _state.phase != GamePhase.DRAFT:
		return
	var card: CardData = _state.current_player.draft_offer[offer_index] \
		if offer_index >= 0 and offer_index < _state.current_player.draft_offer.size() else null
	if not _controller.choose_draft_card(offer_index):
		hud.show_message(_controller.last_error)
		return
	_log("%s kept %s." % [_player_label(_human_player), card.name if card != null else "a card"])
	# Deferred: the popup's cards are freed, and we are inside one of their click signals.
	_after_draft.call_deferred()


func _after_draft() -> void:
	hud.draft.hide_popup()
	_mode = InputMode.IDLE
	_update_hint()
	_refresh()


func _on_hand_card_selected(hand_index: int) -> void:
	if not _can_human_act():
		if _mode != InputMode.BUSY and _state != null and _state.winner < 0:
			hud.show_message("Wait for your main phase.")
		return
	var hand: Array[CardData] = _state.players[_human_player].hand
	if hand_index < 0 or hand_index >= hand.size():
		return
	if _mode == InputMode.CARD_SELECTED and _selected_hand_index == hand_index:
		_cancel_selection()
		return

	var card: CardData = hand[hand_index]
	var cost: int = _controller.get_card_cost(card)
	if cost > _state.current_player.action_points:
		hud.show_message("Not enough AP: %s costs %d." % [card.name, cost])
		return

	_cancel_selection()
	_mode = InputMode.CARD_SELECTED
	_selected_hand_index = hand_index
	_selected_card = card
	hud.hand.set_selected_index(hand_index)

	var tiles: Array[Vector2i] = []
	if card.card_type == CardType.UNIT:
		for y in range(_state.board.height):
			for x in range(_state.board.width):
				var pos := Vector2i(x, y)
				if _controller.can_play_unit_card(card, pos):
					tiles.append(pos)
		board.show_highlights(tiles, HighlightKind.DEPLOY)
		if tiles.size() == 0:
			hud.show_message("No free tile in your back rows.")
	else:
		tiles = _controller.get_valid_spell_tiles(card)
		# Spells reach only GameConfig.SpellCastRadius tiles around your units: show where they may be centred.
		board.show_highlights(tiles, HighlightKind.SPELL)
		_update_range_highlight()
		if tiles.size() == 0:
			hud.show_message("There is no valid tile for this spell." if card.targets_tile else "There is no piece to target.")
	hud.set_cancel_enabled(true)
	_update_hint()


# ------------------------------------------------------------------ board input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_RIGHT:
			if _is_selecting():
				_cancel_selection()
				get_viewport().set_input_as_handled()
			return

	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			match key.keycode:
				KEY_ESCAPE:
					if _is_selecting():
						_cancel_selection()
					get_viewport().set_input_as_handled()
				KEY_B:
					_on_build_pressed()
					get_viewport().set_input_as_handled()
				KEY_T:
					_on_trap_pressed()
					get_viewport().set_input_as_handled()
				KEY_V:
					_on_view_toggle_pressed()
					get_viewport().set_input_as_handled()
				KEY_D:
					_on_draw_pressed()
					get_viewport().set_input_as_handled()
				KEY_C:
					on_convert_vp_pressed()
					get_viewport().set_input_as_handled()
				KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
					_on_end_turn_pressed()
					get_viewport().set_input_as_handled()


func _on_tile_hovered(pos: Vector2i) -> void:
	_hover_tile = null if pos.x < 0 else pos
	_update_board_info()
	_update_range_highlight()
	if pos.x < 0 or _mode == InputMode.BUSY or _state == null:
		board.clear_highlights(HighlightKind.HOVER)
		overlay.clear_attack_preview()
		overlay.clear_spell_area_preview()
		if _mode != InputMode.BUSY:
			_update_hint()
		return
	var tile: Vector2i = pos
	if _mode == InputMode.CARD_SELECTED and _selected_card != null and _selected_card.targets_tile:
		var area: Array[Vector2i] = _controller.get_spell_area_preview(_selected_card, tile)
		board.show_highlights(area, HighlightKind.HOVER)
		if _controller.can_cast_spell_at(_selected_card, tile):
			overlay.show_spell_area_preview(area, _selected_card.tile_effect, board, _state.board)
		else:
			overlay.clear_spell_area_preview()
		return
	if _mode == InputMode.CHOOSING_MOVE and _selected_piece != null:
		board.show_highlights(_single(tile), HighlightKind.HOVER)
		if tile != _selected_piece.position and _controller.get_valid_move_targets(_selected_piece).has(tile):
			overlay.show_preview(_selected_piece, tile, null, board, _controller.get_planned_path(_selected_piece, tile), _state.board)
		else:
			var no_path: Array[Vector2i] = []
			overlay.show_preview(_selected_piece, null, null, board, no_path, _state.board)
		return
	if _mode == InputMode.CHOOSING_ATTACK and _selected_piece != null:
		board.show_highlights(_single(tile), HighlightKind.HOVER)
		_show_attack_plan_preview(tile)
		return
	if _mode == InputMode.IDLE:
		board.show_highlights(_single(tile), HighlightKind.HOVER)
		var piece: Piece = _state.board.get_piece_at(tile)
		if piece != null:
			hud.set_hint(_describe_piece_short(piece))
		else:
			_update_hint()
		return
	board.show_highlights(_single(tile), HighlightKind.HOVER)


func _clear_all_highlights() -> void:
	board.clear_highlights()
	_range_tiles.clear()


func _on_hand_card_hover_changed(card: CardView, hovered: bool) -> void:
	if hovered:
		_hovered_hand_card = card.card if card != null else null
	elif card != null and card.card == _hovered_hand_card:
		_hovered_hand_card = null
	_update_range_highlight()


## Faint range overlay: the cast range of the selected (or hovered) spell card, the reach of a hovered building
## (Turret shots, Shrine heals, Obelisk cast radius) or of the building a Builder would place on the hovered tile.
func _update_range_highlight() -> void:
	var tiles: Array[Vector2i] = []
	var human_main: bool = _state != null and _controller != null and _mode != InputMode.BUSY and _state.winner < 0 \
		and _state.current_player_index == _human_player and _state.phase == GamePhase.MAIN
	if human_main:
		var spell: CardData = null
		if _mode == InputMode.CARD_SELECTED:
			spell = _selected_card
		elif _mode == InputMode.IDLE:
			spell = _hovered_hand_card
		if spell != null and spell.card_type == CardType.SPELL:
			tiles = _controller.get_spell_range_tiles()
		elif _hover_tile != null:
			var tile: Vector2i = _hover_tile
			var piece: Piece = _state.board.get_piece_at(tile)
			if _mode == InputMode.IDLE and piece != null and piece.is_building:
				tiles = _controller.get_building_range_tiles(piece.building, piece.position, piece.effective_range, piece.source.clan)
			elif _mode == InputMode.CHOOSING_BUILD and _selected_piece != null \
					and _controller.get_valid_build_tiles(_selected_piece, _planned_move).has(tile):
				var type: int = _controller.get_build_type(_selected_piece)
				var clan: int = _selected_piece.source.clan
				tiles = _controller.get_building_range_tiles(type, tile, BuildingInfo.get_card(type, clan).range, clan)
	elif _state != null and _hover_tile != null and _controller != null and _state.winner < 0:
		var building: Piece = _state.board.get_piece_at(_hover_tile)
		if building != null and building.is_building:
			# Buildings can be inspected while waiting for the opponent, too.
			tiles = _controller.get_building_range_tiles(building.building, building.position, building.effective_range, building.source.clan)
	if tiles.size() == _range_tiles.size() and tiles.all(func(t: Vector2i) -> bool: return _range_tiles.has(t)):
		return
	_range_tiles = tiles
	if tiles.size() == 0:
		board.clear_highlights(HighlightKind.RANGE)
	else:
		board.show_highlights(tiles, HighlightKind.RANGE)


## While choosing an attack: shows the planned order with the hovered attack arc and, for occupied targets,
## the predicted consequences (damage incl. friendly fire, kills, pushes, new tile effects).
func _show_attack_plan_preview(tile: Vector2i) -> void:
	var from_pos: Vector2i = _planned_move if _planned_move != null else _selected_piece.position
	var path: Array[Vector2i] = []
	if _planned_move != null:
		path = _controller.get_planned_path(_selected_piece, _planned_move)
	var valid: bool = tile != from_pos and _controller.get_valid_attack_targets(_selected_piece, from_pos).has(tile)
	overlay.show_preview(_selected_piece, _planned_move, tile if valid else null, board, path, _state.board)
	# Area attackers: show the whole area; predict as soon as anything in it would be hit.
	var any_hit: bool = valid and _state.board.is_occupied(tile)
	if valid and _selected_piece.attack_area != AreaShape.SINGLE:
		var area: Array[Vector2i] = []
		for a: Vector2i in _state.board.get_area_tiles(tile, _selected_piece.attack_area):
			if a != from_pos:
				area.append(a)
				if _state.board.is_occupied(a) and _state.board.get_piece_at(a) != _selected_piece:
					any_hit = true
		overlay.show_spell_area_preview(area, null, board)
	else:
		overlay.clear_spell_area_preview()
	if not any_hit:
		overlay.clear_attack_preview()
		_update_hint()
		return
	var p: ChainPreview = _controller.predict_attack(_selected_piece, from_pos, tile)
	if p == null or not p.is_valid:
		overlay.clear_attack_preview()
		_update_hint()
		return
	overlay.show_attack_preview(p, board, _state)
	hud.set_hint(_describe_chain_preview(p, tile))


func _describe_chain_preview(p: ChainPreview, tile: Vector2i) -> String:
	var target: Piece = _state.board.get_piece_at(tile)
	var friendly: bool = target != null and target.owner_index == _human_player and target != _selected_piece
	var parts := PackedStringArray()
	if friendly and p.friendly_healed <= 0:
		parts.append("hits your own %s!" % _piece_label(target))
	if p.enemy_hp_lost > 0 or not friendly:
		parts.append("%d enemy dmg" % p.enemy_hp_lost)
	if p.enemy_kills > 0:
		parts.append("%d kill%s" % [p.enemy_kills, "s" if p.enemy_kills > 1 else ""])
	if p.friendly_hp_lost > 0:
		parts.append("%d friendly dmg" % p.friendly_hp_lost)
	if p.friendly_kills > 0:
		parts.append("%d own piece%s die%s" % [p.friendly_kills, "s" if p.friendly_kills > 1 else "", "" if p.friendly_kills > 1 else "s"])
	if p.friendly_healed > 0:
		parts.append("+%d healed" % p.friendly_healed)
	if p.new_tile_effects.size() > 0:
		parts.append("%d tile effect%s" % [p.new_tile_effects.size(), "s" if p.new_tile_effects.size() > 1 else ""])
	return "Preview: %s. Click to confirm." % ", ".join(parts)


func _on_tile_clicked(v: Vector2i) -> void:
	if not _can_human_act():
		return
	var pos: Vector2i = v
	match _mode:
		InputMode.IDLE:
			_handle_idle_click(pos)
		InputMode.CARD_SELECTED:
			_handle_card_target_click(pos)
		InputMode.CHOOSING_MOVE:
			_handle_move_click(pos)
		InputMode.CHOOSING_ATTACK:
			_handle_attack_click(pos)
		InputMode.CHOOSING_BUILD:
			_handle_build_click(pos)
		InputMode.CHOOSING_TRAP:
			_handle_trap_click(pos)


## Floating ability buttons beside the selected unit (currently: Build for Builders), docked on the side that
## hides the fewest tiles the player is choosing from. 'from' is the planned destination during the attack
## step (a unit may move and then build instead of attacking); null = its current tile. Unavailable abilities
## are shown greyed out with the reason as tooltip.
func _show_unit_actions(piece: Piece, from_tile: Variant = null) -> void:
	var abilities: Array[UnitActionBar.Ability] = []
	var build: int = _controller.get_build_type(piece)
	var at: Vector2i = from_tile if from_tile != null else piece.position
	if build != BuildingType.NONE:
		var cost: int = BuildingInfo.get_cost(build)
		var turns: int = BuildingInfo.get_build_turns(build)
		var count: int = BuildingInfo.get_build_count(build)
		var reason: String = ""
		if piece.constructing_id >= 0:
			reason = "Already building."
		elif cost > _state.current_player.action_points:
			reason = "Needs %d AP." % cost
		elif _controller.get_valid_build_tiles(piece, from_tile).size() == 0:
			reason = "No free tile next to it."
		var clan: int = piece.source.clan
		var what: String = ("%d %ss" % [count, BuildingInfo.display_name(build, clan)]) if count > 1 else BuildingInfo.display_name(build, clan)
		abilities.append(UnitActionBar.Ability.new(FxIconShape.HAMMER, "Build %s" % BuildingInfo.display_name(build, clan), cost, reason.length() == 0,
			"Build %s: %s (%d turn%s, B). Can follow a move instead of an attack." % [what, BuildingInfo.get_description(build, clan), turns, "s" if turns > 1 else ""]
			+ (("\n%s" % reason) if reason.length() > 0 else ""), _on_build_pressed))
	var trap: Variant = _controller.get_trap_type(piece)
	if trap != null:
		var cost: int = _state.config.trap_ap_cost
		var reason: String = ""
		if piece.constructing_id >= 0:
			reason = "Busy building."
		elif cost > _state.current_player.action_points:
			reason = "Needs %d AP." % cost
		elif _controller.get_valid_trap_tiles(piece, from_tile).size() == 0:
			reason = "No free tile next to it."
		abilities.append(UnitActionBar.Ability.new(FxIconShape.TRAP, "Set Trap", cost, reason.length() == 0,
			("%s: hidden from the enemy. An enemy stepping on it is stopped and takes %s " % [TrapInfo.display_name(trap), TrapInfo.describe(trap)])
			+ "(T). Can follow a move instead of an attack." + (("\n%s" % reason) if reason.length() > 0 else ""), _on_trap_pressed))
	if abilities.size() == 0:
		hud.action_bar.hide_bar()
		return
	var id: int = piece.id
	var moved: bool = at != piece.position
	var keep_visible: Array[Vector2i] = _controller.get_valid_attack_targets(piece, at) if from_tile != null else _controller.get_valid_move_targets(piece)
	keep_visible.append(at)
	hud.action_bar.show_for(func() -> Variant:
		var view: PieceView = animator.get_view(id)
		var camera: Camera3D = null
		if camera_rig != null:
			camera = camera_rig.camera
		if camera == null and get_viewport() != null:
			camera = get_viewport().get_camera_3d()
		if view == null or camera == null or not is_instance_valid(view):
			return null
		var body: Vector3 = (board.grid_to_world(at) if moved else view.global_position) + Vector3(0, 0.3, 0)
		if camera.is_position_behind(body):
			return null
		var center: Vector2 = camera.unproject_position(body)
		var half_tile: float = camera.unproject_position(board.grid_to_world(at)) \
			.distance_to(camera.unproject_position(board.grid_to_world(Vector2i(at.x + 1, at.y)))) * 0.5
		var avoid: Array[Vector2] = []
		for pos: Vector2i in keep_visible:
			avoid.append(camera.unproject_position(board.grid_to_world(pos)))
		return UnitActionBar.Placement.new(center, half_tile, avoid)
	, abilities)


## Build mode: right after selecting the unit (build where it stands) or after choosing its move (the build
## replaces the attack). Green tiles around the destination are valid; Barricades take two clicks.
func _on_build_pressed() -> void:
	var piece: Piece = _selected_piece
	if not _can_human_act() or piece == null or (_mode != InputMode.CHOOSING_MOVE and _mode != InputMode.CHOOSING_ATTACK):
		return
	var type: int = _controller.get_build_type(piece)
	if type == BuildingType.NONE:
		return
	if _mode == InputMode.CHOOSING_MOVE:
		_planned_move = null
	var tiles: Array[Vector2i] = _controller.get_valid_build_tiles(piece, _planned_move)
	if tiles.size() == 0:
		hud.show_message("No free tile next to this unit to build on.")
		return
	_mode = InputMode.CHOOSING_BUILD
	_build_tiles.clear()
	hud.action_bar.hide_bar()
	board.clear_highlights(HighlightKind.MOVE)
	board.clear_highlights(HighlightKind.ATTACK)
	overlay.clear_attack_preview()
	if _planned_move != null:
		board.show_highlights(_single(_planned_move), HighlightKind.MOVE)
		overlay.show_preview(piece, _planned_move, null, board, _controller.get_planned_path(piece, _planned_move), _state.board)
	else:
		overlay.clear_preview()
	board.show_highlights(tiles, HighlightKind.DEPLOY)
	_update_range_highlight()
	_update_build_hint()


## Trap mode: like building, right after selecting the Trapper or after choosing its move (replaces the attack).
func _on_trap_pressed() -> void:
	var piece: Piece = _selected_piece
	if not _can_human_act() or piece == null or (_mode != InputMode.CHOOSING_MOVE and _mode != InputMode.CHOOSING_ATTACK):
		return
	var trap: Variant = _controller.get_trap_type(piece)
	if trap == null:
		return
	if _mode == InputMode.CHOOSING_MOVE:
		_planned_move = null
	var tiles: Array[Vector2i] = _controller.get_valid_trap_tiles(piece, _planned_move)
	if tiles.size() == 0:
		hud.show_message("No free tile next to this unit for a trap.")
		return
	_mode = InputMode.CHOOSING_TRAP
	hud.action_bar.hide_bar()
	board.clear_highlights(HighlightKind.MOVE)
	board.clear_highlights(HighlightKind.ATTACK)
	overlay.clear_attack_preview()
	if _planned_move != null:
		board.show_highlights(_single(_planned_move), HighlightKind.MOVE)
		overlay.show_preview(piece, _planned_move, null, board, _controller.get_planned_path(piece, _planned_move), _state.board)
	else:
		overlay.clear_preview()
	board.show_highlights(tiles, HighlightKind.DEPLOY)
	hud.set_hint("%s: click a green tile to hide a %s (%d AP). Esc cancels." % [_piece_label(piece), TrapInfo.display_name(trap), _state.config.trap_ap_cost])


func _handle_trap_click(pos: Vector2i) -> void:
	var piece: Piece = _selected_piece
	if piece == null:
		_cancel_selection()
		return
	var move: Variant = _planned_move
	_cache_piece_names()
	var events: Variant = _controller.set_trap(piece, pos, move)
	if events == null:
		hud.show_message(_controller.last_error)
		return
	var trap_value: Variant = _controller.get_trap_type(piece)
	var trap: int = trap_value if trap_value != null else TrapType.SPIKE
	# Hotseat: the log is shared, so the trap's tile stays secret.
	var moved: String = ("moves to %s and " % str(move)) if move != null else ""
	if _hotseat:
		_log("%s %s %shides a trap." % [_possessive_label(_human_player), _piece_label(piece), moved])
	else:
		_log("Your %s %shides a %s at %s." % [_piece_label(piece), moved, TrapInfo.display_name(trap), str(pos)])
	_cancel_selection()
	_animate_spell_events_async(_copy_events(events), _generation)


func _update_build_hint() -> void:
	var piece: Piece = _selected_piece
	if piece == null:
		return
	var type: int = _controller.get_build_type(piece)
	var count: int = BuildingInfo.get_build_count(type)
	var building_name: String = BuildingInfo.display_name(type, piece.source.clan)
	var first: String = ("click green tiles for your %d %ss" % [count, building_name]) if count > 1 else ("click a green tile to build a %s" % building_name)
	if _build_tiles.size() == 0:
		hud.set_hint("%s: %s (%d AP). Esc cancels." % [_piece_label(piece), first, BuildingInfo.get_cost(type)])
	else:
		hud.set_hint("%s: click a second green tile - or the marked tile again to build just one." % _piece_label(piece))


func _handle_build_click(pos: Vector2i) -> void:
	var piece: Piece = _selected_piece
	if piece == null:
		_cancel_selection()
		return
	var type: int = _controller.get_build_type(piece)
	var valid: Array[Vector2i] = _controller.get_valid_build_tiles(piece, _planned_move)
	var again: bool = _build_tiles.has(pos)
	if not again:
		if not valid.has(pos):
			hud.show_message("Build on a green tile next to the unit.")
			return
		_build_tiles.append(pos)
		var remaining: int = 0
		for t: Vector2i in valid:
			if not _build_tiles.has(t):
				remaining += 1
		if _build_tiles.size() < BuildingInfo.get_build_count(type) and remaining > 0:
			# Barricades: mark the first tile and wait for the second.
			Sfx.play(SfxId.CARD_PICK)
			board.show_highlights(_build_tiles, HighlightKind.SELECTED)
			board.show_highlights(_single(piece.position), HighlightKind.HOVER)
			_update_build_hint()
			return
	_cache_piece_names()
	var move: Variant = _planned_move
	var tiles: Array[Vector2i] = _build_tiles.duplicate()
	var events: Variant = _controller.build(piece, tiles, move)
	if events == null:
		hud.show_message(_controller.last_error)
		_build_tiles.clear()
		return
	var where_parts := PackedStringArray()
	for t: Vector2i in tiles:
		where_parts.append(str(t))
	var where: String = " and ".join(where_parts)
	var clan_name: String = BuildingInfo.display_name(type, piece.source.clan)
	var what: String = ("%d %ss" % [tiles.size(), clan_name]) if tiles.size() > 1 else ("a %s" % clan_name)
	_log("%s %s %sstarts building %s at %s." % [_possessive_label(_human_player), _piece_label(piece), ("moves to %s and " % str(move)) if move != null else "", what, where])
	_cancel_selection()
	_animate_spell_events_async(_copy_events(events), _generation)


func _handle_idle_click(pos: Vector2i) -> void:
	var piece: Piece = _state.board.get_piece_at(pos)
	if piece == null:
		return
	if piece.owner_index == _human_player:
		_select_piece(piece)
	else:
		hud.show_message(_describe_piece(piece), 3.5)


func _handle_card_target_click(pos: Vector2i) -> void:
	var card: CardData = _selected_card
	if card == null:
		_cancel_selection()
		return

	if card.card_type == CardType.UNIT:
		var piece: Piece = _controller.play_unit_card(card, pos)
		if piece == null:
			hud.show_message(_controller.last_error)
			return
		animator.spawn_view(piece)
		animator.play_summon(piece.id)
		_cache_piece_names()
		_log("%s deployed %s at %s." % [_player_label(_human_player), card.name, str(pos)])
		_cancel_selection()
		_refresh()
		return

	_cache_piece_names()
	var cast: bool
	var target_text: String
	if card.targets_tile:
		cast = _controller.play_spell_on_tile(card, pos)
		target_text = str(pos)
	else:
		var target: Piece = _state.board.get_piece_at(pos)
		cast = _controller.play_spell_card(card, target)
		target_text = _piece_name(target.id) if target != null else str(pos)
	if not cast:
		hud.show_message(_controller.last_error)
		return
	_log("%s cast %s on %s." % [_player_label(_human_player), card.name, target_text])
	_cancel_selection()
	_animate_spell_events_async(_copy_events(_controller.last_spell_events), _generation)


## Animates the immediate events of a spell (cast VFX, damage, deaths, heals, tile effects) BEFORE the
## views are synced, so killed pieces play their death, then refreshes the HUD and order arrows.
func _animate_spell_events_async(events: Array[ResolutionEvent], generation: int) -> void:
	_mode = InputMode.BUSY
	_clear_all_highlights()
	await animator.play_events(events, _state)
	if not _is_current(generation):
		return
	for e: ResolutionEvent in events:
		if e.type != ResolutionEventType.SPELL_CAST:
			_log(_describe_event(e))
	_mode = InputMode.IDLE
	_update_hint()
	_refresh()
	_update_order_overlay()


func _handle_move_click(pos: Vector2i) -> void:
	var piece: Piece = _selected_piece
	if piece == null or _state.get_piece(piece.id) == null:
		_cancel_selection()
		return

	if pos == piece.position:
		_begin_attack_step(null)
		return
	if _controller.get_valid_move_targets(piece).has(pos):
		_begin_attack_step(pos)
		return

	var other: Piece = _state.board.get_piece_at(pos)
	if other != null and other.owner_index == _human_player:
		_select_piece(other)
	elif other != null:
		hud.show_message(_describe_piece(other), 3.5)
	else:
		hud.show_message("Out of movement range. Click a blue tile or the piece itself to stay.")


func _handle_attack_click(pos: Vector2i) -> void:
	var piece: Piece = _selected_piece
	if piece == null or _state.get_piece(piece.id) == null:
		_cancel_selection()
		return
	var from_pos: Vector2i = _planned_move if _planned_move != null else piece.position
	var attack: Variant = null
	if pos != from_pos and _controller.get_valid_attack_targets(piece, from_pos).has(pos):
		attack = pos
	_execute_action(piece, _planned_move, attack)


func _select_piece(piece: Piece) -> void:
	if not _controller.can_command(piece):
		hud.show_message(("%s: Summoning sick - can act next turn." % _piece_label(piece))
			if piece.is_summoning_sick(_state.turn_number) else _controller.last_error, 3.0)
		return
	if _state.config.order_ap_cost > _state.current_player.action_points:
		hud.show_message("Not enough AP: commanding %s costs %d AP." % [_piece_label(piece), _state.config.order_ap_cost], 3.0)
		return
	_cancel_selection()
	_mode = InputMode.CHOOSING_MOVE
	_selected_piece = piece
	_planned_move = null

	var view: PieceView = animator.get_view(piece.id)
	if view != null:
		view.set_selected(true)
	board.show_highlights(_single(piece.position), HighlightKind.SELECTED)
	board.show_highlights(_controller.get_valid_move_targets(piece), HighlightKind.MOVE)
	var no_path: Array[Vector2i] = []
	overlay.show_preview(piece, null, null, board, no_path, _state.board)
	hud.set_cancel_enabled(true)
	_show_unit_actions(piece)
	_update_hint()


func _begin_attack_step(move: Variant) -> void:
	var piece: Piece = _selected_piece
	_mode = InputMode.CHOOSING_ATTACK
	_planned_move = move
	var from_pos: Vector2i = move if move != null else piece.position

	board.clear_highlights(HighlightKind.MOVE)
	if move != null:
		board.show_highlights(_single(move), HighlightKind.MOVE)
	board.show_highlights(_controller.get_valid_attack_targets(piece, from_pos), HighlightKind.ATTACK)
	var path: Array[Vector2i] = []
	if move != null:
		path = _controller.get_planned_path(piece, move)
	overlay.show_preview(piece, move, null, board, path, _state.board)
	_show_unit_actions(piece, move if move != null else piece.position)
	_update_hint()


## Commands a piece: its move and attack resolve immediately and are animated right away.
func _execute_action(piece: Piece, move: Variant, attack: Variant) -> void:
	var moves: bool = move != null and move != piece.position
	if not moves and attack == null:
		_cancel_selection()
		hud.show_message("%s holds position (no AP spent)." % _piece_label(piece))
		return
	_cache_piece_names()
	var target: Piece = _state.board.get_piece_at(attack) if attack != null else null
	var events: Variant = _controller.act(piece, move, attack)
	if events == null:
		hud.show_message(_controller.last_error)
		return
	var text: String = ("moves to %s" % str(move)) if moves else "stays"
	if attack != null:
		text += (" and attacks %s" % _piece_name(target.id)) if target != null else (" and attacks %s" % str(attack))
	_log("%s %s %s." % [_possessive_label(_human_player), _piece_label(piece), text])
	_cancel_selection()
	_animate_spell_events_async(_copy_events(events), _generation)


# ------------------------------------------------------------------ selection / UI helpers

func _is_selecting() -> bool:
	return _mode == InputMode.CARD_SELECTED or _mode == InputMode.CHOOSING_MOVE or _mode == InputMode.CHOOSING_ATTACK \
		or _mode == InputMode.CHOOSING_BUILD or _mode == InputMode.CHOOSING_TRAP


func _reset_selection() -> void:
	_selected_hand_index = -1
	_selected_card = null
	_selected_piece = null
	_planned_move = null
	_build_tiles.clear()


## Clears any card/piece selection, highlights and previews and returns to Idle (not while Busy).
func _cancel_selection() -> void:
	_reset_selection()
	if _mode != InputMode.BUSY:
		_mode = InputMode.IDLE
	_clear_all_highlights()
	animator.clear_selection()
	overlay.clear_preview()
	overlay.clear_attack_preview()
	overlay.clear_spell_area_preview()
	hud.hand.set_selected_index(-1)
	hud.set_cancel_enabled(false)
	hud.action_bar.hide_bar()
	_update_range_highlight()
	_update_hint()


func _can_human_act() -> bool:
	return _state != null \
		and not _autoplay \
		and _mode != InputMode.BUSY \
		and _state.winner < 0 \
		and _state.current_player_index == _human_player \
		and _state.phase == GamePhase.MAIN


## Refreshes the HUD labels, the human hand, the button states and the "can act" glows.
func _refresh() -> void:
	if _state == null:
		return
	hud.update_state(_state)

	var can_act: bool = _can_human_act()
	var human: PlayerState = _state.players[_human_player]
	var shown: Array[CardData] = []
	if not _conceal_hand:
		shown = human.hand
	hud.hand.show_hand(shown, _controller.get_card_cost,
		func(card: CardData) -> bool: return can_act and _controller.get_card_cost(card) <= human.action_points)
	if _mode == InputMode.CARD_SELECTED:
		hud.hand.set_selected_index(_selected_hand_index)
	hud.set_end_turn_enabled(can_act)
	hud.set_cancel_enabled(can_act and _is_selecting())
	hud.set_draw_enabled(can_act and _controller.can_draw())
	_update_can_act()
	_update_board_info()


## Hover info for the tile under the mouse: the piece standing there (stats, keywords, spells, statuses,
## order) or the tile effect on it. Hidden while animations run (the state is already ahead of the view).
func _update_board_info() -> void:
	if _state == null or _mode == InputMode.BUSY or _hover_tile == null or hud.deck_select.visible:
		hud.hide_board_info()
		return
	var tile: Vector2i = _hover_tile
	var piece: Piece = _state.board.get_piece_at(tile)
	var sheet: InfoSheet = InfoText.piece(piece, _state, _human_player) if piece != null else InfoText.tile(tile, _state, _human_player)
	hud.show_board_info(sheet)


## Green glow on the human's pieces that can still be commanded this turn (no order yet, enough AP).
func _update_can_act() -> void:
	animator.sync_exhausted(_state)
	if animator.is_playing:
		return
	var human_main: bool = _can_human_act()
	var ap: int = _state.players[_human_player].action_points
	for piece: Piece in _state.pieces:
		var view: PieceView = animator.get_view(piece.id)
		if view == null:
			continue
		var can_act: bool = human_main and piece.owner_index == _human_player and not piece.has_acted(_state.turn_number) \
			and ap >= _state.config.order_ap_cost and _controller.can_command(piece)
		view.set_can_act(can_act)


## Clears the order overlay (actions resolve immediately; nothing stays queued).
func _update_order_overlay() -> void:
	if _state == null:
		return
	overlay.show_orders(_state, board, func(p: Piece, t: Vector2i) -> Array[Vector2i]: return _controller.get_planned_path(p, t))


func _update_hint() -> void:
	if _state == null:
		return
	if _state.winner >= 0:
		hud.set_hint("Game over.")
		return
	match _mode:
		InputMode.BUSY:
			return
		InputMode.CARD_SELECTED:
			if _selected_card != null and _selected_card.card_type == CardType.SPELL:
				hud.set_hint(("%s: click a tile to cast it. Esc cancels." % _selected_card.name) if _selected_card.targets_tile
					else ("%s: click a piece to cast it. Esc cancels." % _selected_card.name))
			else:
				hud.set_hint("%s: click a green tile to deploy. Esc cancels." % (_selected_card.name if _selected_card != null else ""))
			return
		InputMode.CHOOSING_MOVE:
			hud.set_hint("%s: click a blue tile (own pieces get pushed) or itself to stay." % _piece_label_with_keywords(_selected_piece))
			return
		InputMode.CHOOSING_ATTACK:
			hud.set_hint("%s: click red to attack now (own pieces take damage too), elsewhere = move only." % _piece_label_with_keywords(_selected_piece))
			return

	if _state.current_player_index != _human_player or _autoplay:
		hud.set_hint("%s's turn." % _player_label(_state.current_player_index))
	elif _state.phase == GamePhase.DRAFT:
		hud.set_hint("Choose a card to keep.")
	else:
		hud.set_hint("Play cards or command pieces (%d AP). D: draw, C: VP->AP, Enter: end turn." % _state.config.order_ap_cost)


## Where cards of destroyed pieces fly to: the human's HUD deck pile (projected into the world), AI = default.
## Returns a Vector3 or null.
func _get_deck_world(player: int) -> Variant:
	if player != _human_player or hud == null or not is_inside_tree():
		return null
	var camera: Camera3D = null
	if camera_rig != null:
		camera = camera_rig.camera
	if camera == null and get_viewport() != null:
		camera = get_viewport().get_camera_3d()
	var screen: Vector2 = hud.deck_pile_screen_position
	if camera == null or screen == Vector2.ZERO:
		return null
	var depth: float = camera.global_position.distance_to(board.global_position) * 0.7
	return camera.project_position(screen, depth)


func _delay_async(seconds: float) -> void:
	if seconds <= 0.0:
		return
	await get_tree().create_timer(seconds).timeout


func _is_current(generation: int) -> bool:
	return generation == _generation and is_inside_tree()


func _get_ai_for(player: int) -> SimpleAi:
	if player == AI_PLAYER:
		return _ai
	return _autoplay_ai if player == _human_player else null


func _log(line: String) -> void:
	hud.log(line)
	if _autoplay:
		print(line)


func _flush_pending_log() -> void:
	for line in _pending_log:
		_log(line)
	_pending_log.clear()


func _cache_piece_names() -> void:
	for p: Piece in _state.pieces:
		_piece_names[p.id] = _piece_name_for(p)


func _piece_name_for(p: Piece) -> String:
	var owner_text: String = ("P%d" % (p.owner_index + 1)) if _hotseat else ("your" if p.owner_index == _human_player else "AI")
	return "%s %s" % [owner_text, p.source.name if p.source != null else "piece"]


func _piece_name(id: int) -> String:
	if id < 0:
		return "empty tile"
	return _piece_names[id] if _piece_names.has(id) else "piece #%d" % id


static func _piece_label(piece: Piece) -> String:
	if piece != null and piece.source != null:
		return piece.source.name
	return "Piece"


static func _piece_label_with_keywords(piece: Piece) -> String:
	if piece != null and piece.keywords != Keyword.NONE:
		return "%s [%s]" % [_piece_label(piece), KeywordInfo.format(piece.keywords)]
	return _piece_label(piece)


func _player_label(player: int) -> String:
	if _hotseat:
		return HOTSEAT_NAMES[player]
	return "You" if player == _human_player else "AI"


## "Your" / "AI" (hotseat: "Player 1's" / "Player 2's").
func _possessive_label(player: int) -> String:
	if _hotseat:
		return "%s's" % HOTSEAT_NAMES[player]
	return "Your" if player == _human_player else "AI"


## Owner prefix of a piece seen by the view player: "Your" / "AI" (hotseat: "Your" / "Enemy").
func _owner_label(p: Piece) -> String:
	if p.owner_index == _human_player:
		return "Your"
	return "Enemy" if _hotseat else "AI"


## One-line piece info for the hint ribbon (hover).
func _describe_piece_short(p: Piece) -> String:
	var text: String = "%s %s: %d/%d HP, %d Atk, %d Mov, %d Rng" % [
		_owner_label(p), _piece_label(p), p.current_hp, p.max_hp,
		p.effective_attack, p.effective_movement, p.effective_range]
	if p.total_shield > 0:
		text += ", %d Shield" % p.total_shield
	if p.keywords != Keyword.NONE:
		text += " - %s" % KeywordInfo.format(p.keywords)
	if p.is_frozen:
		text += " - Frozen"
	if p.has_status(StatusEffectType.OVERCHARGED):
		text += " - Overcharged"
	if p.is_summoning_sick(_state.turn_number):
		text += " (Zzz)"
	return text


func _describe_piece(p: Piece) -> String:
	var text: String = "%s %s: HP %d/%d, Shield %d, Atk %d, Mov %d, Rng %d" % [
		_owner_label(p), p.source.name if p.source != null else "",
		p.current_hp, p.max_hp, p.total_shield, p.effective_attack, p.effective_movement, p.effective_range]
	if p.active_spells.size() > 0:
		text += ", %d spell(s)" % p.active_spells.size()
	if p.is_frozen:
		text += ", Frozen"
	if p.has_status(StatusEffectType.OVERCHARGED):
		text += ", Overcharged"
	for k: int in KeywordInfo.split(p.keywords):
		text += "\n%s: %s" % [KeywordInfo.display_name(k), KeywordInfo.get_description(k)]
	return text


func _describe_event(e: ResolutionEvent) -> String:
	var n: String = _piece_name(e.piece_id)
	match e.type:
		ResolutionEventType.MOVED:
			return "%s moves %s -> %s" % [n, str(e.from), str(e.to)]
		ResolutionEventType.MOVE_BLOCKED:
			return "%s is blocked moving to %s" % [n, str(e.to)]
		ResolutionEventType.ATTACKED:
			return "%s %s %s" % [n, "zaps" if e.is_secondary else "attacks", str(e.to)] \
				+ ((" (%s)" % _piece_name(e.other_piece_id)) if e.other_piece_id >= 0 else "")
		ResolutionEventType.ATTACK_CANCELLED:
			return "%s's attack on %s is cancelled" % [n, str(e.to)]
		ResolutionEventType.DAMAGED:
			return ("%s takes %d damage" % [n, e.hp_lost]) \
				+ ((" (%d blocked)" % e.shield_absorbed) if e.shield_absorbed > 0 else "") \
				+ (", HP %d" % e.remaining_hp)
		ResolutionEventType.DIED:
			return "%s dies" % n
		ResolutionEventType.SPELL_EXPIRED:
			return "%s on %s expired" % [e.spell_name, n]
		ResolutionEventType.PUSHED:
			return "%s is pushed %s -> %s by %s" % [n, str(e.from), str(e.to), _piece_name(e.other_piece_id)]
		ResolutionEventType.PUSH_BLOCKED:
			return "%s cannot be pushed to %s" % [n, str(e.to)]
		ResolutionEventType.HEALED:
			return "%s is healed +%d, HP %d" % [n, e.amount, e.remaining_hp]
		ResolutionEventType.RETURNED_TO_DECK:
			if e.amount > 0:
				return "%s rises again: %s returns to %s's deck" % [n, e.card_name, _player_label(e.player_index)]
			return "%s returns to %s's deck" % [e.card_name, _player_label(e.player_index)]
		ResolutionEventType.TILE_EFFECT_APPLIED:
			return "%s appears at %s (%d turns)" % [KeywordInfo.get_tile_effect_name(e.tile_effect), str(e.to), e.amount]
		ResolutionEventType.TILE_EFFECT_EXPIRED:
			return "%s at %s fades" % [KeywordInfo.get_tile_effect_name(e.tile_effect), str(e.to)]
		ResolutionEventType.TILE_DAMAGE:
			return "%s burns on lava (%d)" % [n, e.amount]
		ResolutionEventType.TILE_HEAL:
			return "%s is healed +%d by the sanctuary, HP %d" % [n, e.amount, e.remaining_hp]
		ResolutionEventType.STATUS_APPLIED:
			return "%s is %s" % [n, KeywordInfo.get_status_name(e.status)]
		ResolutionEventType.STATUS_EXPIRED:
			if e.is_secondary:
				return "%s releases its %s charge" % [n, KeywordInfo.get_status_name(e.status)]
			return "%s is no longer %s" % [n, KeywordInfo.get_status_name(e.status)]
		ResolutionEventType.SPELL_CAST:
			return "%s cast %s at %s%s" % [_player_label(e.player_index), e.card_name, str(e.to),
				" (empowered by an Obelisk)" if e.amount > 0 else ""]
		ResolutionEventType.DEATHRATTLE:
			return "Deathrattle of %s: %s" % [e.card_name, e.spell_name]
		ResolutionEventType.BUILDING_STARTED:
			return "%s starts building a %s at %s" % [n, e.spell_name, str(e.to)]
		ResolutionEventType.BUILDING_COMPLETED:
			return "%s at %s is finished" % [e.spell_name, str(e.to)]
		ResolutionEventType.AURA_PULSE:
			return "%s's %s pulses" % [n, e.spell_name]
		ResolutionEventType.FIRST_HIT_TRIGGERED:
			return "%s is hit for the first time: %s" % [n, e.spell_name]
		ResolutionEventType.TRAP_SET:
			if e.player_index == _human_player and not _hotseat:
				return "%s hides a %s at %s" % [n, e.card_name, str(e.to)]
			return "%s hides a trap somewhere" % _player_label(e.player_index)
		ResolutionEventType.TRAP_TRIGGERED:
			var whose: String = _possessive_label(e.player_index) if _hotseat else ("your" if e.player_index == _human_player else "an enemy")
			return "%s steps into %s %s at %s!" % [n, whose, e.card_name, str(e.to)]
		ResolutionEventType.TERRAIN_DAMAGED:
			if e.remaining_hp <= 0:
				return "The rock at %s crumbles" % str(e.to)
			return "The rock at %s takes %d damage (%d HP left)" % [str(e.to), e.amount, e.remaining_hp]
		ResolutionEventType.AP_GAINED:
			return "%s gain%s %d AP%s (%s)" % [_player_label(e.player_index), "" if e.player_index == _human_player and not _hotseat else "s",
				e.amount, " next turn" if e.is_secondary else "", e.card_name]
	return ResolutionEventType.name_of(e.type)


static func _to_list(cards: Array[CardData]) -> Array[CardData]:
	var list: Array[CardData] = []
	if cards == null:
		return list
	for card in cards:
		if card != null:
			list.append(card)
	return list


## Port helper: one-tile typed array (C# new[] { tile }).
static func _single(tile: Vector2i) -> Array[Vector2i]:
	var list: Array[Vector2i] = [tile]
	return list


## Port helper: typed copy of an event list (C# new List<ResolutionEvent>(events)).
static func _copy_events(events: Array) -> Array[ResolutionEvent]:
	var list: Array[ResolutionEvent] = []
	for e in events:
		list.append(e)
	return list
