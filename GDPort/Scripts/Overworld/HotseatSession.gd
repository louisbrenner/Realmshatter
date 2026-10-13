class_name HotseatSession
extends RefCounted
## Hand-over data for a local hotseat match (two humans on one device), started from the overworld.
## Independent of BattleSession: no NPC, no rewards, the profile is never touched.

## True while a hotseat match is pending / running.
static var is_active: bool = false


## Starts a hotseat match (call change_scene_to_file(BattleSession.BATTLE_SCENE) afterwards).
static func begin(player_position: Vector2, house: int = Clan.NONE) -> void:
	is_active = true
	BattleSession.return_position = player_position
	BattleSession.return_house = house


## Ends the match; the overworld shows 'message' as a toast on return.
static func complete(message: String) -> void:
	is_active = false
	BattleSession.pending_message = message
