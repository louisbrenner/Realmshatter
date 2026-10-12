class_name GameConfig
extends Resource
## Global rule configuration. Coordinates: x = column (0..board_width-1, left to right),
## y = row (0..board_height-1, row 0 is the top / far side of player 0).

@export_group("Board")
@export var board_width: int = 12
@export var board_height: int = 16
## Scoring zone as (x, y, width, height): an 8x8 area with a 2-tile neutral border around it
## (columns 2-9, rows 4-11 on the 12x16 board; rows 0-1 and 14-15 are the deploy rows).
@export var scoring_zone: Rect2i = Rect2i(2, 4, 8, 8)
## The "crown" field inside the scoring zone: pieces there score hot_zone_points instead of 1.
@export var hot_zone: Rect2i = Rect2i(5, 7, 2, 2)
## VP per piece standing on the crown field at the start of its owner's turn.
@export var hot_zone_points: int = 2
## Extra AP per finished Mana Well (building) at the start of its owner's turn.
@export var mana_well_ap: int = 1
## Spells may only be cast on tiles within this many tiles (Manhattan) of one of your units.
@export var spell_cast_radius: int = 4
## Your spells aimed within this many tiles (Manhattan) of your finished Obelisk are empowered (+1).
@export var obelisk_empower_radius: int = 4
## Duration (global turns) of the rubble a destroyed building leaves behind.
@export var rubble_duration: int = 4
## Number of back rows each player may deploy into.
@export var deploy_rows: int = 2

@export_group("Rules")
@export var base_ap: int = 3
@export var unit_ap_cost: int = 1
@export var spell_ap_cost: int = 2
@export var points_target: int = 25
@export var starting_hand_size: int = 5
@export var draft_offer_size: int = 3
## AP cost of the Draw action (draft offer of up to draft_offer_size cards, keep one).
@export var draw_ap_cost: int = 1
## AP cost of commanding a piece (its move + attack resolve immediately; once per piece and turn).
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
@export var burning_lava_duration: int = 4
## Duration (global turns) of the Ice, Storm cells, Healing springs and Mud that clan attacks leave behind.
@export var attack_ground_duration: int = 4
## Duration (global turns) of Frozen; 1 = through the victim owner's next turn.
@export var frost_duration: int = 1
## Heal of a Mending hit on a friendly.
@export var mending_heal: int = 1
## Damage of an Echo piece's second strike.
@export var echo_bonus_damage: int = 1
## Damage multiplier of an Overcharged piece's next attack.
@export var overcharge_multiplier: int = 2
## Damage of an Arc piece's zap on each piece next to its target.
@export var arc_damage: int = 1
## Duration (global turns) of statuses granted by spells (e.g. Overcharged).
@export var spell_status_duration: int = 2
## Duration (global turns) of Lava / Walls created by deathrattles.
@export var trigger_effect_duration: int = 4
## Damage a pushed piece takes when it is shoved into another piece, a building, a wall or a rock.
@export var push_collision_damage: int = 1
## Maximum number of friendlies a single move can push in a row.
@export var max_push_chain: int = 3
## Movement a unit spends to enter a Water tile (rivers, ponds).
@export var water_move_cost: int = 2
## Hit points of a breakable Rock wall.
@export var rock_hp: int = 3
## AP cost of setting a trap (Trapper keyword; replaces the attack of the unit's action).
@export var trap_ap_cost: int = 1
## Traps one Trapper may have at once; setting another replaces its oldest.
@export var max_traps_per_trapper: int = 2
## Planted units may be deployed up to this many tiles (Manhattan) from one of their owner's units.
@export var plant_radius: int = 2
