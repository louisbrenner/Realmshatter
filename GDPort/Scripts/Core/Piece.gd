class_name Piece
extends RefCounted
## A unit on the board. Pure data; mutated only by core classes.

var id: int = 0
var owner_index: int = 0
var source: CardData
var base_stats: PieceStats
## UnitRole value.
var role: int = UnitRole.ATTACK
var ap_bonus: int = 0
## Keyword flags (copied from the card).
var keywords: int = Keyword.NONE

var position: Vector2i = Vector2i.ZERO
var current_hp: int = 0
## Remaining base shield (does not regenerate). Spell shields are tracked on ActiveSpell.
var current_shield: int = 0
var active_spells: Array[ActiveSpell] = []
## Temporary statuses (Frozen, Overcharged...). Read-only for views.
var status_effects: Array[StatusEffect] = []
## Queued order for the current turn, or null.
var order: PieceOrder = null
## Global turn number in which the piece entered the board.
var summoned_turn: int = 0

var is_alive: bool:
	get:
		return current_hp > 0

## True while Frozen (effective movement 0).
var is_frozen: bool:
	get:
		return has_status(StatusEffectType.FROZEN)

var effective_movement: int:
	get:
		return 0 if is_frozen else maxi(0, base_stats.movement + _sum_delta(func(e: SpellEffect) -> int: return e.movement_delta))

var effective_attack: int:
	get:
		return maxi(0, base_stats.attack + _sum_delta(func(e: SpellEffect) -> int: return e.attack_delta))

var effective_range: int:
	get:
		return maxi(0, base_stats.range + _sum_delta(func(e: SpellEffect) -> int: return e.range_delta))

var max_hp: int:
	get:
		return maxi(1, base_stats.hp + _sum_delta(func(e: SpellEffect) -> int: return e.hp_delta))

## Base shield remaining plus all remaining spell shields.
var total_shield: int:
	get:
		var total: int = current_shield
		for s: ActiveSpell in active_spells:
			total += s.remaining_shield
		return total

## Effective stats including spell modifiers (hp = current HP, shield = total shield).
var effective_stats: PieceStats:
	get:
		return PieceStats.new(effective_movement, effective_attack, current_hp, effective_range, total_shield)


func _init(p_id: int = 0, p_owner_index: int = 0, p_source: CardData = null, p_position: Vector2i = Vector2i.ZERO, p_summoned_turn: int = 0) -> void:
	summoned_turn = p_summoned_turn
	id = p_id
	owner_index = p_owner_index
	source = p_source
	position = p_position
	if p_source == null:
		# Only used by copy(); fields are filled in there.
		base_stats = PieceStats.new()
		return
	base_stats = PieceStats.from_card(p_source)
	role = p_source.role
	ap_bonus = p_source.ap_bonus
	keywords = p_source.keywords
	current_hp = maxi(1, base_stats.hp)
	current_shield = maxi(0, base_stats.shield)


## Deep copy (spells, statuses, order) for state clones / previews. C# copy constructor.
func copy() -> Piece:
	var p := Piece.new(id, owner_index, null, position, summoned_turn)
	p.source = source
	p.base_stats = base_stats.copy()
	p.role = role
	p.ap_bonus = ap_bonus
	p.keywords = keywords
	p.current_hp = current_hp
	p.current_shield = current_shield
	for s: ActiveSpell in active_spells:
		var spell := ActiveSpell.new(s.source, s.effect.copy(), s.caster_index, s.cast_turn, s.expiry_turn)
		spell.remaining_shield = s.remaining_shield
		p.active_spells.append(spell)
	for s: StatusEffect in status_effects:
		p.status_effects.append(StatusEffect.new(s.type, s.applied_turn, s.expiry_turn, s.source_name))
	if order != null:
		p.order = PieceOrder.new(order.move_target, order.attack_target, order.order_index)
		p.order.ap_paid = order.ap_paid
	return p


## True while the piece may not receive orders: on the turn it was summoned (it becomes commandable
## on its owner's next turn, i.e. any turn after summoned_turn).
func is_summoning_sick(turn_number: int) -> bool:
	return turn_number <= summoned_turn


## True if the piece has all given keyword flags.
func has_keyword(keyword: int) -> bool:
	return keyword != Keyword.NONE and (keywords & keyword) == keyword


## True if the piece currently has the status.
func has_status(type: int) -> bool:
	for s: StatusEffect in status_effects:
		if s.type == type:
			return true
	return false


func _sum_delta(selector: Callable) -> int:
	var sum: int = 0
	for s: ActiveSpell in active_spells:
		sum += selector.call(s.effect)
	return sum


func _to_string() -> String:
	var source_name: String = source.name if source != null else ""
	return "#%d %s (P%d) at %s HP %d/%d SHD %d" % [id, source_name, owner_index, str(position), current_hp, max_hp, total_shield]
