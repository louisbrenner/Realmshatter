class_name GameConfig
extends Resource
## Global rule configuration. Coordinates: x = column (0..board_width-1, left to right),
## y = row (0..board_height-1, row 0 is the top / far side of player 0).

@export_group("Board")
@export var board_width: int = 10
@export var board_height: int = 8
## Scoring zone as (x, y, width, height). Default: columns 2-7, rows 3-4.
@export var scoring_zone: Rect2i = Rect2i(2, 3, 6, 2)
## Number of back rows each player may deploy into.
@export var deploy_rows: int = 2

@export_group("Rules")
@export var base_ap: int = 3
@export var unit_ap_cost: int = 1
@export var spell_ap_cost: int = 2
@export var points_target: int = 20
@export var starting_hand_size: int = 3
@export var draft_offer_size: int = 3
## AP cost of the Draw action (draft offer of up to draft_offer_size cards, keep one).
@export var draw_ap_cost: int = 1
## AP cost of giving a piece a new order (replacing an existing order is free).
@export var order_ap_cost: int = 1
## Maximum victory points a player may convert into action points per turn (1 VP -> 1 AP).
@export var max_vp_to_ap_per_turn: int = 2
## Extra AP for the second player (player 1) on its first turn.
@export var second_player_first_turn_bonus_ap: int = 1

## Damage dealt by Lava at the start of the occupant owner's turn.
@export_group("Map Effects & Keywords")
@export var lava_damage: int = 1
## HP healed by a Healing tile at the start of the occupant owner's turn.
@export var healing_tile_amount: int = 1
## Duration (global turns) of the Lava left by Burning attacks.
@export var burning_lava_duration: int = 2
## Duration (global turns) of Frozen; 1 = through the victim owner's next turn.
@export var frost_duration: int = 1
## Heal of a Mending hit on a friendly.
@export var mending_heal: int = 1
## Extra damage of Echo pieces' chain shots.
@export var echo_bonus_damage: int = 1
## Damage multiplier of an Overcharged piece's chain shots.
@export var overcharge_multiplier: int = 2
## Duration (global turns) of statuses granted by spells (e.g. Overcharged).
@export var spell_status_duration: int = 2
## Maximum number of friendlies a single move can push in a row.
@export var max_push_chain: int = 3
