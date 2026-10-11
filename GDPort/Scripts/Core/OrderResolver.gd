class_name OrderResolver
extends RefCounted
## Resolves the queued orders of one player, plus the shared damage / heal / tile / status helpers.
##
## Rules (v3):
## - Orders resolve in ascending PieceOrder.order_index. Per piece: move first, then attack.
## - Move: the shortest path is recomputed at resolution (BoardState.find_path with the mover's owner):
##   friendlies can be passed, enemies and walls block, Frozen pieces cannot move. Unreachable -> MOVE_BLOCKED
##   (the piece stays). If the destination holds a friendly, that friendly is PUSHED one tile further in the
##   direction of the last step; a push may chain into further friendlies (up to GameConfig.max_push_chain
##   pieces). If the push is impossible (edge, wall, enemy, chain too long) a PUSH_BLOCKED event is emitted
##   and the mover stops on the last free tile of its path (MOVE_BLOCKED if there is none).
##   The attack is then re-checked for range from the actual position (ATTACK_CANCELLED if out of range).
## - Attack hits whatever piece stands on the target tile at that moment (empty tile = miss).
##   Enemy: takes the shot damage. Spell shields absorb first, then base shield, then HP.
##   Keywords on enemy hits: Burning (Lava on the tile), Frost (Frozen), Push (knock back 1 tile).
## - Friendly target: takes NO damage (Mending: heals it), but is triggered (CHAIN_TRIGGERED) and fires
##   once: sideways along its row (owner's LEFT first, then RIGHT; Conduit: then also forward and back)
##   up to its effective_range, hitting the NEAREST piece per direction (pieces and walls stop the shot).
##   Chain shot damage = effective_attack (+ echo_bonus_damage with Echo) (x overcharge_multiplier when
##   Overcharged; the status is consumed). Enemies take damage; friendlies chain further.
## - Pierce: every shot of a Pierce piece also hits the piece directly behind the target (same rules,
##   one extra tile in the shot direction, no further pierce).
## - Each piece fires at most once per resolution: a piece already fired (via its own order or a
##   chain) cannot be chain-triggered again, and a piece fired by a chain skips its own queued attack.
## - Pieces reaching 0 HP die immediately (removed from the board, orders skipped) and their card
##   returns to the owner's deck (Undying: an upgraded copy with +1 Attack / +1 Hp / Level + 1).


class Context:
	var state: GameState
	var events: Array[ResolutionEvent] = []
	## Set of piece ids that already fired (id -> true).
	var fired: Dictionary = {}

	var board: BoardState:
		get:
			return state.board

	var config: GameConfig:
		get:
			return state.config


static func _new_context(state: GameState) -> Context:
	var ctx := Context.new()
	ctx.state = state
	ctx.events = []
	return ctx


## Builds a ResolutionEvent with the common fields (C# object initializer equivalent).
static func _make_event(type: int, piece_id: int = -1, other_piece_id: int = -1,
		from: Vector2i = Vector2i.ZERO, to: Vector2i = Vector2i.ZERO) -> ResolutionEvent:
	var e := ResolutionEvent.new()
	e.type = type
	e.piece_id = piece_id
	e.other_piece_id = other_piece_id
	e.from = from
	e.to = to
	return e


## Resolves all orders of the given player's pieces and returns the chronological events.
static func resolve(state: GameState, player_index: int) -> Array[ResolutionEvent]:
	var ctx := _new_context(state)

	var ordered: Array[Piece] = []
	for p: Piece in state.get_pieces_of(player_index):
		if p.order != null:
			ordered.append(p)
	ordered.sort_custom(func(a: Piece, b: Piece) -> bool: return a.order.order_index < b.order.order_index)

	for piece: Piece in ordered:
		if not piece.is_alive or state.get_piece(piece.id) == null:
			continue
		var order: PieceOrder = piece.order

		if order.move_target != null and order.move_target != piece.position:
			_resolve_move(ctx, piece, order.move_target)

		if order.attack_target != null and not ctx.fired.has(piece.id):
			var target: Vector2i = order.attack_target
			if not state.board.is_in_attack_range(piece.position, target, piece.effective_range):
				ctx.events.append(_make_event(ResolutionEventType.ATTACK_CANCELLED, piece.id, -1, piece.position, target))
				continue
			ctx.fired[piece.id] = true
			_hit_tile(ctx, piece, target, false, false, piece.effective_attack, true)

	return ctx.events


## Resolves a single attack of 'attacker' on 'target' exactly like an order would (including chains and
## keywords) and MUTATES the given state. Intended for cloned states (previews / AI simulation).
static func simulate_attack(state: GameState, attacker: Piece, target: Vector2i) -> Array[ResolutionEvent]:
	var ctx := _new_context(state)
	if attacker == null or not attacker.is_alive:
		return ctx.events
	ctx.fired[attacker.id] = true
	_hit_tile(ctx, attacker, target, false, false, attacker.effective_attack, true)
	return ctx.events


## Resolves a single move with the v3 rules (pass-through, push) and MUTATES the state. For clones.
static func simulate_move(state: GameState, piece: Piece, target: Vector2i) -> Array[ResolutionEvent]:
	var ctx := _new_context(state)
	if piece != null and piece.is_alive and piece.position != target:
		_resolve_move(ctx, piece, target)
	return ctx.events


## Turn-start tile ticks for the given player's pieces: Lava damages (GameConfig.lava_damage, may kill),
## Healing heals (GameConfig.healing_tile_amount). Returns the events (TILE_DAMAGE + DAMAGED/DIED/
## RETURNED_TO_DECK, TILE_HEAL).
static func resolve_turn_start(state: GameState, player_index: int) -> Array[ResolutionEvent]:
	var events: Array[ResolutionEvent] = []
	for piece: Piece in state.get_pieces_of(player_index):
		if not piece.is_alive:
			continue
		var pos: Vector2i = piece.position
		var effect_type: int = state.board.get_tile_effect_type(pos)
		if effect_type == TileEffectType.LAVA:
			var dmg: int = maxi(0, state.config.lava_damage)
			var e := _make_event(ResolutionEventType.TILE_DAMAGE, piece.id, -1, pos, pos)
			e.amount = dmg
			e.tile_effect = TileEffectType.LAVA
			events.append(e)
			apply_damage(state, piece, dmg, -1, events)
		elif effect_type == TileEffectType.HEALING:
			var healed: int = mini(maxi(0, state.config.healing_tile_amount), piece.max_hp - piece.current_hp)
			if healed > 0:
				piece.current_hp += healed
				var e := _make_event(ResolutionEventType.TILE_HEAL, piece.id, -1, pos, pos)
				e.amount = healed
				e.remaining_hp = piece.current_hp
				e.tile_effect = TileEffectType.HEALING
				events.append(e)
	return events


## Applies damage to a piece: spell shields first, then base shield, then HP. If it dies, the piece is
## removed and its card returns to the owner's deck (Undying: upgraded copy). Appends DAMAGED (and
## DIED + RETURNED_TO_DECK) events to 'events' (may be null). Returns HP lost.
static func apply_damage(state: GameState, target: Piece, amount: int, source_piece_id: int, events = null) -> int:
	if amount <= 0 or not target.is_alive:
		return 0
	var remaining: int = amount
	var absorbed: int = 0
	for spell: ActiveSpell in target.active_spells:
		var take: int = mini(spell.remaining_shield, remaining)
		spell.remaining_shield -= take
		absorbed += take
		remaining -= take
	var base_take: int = mini(target.current_shield, remaining)
	target.current_shield -= base_take
	absorbed += base_take
	remaining -= base_take

	var hp_lost: int = mini(target.current_hp, remaining)
	target.current_hp -= hp_lost

	if events != null:
		var e := _make_event(ResolutionEventType.DAMAGED, target.id, source_piece_id, target.position, target.position)
		e.amount = amount
		e.shield_absorbed = absorbed
		e.hp_lost = hp_lost
		e.remaining_hp = target.current_hp
		e.remaining_shield = target.total_shield
		events.append(e)

	if target.current_hp <= 0:
		var pos: Vector2i = target.position
		state.remove_piece(target)
		if events != null:
			events.append(_make_event(ResolutionEventType.DIED, target.id, -1, pos, pos))
		_return_to_deck(state, target, events)
	return hp_lost


## Heals a piece up to its max_hp. Appends a HEALED event if anything was healed. Returns HP healed.
static func apply_heal(state: GameState, target: Piece, amount: int, source_piece_id: int, events = null) -> int:
	if amount <= 0 or target == null or not target.is_alive:
		return 0
	var healed: int = mini(amount, target.max_hp - target.current_hp)
	if healed <= 0:
		return 0
	target.current_hp += healed
	if events != null:
		var e := _make_event(ResolutionEventType.HEALED, target.id, source_piece_id, target.position, target.position)
		e.amount = healed
		e.remaining_hp = target.current_hp
		events.append(e)
	return healed


## Places a tile effect (no rule checks besides: on the board, and a Wall only on an empty tile).
## Replaces an existing effect on that tile. expiry_turn = turn_number + max(1, duration_turns).
static func apply_tile_effect(state: GameState, type: int, pos: Vector2i, duration_turns: int,
		creator_index: int, source_name: String, source_piece_id: int, events = null) -> bool:
	if type == TileEffectType.NONE or not state.board.is_inside(pos):
		return false
	if type == TileEffectType.WALL and state.board.is_occupied(pos):
		return false
	var duration: int = maxi(1, duration_turns)
	var expiry: int = state.turn_number + duration
	state.board.set_tile_effect(TileEffect.new(type, pos, creator_index, state.turn_number, expiry, source_name))
	if events != null:
		var e := _make_event(ResolutionEventType.TILE_EFFECT_APPLIED, -1, source_piece_id, pos, pos)
		e.player_index = creator_index
		e.tile_effect = type
		e.amount = duration
		e.expiry_turn = expiry
		e.card_name = source_name
		events.append(e)
	return true


## Adds (or refreshes) a status on a piece. expiry_turn = turn_number + max(1, duration_turns).
static func apply_status(state: GameState, target: Piece, type: int, duration_turns: int,
		source_name: String, source_piece_id: int, events = null) -> void:
	if type == StatusEffectType.NONE or target == null or not target.is_alive:
		return
	var expiry: int = state.turn_number + maxi(1, duration_turns)
	for i: int in range(target.status_effects.size() - 1, -1, -1):
		if target.status_effects[i].type == type:
			expiry = maxi(expiry, target.status_effects[i].expiry_turn)
			target.status_effects.remove_at(i)
	target.status_effects.append(StatusEffect.new(type, state.turn_number, expiry, source_name))
	if events != null:
		var e := _make_event(ResolutionEventType.STATUS_APPLIED, target.id, source_piece_id, target.position, target.position)
		e.status = type
		e.expiry_turn = expiry
		events.append(e)


## Main axis direction of a shot from 'from' to 'to' (unit vector; x wins ties). Used for Push and Pierce.
static func attack_direction(from: Vector2i, to: Vector2i) -> Vector2i:
	var dx: int = to.x - from.x
	var dy: int = to.y - from.y
	if dx == 0 and dy == 0:
		return Vector2i(0, 0)
	return Vector2i(signi(dx), 0) if absi(dx) >= absi(dy) else Vector2i(0, signi(dy))


# ------------------------------------------------------------------ internals

static func _return_to_deck(state: GameState, piece: Piece, events) -> void:
	var card: CardData = piece.source
	if card == null or piece.owner_index < 0 or piece.owner_index >= state.players.size():
		return
	var undying: bool = piece.has_keyword(Keyword.UNDYING)
	var returned: CardData = card.create_undying_upgrade() if undying else card
	state.players[piece.owner_index].deck.append(returned)
	if events != null:
		var e := _make_event(ResolutionEventType.RETURNED_TO_DECK, piece.id, -1, piece.position, piece.position)
		e.player_index = piece.owner_index
		e.card_name = returned.name
		e.amount = returned.level if undying else 0
		events.append(e)


static func _resolve_move(ctx: Context, piece: Piece, target: Vector2i) -> void:
	var from: Vector2i = piece.position
	var path_v: Variant = ctx.board.find_path(from, target, piece.effective_movement, piece.owner_index)
	if path_v == null or (path_v as Array).is_empty():
		ctx.events.append(_make_event(ResolutionEventType.MOVE_BLOCKED, piece.id, -1, from, target))
		return
	var path: Array[Vector2i] = path_v

	var dest: Vector2i = path[path.size() - 1]
	var occupant: Piece = ctx.board.get_piece_at(dest)
	if occupant == null:
		ctx.board.move_piece(piece, dest)
		ctx.events.append(_moved_event(piece, from, path))
		return

	var prev: Vector2i = path[path.size() - 2] if path.size() >= 2 else from
	var push_events: Array[ResolutionEvent] = []
	if _try_push_line(ctx, occupant, dest - prev, true, piece.owner_index, ctx.config.max_push_chain, piece.id, push_events):
		ctx.board.move_piece(piece, dest)
		ctx.events.append(_moved_event(piece, from, path))
		ctx.events.append_array(push_events)
		return

	ctx.events.append_array(push_events)
	var stop: int = -1
	for i: int in range(path.size() - 2, -1, -1):
		if not ctx.board.is_occupied(path[i]):
			stop = i
			break
	if stop < 0:
		ctx.events.append(_make_event(ResolutionEventType.MOVE_BLOCKED, piece.id, -1, from, target))
		return
	var walked: Array[Vector2i] = []
	for i: int in range(stop + 1):
		walked.append(path[i])
	ctx.board.move_piece(piece, walked[walked.size() - 1])
	ctx.events.append(_moved_event(piece, from, walked))


static func _moved_event(piece: Piece, from: Vector2i, path: Array[Vector2i]) -> ResolutionEvent:
	var e := _make_event(ResolutionEventType.MOVED, piece.id, -1, from, path[path.size() - 1])
	e.path = path.duplicate()
	return e


## Pushes 'first' one tile in 'dir'. With allow_chain, further pieces of chain_owner in the way are pushed
## too (line of at most max_chain pieces). PUSHED events (farthest piece first) or one PUSH_BLOCKED event
## are appended to 'events'. Returns true if the push happened.
static func _try_push_line(ctx: Context, first: Piece, dir: Vector2i, allow_chain: bool, chain_owner: int,
		max_chain: int, pusher_id: int, events: Array[ResolutionEvent]) -> bool:
	var line: Array[Piece] = [first]
	var next: Vector2i = first.position + dir
	var ok: bool = dir != Vector2i(0, 0)
	while ok:
		if not ctx.board.is_passable(next):
			ok = false
			break
		var p: Piece = ctx.board.get_piece_at(next)
		if p == null:
			break
		if allow_chain and p.owner_index == chain_owner and line.size() < maxi(1, max_chain):
			line.append(p)
			next += dir
			continue
		ok = false

	if not ok:
		events.append(_make_event(ResolutionEventType.PUSH_BLOCKED, first.id, pusher_id, first.position, first.position + dir))
		return false

	for i: int in range(line.size() - 1, -1, -1):
		var p: Piece = line[i]
		var from: Vector2i = p.position
		var to: Vector2i = from + dir
		ctx.board.move_piece(p, to)
		events.append(_make_event(ResolutionEventType.PUSHED, p.id, pusher_id, from, to))
	return true


static func _hit_tile(ctx: Context, attacker: Piece, tile: Vector2i, is_chain: bool, is_pierce: bool,
		damage: int, allow_pierce: bool) -> void:
	var target: Piece = ctx.board.get_piece_at(tile)
	var attacked := _make_event(ResolutionEventType.ATTACKED, attacker.id,
		target.id if target != null else -1, attacker.position, tile)
	attacked.is_chain = is_chain
	attacked.is_pierce = is_pierce
	ctx.events.append(attacked)

	var dir: Vector2i = attack_direction(attacker.position, tile)
	var behind: Piece = null
	var behind_tile: Vector2i = tile + dir
	if allow_pierce and attacker.has_keyword(Keyword.PIERCE) and ctx.board.is_passable(behind_tile):
		behind = ctx.board.get_piece_at(behind_tile)

	if target != null:
		if target.owner_index != attacker.owner_index:
			_hit_enemy(ctx, attacker, target, tile, dir, damage)
		else:
			if attacker.has_keyword(Keyword.MENDING):
				apply_heal(ctx.state, target, ctx.config.mending_heal, attacker.id, ctx.events)
			if not ctx.fired.has(target.id):
				ctx.fired[target.id] = true
				ctx.events.append(_make_event(ResolutionEventType.CHAIN_TRIGGERED, target.id, attacker.id,
					attacker.position, target.position))
				_fire_chain(ctx, target)

	if behind != null and behind.is_alive and attacker.is_alive and ctx.board.get_piece_at(behind_tile) == behind:
		_hit_tile(ctx, attacker, behind_tile, is_chain, true, damage, false)


static func _hit_enemy(ctx: Context, attacker: Piece, target: Piece, tile: Vector2i, dir: Vector2i, damage: int) -> void:
	apply_damage(ctx.state, target, damage, attacker.id, ctx.events)
	if attacker.has_keyword(Keyword.BURNING):
		apply_tile_effect(ctx.state, TileEffectType.LAVA, tile, ctx.config.burning_lava_duration,
			attacker.owner_index, attacker.source.name if attacker.source != null else "Burning", attacker.id, ctx.events)
	if not target.is_alive:
		return
	if attacker.has_keyword(Keyword.FROST):
		apply_status(ctx.state, target, StatusEffectType.FROZEN, ctx.config.frost_duration,
			attacker.source.name if attacker.source != null else "Frost", attacker.id, ctx.events)
	if attacker.has_keyword(Keyword.PUSH):
		_try_push_line(ctx, target, dir, false, -1, 1, attacker.id, ctx.events)


static func _fire_chain(ctx: Context, shooter: Piece) -> void:
	var damage: int = shooter.effective_attack
	if shooter.has_keyword(Keyword.ECHO):
		damage += ctx.config.echo_bonus_damage
	for i: int in range(shooter.status_effects.size() - 1, -1, -1):
		if shooter.status_effects[i].type != StatusEffectType.OVERCHARGED:
			continue
		shooter.status_effects.remove_at(i)
		damage *= maxi(1, ctx.config.overcharge_multiplier)
		var e := _make_event(ResolutionEventType.STATUS_EXPIRED, shooter.id, -1, shooter.position, shooter.position)
		e.status = StatusEffectType.OVERCHARGED
		e.is_chain = true
		ctx.events.append(e)
		break

	var left: int = BoardState.left_direction(shooter.owner_index)
	var forward: int = BoardState.forward_direction(shooter.owner_index)
	var dirs: Array[Vector2i] = [Vector2i(left, 0), Vector2i(-left, 0)]
	if shooter.has_keyword(Keyword.CONDUIT):
		dirs.append(Vector2i(0, forward))
		dirs.append(Vector2i(0, -forward))

	var range_: int = shooter.effective_range
	for dir: Vector2i in dirs:
		if not shooter.is_alive:
			return
		for d: int in range(1, range_ + 1):
			var tile := Vector2i(shooter.position.x + dir.x * d, shooter.position.y + dir.y * d)
			if not ctx.board.is_passable(tile):
				break
			if ctx.board.is_occupied(tile):
				_hit_tile(ctx, shooter, tile, true, false, damage, true)
				break
