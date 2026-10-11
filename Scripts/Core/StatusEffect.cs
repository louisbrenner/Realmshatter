namespace Realmshatter;

/// <summary>A temporary status on a piece. Expires at the END of turn ExpiryTurn (or earlier when consumed).</summary>
public sealed class StatusEffect
{
	public StatusEffectType Type { get; }
	public int AppliedTurn { get; }
	public int ExpiryTurn { get; }
	/// <summary>Name of the card that caused the status, for tooltips.</summary>
	public string SourceName { get; }

	public StatusEffect(StatusEffectType type, int appliedTurn, int expiryTurn, string sourceName)
	{
		Type = type;
		AppliedTurn = appliedTurn;
		ExpiryTurn = expiryTurn;
		SourceName = sourceName ?? "";
	}

	public override string ToString() => $"{Type} (until end of turn {ExpiryTurn})";
}
