class_name Hud
extends CanvasLayer
## Screen-space HUD (root of Scenes/UI/Hud.tscn), Hearthstone styled: victory points as coin stacks,
## action points as mana crystals with VP-to-AP conversion slots, a deck pile Draw button, a big
## End Turn button, a turn plaque, parchment hint/toast ribbons, a collapsible combat log, turn
## banners, a resolution ticker and a victory/defeat screen. The whole layout is designed for
## reference_resolution and scaled uniformly to the window. It displays state and emits button
## signals; it never changes the game state itself.

signal end_turn_pressed()
signal view_toggle_pressed()
signal cancel_pressed()
signal restart_pressed()
signal draw_pressed()
## The player clicked a VP-to-AP conversion slot (spend 1 VP for 1 AP).
signal convert_vp_pressed()

## Internal: a turn banner finished (replaces the C# shared banner Task).
signal _banner_finished()

const HINT_SIDE_MARGIN := 236.0
const HINT_FONT_SIZE := 15
const HINT_MIN_FONT_SIZE := 13

## Design resolution of the HUD layout; the HUD is scaled uniformly to fit the window.
@export var reference_resolution: Vector2 = Vector2(1152, 648)
## Lower bound of the uniform UI scale (small windows).
@export var min_scale: float = 0.7
## Plays a turn banner automatically when update_state sees a new turn.
@export var auto_turn_banner: bool = true

## Player index whose hand, AP and points fill the own window (0 except in hotseat matches).
var view_player: int = 0
## Display names of both players for hotseat matches; empty = the default "You" / "AI" wording.
var player_names: Array[String] = []
## Player shown in the own (bottom) window; the other one fills the opponent window.
var _human_player: int:
	get: return view_player
var _ai_player: int:
	get: return 1 - view_player

var _root: Control
var _turn_indicator: TurnIndicator
var _view_button: Button
var _hint_ribbon: PanelContainer
var _hint_label: Label
var _ticker: PanelContainer
var _ticker_label: Label
var _toast: PanelContainer
var _message_label: Label
var _player_coins: VictoryCoinStack
var _ai_coins: VictoryCoinStack
var _player_vp_label: Label
var _ai_vp_label: Label
var _player_mana: ManaCrystalBar
var _ai_mana: ManaCrystalBar
var _vp_convert: VpConvertButton
var _deck_pile: DeckPile
var _end_turn_button: EndTurnButton
var _cancel_button: Button
var _log: CombatLog
var _turn_banner: TurnBanner
var _win_screen: Control
var _win_dim: ColorRect
var _victory_banner: VictoryBanner
var _restart_button: Button

var _message_tween: Tween
var _ticker_tween: Tween
var _win_tween: Tween
var _last_state: GameState
var _last_turn: int = -1
var _last_player: int = -1
var _turn_max_ap: Array[int] = [0, 0]
var _last_vp: Array[int] = [-1, -1]
var _last_banner_key: String = ""
## Serial of the last started banner and of the last finished one (C# _bannerTask).
var _banner_serial: int = 0
var _banner_done_serial: int = 0
var _enemy_hand: EnemyHandView
var _board_info: InfoPanel
var _card_info: InfoPanel
var _card_info_owner: CardView

## The hand display (Root/HandView).
var hand: HandView

## The draft popup (Root/DraftPopup).
var draft: DraftPopup

## Ability buttons floating above the selected unit (created in code).
var action_bar: UnitActionBar

## The deck selection screen (created in code on top of the HUD).
var deck_select: DeckSelectScreen

## Current uniform UI scale (window size / reference_resolution).
var ui_scale: float = 1.0

## Screen position (viewport pixels) of the center of the human's deck pile.
var deck_pile_screen_position: Vector2:
	get:
		return _deck_pile.get_global_transform_with_canvas() * (_deck_pile.size * 0.5) if _deck_pile != null else Vector2.ZERO


func _ready() -> void:
	_root = get_node("Root") as Control
	_turn_indicator = get_node("Root/TopBar/TurnIndicator") as TurnIndicator
	_view_button = get_node("Root/TopBar/ViewButton") as Button
	_hint_ribbon = get_node("Root/TopStack/HintRow/HintRibbon") as PanelContainer
	_hint_label = get_node("Root/TopStack/HintRow/HintRibbon/HintLabel") as Label
	_ticker = get_node("Root/TopStack/TickerRow/Ticker") as PanelContainer
	_ticker_label = get_node("Root/TopStack/TickerRow/Ticker/TickerLabel") as Label
	_toast = get_node("Root/TopStack/ToastRow/Toast") as PanelContainer
	_message_label = get_node("Root/TopStack/ToastRow/Toast/MessageLabel") as Label
	_ai_coins = get_node("Root/AiPanel/VBox/Coins") as VictoryCoinStack
	_ai_vp_label = get_node("Root/AiPanel/VBox/Header/VpLabel") as Label
	_ai_mana = get_node("Root/AiPanel/VBox/Mana") as ManaCrystalBar
	_player_coins = get_node("Root/PlayerPanel/VBox/Coins") as VictoryCoinStack
	_player_vp_label = get_node("Root/PlayerPanel/VBox/Header/VpLabel") as Label
	_player_mana = get_node("Root/PlayerPanel/VBox/ManaRow/ManaBar") as ManaCrystalBar
	_vp_convert = get_node("Root/PlayerPanel/VBox/ManaRow/VpConvert") as VpConvertButton
	_deck_pile = get_node("Root/DeckPile") as DeckPile
	_end_turn_button = get_node("Root/EndTurnButton") as EndTurnButton
	_cancel_button = get_node("Root/CancelButton") as Button
	_log = get_node("Root/LogPanel") as CombatLog
	_turn_banner = get_node("Root/TurnBanner") as TurnBanner
	_win_screen = get_node("Root/WinScreen") as Control
	_win_dim = get_node("Root/WinScreen/Dim") as ColorRect
	_victory_banner = get_node("Root/WinScreen/Center/VBox/Banner") as VictoryBanner
	_restart_button = get_node("Root/WinScreen/Center/VBox/RestartButton") as Button
	hand = get_node("Root/HandView") as HandView
	draft = get_node("Root/DraftPopup") as DraftPopup

	_root.theme = HudStyle.create_theme()
	_apply_styles()

	_end_turn_button.pressed.connect(func() -> void:
		Sfx.play(SfxId.END_TURN)
		end_turn_pressed.emit()
	)
	_view_button.pressed.connect(func() -> void:
		Sfx.play(SfxId.BUTTON_CLICK)
		view_toggle_pressed.emit()
	)
	_cancel_button.pressed.connect(func() -> void:
		Sfx.play(SfxId.BUTTON_CLICK)
		cancel_pressed.emit()
	)
	_restart_button.pressed.connect(func() -> void:
		Sfx.play(SfxId.BUTTON_CLICK)
		restart_pressed.emit()
	)
	_deck_pile.pressed.connect(func() -> void:
		Sfx.play(SfxId.CARD_PICK)
		draw_pressed.emit()
	)
	_vp_convert.pressed.connect(func() -> void:
		Sfx.play(SfxId.COIN)
		convert_vp_pressed.emit()
	)

	# The enemy window holds its points, AP and its face-down hand.
	_enemy_hand = EnemyHandView.new()
	_enemy_hand.name = "EnemyHand"
	_enemy_hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_hand.custom_minimum_size = Vector2(220, 74)
	(get_node("Root/AiPanel/VBox") as VBoxContainer).add_child(_enemy_hand)
	# The combat log hangs right below the opponent window (left column); the window sizes to its content.
	var ai_panel := get_node("Root/AiPanel") as Control
	ai_panel.resized.connect(func() -> void: _place_log_below(ai_panel))
	_place_log_below(ai_panel)
	action_bar = UnitActionBar.new()
	action_bar.name = "UnitActionBar"
	_root.add_child(action_bar)
	_root.move_child(action_bar, hand.get_index())

	deck_select = DeckSelectScreen.new()
	deck_select.name = "DeckSelect"
	deck_select.card_scene = hand.card_scene
	_root.add_child(deck_select)
	_board_info = InfoPanel.new()
	_board_info.name = "BoardInfo"
	_board_info.text_width = 240.0
	_root.add_child(_board_info)
	_card_info = InfoPanel.new()
	_card_info.name = "CardInfo"
	_card_info.text_width = 230.0
	_root.add_child(_card_info)
	hand.card_hover_changed.connect(_on_card_hover_changed)
	draft.card_hover_changed.connect(_on_card_hover_changed)

	_toast.visible = false
	_ticker.visible = false
	_win_screen.visible = false
	_hint_ribbon.visible = false
	set_cancel_enabled(false)
	_vp_convert.set_state(0, 2, false)

	get_viewport().size_changed.connect(_apply_scale)
	_apply_scale()


func _exit_tree() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null and viewport.size_changed.is_connected(_apply_scale):
		viewport.size_changed.disconnect(_apply_scale)


func _process(_delta: float) -> void:
	# The board only reports hovers while the mouse is not over UI: hide its info when a control takes over.
	if _board_info != null and _board_info.visible and \
			(get_viewport().gui_get_hovered_control() != null or (_card_info != null and _card_info.visible)):
		_board_info.hide_panel()


## Shows the board hover info (see InfoText) next to the mouse; an empty sheet hides it.
func show_board_info(sheet: InfoSheet) -> void:
	if sheet == null or sheet.is_empty or (_card_info != null and _card_info.visible) or get_viewport().gui_get_hovered_control() != null:
		_board_info.hide_panel()
		return
	_board_info.show_at_cursor(sheet)


## Hides the board hover info.
func hide_board_info() -> void:
	if _board_info != null:
		_board_info.hide_panel()


func _on_card_hover_changed(card: CardView, hovered: bool) -> void:
	if hovered and card != null and card.card != null:
		_card_info_owner = card
		_board_info.hide_panel()
		_card_info.show_beside(card, InfoText.card(card.card, card.ap_cost))
	elif card == _card_info_owner:
		_card_info_owner = null
		_card_info.hide_panel()


## Refreshes everything derivable from the state: VP coin stacks, AP crystals of both players,
## VP conversion slots, deck pile, turn plaque, End Turn button state and (optionally) the turn banner.
func update_state(state: GameState) -> void:
	if state == null:
		return
	var new_game: bool = state != _last_state
	var current: int = state.current_player_index
	var new_turn: bool = new_game or state.turn_number != _last_turn or current != _last_player
	if new_game:
		_turn_max_ap[0] = 0
		_turn_max_ap[1] = 0
		_last_banner_key = ""

	var target: int = state.config.points_target
	var human: PlayerState = state.players[_human_player]
	var ai: PlayerState = state.players[_ai_player]
	_player_coins.target = target
	_ai_coins.target = target
	_update_vp(_human_player, human.victory_points, target, not new_game)
	_update_vp(_ai_player, ai.victory_points, target, not new_game)

	if new_turn and current >= 0 and current < _turn_max_ap.size():
		_turn_max_ap[current] = state.current_player.action_points
	for p in range(_turn_max_ap.size()):
		_turn_max_ap[p] = maxi(maxi(_turn_max_ap[p], state.players[p].action_points), state.config.base_ap)
	_player_mana.min_slots = state.config.base_ap
	_ai_mana.min_slots = state.config.base_ap
	_player_mana.set_values(human.action_points, _turn_max_ap[_human_player], not new_game)
	_ai_mana.set_values(ai.action_points, _turn_max_ap[_ai_player], not new_game)

	var human_main: bool = current == _human_player and state.phase == GamePhase.MAIN and state.winner < 0
	var max_convert: int = state.config.max_vp_to_ap_per_turn
	_vp_convert.set_state(human.vp_converted_this_turn, max_convert,
		human_main and human.victory_points > 0 and human.vp_converted_this_turn < max_convert)

	_deck_pile.set_deck(human.deck.size(), state.config.draw_ap_cost)
	_enemy_hand.set_count(ai.hand.size() + ai.draft_offer.size())
	_end_turn_button.set_player_turn(current == _human_player)
	_end_turn_button.set_nothing_left(human_main and human.action_points <= 0)
	_turn_indicator.set_turn(state.turn_number, current, _phase_caption(state))

	_last_state = state
	_last_turn = state.turn_number
	_last_player = current

	if auto_turn_banner and new_turn and state.winner < 0 and state.phase != GamePhase.NOT_STARTED:
		show_turn_banner(current, state.turn_number)


## Sets the human player's AP crystals explicitly (current / maximum this turn).
func set_action_points(current: int, max_ap: int) -> void:
	_turn_max_ap[_human_player] = maxi(max_ap, current)
	_player_mana.set_values(current, _turn_max_ap[_human_player])


## Updates the VP-to-AP conversion slots (used this turn, maximum per turn, clickable).
func set_vp_conversion(used_this_turn: int, max_per_turn: int, can_convert: bool) -> void:
	_vp_convert.set_state(used_this_turn, max_per_turn, can_convert)


## Green "nothing left to do" glow on the End Turn button.
func set_end_turn_highlight(nothing_left: bool) -> void:
	_end_turn_button.set_nothing_left(nothing_left)


## Updates the deck pile count and draw cost explicitly.
func set_deck_count(count: int, draw_cost: int) -> void:
	_deck_pile.set_deck(count, draw_cost)


## Plays the big "YOUR TURN" / "ENEMY TURN" banner (~1.25 s). Awaitable (coroutine). Repeated calls for the
## same player and turn (e.g. the automatic one from update_state) wait for the running banner instead.
func show_turn_banner(player: int, turn_number: int) -> void:
	var key: String = "%d:%d" % [player, turn_number]
	if key == _last_banner_key:
		var waiting_for: int = _banner_serial
		while _banner_done_serial < waiting_for:
			await _banner_finished
		return
	_last_banner_key = key
	var human: bool = player == _human_player
	Sfx.play(SfxId.TURN_START if human else SfxId.TURN_ENEMY)
	_banner_serial += 1
	var serial: int = _banner_serial
	var title: String = ("%s'S TURN" % player_names[player].to_upper()) if not player_names.is_empty() else ("YOUR TURN" if human else "ENEMY TURN")
	await _turn_banner.play(title, "Turn %d" % turn_number, HudStyle.accent(player))
	_banner_done_serial = maxi(_banner_done_serial, serial)
	_banner_finished.emit()


## Shows the small resolution ticker, e.g. "Order 2/4: Swordsman attacks". index is 1-based;
## total <= 0 omits the count. Hides itself a few seconds after the last step.
## (The C# overload ShowResolutionStep(index, text) is show_resolution_step(index, 0, text) here.)
func show_resolution_step(index: int, total: int, text: String = "") -> void:
	var head: String = ("Order %d/%d" % [index, total]) if total > 0 else ("Step %d" % index)
	_ticker_label.text = head if text.is_empty() else "%s  -  %s" % [head, text]
	_ticker.visible = true
	_ticker.pivot_offset = _ticker.size * 0.5
	if _ticker_tween != null:
		_ticker_tween.kill()
	_ticker.modulate = Color.WHITE
	_ticker.scale = Vector2(1.08, 1.08)
	_ticker_tween = create_tween()
	_ticker_tween.tween_property(_ticker, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_ticker_tween.tween_interval(3.0)
	_ticker_tween.tween_property(_ticker, "modulate:a", 0.0, 0.4)
	_ticker_tween.tween_callback(func() -> void: _ticker.visible = false)


## Hides the resolution ticker.
func hide_resolution_step() -> void:
	if _ticker_tween != null:
		_ticker_tween.kill()
	_ticker_tween = create_tween()
	_ticker_tween.tween_property(_ticker, "modulate:a", 0.0, 0.25)
	_ticker_tween.tween_callback(func() -> void: _ticker.visible = false)


## Sets the parchment hint ribbon below the top bar (empty string hides it).
func set_hint(text: String) -> void:
	_hint_label.text = text
	_hint_ribbon.visible = text.length() > 0
	# Fit between the side panels: shrink the font a little, then wrap.
	var max_width: float = maxf(240.0, _root.size.x - 2.0 * HINT_SIDE_MARGIN)
	var font_size: int = HINT_FONT_SIZE
	while font_size > HINT_MIN_FONT_SIZE and HudStyle.text_width(text, font_size) > max_width:
		font_size -= 1
	_hint_label.add_theme_font_size_override("font_size", font_size)
	var wrap: bool = HudStyle.text_width(text, font_size) > max_width
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	_hint_label.custom_minimum_size = Vector2(max_width, 0.0) if wrap else Vector2.ZERO


## Shows a temporary toast ribbon that pops in and fades out after the given time.
func show_message(text: String, seconds: float = 2.0) -> void:
	if _message_tween != null:
		_message_tween.kill()
	_message_label.text = text
	_toast.visible = not text.is_empty()
	_toast.modulate = Color.WHITE
	_toast.pivot_offset = _toast.size * 0.5
	_toast.scale = Vector2(0.85, 0.85)

	_message_tween = create_tween()
	_message_tween.tween_property(_toast, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_message_tween.tween_interval(maxf(0.1, seconds))
	_message_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)
	_message_tween.tween_callback(func() -> void: _toast.visible = false)


## Sets the view toggle button caption, e.g. "2D" -> "View: 2D".
func set_view_mode_label(mode_name: String) -> void:
	_view_button.text = "View: %s" % mode_name


## Enables or disables the End Turn button.
func set_end_turn_enabled(enabled: bool) -> void:
	_end_turn_button.disabled = not enabled


## Enables or disables the Draw button (deck pile).
func set_draw_enabled(enabled: bool) -> void:
	_deck_pile.disabled = not enabled


## Enables or disables the Cancel button (it fades out while disabled).
func set_cancel_enabled(enabled: bool) -> void:
	_cancel_button.disabled = not enabled
	_cancel_button.modulate = Color(1.0, 1.0, 1.0, 1.0 if enabled else 0.35)


## Appends a line to the combat log.
func log(line: String) -> void:
	_log.add_line(line)


## Clears the combat log.
func clear_log() -> void:
	_log.clear()


## Victory/defeat screen for the given player index (0 = you, 1 = AI) with an optional custom subtitle
## (e.g. rewards) and button caption ("" = default; merges both C# overloads).
func show_win_screen(winner: int, subtitle_override: String = "", button_text: String = "") -> void:
	draft.hide_popup()
	var victory: bool = winner == _human_player
	Sfx.play(SfxId.VICTORY if victory else SfxId.DEFEAT)
	var subtitle: String = subtitle_override
	if subtitle.is_empty():
		if winner == _human_player:
			subtitle = "You reached the victory points target!"
		elif winner == _ai_player:
			subtitle = "The AI reached the victory points target."
		else:
			subtitle = "Game over"
	_restart_button.text = "Play again" if button_text.is_empty() else button_text
	_victory_banner.present(victory, "VICTORY" if victory else "DEFEAT", subtitle)
	_win_screen.visible = true
	if _win_tween != null:
		_win_tween.kill()
	_win_screen.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_win_tween = create_tween()
	_win_tween.tween_property(_win_screen, "modulate:a", 1.0, 0.35)
	_win_dim.color = Color(0.05, 0.03, 0.0, 0.7) if victory else Color(0.0, 0.0, 0.0, 0.78)


## Sets the name shown on the opponent's plaque (e.g. the town NPC).
func set_opponent_name(opponent_name: String) -> void:
	(get_node("Root/AiPanel/VBox/Header/NameLabel") as Label).text = "OPPONENT" if opponent_name.is_empty() else opponent_name.to_upper()


## Hides the win overlay (e.g. after a restart).
func hide_win_screen() -> void:
	if _win_tween != null:
		_win_tween.kill()
	_win_screen.visible = false


func _place_log_below(panel: Control) -> void:
	_log.position = Vector2(_log.position.x, panel.position.y + panel.size.y + 8.0)


func _update_vp(player: int, vp: int, target: int, animate: bool) -> void:
	var coins: VictoryCoinStack = _player_coins if player == _human_player else _ai_coins
	var label: Label = _player_vp_label if player == _human_player else _ai_vp_label
	coins.set_points(vp, animate and _last_vp[player] >= 0)
	label.text = "%d / %d" % [vp, target]
	if animate and _last_vp[player] >= 0 and vp != _last_vp[player]:
		label.pivot_offset = label.size * 0.5
		label.scale = Vector2(1.35, 1.35)
		var tween: Tween = label.create_tween()
		tween.tween_property(label, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_last_vp[player] = vp


func _phase_caption(state: GameState) -> String:
	var human: bool = state.current_player_index == _human_player
	var other: String = player_names[_ai_player] if not player_names.is_empty() else "AI"
	match state.phase:
		GamePhase.DRAFT:
			return "Choose a card" if human else "%s drafts" % other
		GamePhase.MAIN:
			return "Your move" if human else "%s is planning" % other
		GamePhase.RESOLVING:
			return "Ending turn"
		GamePhase.GAME_OVER:
			return "Game over"
		_:
			return ""


func _apply_scale() -> void:
	if _root == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var reference := Vector2(maxf(1.0, reference_resolution.x), maxf(1.0, reference_resolution.y))
	var s: float = maxf(min_scale, minf(viewport_size.x / reference.x, viewport_size.y / reference.y))
	ui_scale = s
	_root.position = Vector2.ZERO
	_root.scale = Vector2(s, s)
	_root.size = viewport_size / s


func _apply_styles() -> void:
	var top_bar: Panel = get_node("Root/TopBar") as Panel
	var bar: StyleBoxFlat = HudStyle.box(Color(HudStyle.WOOD_DARK, 0.92), HudStyle.GOLD_DARK, 0, 0, 10, 0.55)
	bar.border_width_bottom = 3
	bar.border_color = HudStyle.GOLD_DARK
	top_bar.add_theme_stylebox_override("panel", bar)

	_hint_ribbon.add_theme_stylebox_override("panel", HudStyle.parchment_panel(20, 5))
	_hint_label.add_theme_color_override("font_color", HudStyle.INK)
	_hint_label.add_theme_constant_override("outline_size", 0)
	_hint_label.add_theme_font_size_override("font_size", 15)

	var toast: StyleBoxFlat = HudStyle.parchment_panel(26, 8)
	toast.border_color = Color(0.6, 0.2, 0.08)
	toast.set_border_width_all(3)
	_toast.add_theme_stylebox_override("panel", toast)
	_message_label.add_theme_color_override("font_color", Color(0.45, 0.1, 0.04))
	_message_label.add_theme_constant_override("outline_size", 0)
	_message_label.add_theme_font_size_override("font_size", 18)

	var ticker: StyleBoxFlat = HudStyle.box(Color(0.1, 0.06, 0.03, 0.92), HudStyle.GOLD, 14, 2, 8)
	ticker.content_margin_left = 16
	ticker.content_margin_right = 16
	ticker.content_margin_top = 3
	ticker.content_margin_bottom = 3
	_ticker.add_theme_stylebox_override("panel", ticker)
	_ticker_label.add_theme_color_override("font_color", HudStyle.GOLD)
	_ticker_label.add_theme_font_size_override("font_size", 15)
	_ticker_label.add_theme_constant_override("outline_size", 4)

	_style_panels()
	_style_vp(_ai_vp_label)
	_style_vp(_player_vp_label)

	_view_button.add_theme_font_size_override("font_size", 14)
	_cancel_button.add_theme_font_size_override("font_size", 14)
	_restart_button.add_theme_font_size_override("font_size", 20)


## Hotseat: shows 'player' in the own window (hand, AP, points, VP conversion) and the other player in the opponent
## window, both in their own colours and with the given names (index 0 / 1).
func set_view_player(player: int, names: Array[String]) -> void:
	view_player = clampi(player, 0, 1)
	player_names = names
	_last_vp[0] = -1
	_last_vp[1] = -1
	_style_panels()
	_turn_indicator.set_labels("P1" if not names.is_empty() else "YOU", "P2" if not names.is_empty() else "AI")
	if not names.is_empty():
		(get_node("Root/PlayerPanel/VBox/Header/NameLabel") as Label).text = names[view_player].to_upper()
		(get_node("Root/AiPanel/VBox/Header/NameLabel") as Label).text = names[1 - view_player].to_upper()
	_last_state = null


## Own window in the view player's colour, opponent window in the other player's.
func _style_panels() -> void:
	var own: Color = HudStyle.accent(_human_player)
	var enemy: Color = HudStyle.accent(_ai_player)
	(get_node("Root/AiPanel") as PanelContainer).add_theme_stylebox_override("panel", HudStyle.wood_panel(enemy, 8))
	(get_node("Root/PlayerPanel") as PanelContainer).add_theme_stylebox_override("panel", HudStyle.wood_panel(own, 8))
	_style_header(get_node("Root/AiPanel/VBox/Header/NameLabel") as Label, enemy)
	_style_header(get_node("Root/PlayerPanel/VBox/Header/NameLabel") as Label, own)
	_player_coins.accent = own
	_ai_coins.accent = enemy
	_player_coins.queue_redraw()
	_ai_coins.queue_redraw()


static func _style_header(label: Label, accent: Color) -> void:
	label.add_theme_color_override("font_color", accent.lerp(Color.WHITE, 0.25))
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_constant_override("outline_size", 5)


static func _style_vp(label: Label) -> void:
	label.add_theme_color_override("font_color", HudStyle.GOLD)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_constant_override("outline_size", 5)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
