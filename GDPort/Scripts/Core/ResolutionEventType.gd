class_name ResolutionEventType
extends RefCounted
## Kind of a resolution event emitted by OrderResolver / TurnController. Views must ignore unknown types.

enum { MOVED = 0, MOVE_BLOCKED = 1, ATTACKED = 2, ATTACK_CANCELLED = 3, DAMAGED = 4, DIED = 5, CHAIN_TRIGGERED = 6, SPELL_EXPIRED = 7, PUSHED = 8, PUSH_BLOCKED = 9, HEALED = 10, RETURNED_TO_DECK = 11, TILE_EFFECT_APPLIED = 12, TILE_EFFECT_EXPIRED = 13, TILE_DAMAGE = 14, TILE_HEAL = 15, STATUS_APPLIED = 16, STATUS_EXPIRED = 17, SPELL_CAST = 18 }

const NAMES := { MOVED: "Moved", MOVE_BLOCKED: "MoveBlocked", ATTACKED: "Attacked", ATTACK_CANCELLED: "AttackCancelled", DAMAGED: "Damaged", DIED: "Died", CHAIN_TRIGGERED: "ChainTriggered", SPELL_EXPIRED: "SpellExpired", PUSHED: "Pushed", PUSH_BLOCKED: "PushBlocked", HEALED: "Healed", RETURNED_TO_DECK: "ReturnedToDeck", TILE_EFFECT_APPLIED: "TileEffectApplied", TILE_EFFECT_EXPIRED: "TileEffectExpired", TILE_DAMAGE: "TileDamage", TILE_HEAL: "TileHeal", STATUS_APPLIED: "StatusApplied", STATUS_EXPIRED: "StatusExpired", SPELL_CAST: "SpellCast" }

## Equivalent of C# enum ToString().
static func name_of(value: int) -> String:
	return NAMES.get(value, str(value))
