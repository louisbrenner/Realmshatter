class_name Piece
extends RefCounted
## A unit on the board. Pure data; mutated only by core classes.

var id: int = 0
var owner_index: int = 0
var source: CardData
var base_stats: PieceStats
## UnitRole value.
var role: int = 0
var ap_bonus: int = 0
## Keyword flags (copied from the card).
var keywords: int = 0

var position: Vector2i = Vector2i.ZERO
var current_hp: int = 0
## Remaining base shield (does not regenerate). Spell shields are tracked on ActiveSpell.
var current_shield: int = 0
var active_spells: Array[ActiveSpell] = []
## Temporary statuses (Frozen, Overcharged...). Read-only for views.
var status_effects: Array[StatusEffect] = []
## True for building pieces (source.card_type == BUILDING).
var is_building: bool:
	get:
		return source != null and source.card_type == CardType.BUILDING
## Which building this piece is (BuildingType.NONE for units).
var building: int:
	get:
		return source.building if source != null else BuildingType.NONE
## Buildings: still being built (no effect yet). Cleared when it is finished.
var under_construction: bool = false
## Buildings: global turn at whose start it is finished.
var complete_turn: int = 0
## Buildings: id of the unit building it (-1 = none).
var builder_id: int = -1
## Builders: id of the unfinished building they work on (-1 = none). They cannot move meanwhile.
var constructing_id: int = -1
## Turrets: global turn in which it last fired (once per turn).
var reacted_turn: int = -1
## True once the piece has taken damage (its first-hit effect is used up).
var was_hit: bool = false
## Permanent attack bonus (e.g. from Enrage).
var bonus_attack: int = 0
## Global turn number in which the piece last acted (moved / attacked); -1 = never.
var acted_turn: int = -1
## Global turn number in which the piece entered the board.
var summoned_turn: int = 0

var is_alive: bool:
	get:
		return current_hp > 0


func _init(p_id: int = 0, p_owner_index: int = 0, p_source: CardData = null, p_position: Vector2i = Vector2i.ZERO,
		p_summoned_turn: int = 0) -> void:
	summoned_turn = p_summoned_turn
	id = p_id
	owner_index = p_owner_index
	source = p_source
	if p_source == null:
		# Only used by copy_of (C# internal copy constructor).
		base_stats = PieceStats.new()
		return
	base_stats = PieceStats.from_card(p_source)
	role = p_source.role
	ap_bonus = p_source.ap_bonus
	keywords = p_source.keywords
	position = p_position
	current_hp = maxi(1, base_stats.hp)
	current_shield = maxi(0, base_stats.shield)


## Deep copy (spells, statuses, acted turn) for state clones / previews. C# internal copy constructor.
static func copy_of(other: Piece) -> Piece:
	var p := Piece.new()
	p.id = other.id
	p.owner_index = other.owner_index
	p.source = other.source
	p.base_stats = other.base_stats.copy()
	p.role = other.role
	p.ap_bonus = other.ap_bonus
	p.keywords = other.keywords
	p.position = other.position
	p.current_hp = other.current_hp
	p.current_shield = other.current_shield
	p.summoned_turn = other.summoned_turn
	for s: ActiveSpell in other.active_spells:
		var spell := ActiveSpell.new(s.source, s.effect, s.caster_index, s.cast_turn, s.expiry_turn)
		spell.remaining_shield = s.remaining_shield
		p.active_spells.append(spell)
	for s: StatusEffect in other.status_effects:
		p.status_effects.append(StatusEffect.new(s.type, s.applied_turn, s.expiry_turn, s.source_name))
	p.acted_turn = other.acted_turn
	p.was_hit = other.was_hit
	p.bonus_attack = other.bonus_attack
	p.under_construction = other.under_construction
	p.complete_turn = other.complete_turn
	p.builder_id = other.builder_id
	p.constructing_id = other.constructing_id
	p.reacted_turn = other.reacted_turn
	return p


## True while the piece may not receive orders: on the turn it was summoned (it becomes commandable
## on its owner's next turn, i.e. any turn after summoned_turn).
func is_summoning_sick(turn_number: int) -> bool:
	return turn_number <= summoned_turn


## True if the piece already acted in the given turn (each piece acts once per turn).
func has_acted(turn_number: int) -> bool:
	return acted_turn == turn_number


## True if the piece has all given keyword flags.
func has_keyword(keyword: int) -> bool:
	return keyword != Keyword.NONE and (keywords & keyword) == keyword


## True if the piece scores VP in the scoring zone: not buildings, not Planted units, and not units that are busy
## building (they score again once their building is finished).
var can_score: bool:
	get:
		return not is_building and not has_keyword(Keyword.PLANTED) and constructing_id < 0


## True if the piece currently has the status.
func has_status(type: int) -> bool:
	for s: StatusEffect in status_effects:
		if s.type == type:
			return true
	return false


## True while Frozen (effective movement 0).
var is_frozen: bool:
	get:
		return has_status(StatusEffectType.FROZEN)

var effective_movement: int:
	get:
		return 0 if is_frozen else maxi(0, base_stats.movement + _sum_delta(func(e: SpellEffect) -> int: return e.movement_delta))
var effective_attack: int:
	get:
		return maxi(0, base_stats.attack + bonus_attack + _sum_delta(func(e: SpellEffect) -> int: return e.attack_delta))
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


func _sum_delta(selector: Callable) -> int:
	var sum: int = 0
	for s: ActiveSpell in active_spells:
		sum += int(selector.call(s.effect))
	return sum


func _to_string() -> String:
	return "#%d %s (P%d) at %s HP %d/%d SHD %d" % [id, source.name if source != null else "", owner_index,
		str(position), current_hp, max_hp, total_shield]
