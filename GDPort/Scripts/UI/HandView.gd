class_name HandView
extends HBoxContainer
## Hearthstone-style fanned hand at the bottom of the screen. Cards overlap on an arc; the hovered
## card straightens, enlarges and comes to the front while its neighbours move aside. Only displays
## the hand and reports clicks; the GameManager decides what a selection means.

signal card_selected(hand_index: int)

## A hand card was hovered (true) or left (false); used for the card info panel.
signal card_hover_changed(card: CardView, hovered: bool)

@export var card_scene: PackedScene
@export var card_spacing: float = 100.0
@export var fan_angle_degrees: float = 4.0
@export var arc_drop: float = 5.0
@export var hover_scale: float = 1.45
## Scale of resting (not hovered) cards; small so the board's bottom rows stay visible.
@export var rest_scale: float = 0.8
@export var selected_rise: float = 40.0
## How far resting cards sink below the hand area (Hearthstone-style peek); hovered cards rise fully.
@export var rest_sink: float = 62.0
@export var push_aside: float = 60.0
@export var layout_tween_time: float = 0.14

var _cards: Array[CardView] = []
var _tweens: Dictionary = {}  # CardView -> Tween
var _fan: Control
var _selected_index: int = -1
var _hovered_index: int = -1
var _order_queued: bool = false

## Number of cards currently displayed.
var card_count: int:
	get:
		return _cards.size()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_fan()


## Shows the hand and clears the selection. cost_of returns the AP cost, can_afford decides the
## playable glow (unplayable cards still emit card_selected). Existing card views are reused so
## cards slide to their new places; new cards are dealt in from the right.
## cost_of / can_afford are Callables (CardData) -> int / bool; pass Callable() for the defaults.
func show_hand(hand, cost_of: Callable, can_afford: Callable) -> void:
	_ensure_fan()
	if card_scene == null:
		push_error("HandView: CardScene is not assigned.")
		_clear_cards()
		return
	if hand == null:
		_clear_cards()
		return

	var unused: Array[CardView] = _cards.duplicate()
	var ordered: Array[CardView] = []
	var fresh: Array[CardView] = []
	for card: CardData in hand:
		var view: CardView = null
		for v: CardView in unused:
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
			fresh.append(view)
		view.setup(card, cost_of.call(card) if cost_of.is_valid() else card.ap_cost)
		view.set_playable(not can_afford.is_valid() or can_afford.call(card))
		ordered.append(view)
	for view: CardView in unused:
		_free_card(view)
	_cards.clear()
	_cards.append_array(ordered)

	var deal_from := Vector2(_fan.size.x + 60.0, _fan.size.y - 120.0)
	var dealt: int = 0
	for view: CardView in fresh:
		view.position = deal_from
		view.rotation = deg_to_rad(20.0)
		if dealt < 4:
			Sfx.play_delayed(SfxId.CARD_DEAL, dealt * 0.09)
		dealt += 1

	_hovered_index = -1
	for i in range(_cards.size()):
		if _cards[i].is_hovered:
			_hovered_index = i
			break
	_selected_index = -1
	for i in range(_cards.size()):
		_cards[i].set_selected(false)
	_restore_order()
	_relayout(true)


## Highlights the card at the given hand index (-1 = no selection).
func set_selected_index(index: int) -> void:
	_selected_index = index if (index >= 0 and index < _cards.size()) else -1
	for i in range(_cards.size()):
		_cards[i].set_selected(i == _selected_index)
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
	var base_y: float = hover_y + rest_sink

	for i in range(n):
		var card: CardView = _cards[i]
		card.pivot_offset = Vector2(card_size.x * 0.5, card_size.y)
		var off: float = i - (n - 1) * 0.5
		var x: float = center + off * spacing
		var y: float = base_y + off * off * arc_drop
		var angle: float = deg_to_rad(off * fan_angle_degrees)
		var card_scale: float = rest_scale
		if _hovered_index >= 0 and i != _hovered_index:
			var d: int = i - _hovered_index
			x += signi(d) * push_aside / absi(d)
		if i == _hovered_index:
			angle = 0.0
			card_scale = hover_scale
			y = hover_y
		elif i == _selected_index:
			y -= selected_rise
			card_scale = rest_scale * 1.06
			angle *= 0.5
		var pos := Vector2(x - card_size.x * 0.5, y)
		if _tweens.has(card):
			var old: Tween = _tweens[card]
			if old != null and old.is_valid():
				old.kill()
		if not animate:
			card.position = pos
			card.rotation = angle
			card.scale = Vector2(card_scale, card_scale)
			continue
		var tween: Tween = card.create_tween()
		tween.set_parallel(true)
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "position", pos, layout_tween_time)
		tween.tween_property(card, "rotation", angle, layout_tween_time)
		tween.tween_property(card, "scale", Vector2(card_scale, card_scale), layout_tween_time)
		_tweens[card] = tween


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
	if _hovered_index >= 0 and _hovered_index < _cards.size() and is_instance_valid(_cards[_hovered_index]) \
			and _cards[_hovered_index].get_parent() == _fan:
		_fan.move_child(_cards[_hovered_index], -1)


func _on_card_hover_changed(card: CardView, hovered: bool) -> void:
	var index: int = _cards.find(card)
	if index < 0:
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
	for view: CardView in _cards:
		_free_card(view)
	_cards.clear()
	_hovered_index = -1
	_selected_index = -1
