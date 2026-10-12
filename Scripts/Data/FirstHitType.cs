namespace Realmshatter;

/// <summary>Effect a unit triggers the first time it takes damage and survives (CardData.OnFirstHit).</summary>
public enum FirstHitType
{
	None,
	/// <summary>The attacker takes Amount damage.</summary>
	Thorns,
	/// <summary>The attacker is pushed 1 tile away.</summary>
	Repel,
	/// <summary>Gains Amount Shield.</summary>
	Harden,
	/// <summary>Gains +Amount Attack for the rest of the game.</summary>
	Enrage,
	/// <summary>Pushes every piece next to it 1 tile away.</summary>
	Shockwave,
}
