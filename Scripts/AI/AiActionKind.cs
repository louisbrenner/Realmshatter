namespace Realmshatter;

/// <summary>Kind of step the AI executed during its turn.</summary>
public enum AiActionKind
{
	Draft,
	PlayUnit,
	PlaySpell,
	/// <summary>Commanded a piece (move + attack resolved immediately).</summary>
	Command,
	/// <summary>A Builder started a building (TurnController.Build).</summary>
	Build,
	/// <summary>A Trapper hid a trap (TurnController.SetTrap); the target tile stays secret in the description.</summary>
	Trap,
	/// <summary>Converted 1 VP into 1 AP (TurnController.ConvertVpToAp).</summary>
	ConvertVp,
}
