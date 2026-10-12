class_name HitEffect
extends RefCounted
## Side effects of a single predicted hit (see PredictedHit). Flags.

enum { NONE = 0, LAVA = 1, FROZEN = 2, PUSHED = 4, PUSH_BLOCKED = 8, HEALED = 16, KILLED = 64 }

const NAMES := { NONE: "None", LAVA: "Lava", FROZEN: "Frozen", PUSHED: "Pushed", PUSH_BLOCKED: "PushBlocked", HEALED: "Healed", KILLED: "Killed" }

## Equivalent of C# [Flags] enum ToString(): ", "-joined names, "None" for 0.
static func name_of(value: int) -> String:
	if value == 0:
		return NAMES[0]
	var parts: Array[String] = []
	var rest: int = value
	for v: int in NAMES:
		if v != 0 and (value & v) == v:
			parts.append(NAMES[v])
			rest &= ~v
	if rest != 0:
		return str(value)
	return ", ".join(parts)
