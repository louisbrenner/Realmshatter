class_name GameManager
extends Node
## Root script of Main.tscn. Wires the pure rules (GameState / TurnController) to the board view,
## animator, order overlay, camera, HUD and the AI, and runs the human input state machine (player 0).
## User args: --selftest prints the rules and AI self-tests, --autoplay lets a second SimpleAi
## play the human side until game over and then quits (debug).

const HUMAN_PLAYER := 0
const AI_PLAYER := 1
const MAX_AUTOMATED_TURNS := 1000

## One committed order captured before EndTurn (for the "Order 2/4" resolution ticker).
class OrderStep:
	var piece_id: int
	var text: String

	func _init(p_piece_id: int = -1, p_text: String = "") -> void:
		piece_id = p_piece_id
		text = p_text

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
## Random seed for draws (0 = random every game).
@export var seed: int = 0
## Pause in seconds before and after the AI plays its cards.
@export var ai_step_delay: float = 0.6

@export_group("Nodes")
@export var board: BoardView
@export var animator: BoardAnimator
@export var camera_rig: CameraRig
@export var hud: Hud
## Order arrows / numbers, planning and chain previews (created at the origin if not assigned).
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
var _planned_move: Variant = null

var _pending_log: Array[String] = []
var _piece_names: Dictionary = {}
var _captured_spell_events: Array = []
var _capture_spells: bool = false
var _pending_score_tiles: Array[Vector2i] = []
var _pending_score_player: int = -1
var _player_theme: DeckData
var _ai_theme: DeckData
var _hover_tile: Variant = null
var _theme_random: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	if board == null or animator == null or camera_rig == null or hud == null:
		push_error("GameManager: Board, Animator, CameraRig and Hud must be assigned.")
		return
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
	hud.draft.card_chosen.connect(_on_draft_card_chosen)
	hud.deck_select.deck_chosen.connect(_on_deck_chosen)
	camera_rig.view_mode_changed.connect(_on_view_mode_changed)
	_on_view_mode_changed(int(camera_rig.mode))

	_begin_new_game()


## Shows the deck selection (when ThemeDecks are set and not autoplaying), otherwise starts right away.
func _begin_new_game() -> void:
	var themes: Array[DeckData] = _theme_list()
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
func _show_deck_selection(themes: Array[DeckData]) -> void:
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
	hud.deck_select.present(themes)


func _on_deck_chosen(index: int) -> void:
	var themes: Array[DeckData] = _theme_list()
	if index < 0 or index >= themes.size():
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
	_controller = TurnController.new(_state)
	_ai = SimpleAi.new(_controller, AI_PLAYER)
	_autoplay_ai = SimpleAi.new(_controller, HUMAN_PLAYER) if _autoplay else null
	_subscribe_controller()

	_pending_log.clear()
	_piece_names.clear()
	_captured_spell_events.clear()
	_pending_score_tiles.clear()
	_pending_score_player = -1
	_hover_tile = null
	_reset_selection()
	_mode = InputMode.IDLE
	if player_deck_res != null and ai_deck_res != null:
		_pending_log.append("Your deck: %s. AI deck: %s." % [player_deck_res.name, ai_deck_res.name])

	var fit := Vector2(cfg.board_width, cfg.board_height)
	if camera_rig.board_fit_size != fit:
		camera_rig.board_fit_size = fit
		camera_rig.set_mode(camera_rig.mode, false)

	board.build(_state.board)
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


func _on_turn_started(player: int) -> void:
	_pending_log.append("--- Turn %d: %s (%d AP) ---" % [_state.turn_number, _player_label(player), _state.players[player].action_points])
	if player == 1 and _state.players[player].turns_started == 1 and _state.config.second_player_first_turn_bonus_ap > 0:
		_pending_log.append("%s moves second: +%d AP this turn." % [_player_label(player), _state.config.second_player_first_turn_bonus_ap])


func _on_victory_points_scored(player: int, points: int) -> void:
	_pending_log.append("%s scored %d VP (total %d)." % [_player_label(player), points, _state.players[player].victory_points])
	_pending_score_player = player
	_pending_score_tiles.clear()
	for p: Piece in _state.get_pieces_of(player):
		if _state.board.is_in_scoring_zone(p.position):
			_pending_score_tiles.append(p.position)


func _on_game_over(winner: int) -> void:
	_pending_log.append("%s reached %d VP and wins!" % [_player_label(winner), _state.config.points_target])


func _on_spell_resolved(events: Array) -> void:
	if _capture_spells and events != null:
		_captured_spell_events.append(events.duplicate())


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
					var events: Array = _captured_spell_events[spell_index]
					spell_index += 1
					await animator.play_events(events, _state, false)
					for e: ResolutionEvent in events:
						if e.type != ResolutionEventType.SPELL_CAST:
							_log(_describe_event(e))
			AiActionKind.CONVERT_VP:
				hud.show_message("%s converted 1 VP into 1 AP." % _player_label(action.player_index))
		if not _is_current(generation):
			return


## Ends the current turn, animates the resolution events order by order and logs them.
func _end_turn_async(generation: int) -> bool:
	if _state.phase != GamePhase.MAIN:
		hud.show_message("You can only end the turn in the main phase.")
		return false

	_mode = InputMode.BUSY
	hud.set_hint("Resolving orders...")
	_refresh()

	_cache_piece_names()
	var plan: Array[OrderStep] = _build_order_plan()
	var events: Array = _controller.end_turn()
	var turn_start_events: Array = _controller.last_turn_start_events.duplicate()

	overlay.clear_all()
	var grouped: Array = _group_events_by_order(events, plan)
	var groups: Array = grouped[0]
	var group_steps: Array[int] = grouped[1]
	await animator.play_event_groups(groups, _state, func(gi: int) -> void:
		var step: int = group_steps[gi]
		if step >= 0:
			hud.show_resolution_step(step + 1, plan.size(), plan[step].text)
		else:
			hud.hide_resolution_step()
	, turn_start_events.size() == 0)
	hud.hide_resolution_step()
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
		await animator.play_score(tiles, player)
	_pending_score_player = -1


func _enter_human_turn_or_game_over() -> void:
	_reset_selection()
	board.clear_highlights()
	animator.clear_selection()
	overlay.clear_preview()
	overlay.clear_attack_preview()
	overlay.clear_spell_area_preview()

	if _state.winner >= 0:
		_mode = InputMode.IDLE
		_refresh()
		hud.set_hint("Game over.")
		hud.show_win_screen(_state.winner)
		if _autoplay:
			print("AUTOPLAY RESULT: winner = %s after %d turns, VP %d : %d, pieces alive %d." % [
				_player_label(_state.winner), _state.turn_number,
				_state.players[0].victory_points, _state.players[1].victory_points, _state.pieces.size()])
			get_tree().quit()
		return

	_mode = InputMode.IDLE
	# Turns start in Main phase; this only resumes an unfinished (already paid) draw.
	if _state.current_player_index == HUMAN_PLAYER and _state.phase == GamePhase.DRAFT and not _autoplay:
		hud.draft.show_offer(_state.current_player.draft_offer, _controller.get_card_cost)
	_update_hint()
	_refresh()
	_update_order_overlay()


## The current player's committed orders in resolution order, with a short ticker text each.
func _build_order_plan() -> Array[OrderStep]:
	var pieces: Array[Piece] = []
	for p: Piece in _state.get_pieces_of(_state.current_player_index):
		if p.order != null:
			pieces.append(p)
	pieces.sort_custom(func(a: Piece, b: Piece) -> bool: return a.order.order_index < b.order.order_index)
	var plan: Array[OrderStep] = []
	for p in pieces:
		var who: String = "%s %s" % ["Your" if p.owner_index == HUMAN_PLAYER else "AI", _piece_label(p)]
		var parts: Array[String] = []
		if p.order.move_target != null and p.order.move_target != p.position:
			parts.append("moves")
		if p.order.attack_target != null:
			var target: Piece = _state.board.get_piece_at(p.order.attack_target)
			if target == null or target == p:
				parts.append("attacks")
			elif target.owner_index == p.owner_index:
				parts.append("triggers %s" % _piece_label(target))
			else:
				parts.append("attacks %s" % _piece_label(target))
		var text: String = ("%s %s" % [who, " & ".join(parts)]) if parts.size() > 0 else ("%s holds" % who)
		plan.append(OrderStep.new(p.id, text))
	return plan


## Splits the chronological resolution events into one group per resolved order (a group starts with the
## acting piece's move / attack) plus a trailing upkeep group (expiring spells, statuses, tile effects).
## Returns [groups: Array (of Array[ResolutionEvent]), group_steps: Array[int]];
## group_steps[i] = plan index of group i, or -1 for upkeep.
static func _group_events_by_order(events: Array, plan: Array[OrderStep]) -> Array:
	const NO_STEP := -2147483648
	var groups: Array = []
	var group_steps: Array[int] = []
	var current: Array[ResolutionEvent] = []
	var has_current: bool = false
	var current_step: int = NO_STEP
	var last_plan_index: int = -1
	for i in range(events.size()):
		var e: ResolutionEvent = events[i]
		var upkeep: bool = e.type == ResolutionEventType.SPELL_EXPIRED or e.type == ResolutionEventType.TILE_EFFECT_EXPIRED \
			or (e.type == ResolutionEventType.STATUS_EXPIRED and not e.is_chain)
		var step: int
		if upkeep:
			step = -1
		else:
			var actor: int = -1
			match e.type:
				ResolutionEventType.MOVED, ResolutionEventType.MOVE_BLOCKED, ResolutionEventType.ATTACK_CANCELLED:
					actor = e.piece_id
				ResolutionEventType.ATTACKED:
					actor = -1 if (e.is_chain or e.is_pierce) else e.piece_id
				ResolutionEventType.PUSH_BLOCKED:
					var next: ResolutionEvent = events[i + 1] if i + 1 < events.size() else null
					if next != null and (next.type == ResolutionEventType.MOVED or next.type == ResolutionEventType.MOVE_BLOCKED) \
							and next.piece_id == e.other_piece_id:
						actor = e.other_piece_id
			step = maxi(last_plan_index, 0) if (current_step == NO_STEP or current_step < 0) else current_step
			if actor >= 0:
				for k in range(last_plan_index + 1, plan.size()):
					if plan[k].piece_id == actor:
						step = k
						break
			if plan.size() == 0:
				step = -1
		if not has_current or step != current_step:
			current = []
			has_current = true
			groups.append(current)
			group_steps.append(step)
			current_step = step
			if step > last_plan_index:
				last_plan_index = step
		current.append(e)
	return [groups, group_steps]


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
	_begin_new_game()


func _on_draw_pressed() -> void:
	if not _can_human_act():
		return
	_cancel_selection()
	if not _controller.draw():
		hud.show_message(_controller.last_error)
		return
	_log("You paid %d AP to draw." % _state.config.draw_ap_cost)
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
	_log("You converted 1 VP into 1 AP (%d conversion(s) left this turn)." % _controller.remaining_vp_conversions)
	hud.show_message("+1 AP for 1 VP (%d left this turn)." % _controller.remaining_vp_conversions)
	_update_hint()
	_refresh()


func _on_draft_card_chosen(offer_index: int) -> void:
	if _mode == InputMode.BUSY or _state.current_player_index != HUMAN_PLAYER or _state.phase != GamePhase.DRAFT:
		return
	var card: CardData = _state.current_player.draft_offer[offer_index] \
		if offer_index >= 0 and offer_index < _state.current_player.draft_offer.size() else null
	if not _controller.choose_draft_card(offer_index):
		hud.show_message(_controller.last_error)
		return
	_log("You kept %s." % (card.name if card != null else "a card"))
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
	var hand: Array[CardData] = _state.players[HUMAN_PLAYER].hand
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
		# Area spells can target (almost) any tile: the hover preview shows the area instead of a board-wide highlight.
		if not card.targets_tile:
			board.show_highlights(tiles, HighlightKind.SPELL)
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
	if pos.x < 0 or _mode == InputMode.BUSY or _state == null:
		board.clear_highlights(HighlightKind.HOVER)
		overlay.clear_attack_preview()
		overlay.clear_spell_area_preview()
		if _mode != InputMode.BUSY:
			_update_hint()
		return
	var tile: Vector2i = pos
	var single: Array[Vector2i] = [tile]
	if _mode == InputMode.CARD_SELECTED and _selected_card != null and _selected_card.targets_tile:
		var area: Array[Vector2i] = _controller.get_spell_area_preview(_selected_card, tile)
		board.show_highlights(area, HighlightKind.HOVER)
		if _controller.can_cast_spell_at(_selected_card, tile):
			overlay.show_spell_area_preview(area, _selected_card.tile_effect, board, _state.board)
		else:
			overlay.clear_spell_area_preview()
	elif _mode == InputMode.CHOOSING_MOVE and _selected_piece != null:
		board.show_highlights(single, HighlightKind.HOVER)
		if tile != _selected_piece.position and _controller.get_valid_move_targets(_selected_piece).has(tile):
			overlay.show_preview(_selected_piece, tile, null, board, _controller.get_planned_path(_selected_piece, tile), _state.board)
		else:
			var no_path: Array[Vector2i] = []
			overlay.show_preview(_selected_piece, null, null, board, no_path, _state.board)
	elif _mode == InputMode.CHOOSING_ATTACK and _selected_piece != null:
		board.show_highlights(single, HighlightKind.HOVER)
		_show_attack_plan_preview(tile)
	elif _mode == InputMode.IDLE:
		board.show_highlights(single, HighlightKind.HOVER)
		var piece: Piece = _state.board.get_piece_at(tile)
		if piece != null:
			hud.set_hint(_describe_piece_short(piece))
		else:
			_update_hint()
	else:
		board.show_highlights(single, HighlightKind.HOVER)


## While choosing an attack: shows the planned order with the hovered attack arc and, for occupied targets,
## the predicted consequences (chain shots of triggered friendlies, damage, kills, pushes, new tile effects).
func _show_attack_plan_preview(tile: Vector2i) -> void:
	var from_pos: Vector2i = _planned_move if _planned_move != null else _selected_piece.position
	var path: Array[Vector2i] = []
	if _planned_move != null:
		path = _controller.get_planned_path(_selected_piece, _planned_move)
	var valid: bool = tile != from_pos and _controller.get_valid_attack_targets(_selected_piece, from_pos).has(tile)
	overlay.show_preview(_selected_piece, _planned_move, tile if valid else null, board, path, _state.board)
	if not valid or not _state.board.is_occupied(tile):
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
	var friendly: bool = target != null and target.owner_index == HUMAN_PLAYER and target != _selected_piece
	var parts: Array[String] = []
	if friendly:
		parts.append("triggers %s" % _piece_label(target))
	parts.append("%d enemy dmg" % p.enemy_hp_lost)
	if p.enemy_kills > 0:
		parts.append("%d kill%s" % [p.enemy_kills, "s" if p.enemy_kills > 1 else ""])
	if p.triggered_piece_ids.size() > 0 and not (friendly and p.triggered_piece_ids.size() == 1):
		parts.append("%d chain%s" % [p.triggered_piece_ids.size(), "s" if p.triggered_piece_ids.size() > 1 else ""])
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


func _handle_idle_click(pos: Vector2i) -> void:
	var piece: Piece = _state.board.get_piece_at(pos)
	if piece == null:
		return
	if piece.owner_index == HUMAN_PLAYER:
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
		_log("You deployed %s at %s." % [card.name, str(pos)])
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
	_log("You cast %s on %s." % [card.name, target_text])
	_cancel_selection()
	_animate_spell_events_async(_controller.last_spell_events.duplicate(), _generation)


## Animates the immediate events of a spell (cast VFX, damage, deaths, heals, tile effects) BEFORE the
## views are synced, so killed pieces play their death, then refreshes the HUD and order arrows.
func _animate_spell_events_async(events: Array, generation: int) -> void:
	_mode = InputMode.BUSY
	board.clear_highlights()
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
	if other != null and other.owner_index == HUMAN_PLAYER:
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
	_issue_order(piece, _planned_move, attack)


func _select_piece(piece: Piece) -> void:
	if not _controller.can_command(piece):
		hud.show_message(("%s: Summoning sick - can act next turn." % _piece_label(piece))
			if piece.is_summoning_sick(_state.turn_number) else _controller.last_error, 3.0)
		return
	if piece.order == null and _state.config.order_ap_cost > _state.current_player.action_points:
		hud.show_message("Not enough AP: commanding %s costs %d AP." % [_piece_label(piece), _state.config.order_ap_cost], 3.0)
		return
	_cancel_selection()
	_mode = InputMode.CHOOSING_MOVE
	_selected_piece = piece
	_planned_move = null

	var view: PieceView = animator.get_view(piece.id)
	if view != null:
		view.set_selected(true)
	var selected_tiles: Array[Vector2i] = [piece.position]
	board.show_highlights(selected_tiles, HighlightKind.SELECTED)
	board.show_highlights(_controller.get_valid_move_targets(piece), HighlightKind.MOVE)
	var no_path: Array[Vector2i] = []
	overlay.show_preview(piece, null, null, board, no_path, _state.board)
	hud.set_cancel_enabled(true)
	_update_hint()


func _begin_attack_step(move: Variant) -> void:
	var piece: Piece = _selected_piece
	_mode = InputMode.CHOOSING_ATTACK
	_planned_move = move
	var from_pos: Vector2i = move if move != null else piece.position

	board.clear_highlights(HighlightKind.MOVE)
	if move != null:
		var move_tiles: Array[Vector2i] = [move]
		board.show_highlights(move_tiles, HighlightKind.MOVE)
	board.show_highlights(_controller.get_valid_attack_targets(piece, from_pos), HighlightKind.ATTACK)
	var path: Array[Vector2i] = []
	if move != null:
		path = _controller.get_planned_path(piece, move)
	overlay.show_preview(piece, move, null, board, path, _state.board)
	_update_hint()


func _issue_order(piece: Piece, move: Variant, attack: Variant) -> void:
	var had_order: bool = piece.order != null
	var ap_before: int = _state.current_player.action_points
	var target: Piece = _state.board.get_piece_at(attack) if attack != null else null
	if not _controller.set_order(piece, move, attack):
		hud.show_message(_controller.last_error)
		return
	var ap_delta: int = _state.current_player.action_points - ap_before
	var ap_text: String = (", %d AP" % -ap_delta) if ap_delta < 0 else ((", +%d AP refunded" % ap_delta) if ap_delta > 0 else "")

	var label: String = _piece_label(piece)
	if piece.order == null:
		hud.show_message(("%s: order cleared%s." % [label, ap_text]) if had_order else ("%s holds position." % label))
	else:
		var text: String = ("move to %s" % str(move)) if move != null else "stay"
		if attack != null:
			if target != null and target.owner_index == HUMAN_PLAYER and target != piece:
				text += ", chain via %s" % _piece_label(target)
			else:
				text += ", attack %s" % str(attack)
		hud.show_message("%s: %s (order %d%s)." % [label, text, piece.order.order_index + 1, ap_text])
	var view: PieceView = animator.get_view(piece.id)
	if view != null:
		view.set_has_order(piece.order != null)
	_cancel_selection()
	_refresh()
	_update_order_overlay()


# ------------------------------------------------------------------ selection / UI helpers

func _is_selecting() -> bool:
	return _mode == InputMode.CARD_SELECTED or _mode == InputMode.CHOOSING_MOVE or _mode == InputMode.CHOOSING_ATTACK


func _reset_selection() -> void:
	_selected_hand_index = -1
	_selected_card = null
	_selected_piece = null
	_planned_move = null


## Clears any card/piece selection, highlights and previews and returns to Idle (not while Busy).
func _cancel_selection() -> void:
	_reset_selection()
	if _mode != InputMode.BUSY:
		_mode = InputMode.IDLE
	board.clear_highlights()
	animator.clear_selection()
	overlay.clear_preview()
	overlay.clear_attack_preview()
	overlay.clear_spell_area_preview()
	hud.hand.set_selected_index(-1)
	hud.set_cancel_enabled(false)
	_update_hint()


func _can_human_act() -> bool:
	return _state != null \
		and not _autoplay \
		and _mode != InputMode.BUSY \
		and _state.winner < 0 \
		and _state.current_player_index == HUMAN_PLAYER \
		and _state.phase == GamePhase.MAIN


## Refreshes the HUD labels, the human hand, the button states and the "can act" glows.
func _refresh() -> void:
	if _state == null:
		return
	hud.update_state(_state)

	var can_act: bool = _can_human_act()
	var human: PlayerState = _state.players[HUMAN_PLAYER]
	hud.hand.show_hand(human.hand, _controller.get_card_cost,
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
	var text: String = InfoText.piece(piece, _state, HUMAN_PLAYER) if piece != null else InfoText.tile(tile, _state, HUMAN_PLAYER)
	hud.show_board_info(text)


## Green glow on the human's pieces that can still be commanded this turn (no order yet, enough AP).
func _update_can_act() -> void:
	if animator.is_playing:
		return
	var human_main: bool = _can_human_act()
	var ap: int = _state.players[HUMAN_PLAYER].action_points
	for piece: Piece in _state.pieces:
		var view: PieceView = animator.get_view(piece.id)
		if view == null:
			continue
		var can_act: bool = human_main and piece.owner_index == HUMAN_PLAYER and piece.order == null \
			and ap >= _state.config.order_ap_cost and _controller.can_command(piece)
		view.set_can_act(can_act)


## Redraws the committed order arrows / numbers of the current player.
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
			hud.set_hint("%s: click red to attack (own piece = chain), else move only." % _piece_label_with_keywords(_selected_piece))
			return

	if _state.current_player_index != HUMAN_PLAYER or _autoplay:
		hud.set_hint("%s's turn." % _player_label(_state.current_player_index))
	elif _state.phase == GamePhase.DRAFT:
		hud.set_hint("Choose a card to keep.")
	else:
		hud.set_hint("Play cards or command pieces (%d AP). D: draw, C: VP->AP, Enter: end turn." % _state.config.order_ap_cost)


## Where cards of destroyed pieces fly to: the human's HUD deck pile (projected into the world), AI = default.
## Returns a Vector3 or null.
func _get_deck_world(player: int) -> Variant:
	if player != HUMAN_PLAYER or hud == null or not is_inside_tree():
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
	return _autoplay_ai if player == HUMAN_PLAYER else null


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


static func _piece_name_for(p: Piece) -> String:
	return "%s %s" % ["your" if p.owner_index == HUMAN_PLAYER else "AI", p.source.name if p.source != null else "piece"]


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


static func _player_label(player: int) -> String:
	return "You" if player == HUMAN_PLAYER else "AI"


## One-line piece info for the hint ribbon (hover).
func _describe_piece_short(p: Piece) -> String:
	var text: String = "%s %s: %d/%d HP, %d Atk, %d Mov, %d Rng" % [
		"Your" if p.owner_index == HUMAN_PLAYER else "AI", _piece_label(p), p.current_hp, p.max_hp,
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


static func _describe_piece(p: Piece) -> String:
	var text: String = "%s %s: HP %d/%d, Shield %d, Atk %d, Mov %d, Rng %d" % [
		"Your" if p.owner_index == HUMAN_PLAYER else "AI", p.source.name if p.source != null else "",
		p.current_hp, p.max_hp, p.total_shield, p.effective_attack, p.effective_movement, p.effective_range]
	if p.active_spells.size() > 0:
		text += ", %d spell(s)" % p.active_spells.size()
	if p.is_frozen:
		text += ", Frozen"
	if p.has_status(StatusEffectType.OVERCHARGED):
		text += ", Overcharged"
	for k: int in KeywordInfo.split(p.keywords):
		text += "\n%s: %s" % [KeywordInfo.get_keyword_name(k), KeywordInfo.get_description(k)]
	return text


func _describe_event(e: ResolutionEvent) -> String:
	var n: String = _piece_name(e.piece_id)
	match e.type:
		ResolutionEventType.MOVED:
			return "%s moves %s -> %s" % [n, str(e.from), str(e.to)]
		ResolutionEventType.MOVE_BLOCKED:
			return "%s is blocked moving to %s" % [n, str(e.to)]
		ResolutionEventType.ATTACKED:
			return "%s %s %s" % [n, "chain-fires" if e.is_chain else "attacks", str(e.to)] \
				+ ((" (%s)" % _piece_name(e.other_piece_id)) if e.other_piece_id >= 0 else "")
		ResolutionEventType.ATTACK_CANCELLED:
			return "%s's attack on %s is cancelled" % [n, str(e.to)]
		ResolutionEventType.DAMAGED:
			return ("%s takes %d damage" % [n, e.hp_lost]) \
				+ ((" (%d blocked)" % e.shield_absorbed) if e.shield_absorbed > 0 else "") \
				+ (", HP %d" % e.remaining_hp)
		ResolutionEventType.DIED:
			return "%s dies" % n
		ResolutionEventType.CHAIN_TRIGGERED:
			return "%s is triggered by %s" % [n, _piece_name(e.other_piece_id)]
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
			if e.is_chain:
				return "%s releases its %s charge" % [n, KeywordInfo.get_status_name(e.status)]
			return "%s is no longer %s" % [n, KeywordInfo.get_status_name(e.status)]
		ResolutionEventType.SPELL_CAST:
			return "%s cast %s at %s" % [_player_label(e.player_index), e.card_name, str(e.to)]
	return ResolutionEventType.name_of(e.type)


static func _to_list(cards: Array[CardData]) -> Array[CardData]:
	var list: Array[CardData] = []
	if cards == null:
		return list
	for card in cards:
		if card != null:
			list.append(card)
	return list
