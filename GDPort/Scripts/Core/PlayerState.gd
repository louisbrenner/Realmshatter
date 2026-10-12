class_name PlayerState
extends RefCounted
## Per-player resources and cards.

var index: int = 0
var victory_points: int = 0
var action_points: int = 0
## Victory points converted into action points during the current turn (reset at turn start).
var vp_converted_this_turn: int = 0
## Extra AP at the start of every one of this player's turns (e.g. the endboss).
var bonus_ap_per_turn: int = 0
## AP added at the start of this player's next turn (Tribute deathrattles, Plunder on the enemy's turn).
var pending_ap: int = 0
## Number of turns this player has started (1 during its first turn).
var turns_started: int = 0
var hand: Array[CardData] = []
## Remaining draw pile. Draft offers are drawn from here; unpicked cards and destroyed Undying pieces return to it.
var deck: Array[CardData] = []
## Cards of destroyed pieces (lost for the rest of the game).
var graveyard: Array[CardData] = []
## Current draft offer (up to DraftOfferSize cards); empty when no draft is pending.
var draft_offer: Array[CardData] = []


func _init(p_index: int = 0, p_deck: Array = []) -> void:
	index = p_index
	for c: CardData in p_deck:
		deck.append(c)


## Copy for state clones (card lists are copied, cards are shared). C# copy constructor.
static func copy_of(other: PlayerState) -> PlayerState:
	var p := PlayerState.new(other.index)
	p.victory_points = other.victory_points
	p.action_points = other.action_points
	p.vp_converted_this_turn = other.vp_converted_this_turn
	p.turns_started = other.turns_started
	p.pending_ap = other.pending_ap
	p.bonus_ap_per_turn = other.bonus_ap_per_turn
	p.hand.append_array(other.hand)
	p.deck.append_array(other.deck)
	p.draft_offer.append_array(other.draft_offer)
	p.graveyard.append_array(other.graveyard)
	return p
