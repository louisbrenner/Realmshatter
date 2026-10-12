class_name HandView
extends HBoxContainer
## Hearthstone-style fanned hand at the bottom of the screen. Cards overlap on an arc; the hovered
## card straightens, enlarges and comes to the front while its neighbours move aside. Only displays
## the hand and reports clicks; the GameManager decides what a selection means.

signal card_selected(hand_index: int)

## A hand card was hovered (true) or left (false); used for the card info panel.
signal card_hover_changed(card: CardView, hovered: bool)

@export var card_scene: PackedScene
@export var card_spacing: float = 92.0
@export var fan_angle_degrees: float = 4.0
@export var arc_drop: float = 5.0
@export var hover_scale: float = 1.3
## Scale of resting (not hovered) cards; small so the board's bottom rows stay visible.
@export var rest_scale: float = 0.7
@export var selected_rise: float = 30.0
## While a card is selected (targeting the board) the whole hand sinks this much further.
@export var selected_sink: float = 0.0
## How far the whole hand rises (less sunk) while one of its cards is hovered.
@export var hover_lift: float = 62.0
## Where the selected card waits while it is being played: centre in HUD-root units (x, y as a fraction of the height).
@export var selected_park_position: Vector2 = Vector2(310.0, 0.46)
## How far resting cards sink below the hand area (Hearthstone-style peek); hovered cards rise fully.
@export var rest_sink: float = 80.0
## How far the neighbours of a hovered card stay tucked under its edges (no gap between them).
@export var hover_overlap: float = 26.0
@export var layout_tween_time: float = 0.14

var _cards: Array[CardView] = []
var _tweens: Dictionary = {}
var _fan: Control
var _selected_index: int = -1
var _hovered_index: int = -1
var _suppress_hover: CardView
var _order_queued: bool = false

## Number of cards currently displayed.
var card_count: int:
	get:
		return _cards.size()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_fan()


## Shows the hand and clears the selection. cost_of (Callable CardData -> int) returns the AP cost, can_afford
## (Callable CardData -> bool) decides the playable glow (unplayable cards still emit card_selected). Either may be
## null / an invalid Callable. Existing card views are reused so cards slide to their new places; new cards are
## dealt in from the right.
func show_hand(hand: Array, cost_of: Variant = null, can_afford: Variant = null) -> void:
	_ensure_fan()
	if card_scene == null:
		push_error("HandView: card_scene is not assigned.")
		_clear_cards()
		return
	if hand == null:
		_clear_cards()
		return
	var has_cost: bool = cost_of is Callable and (cost_of as Callable).is_valid()
	var has_afford: bool = can_afford is Callable and (can_afford as Callable).is_valid()

	var unused: Array[CardView] = _cards.duplicate()
	var ordered: Array[CardView] = []
	var fresh: Dictionary = {}
	for card: CardData in hand:
		var view: CardView = null
		for v in unused:
			if v.card == card:
				view = v
				break
		if view != null:
			unused.erase(view)
		else:
			view = card_scene.instantiate() as CardView
			view.managed_layout = true
			_fan.add_child(view)
			view.card_clicked.connect(_on_card_clicked)
			view.hover_changed.connect(_on_card_hover_changed)
			fresh[view] = true
		view.setup(card, int((cost_of as Callable).call(card)) if has_cost else card.ap_cost)
		view.set_playable(not has_afford or bool((can_afford as Callable).call(card)))
		ordered.append(view)
	for view in unused:
		_free_card(view)
	_cards.clear()
	_cards.append_array(ordered)

	var deal_from := Vector2(_fan.size.x + 60.0, _fan.size.y - 120.0)
	var dealt: int = 0
	for view: CardView in fresh.keys():
		view.position = deal_from
		view.rotation = deg_to_rad(20.0)
		if dealt < 4:
			Sfx.play_delayed(SfxId.CARD_DEAL, dealt * 0.09)
		dealt += 1

	_hovered_index = -1
	for i in range(_cards.size()):
		if _cards[i].is_hovered and _cards[i] != _suppress_hover:
			_hovered_index = i
			break
	_selected_index = -1
	for i in range(_cards.size()):
		_cards[i].set_selected(false)
	_restore_order()
	_relayout(true)


## Highlights the card at the given hand index (-1 = no selection).
func set_selected_index(index: int) -> void:
	_selected_index = index if index >= 0 and index < _cards.size() else -1
	for i in range(_cards.size()):
		_cards[i].set_selected(i == _selected_index)
	if _selected_index >= 0:
		# The mouse is still on the clicked card: drop it out of the way until the pointer leaves it.
		var selected: CardView = _cards[_selected_index]
		_suppress_hover = selected
		if _hovered_index >= 0:
			card_hover_changed.emit(_cards[_hovered_index], false)
		_hovered_index = -1
	else:
		_suppress_hover = null
	_relayout(true)


func _ensure_fan() -> void:
	if _fan != null:
		return
	_fan = Control.new()
	_fan.name = "Fan"
	_fan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fan.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fan.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_fan)
	_fan.resized.connect(func() -> void: _relayout(false))


func _relayout(animate: bool) -> void:
	if _fan == null:
		return
	var n: int = _cards.size()
	if n == 0 or _fan.size.x < 1.0:
		return
	var card_size: Vector2 = _cards[0].size if _cards[0].size.x > 0 else Vector2(150, 210)
	var width: float = maxf(card_size.x, _fan.size.x)
	var spacing: float = minf(card_spacing, (width - card_size.x * rest_scale) / (n - 1)) if n > 1 else 0.0
	var center: float = _fan.size.x * 0.5
	var hover_y: float = _fan.size.y - card_size.y
	var hand_hovered: bool = _hovered_index >= 0 and _selected_index < 0
	var base_y: float = hover_y + rest_sink + (selected_sink if _selected_index >= 0 else 0.0) - (hover_lift if hand_hovered else 0.0)
	# The hovered card is enlarged and drawn on top: its neighbours move aside just far enough to sit under its edges.
	var push: float = maxf(0.0, card_size.x * (hover_scale + rest_scale) * 0.5 - hover_overlap - spacing)

	for i in range(n):
		var card: CardView = _cards[i]
		card.pivot_offset = Vector2(card_size.x * 0.5, card_size.y)
		var off: float = i - (n - 1) * 0.5
		var x: float = center + off * spacing
		var y: float = base_y + off * off * arc_drop
		var angle: float = deg_to_rad(off * fan_angle_degrees)
		var s: float = rest_scale
		if _hovered_index >= 0 and i != _hovered_index:
			var d: int = i - _hovered_index
			x += signi(d) * push
		if i == _hovered_index:
			angle = 0.0
			s = hover_scale
			y = hover_y
		elif i == _selected_index:
			# The card being played waits left of the board so the whole board (and the deploy rows) stays visible.
			var park: Vector2 = _park_position_in_fan(card_size)
			x = park.x
			y = park.y
			s = 1.0
			angle = 0.0
		var pos := Vector2(x - card_size.x * 0.5, y)
		if _tweens.has(card):
			var old: Tween = _tweens[card]
			if old != null and old.is_valid():
				old.kill()
		if not animate:
			card.position = pos
			card.rotation = angle
			card.scale = Vector2(s, s)
			continue
		var tween: Tween = card.create_tween()
		tween.set_parallel(true)
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "position", pos, layout_tween_time)
		tween.tween_property(card, "rotation", angle, layout_tween_time)
		tween.tween_property(card, "scale", Vector2(s, s), layout_tween_time)
		_tweens[card] = tween


## Selected-card resting place (bottom-centre anchor, fan coordinates) left of the board.
func _park_position_in_fan(card_size: Vector2) -> Vector2:
	var root := get_parent() as Control
	var root_height: float = root.size.y if root != null else 648.0
	var root_point := Vector2(selected_park_position.x, selected_park_position.y * root_height)
	var local: Vector2 = root_point - position - _fan.position
	return Vector2(local.x, local.y - card_size.y * 0.5)


func _restore_order() -> void:
	# Deferred: hover signals can arrive while the fan is busy adding children.
	if _order_queued:
		return
	_order_queued = true
	_apply_order.call_deferred()


func _apply_order() -> void:
	_order_queued = false
	if _fan == null or not is_instance_valid(_fan):
		return
	for i in range(_cards.size()):
		if is_instance_valid(_cards[i]) and _cards[i].get_parent() == _fan:
			_fan.move_child(_cards[i], mini(i, _fan.get_child_count() - 1))
	if _hovered_index >= 0 and _hovered_index < _cards.size() and is_instance_valid(_cards[_hovered_index]) and _cards[_hovered_index].get_parent() == _fan:
		_fan.move_child(_cards[_hovered_index], -1)


func _on_card_hover_changed(card: CardView, hovered: bool) -> void:
	var index: int = _cards.find(card)
	if index < 0:
		return
	if card == _suppress_hover:
		if not hovered:
			_suppress_hover = null
		return
	if hovered:
		_hovered_index = index
		Sfx.play(SfxId.CARD_HOVER)
	elif _hovered_index == index:
		_hovered_index = -1
	_restore_order()
	_relayout(true)
	card_hover_changed.emit(card, hovered)


func _on_card_clicked(card: CardView) -> void:
	var index: int = _cards.find(card)
	if index >= 0:
		Sfx.play(SfxId.CARD_PICK)
		card_selected.emit(index)


func _free_card(view: CardView) -> void:
	_tweens.erase(view)
	if view.card_clicked.is_connected(_on_card_clicked):
		view.card_clicked.disconnect(_on_card_clicked)
	if view.hover_changed.is_connected(_on_card_hover_changed):
		view.hover_changed.disconnect(_on_card_hover_changed)
	if view.get_parent() != null:
		view.get_parent().remove_child(view)
	view.queue_free()


func _clear_cards() -> void:
	for view in _cards:
		_free_card(view)
	_cards.clear()
	_hovered_index = -1
	_selected_index = -1
