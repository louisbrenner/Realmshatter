class_name BoardAnimator
extends Node
## Owns all PieceViews (id -> view), keeps them in sync with the GameState and plays
## resolution events as awaitable animations with VFX (sparks, projectiles, damage numbers,
## shatter, lightning, camera shake). Piece views and effects are parented to the BoardView.
## Also drives the board's tile effects (BoardView.tile_effects) and the status icons
## (status_markers) for the v3 rules.

## Helper that runs a coroutine in the background so it can be awaited later (C# "Task t = X(); ... await t;").
class _Job extends RefCounted:
	signal done
	var finished: bool = false

	func run(c: Callable) -> void:
		await c.call()
		finished = true
		done.emit()


@export var piece_scene: PackedScene
@export var board: BoardView
## Optional; if empty, the parent of the active Camera3D is used when it is a CameraRig.
@export var camera_rig: CameraRig
@export var player0_color: Color = Color(0.25, 0.5, 1.0)
@export var player1_color: Color = Color(1.0, 0.3, 0.25)
@export var chain_flash_color: Color = Color(1.0, 0.85, 0.2)
@export var damage_text_color: Color = Color(1.0, 0.35, 0.3)
@export var info_text_color: Color = Color(0.8, 0.8, 1.0)
## Pause between consecutive events, in seconds.
@export var event_pause: float = 0.08
## Global slow-down of the board animations: multiplies pauses, step/push tweens and piece move/attack times.
@export var animation_pace: float = 1.3
## Player whose hidden traps are shown on the board (the human).
@export var trap_viewer: int = 0

@export_group("VFX")
@export var impact_color: Color = Color(1.0, 0.62, 0.25)
@export var damage_splat_color: Color = Color(0.85, 0.1, 0.08)
@export var shield_color: Color = Color(1.0, 0.82, 0.35)
@export var buff_color: Color = Color(0.45, 1.0, 0.45)
@export var buff_secondary_color: Color = Color(1.0, 0.85, 0.35)
@export var debuff_color: Color = Color(0.72, 0.3, 1.0)
@export var debuff_secondary_color: Color = Color(0.35, 0.1, 0.6)
@export var score_color: Color = Color(1.0, 0.84, 0.3)
@export var dust_color: Color = Color(0.62, 0.52, 0.4)
@export var shake_strength: float = 0.1
## If true, sync_all shows summoning-sick pieces as exhausted (Piece.is_summoning_sick).
@export var auto_summoning_sickness: bool = true

@export_group("Rules v3")
## Seconds per tile when hopping along a move path.
@export var step_duration: float = 0.13
@export var step_hop_height: float = 0.2
## Seconds for a knockback / push slide.
@export var push_duration: float = 0.16
## If true, sync_all also syncs tile effects (BoardView.sync_tile_effects) and status markers.
@export var auto_sync_board_effects: bool = true
@export var heal_text_color: Color = Color(0.45, 1.0, 0.5)
@export var frost_color: Color = Color(0.55, 0.85, 1.0)
@export var charge_color: Color = Color(0.78, 0.62, 1.0)
@export var echo_color: Color = Color(1.0, 0.78, 0.4)
@export var pierce_color: Color = Color(0.85, 0.92, 1.0)
@export var soul_color: Color = Color(0.55, 1.0, 0.9)

## piece id -> PieceView (untyped values: entries may hold freed instances)
var _views: Dictionary = {}
var _keywords: Dictionary[int, int] = {}
var _owners: Dictionary[int, int] = {}
var _shields: Dictionary[int, int] = {}
var _ranges: Dictionary[int, int] = {}
var _death_positions: Dictionary[int, Vector3] = {}
var _motion_tweens: Dictionary[int, Tween] = {}
var _rig: CameraRig
var _status_markers: StatusMarkerLayer
var _play_state: GameState
## Vector2i or null
var _last_primary_tile: Variant = null

## All current views by piece id.
var views: Dictionary:
	get:
		return _views

## True while play_events is running.
var is_playing: bool = false

## Optional: Callable(player_index: int) -> Variant (Vector3 or null) giving the world position of a player's
## deck (cards of destroyed pieces fly there). Return null to use the default (beside the board on the owner's side).
var deck_world_provider: Callable = Callable()

## Floating status icons (Frozen / Overcharged) above the pieces; created on first use under the Board.
var status_markers: StatusMarkerLayer:
	get:
		if _status_markers == null or not is_instance_valid(_status_markers):
			_status_markers = StatusMarkerLayer.new()
			_status_markers.name = "StatusMarkers"
			_status_markers.view_resolver = func(id: int) -> Node3D: return get_view(id)
			if board != null:
				board.add_child(_status_markers)
			else:
				add_child(_status_markers)
		return _status_markers


## Owner color for a player index.
func get_owner_color(player_index: int) -> Color:
	return player0_color if player_index == 0 else player1_color


## True while all piece tokens are turned 180 degrees (hotseat: board seen from player 1's side).
var flipped: bool = false


## Turns every piece token (portrait, badges, buildings) 180 degrees so it reads upright for the player on the
## other side; use together with CameraRig.set_flipped and its tween_duration. New views spawn already turned.
func set_flipped(value: bool, duration: float) -> void:
	if value == flipped:
		return
	flipped = value
	var yaw: float = PI if value else 0.0
	for v: Variant in _views.values():
		if not is_instance_valid(v):
			continue
		var view := v as PieceView
		if duration <= 0.0:
			view.rotation = Vector3(0.0, yaw, 0.0)
			continue
		view.create_tween().tween_property(view, "rotation:y", yaw, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


## Creates (or returns the existing) view for a piece and places it on its tile.
func spawn_view(piece: Piece) -> PieceView:
	if piece == null:
		return null
	_cache_piece(piece)
	var existing: Variant = _views.get(piece.id)
	if existing != null and is_instance_valid(existing):
		(existing as PieceView).refresh(piece)
		return existing
	if piece_scene == null or board == null:
		push_error("BoardAnimator: PieceScene or Board is not assigned.")
		return null

	var view: PieceView = piece_scene.instantiate() as PieceView
	view.move_duration *= animation_pace
	view.attack_duration *= animation_pace
	board.add_child(view)
	view.setup(piece, get_owner_color(piece.owner_index))
	view.global_position = board.grid_to_world(piece.position)
	view.rotation = Vector3(0.0, PI if flipped else 0.0, 0.0)
	_views[piece.id] = view
	return view


## Removes and frees the view of a piece immediately (no animation).
func remove_view(id: int) -> void:
	if _views.has(id):
		var view: Variant = _views[id]
		_views.erase(id)
		if is_instance_valid(view):
			(view as Node).queue_free()
	if _status_markers != null:
		_status_markers.remove_piece(id)


## Returns the view of a piece, or null.
func get_view(id: int) -> PieceView:
	var view: Variant = _views.get(id)
	if view != null and is_instance_valid(view):
		return view as PieceView
	return null


## Removes all views (and status markers).
func clear_all() -> void:
	for view: Variant in _views.values():
		if is_instance_valid(view):
			(view as Node).queue_free()
	_views.clear()
	_motion_tweens.clear()
	_death_positions.clear()
	if _status_markers != null:
		_status_markers.clear_all()


## Deselects all views.
func clear_selection() -> void:
	for view: Variant in _views.values():
		if is_instance_valid(view):
			(view as PieceView).set_selected(false)


## Turns the green "can act" glow off on all views.
func clear_can_act() -> void:
	for view: Variant in _views.values():
		if is_instance_valid(view):
			(view as PieceView).set_can_act(false)


## Spawns views for pieces without one, removes views of pieces no longer in the state,
## refreshes stats/order indicators and snaps positions to the pieces' tiles. With auto_sync_board_effects
## (and not while play_events runs) it also syncs the tile effects and the status markers.
func sync_all(state: GameState) -> void:
	if state == null or board == null:
		return
	var alive: Dictionary = {}
	for piece: Piece in state.pieces:
		alive[piece.id] = true
		_cache_piece(piece)
		var view: PieceView = get_view(piece.id)
		if view == null:
			view = spawn_view(piece)
		else:
			_kill_motion(piece.id)
			view.refresh(piece)
			view.snap_to(board.grid_to_world(piece.position))
		if view != null and auto_summoning_sickness:
			view.set_exhausted(is_resting(piece, state))

	var stale: Array[int] = []
	for id: int in _views.keys():
		if not alive.has(id):
			stale.append(id)
	for id: int in stale:
		remove_view(id)

	if auto_sync_board_effects and not is_playing:
		sync_board_effects(state)


## Sleeping z's on a piece: summoning sick, busy building, or already acted this turn.
static func is_resting(piece: Piece, state: GameState) -> bool:
	return not piece.is_building and (piece.is_summoning_sick(state.turn_number) or piece.constructing_id >= 0 \
			or piece.has_acted(state.turn_number))


## Updates only the sleeping z's of every piece (cheap; e.g. right after a deploy or an action).
func sync_exhausted(state: GameState) -> void:
	if state == null or not auto_summoning_sickness:
		return
	for piece: Piece in state.pieces:
		var view: PieceView = get_view(piece.id)
		if view != null:
			view.set_exhausted(is_resting(piece, state))


## Syncs tile effects (with the state's turn number for the duration badges) and status markers.
func sync_board_effects(state: GameState) -> void:
	if state == null or board == null:
		return
	board.sync_tile_effects(state.board, state.turn_number, true)
	board.sync_terrain(state.board, state.config.rock_hp)
	board.sync_traps(state.board, trap_viewer)
	status_markers.sync(state, board)


## Animates resolution events in chronological order, then calls sync_all(state) (which also syncs tile
## effects and status markers) unless sync_after is false (views keep their animated positions, e.g. when
## several event lists of one state change are played back to back). Events referring to pieces without a
## view are skipped; unknown types are ignored. (Merges both C# PlayEvents overloads.)
func play_events(events: Array, state: GameState, sync_after: bool = true) -> void:
	var groups: Array = []
	if events != null:
		groups.append(events)
	await play_event_groups(groups, state, Callable(), sync_after)


## Plays several consecutive event lists (e.g. one per resolved order) as one sequence: tile effects and
## status icons are rewound once for all events, before_group(index) is invoked before each non-empty group
## (e.g. to update a "Order 2/4" ticker), and sync_all runs once at the end (if sync_after).
func play_event_groups(groups: Array, state: GameState, before_group: Callable = Callable(), sync_after: bool = true) -> void:
	is_playing = true
	clear_can_act()
	_play_state = state
	if state != null:
		for piece: Piece in state.pieces:
			_cache_piece(piece)
	if groups != null and board != null:
		var all: Array[ResolutionEvent] = []
		for g: Variant in groups:
			if g != null:
				for ev: ResolutionEvent in g:
					all.append(ev)
		board.tile_effects.prepare_for_events(all)
		status_markers.prepare_for_events(all)
		for gi in range(groups.size()):
			var events: Array = groups[gi] if groups[gi] != null else []
			if events.is_empty():
				continue
			# (C# wrapped the callback and each event in try/catch; GDScript has no exceptions.)
			if before_group.is_valid():
				before_group.call(gi)
			for i in range(events.size()):
				if events[i] == null:
					continue
				await _play_event(events, i)
				if event_pause > 0.0:
					await _delay(event_pause)
	is_playing = false
	if sync_after:
		sync_all(state)
	_play_state = null


## Spawns a short popping, rising text at a world position (fire and forget).
func spawn_floating_text(world: Vector3, text: String, color: Color) -> void:
	Vfx.popup_text(board, world, text, color, 60, 1.1)


## Shakes the camera rig (if one is found).
func shake(strength: float, duration: float) -> void:
	var rig: CameraRig = _resolve_rig()
	if rig != null:
		rig.shake(strength, duration)


## Summon: the token slams down from above with a dust shockwave and a light flash.
func play_summon(piece_id: int) -> void:
	var view: PieceView = get_view(piece_id)
	if view == null or board == null:
		return
	var rest: Vector3 = view.global_position
	var owner_c: Color = view.owner_color
	Vfx.glow_flash(board, rest + Vector3(0, 1.6, 0), owner_c.lightened(0.5), 1.4, 0.25)
	Sfx.play(SfxId.SWING, -6.0, 0.8)
	await view.play_drop(2.4, 0.22)
	if not is_instance_valid(view):
		return
	Sfx.play(SfxId.SUMMON)
	Vfx.shockwave(board, rest + Vector3(0, 0.03, 0), Color(1.0, 0.88, 0.65), 1.5, 0.45, 0.1)
	Vfx.dust_ring(board, rest, dust_color, 0.45, 18)
	Vfx.sparkle(board, rest + Vector3(0, 0.25, 0), owner_c.lightened(0.4), 12, 0.6, 0.5)
	Vfx.light_flash(board, rest + Vector3(0, 0.8, 0), owner_c.lightened(0.4), 4.0, 3.5, 0.35)
	shake(shake_strength * 0.8, 0.16)
	await view.play_squash(1.0)


## Spell cast on a piece: glowing motes spiral in (green/gold buff or purple debuff) and burst.
func play_spell_cast(target_piece_id: int, positive: bool) -> void:
	var view: PieceView = get_view(target_piece_id)
	if view == null or board == null:
		return
	var primary: Color = buff_color if positive else debuff_color
	var secondary: Color = buff_secondary_color if positive else debuff_secondary_color
	Sfx.play(SfxId.BUFF_CAST if positive else SfxId.DEBUFF_CAST)
	Vfx.spell_swirl(board, view.global_position, primary, secondary, 0.5)
	await _delay(0.5)
	if not is_instance_valid(view):
		return
	await view.play_flash(primary, 0.3)


## Scoring: coins and sparkles rise from the zone tiles with "+1" popups.
## points_at: optional Callable(Vector2i) -> int.
func play_score(tiles: Array, player: int, points_at: Callable = Callable()) -> void:
	if board == null or tiles == null:
		return
	var text: Color = player0_color.lerp(score_color, 0.6) if player == 0 else player1_color.lerp(score_color, 0.6)
	var count: int = 0
	for tile: Vector2i in tiles:
		var pos: Vector3 = board.grid_to_world(tile)
		Sfx.play(SfxId.COIN, 0.0, 1.0 + 0.04 * count)
		Vfx.coin_fountain(board, pos)
		Vfx.glow_flash(board, pos + Vector3(0, 0.3, 0), score_color, 1.4, 0.3)
		var points: int = int(points_at.call(tile)) if points_at.is_valid() else 1
		Vfx.popup_text(board, pos, "+%d" % points, text, 88 if points > 1 else 72, 1.0)
		if points > 1:
			Vfx.sparkle(board, pos + Vector3(0, 0.5, 0), score_color, 18, 0.9, 0.5)
		count += 1
		await _delay(0.06)
	if count > 0:
		await _delay(0.45)


## Small sparkle on a tile (e.g. for hover feedback); fire and forget.
func play_hover_sparkle(tile: Vector2i) -> void:
	if board != null:
		Vfx.sparkle(board, board.grid_to_world(tile) + Vector3(0, 0.2, 0), score_color, 4, 0.5, 0.3)


## World position of a player's deck (deck_world_provider or beside the board on the owner's side).
func get_deck_world(player_index: int) -> Vector3:
	if deck_world_provider.is_valid():
		var custom: Variant = deck_world_provider.call(player_index)
		if custom != null:
			return custom
	if board == null:
		return Vector3.ZERO
	var ts: float = board.tile_size
	var local := Vector3((board.width * 0.5 + 1.1) * ts, 0.6, (1.0 if player_index == 0 else -1.0) * (board.height * 0.5 + 0.2) * ts)
	return board.to_global(local) if board.is_inside_tree() else local


# ------------------------------------------------------------------ event dispatch

func _play_event(events: Array, index: int) -> void:
	var e: ResolutionEvent = events[index]
	var next: int = -1
	if index + 1 < events.size() and events[index + 1] != null:
		next = (events[index + 1] as ResolutionEvent).type
	var view: PieceView = get_view(e.piece_id)
	match e.type:
		ResolutionEventType.MOVED:
			if view != null:
				await _play_move(e, view)

		ResolutionEventType.MOVE_BLOCKED:
			if view != null:
				Sfx.play_delayed(SfxId.BLOCKED, 0.08)
				spawn_floating_text(view.global_position, "Blocked", info_text_color)
				await view.play_bump(board.grid_to_world(e.to))

		ResolutionEventType.ATTACKED:
			if view != null:
				if e.is_pierce:
					await _play_pierce(e, view)
				elif e.is_secondary:
					await _play_secondary_hit(e)
				else:
					_last_primary_tile = e.to
					await _play_attack(e, view)

		ResolutionEventType.ATTACK_CANCELLED:
			if view != null:
				Sfx.play(SfxId.SPELL_FADE)
				spawn_floating_text(view.global_position, "Fizzled", Color(0.7, 0.7, 0.7))

		ResolutionEventType.DAMAGED:
			_shields[e.piece_id] = e.remaining_shield
			if view != null:
				await _play_damage(e, view)

		ResolutionEventType.DIED:
			if _status_markers != null:
				_status_markers.remove_piece(e.piece_id)
			if view != null:
				_kill_motion(e.piece_id)
				_views.erase(e.piece_id)
				var p: Vector3 = view.global_position + Vector3(0, 0.15, 0)
				_death_positions[e.piece_id] = view.global_position
				Sfx.play(SfxId.DEATH)
				Vfx.shatter(board, p, view.body_color, view.tint_color)
				Vfx.light_flash(board, p + Vector3(0, 0.6, 0), Color(1.0, 0.75, 0.45), 5.0, 3.5, 0.4)
				shake(shake_strength * 1.3, 0.25)
				await view.play_death()
			else:
				_death_positions[e.piece_id] = board.grid_to_world(e.from)

		ResolutionEventType.SPELL_EXPIRED:
			if view != null:
				Sfx.play(SfxId.SPELL_FADE)
				Vfx.sparkle(board, view.global_position + Vector3(0, 0.3, 0), Color(0.75, 0.65, 1.0), 14, 0.7, 0.45)
				Vfx.popup_text(board, view.global_position, "%s fades" % e.spell_name, info_text_color, 44, 1.0)
				await _delay(0.15)

		ResolutionEventType.PUSHED:
			if view != null:
				await _play_push(e, view, next == ResolutionEventType.PUSHED)

		ResolutionEventType.PUSH_BLOCKED:
			if view != null:
				await _play_push_blocked(e, view)

		ResolutionEventType.HEALED:
			await _play_heal(e, view, false)

		ResolutionEventType.TILE_HEAL:
			await _play_heal(e, view, true)

		ResolutionEventType.RETURNED_TO_DECK:
			await _play_return_to_deck(e)

		ResolutionEventType.TILE_EFFECT_APPLIED:
			var sfx: int
			match e.tile_effect:
				TileEffectType.LAVA:
					sfx = SfxId.FIRE
				TileEffectType.WALL:
					sfx = SfxId.WALL_RISE
				TileEffectType.HEALING:
					sfx = SfxId.HEAL
				_:
					sfx = SfxId.BUFF_CAST
			Sfx.play(sfx, -3.0)
			var appear: _Job = _start_job(board.animate_tile_effect_applied.bind(e.to, e.tile_effect, e.expiry_turn))
			if next == ResolutionEventType.TILE_EFFECT_APPLIED:
				await _delay(0.06)
			else:
				await _await_job(appear)

		ResolutionEventType.TILE_EFFECT_EXPIRED:
			Sfx.play(SfxId.TILE_FADE)
			board.animate_tile_effect_expired(e.to)
			await _delay(0.04 if next == ResolutionEventType.TILE_EFFECT_EXPIRED else 0.25)

		ResolutionEventType.TILE_DAMAGE:
			if e.tile_effect == TileEffectType.STORM:
				var pos: Vector3 = board.grid_to_world(e.to)
				var storm := Color(0.8, 0.65, 1.0)
				Sfx.play(SfxId.ZAP)
				Vfx.shockwave(board, pos + Vector3(0, 0.05, 0), storm, 1.6, 0.35)
				Vfx.sparkle(board, pos + Vector3(0, 0.3, 0), storm, 14, 0.5, 0.5)
				Vfx.popup_text(board, pos, "Storm!", storm, 50, 1.2)
				shake(shake_strength * 0.6, 0.15)
				await _delay(0.2)
			else:
				var pos: Vector3 = board.grid_to_world(e.to)
				Sfx.play(SfxId.LAVA_BURN)
				RuleVfx.lava_eruption(board, pos)
				Vfx.popup_text(board, pos, "Lava!", RuleVfx.FIRE_COLOR, 50, 1.25)
				shake(shake_strength * 0.7, 0.15)
				await _delay(0.2)

		ResolutionEventType.STATUS_APPLIED:
			await _play_status_applied(e, view)

		ResolutionEventType.STATUS_EXPIRED:
			await _play_status_expired(e, view)

		ResolutionEventType.SPELL_CAST:
			if e.amount > 0:
				var at: Vector3 = board.grid_to_world(e.to) + Vector3(0, 0.75, 0)
				var arcane := Color(0.75, 0.55, 1.0)
				Vfx.sparkle(board, at, arcane, 18, 0.8, 0.5)
				Vfx.popup_text(board, at, "Empowered!", arcane, 50, 1.1)
			await _play_spell_cast_event(events, index)

		ResolutionEventType.DEATHRATTLE:
			await _play_deathrattle(e)

		ResolutionEventType.FIRST_HIT_TRIGGERED:
			await _play_first_hit(e, view)

		ResolutionEventType.BUILDING_STARTED:
			await _play_building_started(e)

		ResolutionEventType.BUILDING_COMPLETED:
			if view != null:
				Sfx.play(SfxId.WALL_RISE, -2.0, 1.2)
				view.set_under_construction(false)
				Vfx.sparkle(board, view.global_position + Vector3(0, 0.5, 0), score_color, 16, 0.8, 0.4)
				Vfx.popup_text(board, view.global_position + Vector3(0, 0.4, 0), "%s ready!" % e.spell_name, score_color, 50, 1.3)
				await _delay(0.4)

		ResolutionEventType.TRAP_SET:
			if e.player_index == trap_viewer:
				# Only the owner sees where it went.
				var at: Vector3 = board.grid_to_world(e.to)
				Sfx.play(SfxId.LAND, -4.0, 1.3)
				Vfx.dust_ring(board, at, dust_color, 0.3, 8)
				Vfx.popup_text(board, at + Vector3(0, 0.35, 0), e.card_name, info_text_color, 40, 0.8)
				await _delay(0.2)

		ResolutionEventType.TRAP_TRIGGERED:
			var at: Vector3 = board.grid_to_world(e.to)
			var c: Color = TrapInfo.get_color(_parse_enum(TrapType.NAMES, e.spell_name, TrapType.SPIKE))
			Sfx.play(SfxId.BLOCKED, 0.0, 0.8)
			Sfx.play(SfxId.MELEE_HIT, -2.0, 0.7)
			var jaws: MeshInstance3D = VfxAssets.create_icon(FxIconShape.TRAP, 0.7, c, Color(0.08, 0.06, 0.05, 0.9))
			board.add_child(jaws)
			jaws.global_position = at + Vector3(0, 0.55, 0)
			var pop: Tween = jaws.create_tween()
			pop.tween_property(jaws, "scale", Vector3.ONE * 1.3, 0.12).from(Vector3.ONE * 0.3)
			pop.tween_interval(0.45)
			pop.tween_property(jaws, "scale", Vector3.ONE * 0.01, 0.2)
			pop.tween_callback(jaws.queue_free)
			Vfx.shockwave(board, at + Vector3(0, 0.05, 0), c, 0.9, 0.4)
			Vfx.popup_text(board, at + Vector3(0, 0.95, 0), "%s!" % e.card_name, c, 54, 1.1)
			if camera_rig != null:
				camera_rig.shake(shake_strength * 0.6, 0.25)
			board.remove_trap_marker(e.to)
			await _delay(0.45)

		ResolutionEventType.TERRAIN_DAMAGED:
			var at: Vector3 = board.grid_to_world(e.to)
			var crumbled: bool = e.remaining_hp <= 0
			Sfx.play(SfxId.WALL_RISE, 0.0 if crumbled else -5.0, 0.6 if crumbled else 0.9)
			Vfx.dust_ring(board, at, dust_color, 0.55 if crumbled else 0.35, 26 if crumbled else 10)
			Vfx.popup_text(board, at + Vector3(0, 0.55, 0), "Crumbles!" if crumbled else "-%d" % e.amount,
				dust_color.lightened(0.35), 48, 1.0)
			board.show_rock_hp(e.to, e.remaining_hp)
			await _delay(0.3 if crumbled else 0.15)

		ResolutionEventType.AP_GAINED:
			var at: Vector3 = board.grid_to_world(e.from) + Vector3(0, 0.45, 0)
			var mana := Color(0.45, 0.75, 1.0)
			Sfx.play(SfxId.COIN)
			Vfx.sparkle(board, at, mana, 12, 0.7, 0.35)
			Vfx.popup_text(board, at, ("+%d AP next turn" % e.amount) if e.is_secondary else ("+%d AP" % e.amount), mana, 52, 1.2)
			await _delay(0.3)

		ResolutionEventType.AURA_PULSE:
			if view != null:
				var c: Color = ClanInfo.get_color(_parse_enum(Clan.NAMES, e.card_name, Clan.NONE))
				Sfx.play(SfxId.BUFF_CAST, -6.0, 0.8)
				Vfx.shockwave(board, view.global_position + Vector3(0, 0.05, 0), c, 2.6, 0.5, 0.1)
				Vfx.popup_text(board, view.global_position + Vector3(0, 0.3, 0), e.spell_name, c.lightened(0.3), 44, 1.1)
				await _delay(0.3)

		_:
			pass


# ------------------------------------------------------------------ movement

func _play_move(e: ResolutionEvent, view: PieceView) -> void:
	var points: Array[Vector3] = [view.global_position]
	if e.path != null and e.path.size() > 0:
		for p: Vector2i in e.path:
			points.append(board.grid_to_world(p))
	else:
		points.append(board.grid_to_world(e.to))
	var steps: int = points.size() - 1
	if steps <= 0:
		return
	_kill_motion(e.piece_id)
	# Boxed so the lambda can mutate it (GDScript lambdas capture locals by value).
	var last_step: Array[int] = [0]
	var tween: Tween = view.create_tween()
	_motion_tweens[e.piece_id] = tween
	var step_fn := func(t: float) -> void:
		if not is_instance_valid(view):
			return
		var f: float = t * steps
		var seg: int = mini(int(f), steps - 1)
		var u: float = f - seg
		var eased: float = u * u * (3.0 - 2.0 * u)
		if seg > last_step[0]:
			last_step[0] = seg
			Vfx.dust_ring(board, points[seg], dust_color, 0.25, 6)
			Sfx.play(SfxId.STEP)
		view.global_position = points[seg].lerp(points[seg + 1], eased) + Vector3.UP * step_hop_height * 4.0 * u * (1.0 - u)
	tween.tween_method(step_fn, 0.0, 1.0, step_duration * steps * animation_pace)
	await tween.finished
	_motion_tweens.erase(e.piece_id)
	if not is_instance_valid(view):
		return
	view.global_position = points[steps]
	Vfx.dust_ring(board, points[steps], dust_color, 0.35, 10)
	Sfx.play(SfxId.LAND)
	view.play_squash(0.6)


func _play_push(e: ResolutionEvent, view: PieceView, quick: bool) -> void:
	var from_w: Vector3 = board.grid_to_world(e.from)
	var to_w: Vector3 = board.grid_to_world(e.to)
	var dir: Vector3 = to_w - from_w
	dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	var impact: Vector3 = from_w - dir * 0.45 + Vector3(0, 0.3, 0)
	var knockback: bool = _has_keyword(e.other_piece_id, Keyword.PUSH) and _owner_of(e.other_piece_id) != _owner_of(e.piece_id)
	Sfx.play(SfxId.PUSH, 0.0 if knockback else -4.0)
	Vfx.impact_sparks(board, impact, impact_color if knockback else Color(1.0, 0.95, 0.8), 26 if knockback else 12, 0.9 if knockback else 0.5)
	Vfx.smoke_puff(board, impact - Vector3(0, 0.2, 0), dust_color, 5, 0.45)
	shake(shake_strength * (0.9 if knockback else 0.5), 0.12)
	if knockback:
		Vfx.popup_text(board, from_w, "Knockback!", impact_color, 48, 1.15)
	_kill_motion(e.piece_id)
	view.global_position = from_w
	var tween: Tween = view.create_tween()
	_motion_tweens[e.piece_id] = tween
	var push_fn := func(t: float) -> void:
		if is_instance_valid(view):
			view.global_position = from_w.lerp(to_w, t) + Vector3.UP * 0.08 * 4.0 * t * (1.0 - t)
	tween.tween_method(push_fn, 0.0, 1.0, push_duration * animation_pace).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	Vfx.dust_ring(board, from_w, dust_color, 0.3, 8)
	if quick:
		await _delay(0.05)
		return
	await tween.finished
	_motion_tweens.erase(e.piece_id)
	if not is_instance_valid(view):
		return
	Vfx.dust_ring(board, to_w, dust_color, 0.35, 10)
	view.play_squash(0.7)


func _play_push_blocked(e: ResolutionEvent, view: PieceView) -> void:
	var from_w: Vector3 = view.global_position
	var to_w: Vector3 = board.grid_to_world(e.to)
	var dir: Vector3 = to_w - from_w
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	var edge: Vector3 = from_w + dir * 0.5 + Vector3(0, 0.3, 0)
	var bump: _Job = _start_job(view.play_bump.bind(to_w))
	await _delay(0.07)
	Sfx.play(SfxId.BLOCKED)
	Vfx.impact_sparks(board, edge, Color(0.9, 0.9, 1.0), 14, 0.6)
	Vfx.shockwave(board, Vector3(edge.x, 0.05, edge.z), Color(1.0, 0.9, 0.7), 0.7, 0.25, 0.12)
	Vfx.popup_text(board, from_w, "Blocked!", info_text_color, 48, 1.1)
	shake(shake_strength * 0.6, 0.12)
	await _await_job(bump)


# ------------------------------------------------------------------ combat

func _play_attack(e: ResolutionEvent, view: PieceView) -> void:
	var from_w: Vector3 = view.global_position
	var target: Vector3 = board.grid_to_world(e.to)
	var has_target: bool = e.other_piece_id >= 0
	var enemy_target: bool = has_target and _owner_of(e.other_piece_id) != _owner_of(e.piece_id)
	var burning: bool = _has_keyword(e.piece_id, Keyword.BURNING)
	var frost: bool = _has_keyword(e.piece_id, Keyword.FROST)
	var ranged: bool = GridPos.manhattan_distance(e.from, e.to) > 1
	var color: Color = chain_flash_color if e.is_secondary else impact_color
	if burning:
		color = RuleVfx.FIRE_COLOR
	elif frost:
		color = frost_color
	if ranged:
		view.play_recoil(target)
		var bolt: Color
		if burning:
			bolt = RuleVfx.FIRE_COLOR
		elif frost:
			bolt = frost_color
		elif e.is_secondary:
			bolt = chain_flash_color
		else:
			bolt = view.owner_color.lerp(Color(1.0, 0.75, 0.35), 0.55)
		var duration: float = 0.12 + 0.045 * GridPos.manhattan_distance(e.from, e.to)
		Sfx.play(SfxId.ZAP if e.is_secondary else SfxId.SHOOT, -4.0 if e.is_secondary else 0.0)
		if burning:
			Sfx.play(SfxId.FIRE, -8.0, 1.3)
		await Vfx.projectile(board, from_w + Vector3(0, 0.45, 0), target + Vector3(0, 0.35, 0), bolt, duration)
		Sfx.play(SfxId.ARROW_HIT if has_target else SfxId.STEP, 0.0 if has_target else -2.0)
		Vfx.impact_sparks(board, target + Vector3(0, 0.35, 0), bolt, 36 if has_target else 16, 1.0 if has_target else 0.6)
		Vfx.light_flash(board, target + Vector3(0, 0.6, 0), bolt, 3.0, 2.5, 0.25)
		if has_target:
			shake(shake_strength * 0.7, 0.15)
		_play_keyword_impact(target, enemy_target, burning, frost)
		return

	var lunge: _Job = _start_job(view.play_attack.bind(target))
	Sfx.play(SfxId.SWING)
	await _delay(view.impact_time)
	Sfx.play(SfxId.MELEE_HIT if has_target else SfxId.LAND)
	var impact: Vector3 = from_w.lerp(target, 0.75) + Vector3(0, 0.3, 0)
	Vfx.impact_sparks(board, impact, color, 44 if has_target else 18, 1.1 if has_target else 0.6)
	if has_target:
		Vfx.light_flash(board, impact + Vector3(0, 0.4, 0), color, 3.5, 2.5, 0.22)
		shake(shake_strength, 0.18)
	else:
		Vfx.dust_ring(board, target, dust_color, 0.3, 8)
	_play_keyword_impact(target, enemy_target, burning, frost)
	await _await_job(lunge)


func _play_keyword_impact(target: Vector3, enemy_target: bool, burning: bool, frost: bool) -> void:
	if not enemy_target:
		return
	if burning:
		RuleVfx.fire_burst(board, target, 1.0)
	if frost:
		Vfx.sparkle(board, target + Vector3(0, 0.35, 0), frost_color, 14, 0.6, 0.4)


func _play_pierce(e: ResolutionEvent, view: PieceView) -> void:
	var from_w: Vector3 = view.global_position + Vector3(0, 0.4, 0)
	var to_w: Vector3 = board.grid_to_world(e.to) + Vector3(0, 0.35, 0)
	var dir: Vector3 = to_w - from_w
	var end: Vector3 = to_w + (dir.normalized() * 0.35 if dir.length_squared() > 0.0001 else Vector3.ZERO)
	view.play_recoil(to_w)
	Sfx.play(SfxId.SWING, 0.0, 1.4)
	RuleVfx.beam(board, from_w, end, pierce_color, 0.42, 0.28)
	Vfx.popup_text(board, board.grid_to_world(e.to), "Pierce!", pierce_color, 48, 1.3)
	await _delay(0.09)
	var has_target: bool = e.other_piece_id >= 0
	if has_target:
		Sfx.play(SfxId.MELEE_HIT, -2.0, 1.15)
	Vfx.impact_sparks(board, to_w, pierce_color, 34 if has_target else 14, 1.0 if has_target else 0.6)
	if has_target:
		shake(shake_strength * 0.8, 0.15)
	_play_keyword_impact(board.grid_to_world(e.to), has_target and _owner_of(e.other_piece_id) != _owner_of(e.piece_id),
		_has_keyword(e.piece_id, Keyword.BURNING), _has_keyword(e.piece_id, Keyword.FROST))
	await _delay(0.1)


func _play_damage(e: ResolutionEvent, view: PieceView) -> void:
	view.set_stats(e.remaining_hp, e.remaining_shield)
	var p: Vector3 = view.global_position
	if e.hp_lost > 0:
		Sfx.play(SfxId.DAMAGE)
	if e.shield_absorbed > 0:
		Sfx.play(SfxId.SHIELD_BREAK if e.remaining_shield <= 0 else SfxId.SHIELD_BLOCK)
	if e.shield_absorbed > 0:
		if e.remaining_shield <= 0:
			Vfx.shield_shatter(board, p + Vector3(0, 0.3, 0))
		else:
			Vfx.shield_block(board, p + Vector3(0, 0.3, 0))
	if e.hp_lost > 0:
		Vfx.damage_number(board, p, "-%d" % e.hp_lost, damage_splat_color)
	elif e.shield_absorbed > 0:
		Vfx.damage_number(board, p, "-%d" % e.shield_absorbed, shield_color.darkened(0.25))
	if e.hp_lost > 0:
		await view.play_hit()
	else:
		await view.play_flash(shield_color, 0.25)


## Secondary hit of an attack: the Echo strike on the same tile (brass rings) or an Arc zap jumping from the
## main target to a neighbouring piece (lightning, hits friend and foe alike).
func _play_secondary_hit(e: ResolutionEvent) -> void:
	var target: Vector3 = board.grid_to_world(e.to)
	var echo: bool = _has_keyword(e.piece_id, Keyword.ECHO) and _last_primary_tile != null and e.to == _last_primary_tile
	if echo:
		Sfx.play(SfxId.ECHO_RING)
		RuleVfx.echo_ring(board, target, echo_color)
		Vfx.popup_text(board, target, "Echo!", echo_color, 50, 1.3)
		await _delay(0.18)
		Sfx.play(SfxId.MELEE_HIT if e.other_piece_id >= 0 else SfxId.STEP, -5.0, 1.2)
		Vfx.impact_sparks(board, target + Vector3(0, 0.35, 0), echo_color, 20 if e.other_piece_id >= 0 else 8, 0.6)
		return
	var from_w: Vector3 = board.grid_to_world(_last_primary_tile) if _last_primary_tile != null else target
	Sfx.play(SfxId.ZAP)
	Vfx.lightning(board, from_w + Vector3(0, 0.35, 0), target + Vector3(0, 0.35, 0), chain_flash_color.lerp(Color.WHITE, 0.3), 0.4)
	RuleVfx.charge_crackle(board, target + Vector3(0, 0.35, 0), chain_flash_color, 4, 0.5, 0.3)
	Vfx.popup_text(board, target, "Arc!", chain_flash_color.lightened(0.3), 46, 1.3)
	await _delay(0.15)


# ------------------------------------------------------------------ heal / status / deck

func _play_heal(e: ResolutionEvent, view: PieceView, from_tile: bool) -> void:
	var pos: Vector3 = view.global_position if view != null else board.grid_to_world(e.to)
	if view != null:
		var shield: int = _shields.get(e.piece_id, 0)
		view.set_stats(e.remaining_hp, shield)
	Sfx.play(SfxId.HEAL, -4.0 if from_tile else 0.0)
	RuleVfx.heal_burst(board, pos)
	if from_tile:
		Vfx.shockwave(board, pos + Vector3(0, 0.04, 0), RuleVfx.HEAL_GOLD, 1.2, 0.5, 0.08)
	Vfx.popup_text(board, pos, "+%d" % e.amount, heal_text_color, 76, 1.0)
	if view != null:
		await view.play_flash(heal_text_color, 0.3)
	else:
		await _delay(0.25)


func _play_status_applied(e: ResolutionEvent, view: PieceView) -> void:
	var pos: Vector3 = view.global_position if view != null else board.grid_to_world(e.to)
	status_markers.set_status(e.piece_id, e.status, true, pos, true)
	match e.status:
		StatusEffectType.FROZEN:
			Sfx.play(SfxId.FREEZE)
			RuleVfx.ice_burst(board, pos)
			Vfx.popup_text(board, pos, "Frozen!", frost_color, 56, 1.2)
			if view != null:
				await view.play_flash(frost_color, 0.3)
		StatusEffectType.OVERCHARGED:
			Sfx.play(SfxId.CHARGE)
			RuleVfx.charge_crackle(board, pos + Vector3(0, 0.35, 0), charge_color, 6, 0.6, 0.4)
			Vfx.popup_text(board, pos, "Overcharged!", charge_color, 56, 1.2)
			if view != null:
				await view.play_flash(charge_color, 0.3)
		_:
			await _delay(0.1)


func _play_status_expired(e: ResolutionEvent, view: PieceView) -> void:
	var pos: Vector3 = view.global_position if view != null else board.grid_to_world(e.to)
	status_markers.set_status(e.piece_id, e.status, false, null, true)
	if e.status == StatusEffectType.OVERCHARGED and e.is_secondary:
		Sfx.play(SfxId.CHARGE_RELEASE)
		RuleVfx.charge_crackle(board, pos + Vector3(0, 0.35, 0), charge_color.lightened(0.3), 8, 0.95, 0.45)
		Vfx.glow_flash(board, pos + Vector3(0, 0.4, 0), Color.WHITE, 2.4, 0.25)
		Vfx.shockwave(board, pos + Vector3(0, 0.05, 0), charge_color, 1.8, 0.4, 0.1)
		Vfx.popup_text(board, pos, "Overcharge x2!", charge_color.lightened(0.35), 62, 1.55)
		shake(shake_strength * 0.9, 0.18)
		await _delay(0.25)
	elif e.status == StatusEffectType.FROZEN:
		Sfx.play(SfxId.THAW)
		RuleVfx.thaw(board, pos)
		await _delay(0.08)


func _play_return_to_deck(e: ResolutionEvent) -> void:
	var from_w: Vector3 = _death_positions[e.piece_id] if _death_positions.has(e.piece_id) else board.grid_to_world(e.from)
	var player: int = e.player_index if e.player_index >= 0 else _owner_of(e.piece_id)
	var deck: Vector3 = get_deck_world(maxi(0, player))
	if e.amount > 0:
		Sfx.play(SfxId.SOUL)
		Vfx.popup_text(board, from_w, "Returns stronger!", soul_color, 54, 1.25)
		Vfx.popup_text(board, from_w + Vector3(0, -0.32, 0), e.card_name, soul_color.lightened(0.4), 40, 1.25)
		Vfx.glow_flash(board, from_w + Vector3(0, 0.3, 0), soul_color, 1.8, 0.4)
		Vfx.sparkle(board, from_w + Vector3(0, 0.3, 0), soul_color, 16, 0.8, 0.4)
		RuleVfx.soul_wisp(board, from_w + Vector3(0, 0.3, 0), deck, 0.85)
		await _delay(0.5)
	else:
		Sfx.play(SfxId.CARD_DEAL)
		RuleVfx.card_to_deck(board, from_w + Vector3(0, 0.3, 0), deck, get_owner_color(maxi(0, player)), 0.6)
		await _delay(0.22)


func _play_spell_cast_event(events: Array, index: int) -> void:
	var e: ResolutionEvent = events[index]
	if e.piece_id >= 0:
		# Buff look on the caster's own pieces, debuff look on enemy pieces.
		var owner_idx: int = _owner_of(e.piece_id)
		var positive: bool = e.player_index < 0 or owner_idx < 0 or owner_idx == e.player_index
		var target: PieceView = get_view(e.piece_id)
		if not e.card_name.is_empty() and target != null:
			Vfx.popup_text(board, target.global_position + Vector3(0, 0.25, 0), e.card_name,
				buff_color if positive else debuff_color, 50, 1.2)
		await play_spell_cast(e.piece_id, positive)
		return
	var anchor: Vector3 = board.grid_to_world(e.to)
	var type: int = TileEffectType.NONE
	var tiles: Array[Vector3] = []
	for i in range(index + 1, events.size()):
		var n: ResolutionEvent = events[i]
		if n == null or n.type == ResolutionEventType.SPELL_CAST:
			break
		if n.type == ResolutionEventType.TILE_EFFECT_APPLIED:
			type = n.tile_effect
			tiles.append(board.grid_to_world(n.to))
	var name_color: Color
	match type:
		TileEffectType.LAVA:
			name_color = RuleVfx.FIRE_COLOR.lightened(0.2)
		TileEffectType.WALL:
			name_color = Color(0.9, 0.84, 0.72)
		TileEffectType.HEALING:
			name_color = heal_text_color
		_:
			name_color = Color(0.85, 0.65, 1.0)
	if not e.card_name.is_empty():
		Vfx.popup_text(board, anchor, e.card_name, name_color, 58, 1.5)
	match type:
		TileEffectType.LAVA:
			Sfx.play(SfxId.METEOR_FALL)
			await RuleVfx.meteor(board, anchor + Vector3(1.6, 7.5, -2.6), anchor + Vector3(0, 0.15, 0), 0.36)
			Sfx.play(SfxId.EXPLOSION)
			Vfx.impact_sparks(board, anchor + Vector3(0, 0.3, 0), RuleVfx.FIRE_COLOR, 60, 1.5)
			RuleVfx.fire_burst(board, anchor, 1.6)
			Vfx.shockwave(board, anchor + Vector3(0, 0.05, 0), RuleVfx.FIRE_COLOR, 3.2, 0.5, 0.1)
			Vfx.smoke_puff(board, anchor + Vector3(0, 0.3, 0), Color(0.2, 0.15, 0.12), 16, 1.2)
			Vfx.light_flash(board, anchor + Vector3(0, 1.0, 0), RuleVfx.FIRE_COLOR, 8.0, 6.0, 0.5)
			shake(shake_strength * 2.2, 0.32)
			await _delay(0.08)
		TileEffectType.WALL:
			RuleVfx.magic_circle(board, anchor, Color(0.85, 0.78, 0.6))
			for t: Vector3 in tiles:
				Vfx.dust_ring(board, t, dust_color, 0.45, 12)
			shake(shake_strength * 1.3, 0.35)
			await _delay(0.15)
		TileEffectType.HEALING:
			RuleVfx.magic_circle(board, anchor, RuleVfx.HEAL_GOLD)
			for t: Vector3 in tiles:
				Vfx.glow_flash(board, t + Vector3(0, 0.8, 0), RuleVfx.HEAL_GOLD, 1.6, 0.45)
				Vfx.sparkle(board, t + Vector3(0, 0.9, 0), RuleVfx.HEAL_COLOR, 10, 0.9, 0.3)
			Vfx.light_flash(board, anchor + Vector3(0, 1.2, 0), RuleVfx.HEAL_GOLD, 5.0, 5.0, 0.5)
			await _delay(0.25)
		_:
			Sfx.play(SfxId.BUFF_CAST)
			RuleVfx.magic_circle(board, anchor, Color(0.75, 0.45, 1.0))
			await _delay(0.2)


# ------------------------------------------------------------------ triggers

## Deathrattle: a ghostly flash on the death tile, the effect's name, then its own visual.
func _play_deathrattle(e: ResolutionEvent) -> void:
	var pos: Vector3 = board.grid_to_world(e.from)
	var color: Color
	match e.spell_name:
		"Explode":
			color = RuleVfx.FIRE_COLOR
		"Lava Pool":
			color = RuleVfx.FIRE_COLOR
		"Last Blessing":
			color = heal_text_color
		"Rubble":
			color = dust_color.lightened(0.3)
		"Last Word":
			color = soul_color
		_:
			color = Color(0.85, 0.9, 1.0)
	Vfx.popup_text(board, pos + Vector3(0, 0.35, 0), "Deathrattle: %s" % e.spell_name, color, 52, 1.5)
	Vfx.glow_flash(board, pos + Vector3(0, 0.4, 0), color, 2.2, 0.35)
	match e.spell_name:
		"Explode":
			Sfx.play(SfxId.EXPLOSION, -3.0, 1.2)
			RuleVfx.fire_burst(board, pos, 1.4)
			Vfx.shockwave(board, pos + Vector3(0, 0.05, 0), RuleVfx.FIRE_COLOR, 2.4, 0.4, 0.1)
			Vfx.smoke_puff(board, pos + Vector3(0, 0.3, 0), Color(0.2, 0.15, 0.12), 12, 1.0)
			shake(shake_strength * 1.8, 0.28)
		"Shockwave":
			Sfx.play(SfxId.PUSH, 0.0, 0.8)
			Vfx.shockwave(board, pos + Vector3(0, 0.05, 0), Color(1.0, 0.9, 0.7), 2.6, 0.4, 0.12)
			Vfx.dust_ring(board, pos, dust_color, 0.8, 20)
			shake(shake_strength * 1.2, 0.2)
		"Last Blessing":
			Sfx.play(SfxId.HEAL)
			Vfx.shockwave(board, pos + Vector3(0, 0.05, 0), RuleVfx.HEAL_GOLD, 3.0, 0.6, 0.08)
		"Last Word":
			Sfx.play(SfxId.CARD_DEAL)
			Vfx.sparkle(board, pos + Vector3(0, 0.4, 0), soul_color, 16, 0.8, 0.4)
		_:
			Sfx.play(SfxId.SPELL_FADE, 4.0)
	await _delay(0.35)


## A building appears next to its builder: the token drops in as a scaffold with hammering.
func _play_building_started(e: ResolutionEvent) -> void:
	var building: Piece = _play_state.get_piece(e.other_piece_id) if _play_state != null else null
	if building == null:
		return
	var view: PieceView = spawn_view(building)
	if view == null:
		return
	Sfx.play(SfxId.SUMMON, -4.0, 1.1)
	Sfx.play_delayed(SfxId.BLOCKED, 0.25, -6.0, 1.3)
	Sfx.play_delayed(SfxId.BLOCKED, 0.45, -6.0, 1.4)
	Vfx.dust_ring(board, view.global_position, dust_color, 0.6, 18)
	var turns: int = (building.complete_turn - building.summoned_turn) / 2 if building.complete_turn > building.summoned_turn else 1
	Vfx.popup_text(board, view.global_position + Vector3(0, 0.4, 0), "Building %s (%d turns)" % [e.spell_name, turns],
		Color(1.0, 0.85, 0.55), 46, 1.4)
	await view.play_squash(0.8)


## First-hit effect: a burst on the piece and the effect's name; stat changes update the token.
func _play_first_hit(e: ResolutionEvent, view: PieceView) -> void:
	var pos: Vector3 = view.global_position if view != null else board.grid_to_world(e.to)
	var color: Color
	match e.spell_name:
		"Thorns":
			color = Color(0.55, 0.9, 0.35)
		"Harden":
			color = shield_color
		"Enrage":
			color = Color(1.0, 0.35, 0.2)
		_:
			color = Color(0.9, 0.85, 0.7)
	var text: String
	match e.spell_name:
		"Harden":
			text = "Harden +%d" % e.amount
		"Enrage":
			text = "Enrage +%d Atk" % e.amount
		_:
			text = "%s!" % e.spell_name
	Vfx.popup_text(board, pos + Vector3(0, 0.3, 0), text, color, 50, 1.3)
	Vfx.sparkle(board, pos + Vector3(0, 0.35, 0), color, 14, 0.7, 0.4)
	if e.spell_name == "Shockwave":
		Sfx.play(SfxId.PUSH, 0.0, 0.9)
		Vfx.shockwave(board, pos + Vector3(0, 0.05, 0), Color(1.0, 0.9, 0.7), 2.2, 0.35, 0.12)
	elif e.spell_name == "Harden":
		Sfx.play(SfxId.SHIELD_BLOCK)
	else:
		Sfx.play(SfxId.BUFF_CAST, -2.0)
	if view != null:
		view.set_stats(e.remaining_hp, e.remaining_shield)
		var live: Piece = _play_state.get_piece(e.piece_id) if _play_state != null else null
		if live != null:
			view.set_attack(live.effective_attack)
		await view.play_flash(color, 0.25)
	else:
		await _delay(0.2)


# ------------------------------------------------------------------ helpers

func _cache_piece(piece: Piece) -> void:
	_keywords[piece.id] = piece.keywords
	_owners[piece.id] = piece.owner_index
	_shields[piece.id] = piece.total_shield
	_ranges[piece.id] = piece.effective_range


func _has_keyword(piece_id: int, keyword: int) -> bool:
	return _keywords.has(piece_id) and keyword != Keyword.NONE and (_keywords[piece_id] & keyword) == keyword


func _owner_of(piece_id: int) -> int:
	return _owners[piece_id] if _owners.has(piece_id) else -1


func _kill_motion(piece_id: int) -> void:
	if _motion_tweens.has(piece_id):
		var t: Tween = _motion_tweens[piece_id]
		if t != null and t.is_valid():
			t.kill()
		_motion_tweens.erase(piece_id)


func _resolve_rig() -> CameraRig:
	if camera_rig != null and is_instance_valid(camera_rig):
		return camera_rig
	if _rig != null and is_instance_valid(_rig):
		return _rig
	_rig = null
	var vp: Viewport = get_viewport()
	if vp != null:
		var cam: Camera3D = vp.get_camera_3d()
		if cam != null:
			_rig = cam.get_parent() as CameraRig
	return _rig


func _delay(seconds: float) -> void:
	if seconds <= 0.0 or not is_inside_tree():
		return
	await get_tree().create_timer(seconds * animation_pace).timeout


## Port helper for C# Enum.TryParse: value whose NAMES entry equals text, else fallback.
static func _parse_enum(names: Dictionary, text: String, fallback: int) -> int:
	for key: Variant in names:
		if names[key] == text:
			return int(key)
	return fallback


## Port helper: starts a coroutine without awaiting it so it can be awaited later via _await_job.
func _start_job(c: Callable) -> _Job:
	var job := _Job.new()
	job.run(c)
	return job


func _await_job(job: _Job) -> void:
	if not job.finished:
		await job.done
