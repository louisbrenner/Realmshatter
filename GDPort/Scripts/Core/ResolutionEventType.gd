class_name ResolutionEventType
extends RefCounted
## Kind of a resolution event emitted by OrderResolver / TurnController (actions, EndTurn expiries, turn-start
## ticks, spells). Views must ignore types they do not know.

enum {
	MOVED = 0, MOVE_BLOCKED = 1, ATTACKED = 2, ATTACK_CANCELLED = 3, DAMAGED = 4, DIED = 5, SPELL_EXPIRED = 6,
	PUSHED = 7, PUSH_BLOCKED = 8, HEALED = 9, RETURNED_TO_DECK = 10, TILE_EFFECT_APPLIED = 11, TILE_EFFECT_EXPIRED = 12,
	TILE_DAMAGE = 13, TILE_HEAL = 14, STATUS_APPLIED = 15, STATUS_EXPIRED = 16, SPELL_CAST = 17, DEATHRATTLE = 18,
	FIRST_HIT_TRIGGERED = 19, BUILDING_STARTED = 20, BUILDING_COMPLETED = 21, AURA_PULSE = 22, AP_GAINED = 23,
	TERRAIN_DAMAGED = 24, TRAP_SET = 25, TRAP_TRIGGERED = 26,
}

const NAMES := {
	MOVED: "Moved", MOVE_BLOCKED: "MoveBlocked", ATTACKED: "Attacked", ATTACK_CANCELLED: "AttackCancelled",
	DAMAGED: "Damaged", DIED: "Died", SPELL_EXPIRED: "SpellExpired", PUSHED: "Pushed", PUSH_BLOCKED: "PushBlocked",
	HEALED: "Healed", RETURNED_TO_DECK: "ReturnedToDeck", TILE_EFFECT_APPLIED: "TileEffectApplied",
	TILE_EFFECT_EXPIRED: "TileEffectExpired", TILE_DAMAGE: "TileDamage", TILE_HEAL: "TileHeal",
	STATUS_APPLIED: "StatusApplied", STATUS_EXPIRED: "StatusExpired", SPELL_CAST: "SpellCast",
	DEATHRATTLE: "Deathrattle", FIRST_HIT_TRIGGERED: "FirstHitTriggered", BUILDING_STARTED: "BuildingStarted",
	BUILDING_COMPLETED: "BuildingCompleted", AURA_PULSE: "AuraPulse", AP_GAINED: "ApGained",
	TERRAIN_DAMAGED: "TerrainDamaged", TRAP_SET: "TrapSet", TRAP_TRIGGERED: "TrapTriggered",
}

## Equivalent of C# enum ToString().
static func name_of(value: int) -> String:
	return NAMES.get(value, str(value))
