using System;

namespace Realmshatter;

/// <summary>Side effects of a single predicted hit (see PredictedHit).</summary>
[Flags]
public enum HitEffect
{
	None = 0,
	/// <summary>The hit left Lava on a tile (Burning).</summary>
	Lava = 1 << 0,
	/// <summary>The target got Frozen (Frost).</summary>
	Frozen = 1 << 1,
	/// <summary>The target was knocked back (Push).</summary>
	Pushed = 1 << 2,
	/// <summary>A knockback was attempted but blocked.</summary>
	PushBlocked = 1 << 3,
	/// <summary>The friendly target was healed (Mending).</summary>
	Healed = 1 << 4,
	/// <summary>The target died.</summary>
	Killed = 1 << 6,
}
