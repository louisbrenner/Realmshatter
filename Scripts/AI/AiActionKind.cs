namespace Realmshatter;

/// <summary>Kind of step the AI executed during its turn.</summary>
public enum AiActionKind
{
	Draft,
	PlayUnit,
	PlaySpell,
	SetOrder,
	/// <summary>Converted 1 VP into 1 AP (TurnController.ConvertVpToAp).</summary>
	ConvertVp,
}
