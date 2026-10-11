class_name Keyword
extends RefCounted
## Keywords of a unit card (combinable flags). See KeywordInfo / OrderResolver.

enum { NONE = 0, BURNING = 1, FROST = 2, PUSH = 4, PIERCE = 8, MENDING = 16, CONDUIT = 32, ECHO = 64, UNDYING = 128 }

const NAMES := { NONE: "None", BURNING: "Burning", FROST: "Frost", PUSH: "Push", PIERCE: "Pierce", MENDING: "Mending", CONDUIT: "Conduit", ECHO: "Echo", UNDYING: "Undying" }

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
