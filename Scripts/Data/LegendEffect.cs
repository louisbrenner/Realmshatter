namespace Realmshatter;

/// <summary>Unique effect of a Legendary unit (one per clan, see LegendInfo).</summary>
public enum LegendEffect
{
	None,
	/// <summary>Ember Legion: at the start of your turn every enemy standing on Lava takes 2 damage.</summary>
	Wildfire,
	/// <summary>Dawn Covenant: at the start of your turn your units within 3 tiles are healed to full HP.</summary>
	Dawnlight,
	/// <summary>Frostbound: at the start of your turn every enemy within 2 tiles is Frozen.</summary>
	GlacialGrip,
	/// <summary>Storm Circuit: at the start of your turn lightning strikes the 3 nearest enemies (within 5 tiles) for 1 damage.</summary>
	ChainLightning,
	/// <summary>Stone Bastion: it takes at most 1 damage from any single hit.</summary>
	Unbreakable,
}
