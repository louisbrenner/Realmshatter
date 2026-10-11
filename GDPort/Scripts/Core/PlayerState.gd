class_name PlayerState
extends RefCounted
## Per-player resources and cards.

var index: int = 0
var victory_points: int = 0
var action_points: int = 0
## Victory points converted into action points during the current turn (reset at turn start).
var vp_converted_this_turn: int = 0
## Number of turns this player has started (1 during its first turn).
var turns_started: int = 0
var hand: Array[CardData] = []
## Remaining draw pile. Draft offers are drawn from here; unpicked cards and destroyed pieces return to it.
var deck: Array[CardData] = []
## Current draft offer (up to draft_offer_size cards); empty when no draft is pending.
var draft_offer: Array[CardData] = []


func _init(p_index: int = 0, p_deck: Variant = null) -> void:
	index = p_index
	if p_deck != null:
		for c: CardData in p_deck:
			deck.append(c)


## Copy for state clones (card lists are copied, cards are shared). C# copy constructor.
func copy() -> PlayerState:
	var p := PlayerState.new(index)
	p.victory_points = victory_points
	p.action_points = action_points
	p.vp_converted_this_turn = vp_converted_this_turn
	p.turns_started = turns_started
	p.hand.append_array(hand)
	p.deck.append_array(deck)
	p.draft_offer.append_array(draft_offer)
	return p
