class_name OverworldMain
extends Node2D
## Root of Scenes/Overworld.tscn. Builds the town (TownMap), the duelists and vendors from data, the player with a
## following camera and the UI. Handles talking (E / Space / Enter or click), entering and leaving the clan halls
## (walk into a door or press E; inside wait three duelists and the clan leader, see HouseInterior), starting
## battles (BattleSession + scene change to the battle), the shop and the deck builder (Tab), and greets the player
## after a battle - back in the hall or town they left.

@export var npcs: Array[NpcData] = []
@export var vendors: Array[VendorData] = []
@export var player_start: Vector2 = Vector2(960, 780)
@export var talk_distance: float = 70.0
@export var door_distance: float = 40.0
@export var camera_zoom: float = 1.35

const TOWN_CLEAR_COLOR := Color(0.2, 0.32, 0.16)
const HALL_CLEAR_COLOR := Color(0.08, 0.05, 0.03)
const FADE_TIME := 0.22

var _map: TownMap
var _world: Node2D
var _player: OverworldPlayer
var _camera: Camera2D
var _ui: OverworldUi
var _interior: HouseInterior
var _town_people: Array[OverworldNpc] = []
var _hall_people: Array[OverworldNpc] = []
var _nearest: OverworldNpc
var _house: int = Clan.NONE
var _near_door: int = Clan.NONE
var _near_exit: bool = false
var _transitioning: bool = false

## People of the area the player is in (town or the current hall).
var _active_people: Array[OverworldNpc]:
	get:
		return _town_people if _house == Clan.NONE else _hall_people


func _ready() -> void:
	PlayerProfile.ensure_loaded()
	var sfx := Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)
	RenderingServer.set_default_clear_color(TOWN_CLEAR_COLOR)

	_map = TownMap.new()
	_map.name = "Town"
	for v: VendorData in vendors:
		if v != null:
			_map.add_stall(v.position, v.color)
	for npc: NpcData in npcs:
		if npc != null and npc.house == Clan.NONE:
			_map.reserve_spot(npc.position)
	add_child(_map)

	_world = Node2D.new()
	_world.name = "World"
	_world.y_sort_enabled = true
	add_child(_world)
	for npc: NpcData in npcs:
		if npc == null or npc.house != Clan.NONE:
			continue
		var person := OverworldNpc.new()
		person.setup_npc(npc)
		_world.add_child(person)
		_town_people.append(person)
	for vendor: VendorData in vendors:
		if vendor == null:
			continue
		var person := OverworldNpc.new()
		person.setup_vendor(vendor)
		_world.add_child(person)
		_town_people.append(person)

	_player = OverworldPlayer.new()
	_player.name = "Player"
	_player.position = player_start
	_world.add_child(_player)
	_camera = Camera2D.new()
	_camera.zoom = Vector2(camera_zoom, camera_zoom)
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 8.0
	_player.add_child(_camera)
	_camera.make_current()
	_set_camera_limits(Rect2(Vector2.ZERO, TownMap.MAP_SIZE))

	_ui = OverworldUi.new()
	_ui.name = "UI"
	add_child(_ui)
	_ui.deck_button_pressed.connect(_open_deck_builder)
	_ui.shop.closed.connect(func() -> void: _player.input_enabled = true)
	_ui.deck_builder.closed.connect(func() -> void: _player.input_enabled = true)

	_update_house_progress()
	var return_house: int = BattleSession.return_house
	if return_house != Clan.NONE:
		_show_hall(return_house, BattleSession.return_position)
	elif BattleSession.return_position is Vector2:
		_player.position = BattleSession.return_position
	_camera.reset_smoothing()
	_greet_after_battle.call_deferred()


func _process(_delta: float) -> void:
	var nearest: OverworldNpc = null
	var best: float = talk_distance
	for p: OverworldNpc in _active_people:
		var d: float = p.global_position.distance_to(_player.global_position)
		if d < best:
			best = d
			nearest = p
	if nearest != _nearest:
		if _nearest != null:
			_nearest.highlighted = false
		_nearest = nearest
		if _nearest != null:
			_nearest.highlighted = true

	_near_door = Clan.NONE
	_near_exit = false
	if _house == Clan.NONE:
		for h: TownMap.House in _map.houses:
			if TownMap.door_of(h).distance_to(_player.global_position) < door_distance:
				_near_door = h.clan
		_map.highlighted_door = _near_door
	else:
		_near_exit = _interior.is_in_doorway(_player.global_position)

	var busy: bool = _ui.is_busy or _transitioning
	_player.input_enabled = not busy
	if not busy and _nearest == null:
		# Walking into a door enters the hall; walking down out of the doorway leaves it.
		if _near_door != Clan.NONE and _is_held("ui_up", KEY_W):
			_enter_hall(_near_door)
		elif _near_exit and _is_held("ui_down", KEY_S):
			_leave_hall()

	var prompt: String = ""
	if _nearest != null:
		prompt = "E: %s %s" % ["Trade with" if _nearest.vendor != null else "Talk to", _nearest.display_name]
	elif _near_door != Clan.NONE:
		prompt = "E: Enter the hall of the %s" % ClanInfo.display_name(_near_door)
	elif _near_exit:
		prompt = "E: Leave the hall"
	_ui.set_prompt("" if _transitioning else prompt)


func _unhandled_input(event: InputEvent) -> void:
	if _transitioning:
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var key := event as InputEventKey
		match key.keycode:
			KEY_E, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				if _ui.dialogue.is_open:
					_ui.dialogue.confirm_first()
				elif not _ui.is_busy and _nearest != null:
					_talk(_nearest)
				elif not _ui.is_busy and _near_door != Clan.NONE:
					_enter_hall(_near_door)
				elif not _ui.is_busy and _near_exit:
					_leave_hall()
				get_viewport().set_input_as_handled()
			KEY_TAB, KEY_B:
				if _ui.deck_builder.is_open:
					_ui.deck_builder.close()
				elif not _ui.is_busy:
					_open_deck_builder()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				if _ui.dialogue.is_open:
					_end_talk()
				elif _ui.shop.is_open:
					_ui.shop.close()
				elif _ui.deck_builder.is_open:
					_ui.deck_builder.close()
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if not (mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT and not _ui.is_busy):
			return
		var world: Vector2 = get_global_mouse_position()
		for p: OverworldNpc in _active_people:
			if p.global_position.distance_to(world + Vector2(0, 20)) < 30.0:
				if p.global_position.distance_to(_player.global_position) <= talk_distance * 1.6:
					_talk(p)
				else:
					_ui.show_toast("Walk closer to %s to talk." % p.display_name, 2.0)
				get_viewport().set_input_as_handled()
				return


static func _is_held(action: String, key: Key) -> bool:
	return Input.is_action_pressed(action) or Input.is_physical_key_pressed(key)


func _set_camera_limits(area: Rect2) -> void:
	_camera.limit_left = int(area.position.x)
	_camera.limit_top = int(area.position.y)
	_camera.limit_right = int(area.end.x)
	_camera.limit_bottom = int(area.end.y)


# ------------------------------------------------------------------ halls

## Fades out, swaps the town for the clan's hall and fades back in.
func _enter_hall(clan: int) -> void:
	if _transitioning or _house != Clan.NONE:
		return
	Sfx.play(SfxId.BUTTON_CLICK)
	_fade_swap(func() -> void:
		_show_hall(clan, null)
		var leader: NpcData = _find_leader(clan)
		var goal: String = ""
		if leader != null:
			if PlayerProfile.has_defeated(leader.id):
				goal = " You have beaten %s - rematches are always welcome." % leader.name
			else:
				goal = " Beat its three duelists to challenge %s." % leader.name
		_ui.show_toast("Hall of the %s.%s" % [ClanInfo.display_name(clan), goal], 4.0)
	)


## Fades out and returns to the town in front of the hall's door.
func _leave_hall() -> void:
	if _transitioning or _house == Clan.NONE:
		return
	Sfx.play(SfxId.BUTTON_CLICK)
	_fade_swap(_show_town)


func _fade_swap(swap: Callable) -> void:
	_transitioning = true
	_player.input_enabled = false
	_end_talk()
	var fade: Tween = create_tween()
	fade.tween_property(self, "modulate", Color(0.05, 0.05, 0.05), FADE_TIME)
	fade.tween_callback(func() -> void:
		swap.call()
		_camera.reset_smoothing()
	)
	fade.tween_property(self, "modulate", Color.WHITE, FADE_TIME)
	fade.tween_callback(func() -> void: _transitioning = false)


## Builds the clan's hall with its duelists and puts the player at the door (or at a given position).
## at: Vector2 or null.
func _show_hall(clan: int, at: Variant) -> void:
	_house = clan
	_map.visible = false
	_map.highlighted_door = Clan.NONE
	for p: OverworldNpc in _town_people:
		p.visible = false
	_clear_nearest()
	_interior = HouseInterior.new()
	_interior.setup(clan)
	add_child(_interior)
	move_child(_interior, _world.get_index())
	for npc: NpcData in npcs:
		if npc == null or npc.house != clan:
			continue
		var person := OverworldNpc.new()
		person.setup_npc(npc)
		person.position += HouseInterior.ORIGIN
		_world.add_child(person)
		_hall_people.append(person)
	_player.position = at if at != null else HouseInterior.ORIGIN + HouseInterior.ENTRY_POINT
	_set_camera_limits(Rect2(HouseInterior.ORIGIN, HouseInterior.ROOM_SIZE))
	RenderingServer.set_default_clear_color(HALL_CLEAR_COLOR)


## Removes the hall and shows the town again, the player in front of the hall's door.
func _show_town() -> void:
	var left: int = _house
	_house = Clan.NONE
	_clear_nearest()
	for p: OverworldNpc in _hall_people:
		p.queue_free()
	_hall_people.clear()
	if _interior != null:
		_interior.queue_free()
	_interior = null
	_map.visible = true
	for p: OverworldNpc in _town_people:
		p.visible = true
	for h: TownMap.House in _map.houses:
		if h.clan == left:
			_player.position = TownMap.door_of(h) + Vector2(0, 26)
	_set_camera_limits(Rect2(Vector2.ZERO, TownMap.MAP_SIZE))
	RenderingServer.set_default_clear_color(TOWN_CLEAR_COLOR)
	_update_house_progress()


func _clear_nearest() -> void:
	if _nearest != null:
		_nearest.highlighted = false
		_nearest = null


## The duelist of a hall that requires others (its clan leader), or null.
func _find_leader(clan: int) -> NpcData:
	for npc: NpcData in npcs:
		if npc != null and npc.house == clan and npc.requires_defeated.size() > 0:
			return npc
	return null


## Updates the star signs above the hall doors (duelists of each hall beaten / total).
func _update_house_progress() -> void:
	for h: TownMap.House in _map.houses:
		var total: int = 0
		var beaten: int = 0
		for npc: NpcData in npcs:
			if npc != null and npc.house == h.clan:
				total += 1
				beaten += 1 if PlayerProfile.has_defeated(npc.id) else 0
		_map.set_house_progress(h.clan, beaten, total)


# ------------------------------------------------------------------ talking

func _talk(person: OverworldNpc) -> void:
	person.face_toward(_player.global_position)
	if person.vendor != null:
		var v: VendorData = person.vendor
		var trade := func() -> void:
			_end_talk()
			_player.input_enabled = false
			_ui.shop.open_for(v)
		_ui.dialogue.open(v.name, Color(1.0, 0.85, 0.5), v.title, v.greeting, [
			{"label": "Trade", "action": trade},
			{"label": "Leave", "action": _end_talk},
		])
		return
	var npc: NpcData = person.npc
	var unlock: Dictionary = BattleSession.is_unlocked(npc)
	if not unlock["result"]:
		var locked: String = "Come back when you are ready." if npc.locked_line.is_empty() else npc.locked_line
		var what: String = "Duelists of this hall defeated" if npc.house != Clan.NONE else "Clan leaders defeated"
		_ui.dialogue.open(npc.name, Color(0.75, 0.3, 0.95), npc.title,
			"%s\n\n[color=#6b4a2a]%s: [b]%d / %d[/b] · %s[/color]" % [locked, what, int(unlock["beaten"]), int(unlock["needed"]), BattleSession.describe_reward(npc)],
			[{"label": "Leave", "action": _end_talk}])
		return
	var beaten: bool = PlayerProfile.has_defeated(npc.id)
	var line: String = npc.rematch_line if beaten and not npc.rematch_line.is_empty() else npc.greeting
	var deck_name: String = npc.deck.name if npc.deck != null else "?"
	var text: String = ("%s\n\n[color=#6b4a2a]%s · plays [b]%s[/b] · %s · " % [line, ClanInfo.display_name(npc.clan), deck_name, _describe_strength(npc)]) \
		+ ("%s[/color]" % BattleSession.describe_reward(npc))
	_ui.dialogue.open(npc.name, ClanInfo.get_color(npc.clan).darkened(0.1), npc.title, text, [
		{"label": "Rematch!" if beaten else "Battle!", "action": func() -> void: _start_battle(npc)},
		{"label": "Leave", "action": _end_talk},
	])


## Rough deck strength for the dialogue (average card rarity, plus the duelist's bonus AP).
static func _describe_strength(npc: NpcData) -> String:
	if npc.deck == null or npc.deck.cards.size() == 0:
		return "?"
	var rarity: float = 0.0
	for card: CardData in npc.deck.cards:
		rarity += card.rarity if card != null else 0
	rarity /= npc.deck.cards.size()
	if npc.bonus_ap_per_turn > 0 or rarity >= 1.2:
		return "[color=#a02020]Boss[/color]"
	if rarity >= 0.8:
		return "Hard"
	return "Medium" if rarity >= 0.35 else "Easy"


func _end_talk() -> void:
	_ui.dialogue.close()


func _start_battle(npc: NpcData) -> void:
	if not PlayerProfile.get_deck_is_valid():
		var to_builder := func() -> void:
			_end_talk()
			_open_deck_builder()
		_ui.dialogue.open(npc.name, ClanInfo.get_color(npc.clan), npc.title,
			"Come back with a proper deck! You need %d to %d cards - yours has %d." % [PlayerProfile.DECK_MIN, PlayerProfile.DECK_MAX, PlayerProfile.get_deck_count()],
			[
				{"label": "Deck Builder", "action": to_builder},
				{"label": "Leave", "action": _end_talk},
			])
		return
	if npc.deck == null or npc.deck.cards.size() == 0:
		_ui.show_toast("%s has no deck to play with." % npc.name)
		return
	_end_talk()
	_transitioning = true
	_player.input_enabled = false
	Sfx.play(SfxId.TURN_ENEMY)
	BattleSession.begin(npc, _player.global_position, _house)
	var fade: Tween = create_tween()
	fade.tween_property(self, "modulate", Color(0.1, 0.1, 0.1), 0.45)
	fade.tween_callback(func() -> void: get_tree().change_scene_to_file(BattleSession.BATTLE_SCENE))


func _open_deck_builder() -> void:
	_end_talk()
	_player.input_enabled = false
	_ui.deck_builder.open()


func _greet_after_battle() -> void:
	var npc: NpcData = BattleSession.last_opponent
	var message: String = BattleSession.pending_message
	BattleSession.last_opponent = null
	BattleSession.pending_message = ""
	if npc == null or message.is_empty():
		_ui.show_toast("Welcome to Realmshatter! Duel the townsfolk, enter the clan halls - or visit the market.", 5.0)
		return
	var person: OverworldNpc = null
	for p: OverworldNpc in _active_people:
		if p.npc == npc:
			person = p
			break
	if person != null:
		person.face_toward(_player.global_position)
	var won: bool = BattleSession.last_won
	var line: String = npc.defeat_line if won else npc.victory_line
	var unlocked: String = _describe_unlock(npc) if won else ""
	_ui.dialogue.open(npc.name, ClanInfo.get_color(npc.clan).darkened(0.1), npc.title, "%s\n\n[b]%s[/b]%s" % [line, message, unlocked],
		[{"label": "Continue", "action": _end_talk}])
	Sfx.play(SfxId.COIN if won else SfxId.SPELL_FADE)


## Text about a duelist the win just unlocked (the hall's leader or the endboss), or "".
func _describe_unlock(beaten: NpcData) -> String:
	for npc: NpcData in npcs:
		if npc == null or not npc.requires_defeated.has(beaten.id) or PlayerProfile.has_defeated(npc.id):
			continue
		var r: Dictionary = BattleSession.is_unlocked(npc)
		if r["result"]:
			return "\n\n[color=#7a3a10]%s (%s) will now accept your challenge![/color]" % [npc.name, npc.title]
		return "\n\n[color=#6b4a2a]%d / %d beaten on the way to %s.[/color]" % [int(r["beaten"]), int(r["needed"]), npc.name]
	return ""
