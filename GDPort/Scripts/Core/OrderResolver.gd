class_name OrderResolver
extends RefCounted
## Resolves piece actions immediately (there is no end-of-turn resolution), plus the shared damage / heal /
## tile / status helpers.
##
## Rules (v4):
## - A piece acts once per turn: it moves, then attacks; both resolve the moment the attack is declared.
## - Move: shortest path (BoardState.find_path with the mover's owner): friendlies can be passed, enemies and walls
##   block, Frozen pieces cannot move. If the destination holds a friendly, that friendly is PUSHED one tile further
##   in the direction of the last step (a line of up to GameConfig.max_push_chain friendlies can be pushed). If the
##   push is impossible a PushBlocked event is emitted and the mover stops on the last free tile of its path.
##   The attack is then re-checked for range from the actual position (AttackCancelled if out of range).
## - Attack hits whatever piece stands on the target tile (empty tile = miss). Friend or foe, the target takes the
##   damage (spell shields absorb first, then base shield, then HP): friendly fire is real. Only Mending turns a
##   hit on a friendly into a heal (GameConfig.mending_heal) instead of damage.
##   On-hit keywords apply to every damaged piece: Burning (Lava on the tile), Frost (Frozen), Push (knock back).
## - Overcharged: the attack deals GameConfig.overcharge_multiplier x damage; the status is consumed.
## - Pierce: also hits the piece directly behind the target (same damage, no further pierce).
## - Arc: also zaps every piece orthogonally adjacent to the target tile (except the attacker) for
##   GameConfig.arc_damage - friend or foe.
## - Echo: after the attack it strikes the same tile a second time for GameConfig.echo_bonus_damage.
## - Pieces reaching 0 HP die immediately; their card is gone, except Undying cards, which return to the owner's
##   deck as an upgraded copy.
##
## Port note: 'events' parameters that C# accepts as null (events?.Add) are untyped here: pass an
## Array[ResolutionEvent] or null.


class Context:
	var state: GameState
	var events: Array[ResolutionEvent] = []
	var board: BoardState:
		get:
			return state.board
	var config: GameConfig:
		get:
			return state.config


## Builds an event with the common fields (C# object initializer helper).
static func _ev(type: int, piece_id: int, from: Vector2i, to: Vector2i) -> ResolutionEvent:
	var e := ResolutionEvent.new()
	e.type = type
	e.piece_id = piece_id
	e.from = from
	e.to = to
	return e


## Appends to a nullable events list (C# events?.Add).
static func _add(events: Variant, e: ResolutionEvent) -> void:
	if events != null:
		(events as Array).append(e)


static func _new_context(state: GameState) -> Context:
	var ctx := Context.new()
	ctx.state = state
	return ctx


## Resolves one piece action right away: optional move (move != null and != position), then optional attack on
## tile 'attack' (Vector2i or null). Mutates the state and returns the chronological events. No rule / AP checks.
static func resolve_action(state: GameState, piece: Piece, move: Variant, attack: Variant) -> Array[ResolutionEvent]:
	var ctx := _new_context(state)
	if piece == null or not piece.is_alive or state.get_piece(piece.id) == null:
		return ctx.events
	if move != null and (move as Vector2i) != piece.position:
		_resolve_move(ctx, piece, move as Vector2i)
		_trigger_turrets(ctx, piece)
	if attack != null and piece.is_alive and state.get_piece(piece.id) != null:
		var target: Vector2i = attack as Vector2i
		if not state.board.is_in_attack_range(piece.position, target, piece.effective_range):
			ctx.events.append(_ev(ResolutionEventType.ATTACK_CANCELLED, piece.id, piece.position, target))
		else:
			_strike(ctx, piece, target)
	return ctx.events


## Resolves a single attack of 'attacker' on 'target' exactly like an action would (keywords, friendly fire)
## and MUTATES the given state. Intended for cloned states (previews / AI simulation).
static func simulate_attack(state: GameState, attacker: Piece, target: Vector2i) -> Array[ResolutionEvent]:
	var ctx := _new_context(state)
	if attacker != null and attacker.is_alive:
		_strike(ctx, attacker, target)
	return ctx.events


## Resolves a single move (pass-through, push) and MUTATES the state. For clones.
static func simulate_move(state: GameState, piece: Piece, target: Vector2i) -> Array[ResolutionEvent]:
	var ctx := _new_context(state)
	if piece != null and piece.is_alive and piece.position != target:
		_resolve_move(ctx, piece, target)
	return ctx.events


## Turn-start tile ticks for the given player's pieces: Lava damages (GameConfig.lava_damage, may kill),
## Healing heals (GameConfig.healing_tile_amount). Returns the events (TileDamage + Damaged/Died/
## ReturnedToDeck, TileHeal).
static func resolve_turn_start(state: GameState, player_index: int) -> Array[ResolutionEvent]:
	var events: Array[ResolutionEvent] = []
	for piece: Piece in state.get_pieces_of(player_index):
		if not piece.is_alive:
			continue
		var pos: Vector2i = piece.position
		match state.board.get_tile_effect_type(pos):
			TileEffectType.LAVA:
				var dmg: int = maxi(0, state.config.lava_damage)
				var e := _ev(ResolutionEventType.TILE_DAMAGE, piece.id, pos, pos)
				e.amount = dmg
				e.tile_effect = TileEffectType.LAVA
				events.append(e)
				apply_damage(state, piece, dmg, -1, events)
			TileEffectType.STORM:
				var e := _ev(ResolutionEventType.TILE_DAMAGE, piece.id, pos, pos)
				e.amount = 1
				e.tile_effect = TileEffectType.STORM
				events.append(e)
				apply_damage(state, piece, 1, -1, events)
				for n: Vector2i in GridPos.neighbors(pos):
					var near: Piece = state.board.get_piece_at(n)
					if near != null and near.is_alive:
						apply_damage(state, near, 1, -1, events)
			TileEffectType.HEALING:
				var healed: int = mini(maxi(0, state.config.healing_tile_amount), piece.max_hp - piece.current_hp)
				if healed > 0:
					piece.current_hp += healed
					var e := _ev(ResolutionEventType.TILE_HEAL, piece.id, pos, pos)
					e.amount = healed
					e.remaining_hp = piece.current_hp
					e.tile_effect = TileEffectType.HEALING
					events.append(e)
	return events


## Applies damage to a piece: spell shields first, then base shield, then HP. If it dies, the piece is
## removed (Undying: an upgraded copy returns to the owner's deck). Appends Damaged (and
## Died + ReturnedToDeck) events. Returns HP lost. 'events' may be null.
static func apply_damage(state: GameState, target: Piece, amount: int, source_piece_id: int, events: Variant) -> int:
	if amount <= 0 or not target.is_alive:
		return 0
	if target.source != null and target.source.legend == LegendEffect.UNBREAKABLE:
		amount = 1 # Unbreakable: never more than 1 damage per hit
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

	var dmg_event := _ev(ResolutionEventType.DAMAGED, target.id, target.position, target.position)
	dmg_event.other_piece_id = source_piece_id
	dmg_event.amount = amount
	dmg_event.shield_absorbed = absorbed
	dmg_event.hp_lost = hp_lost
	dmg_event.remaining_hp = target.current_hp
	dmg_event.remaining_shield = target.total_shield
	_add(events, dmg_event)

	if target.current_hp <= 0:
		var pos: Vector2i = target.position
		state.remove_piece(target)
		_add(events, _ev(ResolutionEventType.DIED, target.id, pos, pos))
		var killer: Piece = state.get_piece(source_piece_id) if source_piece_id >= 0 else null
		if killer != null and killer.owner_index != target.owner_index and killer.has_keyword(Keyword.PLUNDER):
			grant_ap(state, killer.owner_index, 1, killer.id, killer.source.name if killer.source != null else "Plunder", pos, events)
		var sink: Array[ResolutionEvent] = []
		if events != null:
			sink = events
		if target.is_building:
			_on_building_destroyed(state, target, pos, sink)
		else:
			_return_to_deck(state, target, events)
			_trigger_deathrattle(state, target, pos, sink)
			if target.constructing_id >= 0:
				# The builder died: its unfinished buildings (a Barricade build places two) collapse.
				target.constructing_id = -1
				for site: Piece in state.pieces.duplicate():
					if site.is_building and site.builder_id == target.id and site.under_construction and state.get_piece(site.id) != null:
						apply_damage(state, site, site.current_hp + site.total_shield + 100, -1, events)
	elif not target.was_hit:
		target.was_hit = true
		var sink: Array[ResolutionEvent] = []
		if events != null:
			sink = events
		_trigger_first_hit(state, target, source_piece_id, sink)
	return hp_lost


## A destroyed building frees its builder and leaves impassable rubble for GameConfig.rubble_duration turns.
static func _on_building_destroyed(state: GameState, building: Piece, pos: Vector2i, events: Array[ResolutionEvent]) -> void:
	var builder: Piece = state.get_piece(building.builder_id) if building.builder_id >= 0 else null
	if builder != null and builder.constructing_id == building.id:
		# Still pinned while another of its buildings (the second Barricade) is unfinished.
		var other: Piece = null
		for p: Piece in state.pieces.duplicate():
			if p.is_building and p.builder_id == builder.id and p.under_construction and p.id != building.id:
				other = p
				break
		builder.constructing_id = other.id if other != null else -1
	apply_tile_effect(state, TileEffectType.RUBBLE, pos, maxi(1, state.config.rubble_duration), -1,
		"%s ruins" % (building.source.name if building.source != null else "Building"), building.id, events)


## Finished enemy turrets that have not fired this turn shoot at a piece that just moved into their range.
static func _trigger_turrets(ctx: Context, mover: Piece) -> void:
	for turret: Piece in ctx.state.pieces.duplicate():
		if not mover.is_alive or ctx.state.get_piece(mover.id) == null:
			return
		if turret.building != BuildingType.TURRET or turret.under_construction or turret.owner_index == mover.owner_index \
				or turret.reacted_turn == ctx.state.turn_number or turret.effective_attack <= 0 \
				or not ctx.board.is_in_attack_range(turret.position, mover.position, turret.effective_range):
			continue
		turret.reacted_turn = ctx.state.turn_number
		_hit_tile(ctx, turret, mover.position, turret.effective_attack, false, false, false)


## Turn start of a player's buildings: unfinished buildings whose time has come are finished (builder freed),
## finished Shrines heal the owner's pieces on the 8 surrounding tiles.
static func resolve_buildings_turn_start(state: GameState, player_index: int) -> Array[ResolutionEvent]:
	var events: Array[ResolutionEvent] = []
	for b: Piece in state.get_pieces_of(player_index):
		if not b.is_building:
			continue
		if b.under_construction and state.turn_number >= b.complete_turn:
			b.under_construction = false
			var builder: Piece = state.get_piece(b.builder_id) if b.builder_id >= 0 else null
			if builder != null and builder.constructing_id == b.id:
				builder.constructing_id = -1
			var e := _ev(ResolutionEventType.BUILDING_COMPLETED, b.id, b.position, b.position)
			e.player_index = player_index
			e.spell_name = BuildingInfo.display_name(b.building, b.source.clan)
			events.append(e)
		elif not b.under_construction and b.building == BuildingType.SHRINE:
			for ally: Piece in _around(state, b.position):
				if ally.owner_index == player_index and not ally.is_building:
					apply_heal(state, ally, 1, b.id, events)
		# Finished clan buildings pulse their clan's aura.
		if not b.under_construction and b.source.clan != Clan.NONE and b.is_alive and state.get_piece(b.id) != null:
			_pulse_aura(state, b, b.source.clan, player_index, events)
	return events


## Turn start of a player's Legendary units: Wildfire (enemies on Lava take damage), Dawnlight (full heal nearby),
## Glacial Grip (freeze enemies nearby) and Chain Lightning (strike the nearest enemies). Each fires an AuraPulse
## event with the effect's name first. Unbreakable works in apply_damage instead.
static func resolve_legends(state: GameState, player_index: int) -> Array[ResolutionEvent]:
	var events: Array[ResolutionEvent] = []
	for source: Piece in state.get_pieces_of(player_index).duplicate():
		var legend: int = source.source.legend if source.source != null else LegendEffect.NONE
		if legend == LegendEffect.NONE or legend == LegendEffect.UNBREAKABLE or source.is_building or not source.is_alive \
				or state.get_piece(source.id) == null:
			continue
		var pulse := _ev(ResolutionEventType.AURA_PULSE, source.id, source.position, source.position)
		pulse.player_index = player_index
		pulse.spell_name = LegendInfo.display_name(legend)
		pulse.card_name = Clan.name_of(source.source.clan if source.source != null else Clan.NONE)
		events.append(pulse)
		var enemies: Array[Piece] = []
		for p: Piece in state.pieces:
			if p.owner_index != player_index and p.is_alive:
				enemies.append(p)
		match legend:
			LegendEffect.WILDFIRE:
				for e: Piece in enemies:
					if state.board.get_tile_effect_type(e.position) == TileEffectType.LAVA:
						apply_damage(state, e, LegendInfo.WILDFIRE_DAMAGE, source.id, events)
			LegendEffect.DAWNLIGHT:
				for ally: Piece in state.get_pieces_of(player_index).duplicate():
					if not ally.is_building and ally.current_hp < ally.max_hp \
							and GridPos.manhattan_distance(ally.position, source.position) <= LegendInfo.DAWNLIGHT_RADIUS:
						apply_heal(state, ally, ally.max_hp - ally.current_hp, source.id, events)
			LegendEffect.GLACIAL_GRIP:
				for e: Piece in enemies:
					if not e.is_building and GridPos.manhattan_distance(e.position, source.position) <= LegendInfo.GLACIAL_GRIP_RADIUS:
						apply_status(state, e, StatusEffectType.FROZEN, state.config.frost_duration, LegendInfo.display_name(legend), source.id, events)
			LegendEffect.CHAIN_LIGHTNING:
				var center: Vector2i = source.position
				var in_reach: Array[Piece] = []
				for e: Piece in enemies:
					if GridPos.manhattan_distance(e.position, center) <= LegendInfo.CHAIN_LIGHTNING_RADIUS:
						in_reach.append(e)
				enemies = in_reach
				var closer_first := func(a: Piece, b: Piece) -> bool:
					var da: int = GridPos.manhattan_distance(a.position, center)
					var db: int = GridPos.manhattan_distance(b.position, center)
					return da < db if da != db else a.id < b.id
				enemies.sort_custom(closer_first)
				var i: int = 0
				while i < enemies.size() and i < LegendInfo.CHAIN_LIGHTNING_TARGETS:
					apply_damage(state, enemies[i], 1, source.id, events)
					i += 1
	return events


## Turn start auras of a player's units: each Aura unit pulses its clan effect on the 8 surrounding tiles
## (Fire: 1 damage to enemies, Healing: heal allies 1, Frost: freeze enemies, Storm: allies +1 Attack this turn,
## Stone: allies +1 Shield up to 2).
static func resolve_auras(state: GameState, player_index: int) -> Array[ResolutionEvent]:
	var events: Array[ResolutionEvent] = []
	for source: Piece in state.get_pieces_of(player_index):
		if source.is_building or not source.has_keyword(Keyword.AURA) or not source.is_alive or state.get_piece(source.id) == null:
			continue
		_pulse_aura(state, source, source.source.clan if source.source != null else Clan.NONE, player_index, events)
	return events


## One aura pulse of 'source' (an Aura unit or a clan building): an AuraPulse event, then the clan effect on the
## 8 surrounding tiles - Fire burns enemies, Healing heals allies, Frost freezes enemies, Storm gives allies +1
## Attack this turn, Stone gives allies +1 Shield (up to 2).
static func _pulse_aura(state: GameState, source: Piece, clan: int, player_index: int, events: Array[ResolutionEvent]) -> void:
	var pulse := _ev(ResolutionEventType.AURA_PULSE, source.id, source.position, source.position)
	pulse.player_index = player_index
	pulse.spell_name = TriggerInfo.aura_name(clan)
	pulse.card_name = Clan.name_of(clan)
	events.append(pulse)
	for p: Piece in _around(state, source.position):
		var ally: bool = p.owner_index == player_index
		match clan:
			Clan.FIRE:
				if not ally:
					apply_damage(state, p, 1, source.id, events)
			Clan.HEALING:
				if ally:
					apply_heal(state, p, 1, source.id, events)
			Clan.FROST:
				if not ally and not p.is_building:
					apply_status(state, p, StatusEffectType.FROZEN, state.config.frost_duration, TriggerInfo.aura_name(clan), source.id, events)
			Clan.STORM:
				if ally and not p.is_building:
					p.active_spells.append(ActiveSpell.new(source.source, SpellEffect.new(1), player_index, state.turn_number, state.turn_number))
			Clan.STONE:
				if ally and p.current_shield < 2:
					p.current_shield += 1


## Living pieces on the 8 tiles around a position.
static func _around(state: GameState, center: Vector2i) -> Array[Piece]:
	var list: Array[Piece] = []
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var p: Piece = state.board.get_piece_at(Vector2i(center.x + dx, center.y + dy))
			if p != null and p.is_alive:
				list.append(p)
	return list


## Pushes a piece 1 tile in 'dir' if that tile is free (edge, wall or piece = PushBlocked). Appends events
## ('events' may be null).
static func push_piece(state: GameState, piece: Piece, dir: Vector2i, pusher_id: int, events: Variant) -> bool:
	if piece == null or not piece.is_alive or state.get_piece(piece.id) == null or dir == Vector2i(0, 0):
		return false
	var ctx := _new_context(state)
	if events != null:
		ctx.events = events
	return _try_push_line(ctx, piece, dir, false, -1, 1, pusher_id, ctx.events)


## Pushes every piece next to 'center' one tile away from it (shockwaves).
static func push_neighbors_away(state: GameState, center: Vector2i, pusher_id: int, events: Variant) -> void:
	var pieces: Array[Piece] = []
	for n: Vector2i in GridPos.neighbors(center):
		var p: Piece = state.board.get_piece_at(n)
		if p != null:
			pieces.append(p)
	for p: Piece in pieces:
		push_piece(state, p, p.position - center, pusher_id, events)


static func _trigger_deathrattle(state: GameState, dead: Piece, pos: Vector2i, events: Array[ResolutionEvent]) -> void:
	var card: CardData = dead.source
	if card == null or card.deathrattle == DeathrattleType.NONE:
		return
	var amount: int = maxi(1, card.deathrattle_amount)
	var dr := _ev(ResolutionEventType.DEATHRATTLE, dead.id, pos, pos)
	dr.player_index = dead.owner_index
	dr.spell_name = TriggerInfo.display_name(card.deathrattle)
	dr.card_name = card.name
	dr.amount = amount
	events.append(dr)
	var duration: int = maxi(1, state.config.trigger_effect_duration)
	match card.deathrattle:
		DeathrattleType.EXPLODE:
			var victims: Array[Piece] = []
			for n: Vector2i in GridPos.neighbors(pos):
				var p: Piece = state.board.get_piece_at(n)
				if p != null:
					victims.append(p)
			for p: Piece in victims:
				if p.is_alive and state.get_piece(p.id) != null:
					apply_damage(state, p, amount, dead.id, events)
		DeathrattleType.SHOCKWAVE:
			push_neighbors_away(state, pos, dead.id, events)
		DeathrattleType.LAVA_POOL:
			apply_tile_effect(state, TileEffectType.LAVA, pos, duration, dead.owner_index, card.name, dead.id, events)
			for n: Vector2i in GridPos.neighbors(pos):
				apply_tile_effect(state, TileEffectType.LAVA, n, duration, dead.owner_index, card.name, dead.id, events)
		DeathrattleType.HEAL_ALLIES:
			for p: Piece in state.get_pieces_of(dead.owner_index).duplicate():
				if GridPos.manhattan_distance(p.position, pos) <= 2:
					apply_heal(state, p, amount, dead.id, events)
		DeathrattleType.RAISE_WALLS:
			for n: Vector2i in GridPos.neighbors(pos):
				if state.board.is_passable(n) and not state.board.is_occupied(n):
					apply_tile_effect(state, TileEffectType.WALL, n, duration, dead.owner_index, card.name, dead.id, events)
		DeathrattleType.FROST_NOVA:
			for n: Vector2i in GridPos.neighbors(pos):
				var p: Piece = state.board.get_piece_at(n)
				if p != null and p.owner_index != dead.owner_index and not p.is_building:
					apply_status(state, p, StatusEffectType.FROZEN, state.config.frost_duration, card.name, dead.id, events)
		DeathrattleType.TRIBUTE:
			state.players[dead.owner_index].pending_ap += amount
			var ap := _ev(ResolutionEventType.AP_GAINED, dead.id, pos, pos)
			ap.player_index = dead.owner_index
			ap.amount = amount
			ap.card_name = card.name
			ap.is_secondary = true
			events.append(ap)
		DeathrattleType.DRAW_CARD:
			var owner: PlayerState = state.players[dead.owner_index]
			var i: int = 0
			while i < amount and owner.deck.size() > 0:
				var index: int = state.random.randi_range(0, owner.deck.size() - 1)
				owner.hand.append(owner.deck[index])
				owner.deck.remove_at(index)
				i += 1


static func _trigger_first_hit(state: GameState, target: Piece, source_piece_id: int, events: Array[ResolutionEvent]) -> void:
	var card: CardData = target.source
	if card == null or card.on_first_hit == FirstHitType.NONE:
		return
	var amount: int = maxi(1, card.on_first_hit_amount)
	var source: Piece = state.get_piece(source_piece_id) if source_piece_id >= 0 else null
	if source == target:
		source = null
	if card.on_first_hit == FirstHitType.HARDEN:
		target.current_shield += amount
	elif card.on_first_hit == FirstHitType.ENRAGE:
		target.bonus_attack += amount
	var e := _ev(ResolutionEventType.FIRST_HIT_TRIGGERED, target.id, target.position, target.position)
	e.other_piece_id = source_piece_id
	e.spell_name = TriggerInfo.get_first_hit_name(card.on_first_hit)
	e.card_name = card.name
	e.amount = amount
	e.remaining_hp = target.current_hp
	e.remaining_shield = target.total_shield
	events.append(e)
	match card.on_first_hit:
		FirstHitType.THORNS:
			if source != null and source.is_alive:
				apply_damage(state, source, amount, target.id, events)
		FirstHitType.REPEL:
			if source != null and source.is_alive:
				push_piece(state, source, attack_direction(target.position, source.position), target.id, events)
		FirstHitType.SHOCKWAVE:
			push_neighbors_away(state, target.position, target.id, events)


## Heals a piece up to its max_hp. Appends a Healed event if anything was healed ('events' may be null).
## Returns HP healed.
static func apply_heal(state: GameState, target: Piece, amount: int, source_piece_id: int, events: Variant) -> int:
	if amount <= 0 or target == null or not target.is_alive:
		return 0
	var healed: int = mini(amount, target.max_hp - target.current_hp)
	if healed <= 0:
		return 0
	target.current_hp += healed
	var e := _ev(ResolutionEventType.HEALED, target.id, target.position, target.position)
	e.other_piece_id = source_piece_id
	e.amount = healed
	e.remaining_hp = target.current_hp
	_add(events, e)
	return healed


## Places a tile effect (no rule checks besides: on the board, and a Wall only on an empty tile).
## Replaces an existing effect on that tile. expiry_turn = turn_number + max(1, duration_turns) - 1 (the creation
## turn counts). 'events' may be null.
static func apply_tile_effect(state: GameState, type: int, pos: Vector2i, duration_turns: int,
		creator_index: int, source_name: String, source_piece_id: int, events: Variant) -> bool:
	# The crown field never carries tile effects (no lava, walls, healing or rubble on it).
	if type == TileEffectType.NONE or not state.board.is_inside(pos) or state.board.is_in_hot_zone(pos):
		return false
	if type == TileEffectType.WALL and state.board.is_occupied(pos):
		return false
	# Permanent map effects stay; nothing grows on walls or rocks.
	var existing: TileEffect = state.board.get_tile_effect(pos)
	if (existing != null and existing.is_permanent) or (type != TileEffectType.WALL and state.board.is_wall(pos)):
		return false
	var duration: int = maxi(1, duration_turns)
	var expiry: int = state.turn_number + duration - 1
	state.board.set_tile_effect(TileEffect.new(type, pos, creator_index, state.turn_number, expiry, source_name))
	var e := _ev(ResolutionEventType.TILE_EFFECT_APPLIED, -1, pos, pos)
	e.other_piece_id = source_piece_id
	e.player_index = creator_index
	e.tile_effect = type
	e.amount = duration
	e.expiry_turn = expiry
	e.card_name = source_name
	_add(events, e)
	return true


## Adds (or refreshes) a status on a piece. expiry_turn = turn_number + max(1, duration_turns); Frozen always lasts
## through the victim owner's next turn. 'events' may be null.
static func apply_status(state: GameState, target: Piece, type: int, duration_turns: int,
		source_name: String, source_piece_id: int, events: Variant) -> void:
	if type == StatusEffectType.NONE or target == null or not target.is_alive:
		return
	var expiry: int = state.turn_number + maxi(1, duration_turns)
	if type == StatusEffectType.FROZEN and target.owner_index == state.current_player_index:
		# Frozen during its owner's own turn (e.g. by a deathrattle its attack triggered): it must still sit out
		# the owner's NEXT turn, not thaw before it could move again.
		expiry = maxi(expiry, state.turn_number + 2)
	for i: int in range(target.status_effects.size() - 1, -1, -1):
		if target.status_effects[i].type == type:
			expiry = maxi(expiry, target.status_effects[i].expiry_turn)
			target.status_effects.remove_at(i)
	target.status_effects.append(StatusEffect.new(type, state.turn_number, expiry, source_name))
	var e := _ev(ResolutionEventType.STATUS_APPLIED, target.id, target.position, target.position)
	e.other_piece_id = source_piece_id
	e.status = type
	e.expiry_turn = expiry
	_add(events, e)


## Main axis direction of a shot from 'from' to 'to' (unit vector; x wins ties). Used for Push and Pierce.
static func attack_direction(from: Vector2i, to: Vector2i) -> Vector2i:
	var dx: int = to.x - from.x
	var dy: int = to.y - from.y
	if dx == 0 and dy == 0:
		return Vector2i(0, 0)
	return Vector2i(signi(dx), 0) if absi(dx) >= absi(dy) else Vector2i(0, signi(dy))


## Springs a trap on the piece standing on it: removes the trap, appends TrapTriggered and applies the trap's
## effect (see TrapInfo). The Trapper (if still alive) counts as the damage source.
static func trigger_trap(state: GameState, victim: Piece, trap: Trap, events: Array[ResolutionEvent]) -> void:
	state.board.remove_trap(trap.position)
	var pos: Vector2i = trap.position
	var tt := _ev(ResolutionEventType.TRAP_TRIGGERED, victim.id, pos, pos)
	tt.player_index = trap.owner_index
	tt.card_name = TrapInfo.display_name(trap.type)
	tt.spell_name = TrapType.name_of(trap.type)
	events.append(tt)
	var source: int = trap.source_piece_id if state.get_piece(trap.source_piece_id) != null else -1
	var name: String = TrapInfo.display_name(trap.type)
	match trap.type:
		TrapType.FIRE:
			apply_damage(state, victim, 1, source, events)
			apply_tile_effect(state, TileEffectType.LAVA, pos, state.config.burning_lava_duration, trap.owner_index, name, source, events)
		TrapType.FROST:
			apply_damage(state, victim, 1, source, events)
			if victim.is_alive:
				# +1: it is the victim's own turn, so the freeze has to last through its next one.
				apply_status(state, victim, StatusEffectType.FROZEN, state.config.frost_duration + 1, name, source, events)
		TrapType.SHOCK:
			apply_damage(state, victim, 1, source, events)
			for n: Vector2i in GridPos.neighbors(pos):
				var p: Piece = state.board.get_piece_at(n)
				if p != null and p.owner_index != trap.owner_index:
					apply_damage(state, p, 1, source, events)
		TrapType.PITFALL:
			apply_damage(state, victim, 3, source, events)
		TrapType.SANCTUM:
			apply_damage(state, victim, 1, source, events)
			for ally: Piece in state.get_pieces_of(trap.owner_index).duplicate():
				if not ally.is_building and GridPos.manhattan_distance(ally.position, pos) <= 2:
					apply_heal(state, ally, 1, source, events)
		_:
			apply_damage(state, victim, 2, source, events)


## Damages a breakable Rock and appends a TerrainDamaged event (remaining_hp 0 = it crumbled). 'events' may be null.
static func damage_rock(state: GameState, tile: Vector2i, damage: int, events: Variant) -> void:
	var remaining: int = state.board.damage_rock(tile, damage)
	if remaining < 0:
		return
	var e := _ev(ResolutionEventType.TERRAIN_DAMAGED, -1, tile, tile)
	e.amount = damage
	e.remaining_hp = remaining
	_add(events, e)


## Gives a player AP from a card effect: right away during its own turn, otherwise at the start of its next turn
## (PlayerState.pending_ap). Appends an ApGained event ('events' may be null).
static func grant_ap(state: GameState, player: int, amount: int, source_piece_id: int, source: String, at: Vector2i,
		events: Variant) -> void:
	if amount <= 0 or player < 0 or player >= state.players.size():
		return
	var now: bool = state.current_player_index == player and state.phase != GamePhase.GAME_OVER
	if now:
		state.players[player].action_points += amount
	else:
		state.players[player].pending_ap += amount
	var e := _ev(ResolutionEventType.AP_GAINED, source_piece_id, at, at)
	e.player_index = player
	e.amount = amount
	e.card_name = source
	e.is_secondary = not now
	_add(events, e)


# ------------------------------------------------------------------ internals

static func _return_to_deck(state: GameState, piece: Piece, events: Variant) -> void:
	var card: CardData = piece.source
	if card == null or piece.owner_index < 0 or piece.owner_index >= state.players.size():
		return
	# Destroyed cards are lost; only Undying cards come back, stronger each time.
	if not piece.has_keyword(Keyword.UNDYING):
		state.players[piece.owner_index].graveyard.append(card)
		return
	var returned: CardData = card.create_undying_upgrade()
	state.players[piece.owner_index].deck.append(returned)
	var e := _ev(ResolutionEventType.RETURNED_TO_DECK, piece.id, piece.position, piece.position)
	e.player_index = piece.owner_index
	e.card_name = returned.name
	e.amount = returned.level
	_add(events, e)


## Moves a piece along its path (pushing friendlies at the end). An enemy trap on the way stops the move on its
## tile and springs (trigger_trap).
static func _resolve_move(ctx: Context, piece: Piece, target: Vector2i) -> void:
	var from: Vector2i = piece.position
	var found: Variant = ctx.board.find_path(from, target, piece.effective_movement, piece.owner_index)
	if found == null or (found as Array).size() == 0:
		ctx.events.append(_ev(ResolutionEventType.MOVE_BLOCKED, piece.id, from, target))
		return
	var path: Array[Vector2i] = found
	var trap: Trap = null
	for i: int in path.size():
		if ctx.board.is_occupied(path[i]):
			continue
		var t: Trap = ctx.board.get_trap(path[i])
		if t != null and t.owner_index != piece.owner_index:
			trap = t
			path = path.slice(0, i + 1)
			break
		if ctx.board.get_tile_effect_type(path[i]) == TileEffectType.ICE and i < path.size() - 1:
			# Slides to a halt on the ice.
			path = path.slice(0, i + 1)
			break
	_move_along(ctx, piece, from, target, path)
	if trap != null and piece.is_alive and piece.position == trap.position:
		trigger_trap(ctx.state, piece, trap, ctx.events)


static func _move_along(ctx: Context, piece: Piece, from: Vector2i, target: Vector2i, path: Array[Vector2i]) -> void:
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
		ctx.events.append(_ev(ResolutionEventType.MOVE_BLOCKED, piece.id, from, target))
		return
	var walked: Array[Vector2i] = path.slice(0, stop + 1)
	ctx.board.move_piece(piece, walked[walked.size() - 1])
	ctx.events.append(_moved_event(piece, from, walked))


static func _moved_event(piece: Piece, from: Vector2i, path: Array[Vector2i]) -> ResolutionEvent:
	var e := _ev(ResolutionEventType.MOVED, piece.id, from, path[path.size() - 1])
	e.path = path.duplicate()
	return e


## Pushes 'first' one tile in 'dir'. With allow_chain, further pieces of chain_owner in the way are pushed
## too (line of at most max_chain pieces). Pushed events (farthest piece first) or one PushBlocked event
## are appended to 'events'. Returns true if the push happened.
## A real push (no chain: Push hits, shockwaves, push spells, Repel) that is stopped by an object - another
## piece, a building, a wall or a rock - slams the pushed piece into it: it takes GameConfig.push_collision_damage
## instead of moving. The board edge only blocks.
static func _try_push_line(ctx: Context, first: Piece, dir: Vector2i, allow_chain: bool, chain_owner: int, max_chain: int,
		pusher_id: int, events: Array[ResolutionEvent]) -> bool:
	var line: Array[Piece] = [first]
	var next: Vector2i = first.position + dir
	var ok: bool = dir != Vector2i(0, 0) and not first.is_building
	while ok:
		if not ctx.board.is_passable(next):
			ok = false
			break
		var p: Piece = ctx.board.get_piece_at(next)
		if p == null:
			break
		if allow_chain and p.owner_index == chain_owner and not p.is_building and line.size() < maxi(1, max_chain):
			line.append(p)
			next += dir
			continue
		ok = false

	if not ok:
		var blocked := _ev(ResolutionEventType.PUSH_BLOCKED, first.id, first.position, first.position + dir)
		blocked.other_piece_id = pusher_id
		events.append(blocked)
		var into: Vector2i = first.position + dir
		var hits_object: bool = ctx.board.is_inside(into) and (ctx.board.is_occupied(into) or ctx.board.is_wall(into))
		if not allow_chain and hits_object and dir != Vector2i(0, 0) and not first.is_building:
			apply_damage(ctx.state, first, maxi(0, ctx.config.push_collision_damage), pusher_id, events)
		return false

	for i: int in range(line.size() - 1, -1, -1):
		var p: Piece = line[i]
		var from: Vector2i = p.position
		var to: Vector2i = from + dir
		ctx.board.move_piece(p, to)
		var pushed := _ev(ResolutionEventType.PUSHED, p.id, from, to)
		pushed.other_piece_id = pusher_id
		events.append(pushed)
	return true


## One declared attack: Overcharge multiplier, the main hit (with Pierce / Arc / area), then the Echo strike.
static func _strike(ctx: Context, attacker: Piece, tile: Vector2i) -> void:
	var damage: int = attacker.effective_attack
	for i: int in range(attacker.status_effects.size() - 1, -1, -1):
		if attacker.status_effects[i].type != StatusEffectType.OVERCHARGED:
			continue
		attacker.status_effects.remove_at(i)
		damage *= maxi(1, ctx.config.overcharge_multiplier)
		var e := _ev(ResolutionEventType.STATUS_EXPIRED, attacker.id, attacker.position, attacker.position)
		e.status = StatusEffectType.OVERCHARGED
		e.is_secondary = true
		ctx.events.append(e)
		break
	_hit_tile(ctx, attacker, tile, damage, false, false, true)
	if attacker.is_alive and attacker.has_keyword(Keyword.ECHO) and ctx.config.echo_bonus_damage > 0:
		_hit_tile(ctx, attacker, tile, ctx.config.echo_bonus_damage, true, false, false)


static func _hit_tile(ctx: Context, attacker: Piece, tile: Vector2i, damage: int, secondary: bool, is_pierce: bool,
		primary: bool) -> void:
	var target: Piece = ctx.board.get_piece_at(tile)
	if target == attacker:
		target = null
	var atk := _ev(ResolutionEventType.ATTACKED, attacker.id, attacker.position, tile)
	atk.other_piece_id = target.id if target != null else -1
	atk.is_secondary = secondary
	atk.is_pierce = is_pierce
	ctx.events.append(atk)

	var dir: Vector2i = attack_direction(attacker.position, tile)
	var behind: Piece = null
	var behind_tile: Vector2i = tile + dir
	if primary and attacker.has_keyword(Keyword.PIERCE) and ctx.board.is_passable(behind_tile):
		behind = ctx.board.get_piece_at(behind_tile)
		if behind == attacker:
			behind = null
	# Area attacks: every other piece (or rock) in the area takes the full hit - collected before the main hit
	# pushes anything around.
	var area_tiles: Array[Vector2i] = []
	var area_targets: Array[Piece] = []
	if primary and attacker.attack_area != AreaShape.SINGLE:
		for a: Vector2i in ctx.board.get_area_tiles(tile, attacker.attack_area):
			if a == tile or a == attacker.position:
				continue
			var ap: Piece = ctx.board.get_piece_at(a)
			if ap != null and ap != behind:
				area_targets.append(ap)
			elif ap == null and ctx.board.get_terrain(a) == TerrainType.ROCK:
				area_tiles.append(a)
	var arc_targets: Array[Piece] = []
	if primary and attacker.has_keyword(Keyword.ARC) and ctx.config.arc_damage > 0:
		for n: Vector2i in GridPos.neighbors(tile):
			var p: Piece = ctx.board.get_piece_at(n)
			if p != null and p != attacker and p != behind and not area_targets.has(p):
				arc_targets.append(p)

	if target != null:
		_hit_piece(ctx, attacker, target, tile, dir, damage)
	elif ctx.board.get_terrain(tile) == TerrainType.ROCK:
		damage_rock(ctx.state, tile, damage, ctx.events)
	if primary:
		_leave_attack_ground(ctx, attacker, tile)
	if behind != null and behind.is_alive and attacker.is_alive and ctx.board.get_piece_at(behind_tile) == behind:
		_hit_tile(ctx, attacker, behind_tile, damage, secondary, true, false)
	for p: Piece in area_targets:
		if p.is_alive and attacker.is_alive and ctx.state.get_piece(p.id) != null:
			_hit_tile(ctx, attacker, p.position, damage, true, false, false)
	for a: Vector2i in area_tiles:
		if attacker.is_alive and not ctx.board.is_occupied(a) and ctx.board.get_terrain(a) == TerrainType.ROCK:
			_hit_tile(ctx, attacker, a, damage, true, false, false)
	for p: Piece in arc_targets:
		if p.is_alive and attacker.is_alive and ctx.state.get_piece(p.id) != null:
			_hit_tile(ctx, attacker, p.position, ctx.config.arc_damage, true, false, false)


## Clan attacks mark the ground they hit - whether a piece stood there or not - with an effect that works for
## everyone: Burning = Lava, Frost = Ice, Arc = Storm cell, Mending = Healing spring, Push = Mud (first matching
## keyword wins).
static func _leave_attack_ground(ctx: Context, attacker: Piece, tile: Vector2i) -> void:
	var type: int = TileEffectType.NONE
	var duration: int = 0
	if attacker.has_keyword(Keyword.BURNING):
		type = TileEffectType.LAVA
		duration = ctx.config.burning_lava_duration
	elif attacker.has_keyword(Keyword.FROST):
		type = TileEffectType.ICE
		duration = ctx.config.attack_ground_duration
	elif attacker.has_keyword(Keyword.ARC):
		type = TileEffectType.STORM
		duration = ctx.config.attack_ground_duration
	elif attacker.has_keyword(Keyword.MENDING):
		type = TileEffectType.HEALING
		duration = ctx.config.attack_ground_duration
	elif attacker.has_keyword(Keyword.PUSH):
		type = TileEffectType.MUD
		duration = ctx.config.attack_ground_duration
	if type != TileEffectType.NONE and ctx.board.is_inside(tile):
		apply_tile_effect(ctx.state, type, tile, duration, attacker.owner_index,
			attacker.source.name if attacker.source != null else TileEffectType.name_of(type), attacker.id, ctx.events)


## Damages any hit piece (friend or foe) and applies the attacker's on-hit keywords. Mending heals friendlies instead.
static func _hit_piece(ctx: Context, attacker: Piece, target: Piece, _tile: Vector2i, dir: Vector2i, damage: int) -> void:
	if target.owner_index == attacker.owner_index and attacker.has_keyword(Keyword.MENDING):
		apply_heal(ctx.state, target, ctx.config.mending_heal, attacker.id, ctx.events)
		return
	apply_damage(ctx.state, target, damage, attacker.id, ctx.events)
	if not target.is_alive:
		return
	if attacker.has_keyword(Keyword.FROST):
		apply_status(ctx.state, target, StatusEffectType.FROZEN, ctx.config.frost_duration,
			attacker.source.name if attacker.source != null else "Frost", attacker.id, ctx.events)
	if attacker.has_keyword(Keyword.PUSH):
		_try_push_line(ctx, target, dir, false, -1, 1, attacker.id, ctx.events)
